#!/usr/bin/env python3
"""Build-time export of GLiNER to ONNX for Loom's native entity detector.

Loom's entity discovery is moving off the generative LLM (which derails
and refuses on explicit prose) onto GLiNER — a small bidirectional NER
encoder that is deterministic, refusal-proof, and fast. GLiNER ships as
a PyTorch model; this script converts it ONCE, offline, to ONNX so the
app can run it natively via ONNX Runtime with ZERO runtime Python.

Runtime decision: ONNX Runtime, not CoreML. GLiNER's DeBERTa-v3 backbone
has dynamic control flow in its disentangled-attention relative-position
code that coremltools cannot trace (verified — two conversion attempts
failed at the trace stage). ONNX export, by contrast, is clean.

This is a build-time tool. It is NOT shipped and NOT run by `swift build`.
Run it on a dev machine to (re)generate the model bundle.

Prerequisites (throwaway venv recommended):
    python3 -m venv /tmp/gliner-export && . /tmp/gliner-export/bin/activate
    pip install gliner onnx onnxruntime

Usage:
    python export_gliner_onnx.py [output_dir]

`output_dir` defaults to Sources/LoomCore/Resources/GLiNER (relative to
the repo root). The directory is gitignored — like the Wegmann CoreML
bundle, the weights are regenerated locally before a build, not committed.
"""
import json
import sys
import shutil
import time
from pathlib import Path

# gliner_small-v2.1: DeBERTa-v3-small backbone (~50M params), the
# smallest v2.1 GLiNER. Quantized INT8 ONNX is ~175 MB. Larger variants
# raise recall marginally at 3-4x the size — not worth it for a
# background entity tagger.
MODEL_ID = "urchade/gliner_small-v2.1"

# Files GLiNER's ONNX inference path needs alongside the model: the
# tokenizer assets + the GLiNER head config. The Swift loader reads the
# same set.
REQUIRED_ASSETS = [
    "model_quantized.onnx",
    "gliner_config.json",
    "tokenizer.json",
    "tokenizer_config.json",
    "special_tokens_map.json",
]


def retype_span_mask_to_int64(model_path: Path) -> None:
    """Graph surgery: retype the `span_mask` input from bool to int64.

    GLiNER's ONNX graph declares `span_mask` as `tensor(bool)`, but ONNX
    Runtime's Objective-C API (the one Loom links) exposes no bool
    element type — there is no way to build a bool `ORTValue`. Rather
    than carry a runtime workaround, retype the input to int64 and splice
    a `Cast`-to-bool node in front of its single consumer, so the Swift
    side feeds an int64 0/1 tensor and the graph is otherwise untouched.

    Idempotent: a second run on an already-patched model is a no-op.
    """
    import onnx
    from onnx import TensorProto, helper

    model = onnx.load(str(model_path))
    graph = model.graph
    span_mask_in = next((i for i in graph.input if i.name == "span_mask"), None)
    if span_mask_in is None:
        raise RuntimeError("export has no `span_mask` graph input")
    if span_mask_in.type.tensor_type.elem_type == TensorProto.INT64:
        print("  span_mask already int64 — skipping surgery")
        return

    span_mask_in.type.tensor_type.elem_type = TensorProto.INT64
    casted = "span_mask_bool"
    for node in graph.node:
        for idx, name in enumerate(node.input):
            if name == "span_mask":
                node.input[idx] = casted
    cast = helper.make_node(
        "Cast", ["span_mask"], [casted], to=TensorProto.BOOL, name="CastSpanMaskToBool"
    )
    graph.node.insert(0, cast)
    # No `onnx.checker.check_model` here: the quantized export already
    # trips the strict topological-sort check inside an `If` subgraph
    # (a pre-existing quirk unrelated to this surgery). The Cast node is
    # inserted at index 0 and depends only on a graph input, so it is
    # itself correctly ordered; verify_gliner_onnx.py + the Swift
    # fixture test confirm the patched graph runs and decodes correctly.
    onnx.save(model, str(model_path))
    print("  span_mask retyped bool → int64 (+ Cast-to-bool node)")


def main() -> int:
    repo_root = Path(__file__).resolve().parents[2]
    out_dir = (
        Path(sys.argv[1]).resolve()
        if len(sys.argv) > 1
        else repo_root / "Sources/LoomCore/Resources/GLiNER"
    )

    try:
        from gliner import GLiNER
    except ImportError:
        print("error: `gliner` not installed — see the prerequisites in this file's docstring.")
        return 1

    print(f"loading {MODEL_ID} …", flush=True)
    t0 = time.time()
    model = GLiNER.from_pretrained(MODEL_ID)
    print(f"  loaded in {time.time() - t0:.1f}s")

    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True)

    print(f"exporting quantized ONNX → {out_dir} …", flush=True)
    t0 = time.time()
    # quantize=True → INT8; opset 19 matches what ONNX Runtime 1.19 expects.
    model.export_to_onnx(out_dir, quantize=True, opset=19)
    # Ensure the tokenizer assets are present (export_to_onnx writes the
    # model + gliner_config; the tokenizer is saved explicitly so the
    # Swift side has a complete, self-contained bundle).
    model.data_processor.transformer_tokenizer.save_pretrained(out_dir)
    print(f"  exported in {time.time() - t0:.1f}s")

    # The FP32 model.onnx is large and unused at runtime — drop it.
    fp32 = out_dir / "model.onnx"
    if fp32.exists():
        fp32.unlink()

    # Retype the bool `span_mask` input so ONNX Runtime's Objective-C
    # API (no bool element type) can feed it as int64.
    print("patching span_mask input type …", flush=True)
    retype_span_mask_to_int64(out_dir / "model_quantized.onnx")

    # swift-transformers' tokenizer factory selects the model class
    # from tokenizer_config.json's `tokenizer_class`; it has no
    # DebertaV2 entry. GLiNER's tokenizer is a plain SentencePiece
    # Unigram (tokenizer.json: model.type == "Unigram"), so rewrite the
    # class to XLMRobertaTokenizer — swift-transformers maps that to
    # its generic UnigramTokenizer, and every normalizer / pre-tokenizer
    # / decoder behaviour is read from tokenizer.json regardless. This
    # lets the Swift side load the bundle with the stock AutoTokenizer,
    # no per-model workaround.
    cfg_path = out_dir / "tokenizer_config.json"
    cfg = json.loads(cfg_path.read_text())
    cfg["tokenizer_class"] = "XLMRobertaTokenizer"
    cfg_path.write_text(json.dumps(cfg, indent=2))

    print("\nbundle contents:")
    missing = []
    for name in REQUIRED_ASSETS:
        f = out_dir / name
        if f.exists():
            print(f"  ok    {name}  ({f.stat().st_size / 1e6:.1f} MB)")
        else:
            print(f"  MISSING  {name}")
            missing.append(name)
    if missing:
        print(f"\nerror: {len(missing)} required asset(s) missing from the export.")
        return 1

    print("\nexport complete. Verify with: python verify_gliner_onnx.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())

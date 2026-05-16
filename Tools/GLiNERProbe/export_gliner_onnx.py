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

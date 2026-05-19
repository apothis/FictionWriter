#!/usr/bin/env python3
"""Build-time export of a DeBERTa-v3 NLI cross-encoder to ONNX.

Loom's Continuity Audit pairs claims by embedding cosine, then asks an
LLM to adjudicate. §24 measured that embedding cosine scores *topic*,
not *proposition* — a bi-encoder failure. A cross-encoder scores the
pair jointly; an NLI cross-encoder additionally emits `contradiction` /
`entailment` / `neutral`, and a probe (§25 / A0) confirmed `contradiction`
cleanly flags real world-fact contradictions (34/36 on the eval golds)
while genuinely-unrelated pairs come back `neutral`.

This script converts the NLI model ONCE, offline, to ONNX so the app
runs it natively via ONNX Runtime — the same runtime already linked for
GLiNER, with ZERO runtime Python. It is a build-time tool: NOT shipped,
NOT run by `swift build`.

Runtime decision: ONNX Runtime, not CoreML — the model shares GLiNER's
DeBERTa-v3 backbone, whose disentangled-attention relative-position code
coremltools cannot trace (see export_gliner_onnx.py).

Prerequisites (throwaway venv recommended):
    python3 -m venv /tmp/nli-export && . /tmp/nli-export/bin/activate
    pip install "optimum[onnxruntime]" onnx transformers torch sentencepiece

Usage:
    python export_nli_onnx.py [output_dir]

`output_dir` defaults to Sources/LoomCore/Resources/NLI (relative to the
repo root). The directory is gitignored — like the GLiNER bundle, the
weights are regenerated locally before a build, not committed.
"""
import json
import sys
import shutil
import time
from pathlib import Path

# MoritzLaurer's DeBERTa-v3-large NLI (MNLI+FEVER+ANLI+LING+WANLI) — the
# strongest small open NLI model; the A0 probe (§25) flagged 34/36 real
# eval-fixture contradictions with it. ~435M params; INT8-quantized ONNX
# is ~440 MB — larger than GLiNER's bundle but acceptable for a
# build-time-generated, gitignored asset.
MODEL_ID = "MoritzLaurer/DeBERTa-v3-large-mnli-fever-anli-ling-wanli"

# Files the ONNX inference path needs alongside the model. `config.json`
# carries `id2label` — the Swift decoder reads the verdict order from it
# rather than hard-coding {entailment, neutral, contradiction}.
#
# The model ships FP32, not INT8-quantized. Dynamic INT8 quantization was
# tried and verified to break it: DeBERTa-v3's disentangled-attention is
# quantization-sensitive, and the INT8 model flipped verdicts vs FP32
# (a clear "contradiction" at logit 4.96 collapsed to "neutral" — see
# Tools/NLIProbe/verify_nli_onnx.py). A 3-way argmax with tight margins
# has no tolerance for the logit mush INT8 introduces (GLiNER tolerates
# it because per-span sigmoid NER is far more robust). FP32 is ~1.7 GB —
# large, but the bundle is gitignored and regenerated locally.
REQUIRED_ASSETS = [
    "model.onnx",
    "config.json",
    "tokenizer.json",
    "tokenizer_config.json",
    "special_tokens_map.json",
]


def main() -> int:
    repo_root = Path(__file__).resolve().parents[2]
    out_dir = (
        Path(sys.argv[1]).resolve()
        if len(sys.argv) > 1
        else repo_root / "Sources/LoomCore/Resources/NLI"
    )

    try:
        from optimum.onnxruntime import ORTModelForSequenceClassification
        from transformers import AutoTokenizer
    except ImportError:
        print("error: export deps missing — see the prerequisites in this file's docstring.")
        return 1

    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True)

    print(f"loading + exporting {MODEL_ID} to FP32 ONNX …", flush=True)
    t0 = time.time()
    model = ORTModelForSequenceClassification.from_pretrained(MODEL_ID, export=True)
    model.save_pretrained(out_dir)
    AutoTokenizer.from_pretrained(MODEL_ID).save_pretrained(out_dir)
    print(f"  exported in {time.time() - t0:.1f}s")

    # swift-transformers' tokenizer factory selects the model class from
    # tokenizer_config.json's `tokenizer_class`; it has no DebertaV2
    # entry. The DeBERTa-v3 tokenizer is a plain SentencePiece Unigram —
    # rewrite the class to XLMRobertaTokenizer so the Swift side loads it
    # with the stock AutoTokenizer (the same trick as the GLiNER export).
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

    print("\nexport complete.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

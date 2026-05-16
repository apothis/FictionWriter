#!/usr/bin/env python3
"""Dump a GLiNER tokenizer parity fixture.

Tokenizes a set of probe strings with GLiNER's own DeBERTa-v3
SentencePiece tokenizer and writes the resulting token-id sequences to
a JSON fixture. The Swift `GLiNERTokenizer` test reads the same fixture
and asserts byte-for-byte parity — the load-bearing check that
swift-transformers' Unigram path tokenizes identically to the Python
tokenizer the ONNX model was trained against.

Build-time tool. Run after export_gliner_onnx.py (it loads the model
to get the exact tokenizer the ONNX graph expects).

Usage:
    python dump_tokenizer_fixture.py
"""
import json
import sys
from pathlib import Path

MODEL_ID = "urchade/gliner_small-v2.1"

# Probe strings: plain prose, proper nouns, punctuation, accented
# characters (exercises the normalizer), and explicit content — the
# tagger's actual use case is adult fiction.
PROBE_STRINGS = [
    "Chantal kissed Muriel.",
    "He drew Excalibur from the stone.",
    "She flew to Brussels on Tuesday morning.",
    "Dr. Marius Thorn arrived at the flat.",
    "\"Did you ever call Jacob back?\" she asked.",
    "The cathedral's bell rang twice.",
    "Her tongue traced the soft folds of her sex.",
    "café résumé naïve façade",
    "They had met at University that year and became fast friends.",
    "Muriel — her new lover — pressed against the shower wall.",
]


def main() -> int:
    try:
        from gliner import GLiNER
    except ImportError:
        print("error: `gliner` not installed — see export_gliner_onnx.py's docstring.")
        return 1

    repo_root = Path(__file__).resolve().parents[2]
    out_path = repo_root / "Tests/LoomCoreTests/Fixtures/gliner_tokenizer_fixture.json"

    print(f"loading {MODEL_ID} …", flush=True)
    model = GLiNER.from_pretrained(MODEL_ID)
    tok = model.data_processor.transformer_tokenizer
    print(f"tokenizer: {type(tok).__name__}")

    cases = []
    for text in PROBE_STRINGS:
        ids = tok(text)["input_ids"]
        cases.append({"text": text, "ids": ids})
        print(f"  {len(ids):3d} ids  {text!r}")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps({"cases": cases}, indent=2, ensure_ascii=False))
    print(f"\nwrote {len(cases)} cases → {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Dump a tokenizer-parity fixture for `NLICrossEncoderTests`.

The Swift cross-encoder must produce byte-identical `input_ids` and
`attention_mask` to the Python tokenizer the ONNX model was trained
against — otherwise the model's logits drift. This script generates a
JSON fixture of (premise, hypothesis) → expected tokenization that the
Swift fixture test pins against (mirrors the GLiNER tokenizer-fixture
pattern).

Run after `export_nli_onnx.py` has produced
`Sources/LoomCore/Resources/NLI/`.
"""
import json
import sys
from pathlib import Path


def main() -> int:
    repo_root = Path(__file__).resolve().parents[2]
    bundle = repo_root / "Sources/LoomCore/Resources/NLI"
    out_dir = repo_root / "Tests/LoomCoreTests/Fixtures/NLI"
    out_path = out_dir / "tokenizer_fixture.json"

    try:
        from transformers import AutoTokenizer
    except ImportError:
        print("error: transformers missing — see export_nli_onnx.py prereqs.")
        return 1

    tok = AutoTokenizer.from_pretrained(str(bundle))

    pairs = [
        # Identity — same string both sides.
        ("money has been going missing from the harbour fund",
         "money has been going missing from the harbour fund"),
        # Real attribute contradiction.
        ("Sael has dark hair", "Sael has close-cropped silver hair"),
        # Real timeline contradiction.
        ("King Bren died five winters ago", "King Bren died three winters ago"),
        # Unrelated pair (neutral).
        ("Cole's brother drowned two winters ago",
         "Cole has never entered the old church"),
        # Punctuation + apostrophe + multi-clause.
        ("Lirien knows the old King's death was a quiet poisoning.",
         "King Bren was poisoned."),
    ]

    cases = []
    for a, b in pairs:
        enc = tok(a, b, truncation=True)
        cases.append({
            "premise": a,
            "hypothesis": b,
            "input_ids": enc["input_ids"],
            "attention_mask": enc["attention_mask"],
        })

    out_dir.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps({"cases": cases}, indent=2))
    print(f"wrote {len(cases)} cases → {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Verify the exported NLI ONNX bundle runs and decodes correctly.

Loads model.onnx via ONNX Runtime + the bundled tokenizer, runs a
handful of world-fact pairs, and checks that real contradictions come
back `contradiction` and unrelated pairs `neutral` — i.e. the FP32 ONNX
export is faithful to the source model (§25 A0 probe).

Run after export_nli_onnx.py, from any venv with onnxruntime +
transformers installed.
"""
import sys
import json
from pathlib import Path

import numpy as np
import onnxruntime as ort
from transformers import AutoTokenizer


def main() -> int:
    repo_root = Path(__file__).resolve().parents[2]
    bundle = repo_root / "Sources/LoomCore/Resources/NLI"
    if not (bundle / "model.onnx").exists():
        print("error: no model.onnx — run export_nli_onnx.py first.")
        return 1

    id2label = {int(k): v.lower()
                for k, v in json.loads((bundle / "config.json").read_text())["id2label"].items()}
    tok = AutoTokenizer.from_pretrained(str(bundle))
    sess = ort.InferenceSession(str(bundle / "model.onnx"))
    input_names = {i.name for i in sess.get_inputs()}

    def nli(premise: str, hypothesis: str) -> str:
        enc = tok(premise, hypothesis, return_tensors="np", truncation=True)
        feed = {k: v for k, v in enc.items() if k in input_names}
        logits = sess.run(None, feed)[0][0]
        return id2label[int(np.argmax(logits))]

    # (expected, premise, hypothesis)
    cases = [
        ("contradiction", "the vault is on the fourteenth floor", "the vault is on the ninth floor"),
        ("contradiction", "Sael has dark hair", "Sael has close-cropped silver hair"),
        ("contradiction", "King Bren died five winters ago", "King Bren died three winters ago"),
        ("neutral", "Cole's brother drowned two winters ago", "Cole has never entered the old church"),
        ("neutral", "the lighthouse is north of the village", "Mara has green eyes"),
        ("entailment", "money has been going missing from the harbour fund",
         "money has been going missing from the harbour fund"),
    ]
    ok = 0
    for expected, p, h in cases:
        got = nli(p, h)
        match = got == expected
        ok += match
        print(f"  {'ok  ' if match else 'FAIL'} expected={expected:13} got={got:13}  {p[:34]!r}")
    print(f"\n{ok}/{len(cases)} cases as expected.")
    return 0 if ok == len(cases) else 1


if __name__ == "__main__":
    sys.exit(main())

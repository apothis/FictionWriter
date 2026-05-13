#!/usr/bin/env python3
"""
One-time validation: Swift FuncwordZEmbedder vs Python embed_path_e.

Reads PT-side E vectors from Tools/RagSpike/vectors.json and Swift-side
E vectors from Tools/RagSpike/MlxSpike/vectors_funcword_z_swift.json
(produced by `swift run RagSpike --funcword-z-dump`). Computes per-item
cosine + max-abs-diff. Threshold: cosine ≥ 0.999 across all 16 items.

Not part of the TestKit suite — that's hand-computed unit tests in
Phase5FuncwordZTests.swift. This script is the spike-style end-to-end
"the Swift port matches Python on the real fixture" gate.

Run from repo root:
    Tools/RagSpike/Python/.venv/bin/python3 Tools/RagSpike/MlxSpike/compare_funcword_z.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

REPO_ROOT = Path(__file__).resolve().parents[3]
PT_PATH = REPO_ROOT / "Tools/RagSpike/vectors.json"
SWIFT_PATH = REPO_ROOT / "Tools/RagSpike/MlxSpike/vectors_funcword_z_swift.json"


def load_path(json_path: Path, expected_prefix: str) -> dict[str, list[float]]:
    with open(json_path) as f:
        data = json.load(f)
    for p in data["paths"]:
        if p["path"].startswith(expected_prefix):
            return p["vectors"]
    raise SystemExit(f"no path starting with {expected_prefix} in {json_path}")


def cosine(a: np.ndarray, b: np.ndarray) -> float:
    na, nb = np.linalg.norm(a), np.linalg.norm(b)
    if na == 0 or nb == 0:
        return 0.0
    return float(np.dot(a, b) / (na * nb))


def main() -> int:
    pt = load_path(PT_PATH, "E-funcword-z")
    swift = load_path(SWIFT_PATH, "E-funcword-z-swift")

    ids = sorted(pt.keys(), key=lambda s: int(s))
    print(f"{'id':>5}  {'cosine':>10}  {'max-abs-diff':>14}  pass")
    print("-" * 50)
    all_pass = True
    cosines = []
    diffs = []
    for k in ids:
        a = np.array(pt[k], dtype=np.float64)
        b = np.array(swift[k], dtype=np.float64)
        if a.shape != b.shape:
            print(f"  {k:>3}  shape mismatch: PT {a.shape} vs Swift {b.shape}")
            all_pass = False
            continue
        c = cosine(a, b)
        d = float(np.max(np.abs(a - b)))
        ok = c >= 0.999
        all_pass = all_pass and ok
        cosines.append(c)
        diffs.append(d)
        print(f"  {k:>3}  {c:>10.6f}  {d:>14.6f}  {'✓' if ok else '✗'}")
    print()
    print(f"min cosine: {min(cosines):.6f}")
    print(f"mean cosine: {sum(cosines)/len(cosines):.6f}")
    print(f"max max-abs-diff: {max(diffs):.6f}")
    print()
    print("PASS" if all_pass else "FAIL")
    return 0 if all_pass else 1


if __name__ == "__main__":
    sys.exit(main())

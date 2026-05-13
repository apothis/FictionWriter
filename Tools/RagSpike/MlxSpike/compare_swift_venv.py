#!/usr/bin/env python3
"""
Phase 5 production venv-subprocess pivot validity check.

Compares vectors_swift_venv.json (Swift PythonStyleDistanceClient
spawning a subprocess → loading StyleDistance via sentence-transformers
→ sending embed requests through stdin/stdout JSON-line protocol)
against vectors.json's D-styledistance block (canonical Python output
from embed_offline.py, validated against PyTorch baseline at cosine
1.000000 in LOOM_MLX_PORT_SPIKE.md §8).

Both are the same model + library, so the only sources of drift are:
- Float32 vs Float64 rounding in JSON serialisation.
- Subprocess stdin/stdout text encoding (UTF-8 throughout; should
  be identical to the inline path).

Acceptance: cosine ≥ 0.999 across all 16 fixture items. Any drift
indicates a regression in the Swift-side subprocess plumbing.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

REPO_ROOT = Path(__file__).resolve().parents[3]
SWIFT_VENV = REPO_ROOT / "Tools/RagSpike/MlxSpike/vectors_swift_venv.json"
PYTHON_BASELINE = REPO_ROOT / "Tools/RagSpike/vectors.json"


def load_path(json_path: Path, prefix: str) -> dict[str, list[float]]:
    with open(json_path) as f:
        data = json.load(f)
    for p in data["paths"]:
        if p["path"].startswith(prefix):
            return p["vectors"]
    raise SystemExit(f"no path starting with {prefix} in {json_path}")


def cosine(a: np.ndarray, b: np.ndarray) -> float:
    na, nb = np.linalg.norm(a), np.linalg.norm(b)
    if na == 0 or nb == 0:
        return 0.0
    return float(np.dot(a, b) / (na * nb))


def main() -> int:
    if not SWIFT_VENV.exists():
        print(f"FATAL: {SWIFT_VENV} missing — run `swift run RagSpike --venv-smoke` first")
        return 1
    if not PYTHON_BASELINE.exists():
        print(f"FATAL: {PYTHON_BASELINE} missing — run embed_offline.py first")
        return 1

    swift = load_path(SWIFT_VENV, "D-styledistance-swift-venv")
    python = load_path(PYTHON_BASELINE, "D-styledistance")

    ids = sorted(swift.keys(), key=lambda s: int(s))
    print(f"{'id':>5}  {'cosine':>10}  {'max-abs-diff':>14}  pass")
    print("-" * 50)
    all_pass = True
    cosines = []
    diffs = []
    for k in ids:
        if k not in python:
            print(f"  {k:>3}  MISSING IN PYTHON")
            all_pass = False
            continue
        a = np.array(swift[k], dtype=np.float64)
        b = np.array(python[k], dtype=np.float64)
        c = cosine(a, b)
        d = float(np.max(np.abs(a - b)))
        ok = c >= 0.999
        all_pass = all_pass and ok
        cosines.append(c)
        diffs.append(d)
        print(f"  {k:>3}  {c:>10.6f}  {d:>14.6f}  {'✓' if ok else '✗'}")
    print()
    if cosines:
        print(f"min cosine: {min(cosines):.6f}")
        print(f"mean cosine: {sum(cosines)/len(cosines):.6f}")
        print(f"max max-abs-diff: {max(diffs):.6f}")
    print()
    print("PASS" if all_pass else "FAIL")
    return 0 if all_pass else 1


if __name__ == "__main__":
    sys.exit(main())

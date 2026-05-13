#!/usr/bin/env python3
"""
LOOM_MLX_PORT_SPIKE numerical-validation gate.

Loads PyTorch StyleDistance vectors from Tools/RagSpike/vectors.json
(produced by embed_offline.py) and MLX-converted vectors from
Tools/RagSpike/MlxSpike/vectors_mlx.json, computes per-item cosine
similarity + max-abs-diff, reports pass/fail against the
LOOM_MLX_PORT_SPIKE §1 acceptance bar (cosine ≥ 0.999 across all 16
items).

Run from repo root:
    Tools/RagSpike/Python/.venv/bin/python3 Tools/RagSpike/MlxSpike/compare.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

REPO_ROOT = Path(__file__).resolve().parents[3]
PT_PATH = REPO_ROOT / "Tools/RagSpike/vectors.json"
MLX_PATH = REPO_ROOT / "Tools/RagSpike/MlxSpike/vectors_mlx.json"

THRESHOLD = 0.999


def load_path(json_path: Path, expected_path_prefix: str) -> dict[str, list[float]]:
    with open(json_path) as f:
        data = json.load(f)
    for p in data["paths"]:
        if p["path"].startswith(expected_path_prefix):
            return p["vectors"]
    raise SystemExit(f"no path starting with {expected_path_prefix} in {json_path}")


def cosine(a: np.ndarray, b: np.ndarray) -> float:
    na = np.linalg.norm(a)
    nb = np.linalg.norm(b)
    if na == 0 or nb == 0:
        return 0.0
    return float(np.dot(a, b) / (na * nb))


def main() -> int:
    pt = load_path(PT_PATH, "D-styledistance")
    mlx = load_path(MLX_PATH, "D-styledistance-mlx")

    ids = sorted(pt.keys(), key=lambda s: int(s))
    print(f"{'id':>5}  {'cosine':>10}  {'max-abs-diff':>14}  pass")
    print("-" * 50)
    all_pass = True
    cosines = []
    max_diffs = []
    for k in ids:
        a = np.array(pt[k], dtype=np.float32)
        b = np.array(mlx[k], dtype=np.float32)
        if a.shape != b.shape:
            print(f"  shape mismatch on id {k}: PT {a.shape} vs MLX {b.shape}")
            all_pass = False
            continue
        c = cosine(a, b)
        diff = float(np.max(np.abs(a - b)))
        ok = c >= THRESHOLD
        all_pass = all_pass and ok
        cosines.append(c)
        max_diffs.append(diff)
        flag = "✓" if ok else "✗"
        print(f"  {k:>3}  {c:>10.6f}  {diff:>14.6f}  {flag}")

    print("")
    print(f"min cosine:  {min(cosines):.6f}")
    print(f"mean cosine: {sum(cosines)/len(cosines):.6f}")
    print(f"max max-abs-diff: {max(max_diffs):.6f}")
    print(f"threshold: {THRESHOLD}")
    print("")
    if all_pass:
        print("GATE 1 (numerical): PASS")
        return 0
    print("GATE 1 (numerical): FAIL")
    return 1


if __name__ == "__main__":
    sys.exit(main())

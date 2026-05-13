#!/usr/bin/env python3
"""
LOOM_MLX_PORT_SPIKE end-to-end behavioural gate.

Loads PyTorch D + MLX-D + E vectors from Tools/RagSpike/vectors.json
(after merge) plus the fixture. For each query, ranks excerpts by
cosine similarity and computes NDCG@3 + style-vs-topic preference per
path. Reports a side-by-side table for D-pt vs D-mlx — the spike
passes if per-query NDCG@3 + preference match within ±0.05 AND
top-3 ranking is identical for at least 3 of 4 queries.

Mirrors the Swift scoring in RankingMetrics.swift; pinned against
the same hand-verified values during S1.

Run from repo root:
    Tools/RagSpike/Python/.venv/bin/python3 Tools/RagSpike/MlxSpike/score_e2e.py
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import numpy as np

REPO_ROOT = Path(__file__).resolve().parents[3]
FIXTURE_PATH = REPO_ROOT / "Tests/LoomCoreTests/Fixtures/RagSpike/fixture.json"
VECTORS_PATH = REPO_ROOT / "Tools/RagSpike/vectors.json"


def cosine(a: np.ndarray, b: np.ndarray) -> float:
    na, nb = np.linalg.norm(a), np.linalg.norm(b)
    if na == 0 or nb == 0:
        return 0.0
    return float(np.dot(a, b) / (na * nb))


def rank_excerpts(query_vec: np.ndarray, excerpts: list[tuple[int, np.ndarray]]) -> list[int]:
    scored = [(eid, cosine(query_vec, v)) for eid, v in excerpts]
    scored.sort(key=lambda x: (-x[1], x[0]))  # tie-break ascending id
    return [eid for eid, _ in scored]


def ndcg_at_k(gold: set[int], ranking: list[int], k: int = 3) -> float:
    if not gold or not ranking or k <= 0:
        return 0.0
    eff = min(k, len(ranking))
    dcg = sum(1.0 / math.log2(i + 2) for i, eid in enumerate(ranking[:eff]) if eid in gold)
    ideal_relevant = min(eff, len(gold))
    idcg = sum(1.0 / math.log2(i + 2) for i in range(ideal_relevant))
    return dcg / idcg if idcg > 0 else 0.0


def style_topic_pref(top3: list[int], style_match: set[int], topic_match: set[int]) -> float:
    topic_only = topic_match - style_match
    s = sum(1 for x in top3 if x in style_match)
    t = sum(1 for x in top3 if x in topic_only)
    return (s - t) / 3.0


def main() -> int:
    with open(FIXTURE_PATH) as f:
        fixture = json.load(f)
    with open(VECTORS_PATH) as f:
        vectors_data = json.load(f)

    # Build {path_name: {id: vec}}
    paths: dict[str, dict[int, np.ndarray]] = {}
    for p in vectors_data["paths"]:
        paths[p["path"]] = {int(k): np.array(v, dtype=np.float32) for k, v in p["vectors"].items()}

    print(f"Available paths: {list(paths.keys())}")
    print()

    # Per-query × per-path scoring
    rows: list[tuple[str, str, float, float, list[int]]] = []
    for query in fixture["queries"]:
        q_style = query["style"]
        q_topic = query["topic"]
        style_match = {e["id"] for e in fixture["excerpts"] if e["style"] == q_style}
        topic_match = {e["id"] for e in fixture["excerpts"] if e["topic"] == q_topic}

        for path_name in paths:
            vecs = paths[path_name]
            if query["id"] not in vecs:
                continue
            q_vec = vecs[query["id"]]
            excerpt_pairs = [(e["id"], vecs[e["id"]]) for e in fixture["excerpts"] if e["id"] in vecs]
            ranking = rank_excerpts(q_vec, excerpt_pairs)
            ndcg = ndcg_at_k(style_match, ranking, k=3)
            pref = style_topic_pref(ranking[:3], style_match, topic_match)
            rows.append((f"Q{query['id']}", path_name, ndcg, pref, ranking[:3]))

    # Per-query side-by-side
    print(f"{'query':>5}  {'path':<25}  {'NDCG@3':>7}  {'pref':>7}  top3")
    print("-" * 75)
    for q, p, n, pr, t3 in rows:
        print(f"  {q:>3}  {p:<25}  {n:>7.3f}  {pr:>+7.3f}  {t3}")

    # Aggregate per path
    agg: dict[str, list[tuple[float, float]]] = {}
    for q, p, n, pr, _ in rows:
        agg.setdefault(p, []).append((n, pr))
    print()
    print("=== Aggregate (mean over 4 queries) ===")
    print(f"  {'path':<25}  {'NDCG@3':>7}  {'pref':>7}")
    for p, vals in agg.items():
        mn = sum(v[0] for v in vals) / len(vals)
        mp = sum(v[1] for v in vals) / len(vals)
        print(f"  {p:<25}  {mn:>7.3f}  {mp:>+7.3f}")

    # D vs D-mlx side-by-side
    print()
    print("=== Behavioural gate: D-pytorch vs D-mlx ===")
    pt_rows = {r[0]: r for r in rows if r[1] == "D-styledistance"}
    mlx_rows = {r[0]: r for r in rows if r[1] == "D-styledistance-mlx"}
    all_pass = True
    identical_top3 = 0
    for q in pt_rows:
        pt = pt_rows[q]
        mlx = mlx_rows[q]
        ndcg_diff = abs(pt[2] - mlx[2])
        pref_diff = abs(pt[3] - mlx[3])
        same_top3 = pt[4] == mlx[4]
        if same_top3:
            identical_top3 += 1
        ok = ndcg_diff <= 0.05 and pref_diff <= 0.05
        all_pass = all_pass and ok
        print(f"  {q}  ΔNDCG={ndcg_diff:.3f}  Δpref={pref_diff:.3f}  same_top3={'YES' if same_top3 else 'NO'}  PT={pt[4]} MLX={mlx[4]}")
    print()
    print(f"identical top3 across queries: {identical_top3} / 4 (need ≥ 3)")
    print(f"all ΔNDCG ≤ 0.05 + Δpref ≤ 0.05: {all_pass}")
    print()
    if all_pass and identical_top3 >= 3:
        print("GATE 2 (behavioural): PASS")
        return 0
    print("GATE 2 (behavioural): FAIL")
    return 1


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""
Phase 5 RAG-for-style spike — offline embedding script for Paths D + E.

Reads `Tests/LoomCoreTests/Fixtures/RagSpike/fixture.json`, embeds every
excerpt + query via:
  - Path D: purpose-built style embedder. StyleDistance (primary) with
    Wegmann (fallback) and LUAR (second fallback) per LOOM_RAG_SPIKE §3.
  - Path E: non-neural function-word z-score baseline (Burrows' Delta
    flavoured), used as a diagnostic sanity floor per §7. Implemented
    inline (~30 LOC of numpy) rather than via `faststylometry` so the
    output vector shape is uniform with the neural paths and the Swift
    runner can cosine-rank without special-casing.

Writes `Tools/RagSpike/vectors.json` with the schema the Swift spike
runner consumes alongside its own Kobold/Ollama responses.

Run from the repo root:
    python3 Tools/RagSpike/Python/embed_offline.py

Spike-only — not a production sidecar. If Path D wins, the Phase 5
production-deployment decision (bundled venv vs MLX port vs other) is
out of scope here (see LOOM_RAG_SPIKE §7 PROCEED branches + §9 #5).
"""

from __future__ import annotations

import json
import re
import sys
from collections import Counter
from pathlib import Path
from typing import Iterable

import numpy as np

REPO_ROOT = Path(__file__).resolve().parents[3]
FIXTURE_PATH = REPO_ROOT / "Tests/LoomCoreTests/Fixtures/RagSpike/fixture.json"
OUTPUT_PATH = REPO_ROOT / "Tools/RagSpike/vectors.json"


# --------------------------------------------------------------------- D

D_CANDIDATES = [
    ("StyleDistance/styledistance", "D-styledistance"),
    ("AnnaWegmann/Style-Embedding", "D-wegmann"),
]


def embed_path_d(texts: list[str]) -> tuple[str, str, list[list[float]]]:
    """Try each Path D candidate in order; return the first that loads
    and produces non-degenerate vectors. Returns (model_id, path_id,
    vectors)."""
    from sentence_transformers import SentenceTransformer

    last_err: Exception | None = None
    for model_id, path_id in D_CANDIDATES:
        try:
            print(f"[D] loading {model_id}...", flush=True)
            model = SentenceTransformer(model_id, trust_remote_code=True)
            print(f"[D] encoding {len(texts)} texts via {model_id}...", flush=True)
            vectors = model.encode(
                texts,
                normalize_embeddings=True,
                show_progress_bar=False,
                convert_to_numpy=True,
            )
            # Degenerate-output sanity: any NaN/Inf, or all vectors
            # identical, means the model didn't actually score the
            # texts. Fall through to the next candidate.
            if not np.isfinite(vectors).all():
                print(f"[D] {model_id} produced non-finite values; trying fallback", flush=True)
                continue
            if vectors.std(axis=0).max() < 1e-6:
                print(f"[D] {model_id} produced near-uniform output; trying fallback", flush=True)
                continue
            print(f"[D] {model_id} OK: dim={vectors.shape[1]}", flush=True)
            return model_id, path_id, vectors.tolist()
        except Exception as e:  # noqa: BLE001
            last_err = e
            print(f"[D] {model_id} failed: {e}; trying fallback", flush=True)
            continue

    raise RuntimeError(
        f"All Path D candidates failed. Last error: {last_err}. "
        f"Verify `sentence-transformers` install and HuggingFace cache."
    )


# --------------------------------------------------------------------- E

WORD_RE = re.compile(r"[a-z]+")


def tokenise(text: str) -> list[str]:
    return WORD_RE.findall(text.lower())


def embed_path_e(texts: list[str], top_n: int = 150) -> list[list[float]]:
    """Function-word z-score vector per text — the input to Burrows'
    Delta. The top-N most frequent tokens across the corpus capture
    almost entirely function words for English prose at this corpus
    size; z-scoring per token across the corpus removes corpus-level
    frequency bias.

    Output: N-dim vector per text. Cosine over these slots into the
    same scoring pipeline as the neural paths."""
    token_lists = [tokenise(t) for t in texts]
    counter: Counter[str] = Counter()
    for tokens in token_lists:
        counter.update(tokens)
    top_tokens = [tok for tok, _ in counter.most_common(top_n)]

    # Per-text relative frequency over the top-N vocabulary.
    rel = np.zeros((len(texts), len(top_tokens)), dtype=np.float64)
    for i, tokens in enumerate(token_lists):
        if not tokens:
            continue
        local = Counter(tokens)
        total = sum(local[t] for t in top_tokens) or 1
        for j, tok in enumerate(top_tokens):
            rel[i, j] = local[tok] / total

    # z-score per dimension across the corpus.
    mean = rel.mean(axis=0)
    std = rel.std(axis=0)
    std = np.where(std < 1e-9, 1.0, std)  # guard divide-by-zero
    z = (rel - mean) / std

    return z.tolist()


# --------------------------------------------------------------------- I/O


def load_fixture() -> tuple[list[int], list[str]]:
    with open(FIXTURE_PATH) as f:
        data = json.load(f)
    ids: list[int] = []
    texts: list[str] = []
    for ex in data["excerpts"]:
        ids.append(ex["id"])
        texts.append(ex["text"])
    for q in data["queries"]:
        ids.append(q["id"])
        texts.append(q["text"])
    return ids, texts


def main() -> int:
    print(f"[fixture] reading {FIXTURE_PATH}", flush=True)
    ids, texts = load_fixture()
    print(f"[fixture] {len(ids)} items ({len([i for i in ids if i < 100])} excerpts + {len([i for i in ids if i >= 100])} queries)", flush=True)

    paths_out: list[dict] = []

    # Path D
    try:
        model_id, path_id, d_vectors = embed_path_d(texts)
        paths_out.append({
            "path": path_id,
            "model": model_id,
            "dim": len(d_vectors[0]),
            "vectors": {str(ids[i]): d_vectors[i] for i in range(len(ids))},
        })
    except Exception as e:  # noqa: BLE001
        print(f"[D] FATAL: {e}", file=sys.stderr, flush=True)
        # Continue — Path E doesn't depend on D. The Swift runner will
        # see D missing from vectors.json and report the gap.

    # Path E
    print("[E] computing function-word z-score vectors (top-150 tokens)...", flush=True)
    e_vectors = embed_path_e(texts, top_n=150)
    paths_out.append({
        "path": "E-funcword-z",
        "model": "inline/top150-funcword-zscore",
        "dim": len(e_vectors[0]),
        "vectors": {str(ids[i]): e_vectors[i] for i in range(len(ids))},
    })
    print(f"[E] OK: dim={len(e_vectors[0])}", flush=True)

    output = {
        "version": 1,
        "fixture_sha": "",  # filled by Swift runner if it cares about drift
        "paths": paths_out,
    }
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT_PATH, "w") as f:
        json.dump(output, f)
    print(f"[out] wrote {OUTPUT_PATH} ({len(paths_out)} paths)", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())

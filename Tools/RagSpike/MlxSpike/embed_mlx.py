#!/usr/bin/env python3
"""
LOOM_MLX_PORT_SPIKE — Phase 5 sub-spike, half-day MLX validity check.

Embeds the RagSpike fixture via the MLX-converted StyleDistance model.
Writes Tools/RagSpike/MlxSpike/vectors_mlx.json — same schema as the
existing Tools/RagSpike/vectors.json, suitable for direct substitution
into RagSpike --corpus by relabeling the path entry.

Pipeline mirrors sentence-transformers' canonical pooling (per
StyleDistance's 1_Pooling/config.json): mean over tokens with attention-
mask weighting, then L2-normalize. The mlx-embeddings model's `out[1]`
pooled output is NOT used — that's the BERT-style [CLS] pooler which
sentence-transformers explicitly bypasses.

Run from repo root:
    Tools/RagSpike/Python/.venv/bin/python3 Tools/RagSpike/MlxSpike/embed_mlx.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import mlx.core as mx
from mlx_embeddings import load

REPO_ROOT = Path(__file__).resolve().parents[3]
FIXTURE_PATH = REPO_ROOT / "Tests/LoomCoreTests/Fixtures/RagSpike/fixture.json"
MLX_MODEL_PATH = REPO_ROOT / "Tools/RagSpike/MlxSpike/models/styledistance-mlx"
OUTPUT_PATH = REPO_ROOT / "Tools/RagSpike/MlxSpike/vectors_mlx.json"


def embed_one(model, tokenizer, text: str) -> list[float]:
    toks = tokenizer.encode_plus(
        text,
        return_tensors="mlx",
        padding=True,
        truncation=True,
        max_length=512,
    )
    input_ids = toks["input_ids"]
    attention_mask = toks["attention_mask"]
    out = model(input_ids, attention_mask=attention_mask)
    # out[0]: token hidden states, shape (1, T, 768)
    token_embeddings = out[0]
    # Mean-pool with attention-mask weighting.
    mask = attention_mask[..., None].astype(mx.float32)  # (1, T, 1)
    summed = mx.sum(token_embeddings * mask, axis=1)     # (1, 768)
    counts = mx.sum(mask, axis=1)                         # (1, 1)
    pooled = summed / counts                              # (1, 768)
    # L2-normalize.
    norm = mx.sqrt(mx.sum(pooled * pooled, axis=-1, keepdims=True))
    pooled = pooled / norm
    # Materialise (MLX is lazy) + flatten to a Python list of floats.
    vec = pooled[0].tolist()
    return [float(x) for x in vec]


def main() -> int:
    print(f"[mlx] loading {MLX_MODEL_PATH}...", flush=True)
    model, tokenizer = load(str(MLX_MODEL_PATH))

    print(f"[fixture] reading {FIXTURE_PATH}", flush=True)
    with open(FIXTURE_PATH) as f:
        fixture = json.load(f)

    vectors: dict[str, list[float]] = {}
    items = fixture["excerpts"] + fixture["queries"]
    for item in items:
        vec = embed_one(model, tokenizer, item["text"])
        vectors[str(item["id"])] = vec
        print(f"  embedded id={item['id']} ({item['style']}/{item['topic']}, NSFW={item['nsfw']}) dim={len(vec)}", flush=True)

    output = {
        "version": 1,
        "paths": [{
            "path": "D-styledistance-mlx",
            "model": "StyleDistance/styledistance (mlx-embeddings fp16 conversion)",
            "dim": len(next(iter(vectors.values()))),
            "vectors": vectors,
        }],
    }
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT_PATH, "w") as f:
        json.dump(output, f)
    print(f"[out] wrote {OUTPUT_PATH} ({len(vectors)} vectors)", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())

---
name: LOOM_MLX_PORT_SPIKE
description: Phase 5 production sub-spike — validate StyleDistance MLX conversion before committing
type: project
---

# LOOM_MLX_PORT_SPIKE — half-day MLX conversion validity check

> **Date:** 2026-05-13. **Status:** plan only. **Scope:** half-day sub-spike inside Phase 5 production scope-lock #1 ([`LOOM_PLAN.md`](LOOM_PLAN.md) §5 Phase 5).
>
> The [Phase 5 RAG spike](LOOM_RAG_SPIKE.md) §13 picked **Path D StyleDistance + Path E function-word z-score** as the production retrieval architecture. Production scope-lock #1 was *"StyleDistance deployment: bundled venv vs MLX port."* Pre-implementation research (2026-05-13) surfaced lopsided numbers favouring MLX: ~1 GB venv bundle vs ~30 MB MLX code, ~80-150 ms PyTorch CPU latency vs ~15-40 ms MLX, in-process Swift via `MLXEmbedders` vs HTTP sidecar lifecycle. The single risk: StyleDistance has no direct MLX port; conversion via [`mlx-embeddings`](https://github.com/Blaizzy/mlx-embeddings) might drift numerically.
>
> This spike falsifies that risk in ~4 hours. If conversion is numerically faithful and the re-run §13 numbers don't shift meaningfully, Phase 5 production commits to MLX. If conversion drifts, fall back to venv with eyes open.

## 1. Falsifiable hypothesis

> **Hypothesis**: `mlx-embeddings.convert` produces an MLX-loadable StyleDistance model whose embeddings agree with the canonical `sentence-transformers` outputs at cosine-similarity ≥ 0.999 across all 16 [RAG spike fixture](Tests/LoomCoreTests/Fixtures/RagSpike/fixture.json) items, AND whose per-query NDCG@3 + style-vs-topic preference numbers replicate [`LOOM_RAG_SPIKE.md`](LOOM_RAG_SPIKE.md) §13 within ±0.05.

Both gates must pass. Cosine agreement is the numerical gate; §13 replication is the end-to-end behavioural gate — a path can have ≥ 0.999 cosine agreement and still produce subtly different rankings if the cosines drift on the *one pair that mattered*.

## 2. Why this matters

The Phase 5 production architecture decision (MLX vs venv) is downstream of the conversion-validity question. Without the spike, we'd either:

- (a) Commit to MLX and discover post-implementation that conversion drifts, losing a week to rework.
- (b) Commit to venv defensively, eating ~1 GB bundle + sidecar lifecycle + a day of code signing forever.

The spike's cost is bounded (4 hours) and informs the production scope-lock cleanly.

## 3. Methodology

### 3.1 Conversion

```bash
# In the existing Tools/RagSpike/Python venv
pip install mlx-embeddings
python -m mlx_embeddings.convert \
  --hf-path StyleDistance/styledistance \
  --mlx-path Tools/RagSpike/MlxSpike/models/styledistance-mlx
```

Produces an MLX-format directory with weights (fp16 default) + tokeniser + config.

### 3.2 Numerical validation

`Tools/RagSpike/MlxSpike/embed_mlx.py` — load the converted model via `mlx-embeddings`, embed all 16 fixture items (12 excerpts + 4 queries), normalise (mean-pool + L2), write `vectors_mlx.json` mirroring the existing [`vectors.json`](Tools/RagSpike/Python/embed_offline.py) schema.

`Tools/RagSpike/MlxSpike/compare.py` — load PyTorch vectors from [`vectors.json`](Tools/RagSpike/Python/embed_offline.py)'s `D-styledistance` block; load MLX vectors from `vectors_mlx.json`; compute per-item:

- **Cosine similarity** between PyTorch and MLX embedding for the same text. ≥ 0.999 = pass.
- **Max absolute difference** across vector components. Reported as a check on dynamic-range divergence — fp32 vs fp16 conversion typically gives max-abs-diff ≤ 1e-3.

Reports a per-item table + aggregate pass/fail.

### 3.3 End-to-end behavioural validation

Substitute the MLX vectors for Path D in a re-run of [`RagSpike --corpus`](Tools/RagSpike/main.swift):

- Modify `vectors.json` to label the MLX path as `D-styledistance-mlx`.
- Run `swift run RagSpike --corpus`.
- Compare against the saved [`Tools/RagSpike/last-run/rankings.json`](Tools/RagSpike/last-run/) from the §13 baseline.
- Pass: per-query NDCG@3 differs by < 0.05; per-query preference differs by < 0.05; top-3 ranking identical for at least 3 of 4 queries.

### 3.4 Acceptance bar

Both gates pass → **PROCEED with MLX as the Phase 5 production D backend.** Phase 5 production work begins with adding `MLXEmbedders` to the Swift package and porting the embedding call site.

Either gate fails → **FALL BACK to bundled venv** for D. Document the failure mode in §6 of this doc. Phase 5 production scope-lock #1 closes against venv.

## 4. Out of scope

- **Swift wiring via `MLXEmbedders`.** That's Phase 5 production proper, not the spike. The spike validates conversion; Swift wiring is downstream once the path is committed.
- **Quantisation comparison.** mlx-embeddings supports fp16 / 8-bit / 4-bit. The spike uses default (fp16). 4-bit quantisation experiments belong in Phase 5 production when bundle-size optimisation comes up.
- **Wegmann fallback porting.** Only relevant if StyleDistance quality disappoints in production use, which Phase 5 wouldn't know yet.
- **Tokeniser identity check.** `mlx-embeddings.convert` carries the tokeniser verbatim. The cosine agreement check catches tokeniser drift implicitly — if tokens differ, embeddings differ.

## 5. Risks

- **mlx-embeddings install on Python 3.9.** The existing venv is 3.9.6. MLX wheels support 3.9+; this should work but is the first thing to verify.
- **MLX model load API stability.** mlx-embeddings is a young library; the load/encode API may have shifted between docs and current release. Mitigation: read the actual installed version's docstrings if the documented API doesn't match.
- **Pooling head divergence.** The headline risk per the research pass: sentence-transformers applies mean-pool + L2 in a specific order; the MLX conversion may apply them slightly differently. Catches as cosine-agreement failure if present.

## 6. Sections to append post-spike

- **§7 Conversion results** — what the `mlx-embeddings.convert` command actually emitted.
- **§8 Numerical comparison table** — per-item cosine + max-abs-diff.
- **§9 End-to-end re-run table** — per-query NDCG@3 / preference / top-3 ranking, MLX vs PyTorch baseline.
- **§10 Verdict** — PROCEED / FALL BACK, and the Phase 5 production scope-lock #1 closeout.

---

## 7. Conversion results — 2026-05-13

`mlx-embeddings 0.0.1` does not support `model_type: "roberta"` directly — its `models/` directory ships only `bert.py` and `xlm_roberta.py`. The research agent's claim that it supports "any BERT/RoBERTa-based embedding model" was true *architecturally* but not *out-of-the-box*: model-type dispatch in `utils.py` checks the literal `model_type` string. Workaround:

1. Downloaded StyleDistance via `huggingface_hub.snapshot_download`.
2. Copied the cached snapshot to `Tools/RagSpike/MlxSpike/models/styledistance-patched/`.
3. Patched `config.json`: `"model_type": "roberta"` → `"model_type": "xlm-roberta"`, `"architectures": ["XLMRobertaModel"]`. The XLM-RoBERTa MLX implementation is architecturally identical (same layer count, same hidden_size, same positional-embedding scheme, same `pad_token_id=1`) — only the tokeniser differs in canonical XLM-R, but we keep StyleDistance's own RoBERTa BPE tokeniser via the model files.
4. Ran `mlx_embeddings.convert(hf_path=..., dtype='float16')`.

Also patched a hub-API drift in `mlx_embeddings/utils.py:16` — the package imports `from huggingface_hub.utils._errors import RepositoryNotFoundError`, but hub ≥ 0.26 moved this to `huggingface_hub.errors`. One-line guarded import (try/except), applied in-venv.

Output: `Tools/RagSpike/MlxSpike/models/styledistance-mlx/`, 242 MB total (model.safetensors fp16 = 249 MB by itself).

## 8. Numerical comparison (`compare.py`) — PASS

Per-item cosine similarity between PyTorch sentence-transformers output and MLX-converted output, over all 16 fixture items (12 excerpts + 4 queries):

```
   id      cosine    max-abs-diff  pass
--------------------------------------------------
    1    1.000000        0.000012  ✓
    2    1.000000        0.000008  ✓
    3    1.000000        0.000011  ✓
    4    1.000000        0.000016  ✓
    5    1.000000        0.000007  ✓
    6    1.000000        0.000009  ✓
    7    1.000000        0.000023  ✓
    8    1.000000        0.000007  ✓
    9    1.000000        0.000034  ✓
   10    1.000000        0.000004  ✓
   11    1.000000        0.000006  ✓
   12    1.000000        0.000077  ✓
  101    1.000000        0.000009  ✓
  102    1.000000        0.000008  ✓
  103    1.000000        0.000012  ✓
  104    1.000000        0.000008  ✓

min cosine:  1.000000
mean cosine: 1.000000
max max-abs-diff: 0.000077
```

Threshold was cosine ≥ 0.999; actual is 1.000000 on every item (rounded to 6dp). Max element-wise difference is 7.7e-5 — pure fp16 rounding noise. **The conversion is essentially bit-faithful.**

## 9. End-to-end behavioural re-run (`score_e2e.py`) — PASS

Merged MLX vectors into `vectors.json` alongside the PyTorch baseline, scored both paths against the [LOOM_RAG_SPIKE](LOOM_RAG_SPIKE.md) §5 metrics, side-by-side per query:

```
  Q101  ΔNDCG=0.000  Δpref=0.000  same_top3=YES  PT=[1, 3, 2] MLX=[1, 3, 2]
  Q102  ΔNDCG=0.000  Δpref=0.000  same_top3=YES  PT=[4, 5, 7] MLX=[4, 5, 7]
  Q103  ΔNDCG=0.000  Δpref=0.000  same_top3=YES  PT=[9, 7, 8] MLX=[9, 7, 8]
  Q104  ΔNDCG=0.000  Δpref=0.000  same_top3=YES  PT=[12, 11, 1] MLX=[12, 11, 1]

identical top3 across queries: 4 / 4 (need ≥ 3)
all ΔNDCG ≤ 0.05 + Δpref ≤ 0.05: True
```

Aggregate (mean over 4 queries, mirroring [LOOM_RAG_SPIKE §13.1](LOOM_RAG_SPIKE.md)):

| Path                  | NDCG@3 | preference |
|-----------------------|--------|------------|
| D-styledistance (PyTorch) | 0.883  | +0.833     |
| D-styledistance-mlx       | 0.883  | +0.833     |
| E-funcword-z              | 0.883  | +0.750     |

Threshold was ΔNDCG ≤ 0.05 AND Δpref ≤ 0.05 AND ≥ 3 of 4 queries with identical top-3. Actual: all four queries produced *identical* top-3 rankings; all deltas zero to 3dp. The MLX path is operationally indistinguishable from the PyTorch baseline.

## 10. Verdict — PROCEED with MLX

**Phase 5 production scope-lock #1 closes against MLX.** Both gates pass with margin:

- Numerical: cosine 1.000000 across all 16 items vs 0.999 threshold.
- Behavioural: 4 of 4 identical top-3 rankings vs 3 of 4 threshold; zero NDCG/preference drift.

The conversion is faithful enough that the production decision becomes "MLX or MLX-with-quantisation" rather than "MLX or venv." The venv fallback is no longer load-bearing.

**Phase 5 production architecture lock:**

- **Backend:** MLX via `MLXEmbedders` from [`ml-explore/mlx-swift-lm`](https://github.com/ml-explore/mlx-swift-lm). In-process Swift; no localhost HTTP sidecar; no Python interpreter in the .app bundle; no separate code-signing pipeline for ML-stack native libs.
- **Weights:** ship `Tools/RagSpike/MlxSpike/models/styledistance-mlx/` (242 MB fp16) as a bundled resource OR download on first use into Application Support. Decide at Phase 5 production design lock — fp16 is comfortable for a fiction-writer app size profile, but on-demand download avoids gating distribution on .app payload size.
- **Tokenisation:** `tokenizer.json` (3.5 MB) bundles alongside weights.
- **Quantisation experiment** (Phase 5 optional): mlx-embeddings supports 4-bit; that would cut weights from 242 MB to ~125 MB at some embedding-quality cost. Worth a follow-on validity check (same `compare.py` gate) if bundle size matters.

**Carry-forwards for Phase 5 production:**

1. The model-type-patching workaround (§7.3) needs to be reproducible in the production weight-prep pipeline. Either upstream a `--allow-roberta-as-xlm-roberta` flag to `mlx-embeddings` (real fix), or document the patched-config step + ship the patched `config.json` alongside the weights.
2. The hub-API import patch (§7) is a venv-local hack. Either pin `mlx-embeddings` to a version that fixes the import (when one releases) or vendor `mlx_embeddings/utils.py` in-tree with the patch applied.
3. `MLXEmbedders` Swift wiring is a Phase 5 production task. Pattern: load model + tokeniser at app launch via Swift, call `encode(text:)` returning `[Float]`, wrap in `EmbeddingClient` protocol per [LOOM_RAG_SPIKE.md §13.6](LOOM_RAG_SPIKE.md) graduates list.

## 11. References

- [LOOM_RAG_SPIKE.md §13.6](LOOM_RAG_SPIKE.md) — Phase 5 architecture decision (D + E hybrid).
- [LOOM_PLAN.md §5 Phase 5](LOOM_PLAN.md) — scope-lock #1.
- [Blaizzy/mlx-embeddings](https://github.com/Blaizzy/mlx-embeddings) — conversion tool used.
- [ml-explore/mlx-swift-lm — MLXEmbedders](https://github.com/ml-explore/mlx-swift-lm) — Phase 5 production Swift runtime.
- [StyleDistance model card](https://huggingface.co/StyleDistance/styledistance) — base PyTorch model.
- [WWDC25 session 298](https://developer.apple.com/videos/play/wwdc2025/298/) — Apple's recommended MLX pattern.

## 7. References

- [LOOM_RAG_SPIKE.md §13.6](LOOM_RAG_SPIKE.md) — Phase 5 architecture decision (D + E hybrid).
- [LOOM_PLAN.md §5 Phase 5](LOOM_PLAN.md) — scope-lock #1.
- [Blaizzy/mlx-embeddings](https://github.com/Blaizzy/mlx-embeddings) — primary conversion tool.
- [taylorai/mlx_embedding_models](https://github.com/taylorai/mlx_embedding_models) — secondary option if Blaizzy's fails.
- [ml-explore/mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) — `MLXEmbedders` Swift runtime; used in Phase 5 production proper, not this spike.
- [StyleDistance model card](https://huggingface.co/StyleDistance/styledistance) — RoBERTa-base architecture, mean-pool + L2.
- [WWDC25 session 298](https://developer.apple.com/videos/play/wwdc2025/298/) — Apple's recommended MLX pattern for in-process ML on Apple Silicon.

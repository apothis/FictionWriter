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

## 10. Verdict — PROCEED with MLX [SUPERSEDED 2026-05-13 BY §12]

> **Status update:** MLX was the right choice on paper but the runtime requires full Xcode (for the `metal` compiler), which the user's machine doesn't have and can't fit (29 GB free, 87% full). §12 below documents the production pivot to a Python subprocess; the MLX work is preserved in git history. The §10 verdict + §11 references remain authoritative for the conversion + numerical validation; only the deployment path changed.


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

## 12. Production pivot — Python subprocess (2026-05-13)

The §10 MLX verdict held in code: `MLXStyleDistanceClient` was written, compiled clean against `ml-explore/mlx-swift-lm` 3.31.3, used the API exactly per the README. But at runtime it failed with `MLX error: Failed to load the default metallib. library not found`.

Root cause (documented in mlx-swift's own README):

> SwiftPM (command line) cannot build the Metal shaders so the ultimate build has to be done via Xcode.

The user's machine has **Command Line Tools only**, not full Xcode. The `metal` compiler ships only with full Xcode (~15-20 GB installed without simulators, ~12 GB App Store download). The disk-space check at decision time revealed the data volume at 87% full (29 GB free / 228 GB total) — installing Xcode would have left effectively no headroom even at the bare-Xcode minimum.

The previous research pass (this doc §11) verified the MLX **library** was viable but didn't verify the **toolchain** on the dev machine. That's the *verify-research-claims* memory rule (`feedback_verify_research_claims`) meeting its limit: research agents check published library status; they don't check the user's local install state.

**Pivot decision (user, 2026-05-13):** drop MLX, ship a Python-subprocess Path D conformer using the existing `sentence-transformers` venv (`Tools/RagSpike/Python/.venv`). The subprocess architecture:

- **Long-lived child process.** Spawned on first `embed(_:)` call (lazy); reused for every subsequent embed; dies automatically with the parent (stdin closes → Python's stdin loop exits). No daemon, no port management, no HTTP server, no separate code-signing pipeline for a launcher service.
- **Stdin/stdout JSON-line protocol.** Each request is `{"text": "..."}`; each response is `{"dim": 768, "vec": [...]}` (or `{"error": "..."}`). One ready-signal `{"ready": true}` after model load so the client doesn't race startup.
- **Reuses the existing spike venv.** `Tools/RagSpike/Python/.venv` already has `sentence-transformers` 3.0.x installed (from the original embed_offline.py path). No new dependency burden for the pivot itself; .app bundling of a Python interpreter + venv is a Phase 5.5 production-hardening task.

### 12.1 Implementation landed

- `Tools/RagSpike/Python/embed_subprocess.py` — the stdin/stdout subprocess script (~120 LOC).
- `Sources/LoomCore/Retrieval/PythonStyleDistanceClient.swift` — Swift `EmbeddingClient` conformer (~180 LOC). Owns the subprocess lifecycle, request body builder, response parser, ready-signal handshake. Internal `LineReader` for newline-delimited stdout framing.
- `Tools/RagSpike/MlxSpike/compare_swift_venv.py` — validity check (cosine vs canonical Python output).
- 9 new TestKit tests pinning the wire-format (request body shape, response parser including ready/error/empty-vec cases).
- `RagSpike --venv-smoke` subcommand: full end-to-end run.

### 12.2 Validation

```
=== RagSpike --venv-smoke (Python subprocess D) ===
Embedding 16 items (first call includes model load)...
  id=1: dim=768 (first call) 7.65s
  id=4: dim=768 0.208s
  id=8: dim=768 0.068s
  id=12: dim=768 0.076s
  id=104: dim=768 0.058s
Total: 9.80s
```

```
   id      cosine    max-abs-diff  pass
--------------------------------------------------
    1-104  1.000000    0.000000     ✓ (all 16 items)

min cosine: 1.000000
mean cosine: 1.000000
max max-abs-diff: 0.000000

PASS
```

**Bit-identical to the canonical Python sentence-transformers baseline** — expected, since the Swift client is just an stdin/stdout pipe around the same library that produced the baseline. The numerical equivalence to PyTorch was already established in §8.

Latency profile:
- **Cold start:** ~7.65s (Python interpreter import + StyleDistance model load + first Metal JIT).
- **Warm embed:** 0.05–0.2s per 300-word chunk. Comparable to PyTorch CPU; faster than Kobold round-trip for ingest.
- **One subprocess per Loom run.** No retrieval-time start-up cost after the first embed of a session.

### 12.3 What the pivot does NOT cost

- The pure-Swift Path E ([Sources/LoomCore/Retrieval/FuncwordZEmbedder.swift](Sources/LoomCore/Retrieval/FuncwordZEmbedder.swift)) is unchanged and is the NSFW-parity-balanced half of the hybrid.
- The hybrid retrieval merge ([RankingMetrics.reciprocalRankFusion](Sources/LoomCore/Retrieval/RankingMetrics.swift)) is unchanged.
- The ingest pipeline ([ReferenceIngestPipeline](Sources/LoomCore/Retrieval/ReferenceIngestPipeline.swift)) is unchanged — it accepts any `EmbeddingClient` conformer; the venv path is now one such conformer.
- The retrieval service ([RetrievalService](Sources/LoomCore/Retrieval/RetrievalService.swift)) is unchanged.

### 12.4 What the pivot DOES cost

- **Bundled-Python in Loom.app** (Phase 5.5 deployment work): ~1 GB inside `.app/Contents/Resources/Python/` once we bundle the interpreter + venv. The current spike reuses the user's existing `Tools/RagSpike/Python/.venv` — sufficient to validate the architecture but not shippable.
- **ML-native-lib code-signing** for distribution: every `.so`/`.dylib` in the bundled venv has to be signed individually for hardened runtime + notarisation. Apple's own tooling supports this but it's ~1 day of pipeline work in build.sh. For a single-user app the user is also the developer who signs; for actual distribution this matters.
- **Python interpreter install on user's machine** (alternative if we don't bundle): ~30 MB compressed; CLT's bundled Python 3 works for sentence-transformers. Less clean than bundling but ships immediately.

### 12.5 Re-test path if Xcode arrives later

The MLX work isn't lost — `LOOM_MLX_PORT_SPIKE.md` §7–11 documents the conversion + numerical validation + Swift API surface; `Sources/LoomMLX/MLXStyleDistanceClient.swift` (deleted from working tree in the pivot commit) is preserved in git history at the predecessor commit. To re-test:

1. Install full Xcode (Xcode → Settings → Platforms → install macOS SDK only, skip iOS / etc).
2. Verify `xcrun -sdk macosx metal --version` resolves.
3. Restore the LoomMLX target + MLXStyleDistanceClient.swift from git history.
4. `swift run MLXSwiftSpike --dump` should now produce the same vectors_swift_mlx.json as the venv path. Compare via `Tools/RagSpike/MlxSpike/compare.py`.

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

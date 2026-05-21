# Style retrieval + [STYLE EXEMPLARS] layer

How references become the `fewShotStyleExample` prompt layer. Ingest writes per-reference `.index` sidecars; retrieval reads them and returns top-K `StyleExemplar`s that `StyleExemplarsLayer` formats into a `[STYLE EXEMPLARS]` block. Key files: `Retrieval/RetrievalService.swift`, `Retrieval/ReferenceIngestPipeline.swift`, `Retrieval/CoreMLEmbeddingClient.swift`, `Retrieval/FuncwordZEmbedder.swift`, `Generation/StyleExemplarsLayer.swift`.

The user-facing version is **References (style ingestion)** in User Help; this is the engineering view.

## Two complementary signals

Retrieval is a **hybrid** of two per-chunk vectors, fused — not a single cosine.

| Path | Vector | What it captures | Compute |
|---|---|---|---|
| **D** | Wegmann style embedding, **768-dim** | Voice / register / authorial-style signature | Native CoreML, in-process |
| **E** | Function-word z-score, **150-axis** | Rhythm + function-word frequency fingerprint | Pure-Swift, CPU, in-process |

D is per-chunk and stable. E is **project-corpus-relative** — `FuncwordZEmbedder.fit(corpus:topN:150)` picks the top-150 function words across the whole project's reference corpus, so adding a new reference re-fits E for every chunk. That's why ingest is two-pass (per-reference D + project-wide E refit).

Both vectors live in the chunk sidecar (`ReferenceTextIndex.Chunk.dVec` / `.eVec`); both `ModelFingerprint`s are recorded so a model swap can be detected and the index re-built.

## The D embedder — Wegmann via CoreML

`CoreMLEmbeddingClient` (`Retrieval/CoreMLEmbeddingClient.swift`) drives the bundled `Resources/StyleEmbedding/StyleEmbedding.mlpackage` directly through Apple's `MLModel`:

- **Model:** `AnnaWegmann/Style-Embedding`, RoBERTa backbone. `modelId == "AnnaWegmann/Style-Embedding (CoreML)"`, `dim == 768`.
- **Tokenizer:** HuggingFace fast-tokenizer loaded via `swift-transformers` `AutoTokenizer.from(modelFolder:)`. RoBERTa BPE.
- **Per call:** tokenize → pad/truncate to `maxSequenceLength` (128) tokens with BOS/EOS re-wrap → `MLModel.prediction` → read the 768-vector output. Mean-pool + L2-norm are baked into the graph.
- **Threading:** lazy-loads tokenizer + model on first `embed`; a `DispatchSemaphore` bridges the async tokenizer load into the synchronous `EmbeddingClient.embed` contract. Guarded by an `NSLock`.

**The Phase 8.c migration** replaced a Python `sentence-transformers` subprocess (`PythonEmbeddingClient`) with this native path — drops ~3 GB of Python venv from the install and removes the ~7.65 s subprocess cold-start. Cosine-equivalent to the Python reference within 1e-4 (verified by `Tools/CoreMLProbe/probe_wegmann_coreml.py`; min 0.999993). **Existing `.index` sidecars stay valid** — query-time cosine ranking is preserved across the swap, no re-ingest needed.

`PythonEmbeddingClient` remains as a fallback: if the bundled mlpackage is absent (dev machine where the build script hasn't run), `AppState.embeddingClientFactory` falls back to the venv path. CLT-compatible at runtime — `MLModel` is a system framework, `xcrun coremlcompiler` ships with the Command Line Tools, no Xcode required.

## The E embedder — function-word z-score

`FuncwordZEmbedder` (`Retrieval/FuncwordZEmbedder.swift`), pure-Swift:

1. **Fit** over the project corpus — global token counts, take top-N (default 150) function words by (count desc, first-seen asc).
2. **Per text:** `rel[j] = local_count(vocab[j]) / sum_of_top_N_local_counts` — relative frequency over the fit vocabulary.
3. **z-score per dimension** using corpus mean + population std (ddof=0).

`dim == vocabulary.count` (≤150). Cheap enough to refit on every retrieval query.

## `RetrievalService.retrieve(query:modalityFilter:topK:)`

Mirror of the ingest pipeline — ingest writes, retrieve reads. Six steps:

1. **Load every reference's `.index` sidecar** in the project (`ReferenceStorage.listReferenceIds`). References without a sidecar (ingest not yet run) are silently skipped.
2. **Modality filter** (optional). Chunks tagged with a different `NarrativeMode` are dropped. Passing `.mixed` as the filter is a no-op (deliberate — see test).
3. **Embed the query.** D via the injected `EmbeddingClient`; E via a fresh `FuncwordZEmbedder.fit` over the full corpus, then transform the query. Each step degrades gracefully:
   - D fails → E-only retrieval.
   - All chunks lack `eVec` → D-only retrieval.
   - Both fail → return empty.
4. **Per-path cosine ranking.** Rank candidate chunks by cosine on each path, taking the top `rrfMergeWindow` (default 10) per path.
5. **Reciprocal Rank Fusion merge** (`RankingMetrics.reciprocalRankFusion`, k=10, equal weights). RRF score per candidate = Σ 1/(k + rank_in_path). Robust to the two paths' incomparable score scales — it merges on rank, not raw cosine.
6. **Top-K** from the merged ranking (default 3), returned as `StyleExemplar`s with full provenance (`referenceId`, `referenceName`, `chunkIndex`, `text`, `modality`, `rrfScore`).

Defaults: `rrfK = 10`, `rrfMergeWindow = 10`, `topK = 3`.

## `StyleExemplar`

What retrieval returns:

```swift
struct StyleExemplar {
    let referenceId: UUID
    let referenceName: String
    let chunkIndex: Int
    let text: String
    let modality: NarrativeMode?
    let rrfScore: Double      // for the "why this chunk?" debug view
}
```

## The `[STYLE EXEMPLARS]` block

`StyleExemplarsLayer.format(_:)` (`Generation/StyleExemplarsLayer.swift`) renders the top-K into a block:

```
[STYLE EXEMPLARS]
Use the following passages as voice and style cues for your prose. Do NOT quote,
copy, or paraphrase their content — match their rhythm, sentence length, and
register only.

— from "Hemingway sample" (action):
He walked the road. The road was long.

— from "lush gothic excerpt" (description):
The corridors stretched away in shadow...
[END]
```

The "voice cues, not content" framing is load-bearing (`LOOM_RAG_SPIKE §13.3(d)`): retrieved chunks share *style* with the query but may also share *content* (NSFW-vocabulary clustering, topic overlap), so without the explicit instruction, generation risks plagiarising the exemplar text. Empty exemplar list → empty string → PromptBuilder skips the layer.

## Wiring into generation

`PromptBuilder.buildLayers` emits the formatted block as the `fewShotStyleExample` layer (below-cache, lower eviction priority than the bible/knowledge layers — style is the first thing dropped under budget pressure).

The retrieval call itself is injected as a closure so `PromptBuilder` stays pure:

- `AppState.styleRetriever()` returns `(String, NarrativeMode?) -> [StyleExemplar]`, resolving `currentRetrievalService` on every call (so a project switch doesn't strand the coordinator wired once at editor construction).
- `GenerationCoordinator` calls it with the recent-prose query + the recent-prose's classified modality, and passes the result into the `PromptContext.styleExemplars` the builder reads.
- `AppState.reconfigureRetrieval(for:)` installs a fresh `RetrievalService` on `createProject` / `openProject` / `saveCurrentSessionAs`, releasing the old one (which drops the Python subprocess if the fallback path was active).

The query's modality is classified by the same `NarrativeModeClassifier` used at ingest, so query-modality and chunk-modality are produced by the same tagger — they agree by construction.

## What you can audit

The retrieved exemplars for any past generation are in that generation's `fewShotStyleExample` chiclet (History tab → expand the entry). The chiclet shows the formatted block including provenance lines. The `[retrieval]` debug-log subsystem logs match counts + which path(s) were active per query.

## See also

- **References (style ingestion)** (User Help) — the user-facing surface.
- **Embeddings** — the next section: the Wegmann CoreML bundle, bge-large, funcword-z in more depth.
- **Generation pipeline** — where the `fewShotStyleExample` layer sits in the assembled prompt.
- [`LOOM_RAG_SPIKE.md`](LOOM_RAG_SPIKE.md) §13 — the D+E-hybrid verdict + RRF rationale.
- [`LOOM_SCENE_EXEMPLAR_SPIKE.md`](LOOM_SCENE_EXEMPLAR_SPIKE.md) — the Wegmann-over-StyleDistance embedder probe.

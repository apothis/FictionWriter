# Embeddings

The embedding models Loom uses, what each is for, the abstraction over them, and the dead ends that were tried and reverted. Retrieval *mechanics* (RRF, the `.index` sidecar, the `[STYLE EXEMPLARS]` block) are in the previous section, **Style retrieval**; this is about the embedders themselves.

## Three signals, two purposes

| Signal | Model | Dim | Where it runs | Used for |
|---|---|---|---|---|
| **D (style)** | Wegmann `AnnaWegmann/Style-Embedding` | 768 | native CoreML, in-process | Style retrieval (voice match); entity-discovery dedup |
| **E (style)** | function-word z-score (`FuncwordZEmbedder`) | ≤150 | pure-Swift CPU, in-process | Style retrieval (rhythm/fingerprint), fused with D via RRF |
| **Text** | `bge-large` / `mxbai-embed-large` | ~1024 | Ollama HTTP | Paraphrase dedup + evidence-quote validation in extraction filters |

Two distinct purposes that should not be confused:

- **Style embeddings (D + E)** answer "does this prose *sound* like that prose?" — voice, register, rhythm, independent of topic. Used by retrieval + entity dedup.
- **Text/semantic embeddings (bge)** answer "does this text *mean* the same as that text?" — topical/semantic similarity. Used to dedup paraphrased extracted facts and validate that an extractor's evidence quote actually appears (semantically) in the prose.

Using a semantic embedder for style (or vice versa) is the classic mistake — they're optimised for orthogonal axes.

## The `EmbeddingClient` abstraction

`Retrieval/ReferenceIngestPipeline.swift` declares the protocol the D-path is wired through:

```swift
public protocol EmbeddingClient {
    var modelId: String { get }        // persisted on ModelFingerprint.id
    var dim: Int { get }               // persisted on ModelFingerprint.dim
    func embed(_ text: String) -> EmbeddingVector?   // nil on failure (graceful)
}
```

`embed` returns nil on failure (network, model-load error) rather than throwing — the ingest pipeline records a nil `dVec` and the partial state is recoverable by re-running ingest. `EmbeddingVector` (`Retrieval/Embeddings.swift`) is a `[Float]` wrapper with `dim`. Conformers:

- **`CoreMLEmbeddingClient`** — production. Wegmann via Apple `MLModel`. (See **Style retrieval** for internals.)
- **`PythonEmbeddingClient`** — legacy fallback. Wegmann via a Python `sentence-transformers` subprocess; used only when the bundled `.mlpackage` is absent (dev machine pre-build).

The text embedders (bge) are *not* wired through this protocol — they're called over Ollama HTTP via `EmbeddingClients.swift` (`OllamaEmbedRequest` / `OllamaEmbedResponse`), and a KoboldCpp embeddings endpoint exists too (`KoboldEmbeddingsRequest` / `KoboldEmbeddingsResponse`). Both return an `EmbeddingVector?` with defensive nil-on-bad-payload.

## D — Wegmann style embedding

`AnnaWegmann/Style-Embedding`, RoBERTa backbone, 768-dim, mean-pool + L2-norm baked into the CoreML graph. Chosen over the alternatives by an empirical probe (Phase 8.a §6.1):

- **vs StyleDistance:** Wegmann gave +0.285 style-separation vs StyleDistance's +0.086 — StyleDistance *underperformed even the topical baseline* on Loom's prose. Phase 5 retrieval was migrated off StyleDistance onto Wegmann inside the Phase 8 arc.
- **vs a topical baseline (bge):** Wegmann separates on voice where bge separates on topic — the whole point.

Driven natively via CoreML since Phase 8.c (drops the ~3GB Python venv). See **Style retrieval** for the inference path.

## E — function-word z-score

`Retrieval/FuncwordZEmbedder.swift`. A complementary CPU-only signal that captures rhythm + function-word frequency fingerprint, which a neural style embedder smooths over. Pure Swift, no model file:

1. **Fit** over the project corpus — top-N (default 150) function words by (count desc, first-seen asc).
2. **Relative frequency** per text over that vocabulary.
3. **z-score per dimension** (corpus mean + population std, ddof=0).

Project-corpus-relative, so it re-fits whenever the reference corpus changes. Cheap enough to refit on every retrieval query. Fused with D via Reciprocal Rank Fusion — the two signals are deliberately incomparable in raw scale, so rank fusion rather than score blending.

## Text embedders — bge-large / mxbai-embed-large

Semantic embedders on Ollama, ~1024-dim. Not for style — for the extraction filters:

- **Paraphrase dedup** (`LedgerFilters`) — cosine ≥ ~0.85 between two extracted facts means they're the same fact phrased differently; drop the dupe. Keeps the suggestions queue from filling with restatements.
- **Evidence-quote validation** — an extractor claims a fact with an evidence quote; semantic similarity confirms the quote is actually grounded in the scene prose rather than hallucinated.
- **Entity-discovery dedup** also uses cosine, but against the *style/Wegmann* vectors for the bible-match step — confirm which embedder a given dedup site uses before assuming.

## Cosine + chunking

- **Cosine similarity** — `LedgerExtraction.cosineSimilarity`, `Templates/CosineMatrix`, and the retrieval ranker all compute plain cosine over `[Float]`. No approximate-NN index; corpora are small enough (a project's references, a scene's facts) that brute-force cosine is fine.
- **`RagChunker`** (`Retrieval/Embeddings.swift`) — word-window chunker. `size` = window width in whitespace tokens, `overlap` = trailing tokens repeated at the next window's start. Production ingest uses size 100 / overlap 20. The final window is kept even if short (tail prose still embeds). Invalid inputs (size ≤ 0, overlap ≥ size) return empty. It's a `while` loop, not recursion.

## ModelFingerprint + stale detection

Each `.index` sidecar records a `ModelFingerprint { id, dim }` for both the D and E models (`ReferenceTextIndex.dModel` / `.eModel`). At retrieval time, a mismatch between the sidecar's fingerprint and the live client's `modelId`/`dim` flags the index as stale — the vectors were produced by a different model and shouldn't be cosine-compared against fresh query vectors. The Bible Workspace surfaces this as a re-ingest prompt. (The CoreML migration was specifically engineered to keep the fingerprint stable — cosine-equivalent to the Python path within 1e-4 — so existing sidecars stayed valid across the swap.)

## Dead ends

Tried, measured, reverted — don't re-spike these without new information:

| Path | Verdict | Why |
|---|---|---|
| **StyleDistance** (style embedder) | Reverted for Wegmann | Underperformed even the topical baseline on Loom's prose (+0.086 vs Wegmann's +0.285 separation). `LOOM_SCENE_EXEMPLAR_SPIKE.md` §6.1. |
| **MLX port** of the embedder | Reverted | The MLX path needed a local toolchain (Xcode/Metal) that wasn't installed; surfaced post-implementation. Went with the venv, then native CoreML. `LOOM_MLX_PORT_SPIKE.md` §12. |
| **Python subprocess** (Wegmann inference) | Replaced by CoreML | Worked, but a ~3GB venv + ~7.65s cold-start. Phase 8.c migrated to native `MLModel`. `PythonEmbeddingClient` survives as a fallback only. |
| **DeBERTa-v3 NLI proposition gate** (continuity Part A) | Built, measured no win, ripped out | Extracted-claim paraphrases come back `neutral` under strict NLI even when contradicting. `LOOM_CONTINUITY_AUDIT.md` §25–26. |

GLiNER (DeBERTa-v3 via ONNX) is *not* a dead end — it's the live entity-discovery NER detector. It uses ONNX rather than CoreML because DeBERTa-v3 doesn't trace through coremltools cleanly (verified).

## See also

- **Style retrieval** — how D + E are fused + injected (the previous section).
- **Extraction pipelines** — where the bge text embedders + cosine dedup are used.
- [`LOOM_SCENE_EXEMPLAR_SPIKE.md`](LOOM_SCENE_EXEMPLAR_SPIKE.md) §6.1 — the embedder probe (Wegmann vs StyleDistance).
- [`LOOM_MLX_PORT_SPIKE.md`](LOOM_MLX_PORT_SPIKE.md) §12 — the MLX dead end.
- [`LOOM_NARRATIVE_MODE_SPIKE.md`](LOOM_NARRATIVE_MODE_SPIKE.md) §10 — the modality classifier that tags chunks.

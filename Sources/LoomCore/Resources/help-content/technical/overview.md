# Architecture overview

> **Status:** Phase B placeholder. Real content lands in Phase C, grounded in current shipped code per [`docs/REFERENCE_PLAN.md`](docs/REFERENCE_PLAN.md).

Loom is a Swift Package — `LoomCore` library + `Loom.app` AppKit shell + `Tools/*` spike executables — driven by a separate writer model (KoboldCpp) and structured-task model (Ollama).

## Runtime services

- **Writer LLM** — Goetia (Mistral-Small-3 24B) on KoboldCpp at `192.168.1.201:5001` (configurable). Prose generation via `/api/v1/generate`, instruct-template-wrapped per the detected model family. See `Sources/LoomCore/Networking/KoboldClient.swift`.
- **Structured-task LLM** — gemma4_2b / gemma4_4b on Ollama at `localhost:11434` (configurable). JSON-schema-constrained extraction. See `Sources/LoomCore/Networking/OllamaClient.swift`.
- **Style embedder** — Wegmann style-embedding via native CoreML at `Resources/StyleEmbedding/StyleEmbedding.mlpackage`. See `Sources/LoomCore/Retrieval/CoreMLEmbeddingClient.swift`.
- **Text embedder** — `bge-large` / `mxbai-embed-large` on Ollama (used for dedup, evidence validation, RAG).
- **NER** — GLiNER (DeBERTa-v3) via ONNX Runtime. Deterministic, NSFW-robust entity tagging.

## Three main data-flow paths

- **Generate** — `EditorViewController` → `GenerationCoordinator.start` → `PromptBuilder.build` → Kobold writer → acceptance UI. Style retrieval (when references are ingested) calls `RetrievalService.retrieve` via `AppState.styleRetriever`.
- **Extract** — `LedgerExtractionCoordinator` → `OllamaLedgerExtractor` → `LedgerFilterPipeline` (dedup + evidence-quote validation + leakage filter) → `LedgerDiff` → `LedgerSuggestionsQueue`. Entity discovery is a parallel pipeline (`OllamaEntityDiscoveryExtractor` → `EntityPromotionGate` → `EntityDedupEngine` → `ProposedEntitiesStore`).
- **Ingest** — `AppState.ingestReference` → `ReferenceIngestPipeline.chunkAndEmbedD` (200-word chunks via Wegmann CoreML) + `KoboldNarrativeModeClassifier` (per-chunk modality tag) + `refitAllEVectors` (function-word z-score top-150 axes), writes the `.index` sidecar.

## Where to look next

- [`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md) — every Codable shape + on-disk layout.
- [`LOOM_GENERATION_MODES.md`](LOOM_GENERATION_MODES.md) — per-mode prompt assembly + 20 layers.
- [`LOOM_BIBLE_WORKSPACE.md`](LOOM_BIBLE_WORKSPACE.md) — webview architecture (snapshot/intent pattern; the help panel reuses this).
- [`LOOM_TECH_STACK.md`](LOOM_TECH_STACK.md) — solved-problem registry keyed by problem.

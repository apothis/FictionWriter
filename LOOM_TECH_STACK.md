# Loom — Tech Stack & Solved-Problem Registry

> **Purpose.** Before spiking or building a solution to a problem, **check
> here first** — Loom has accumulated a lot of reusable infrastructure, and
> re-solving a solved problem (or re-spiking a dead end) wastes effort. This
> is a map keyed by *problem → what already solves it → where it lives*. It is
> a pointer index, not a spec; the cited files are the source of truth.
>
> Keep this current: when a new pipeline, library, or capability lands — or a
> spike reaches a verdict — add or update the relevant row.

## 1. External tech stack

| Layer | Choice | Notes |
|---|---|---|
| Language / build | Swift, SwiftPM | `LoomCore` library + `Loom.app` (AppKit) + `Tools/*` spike executables |
| App shell | macOS AppKit | main editor + side-pane inspector |
| Secondary UI | WKWebView + React + Vite + TypeScript + Tailwind + shadcn/ui | the Bible Workspace (`web/`); a contained pivot away from AppKit |
| Writer model | **Goetia** (24B) on **KoboldCpp** @ `192.168.1.201:5001` | prose generation; `/api/v1/generate` raw completion. gemma 4 31B is the recorded alternative |
| Structured-task model | **gemma4_2b / gemma4_4b** on **Ollama** @ `localhost:11434` | extraction / classification; `/api/chat` with JSON-Schema-constrained output |
| Style embeddings | **Wegmann** style-embedding model, native **CoreML** | `StyleEmbedding.mlpackage`; chosen over StyleDistance (§4) |
| Text embeddings | `bge-large`, `mxbai-embed-large` on Ollama; `KoboldEmbedding` | dedup, evidence validation, RAG |
| NER | **GLiNER** (DeBERTa-v3) via **ONNX Runtime** | deterministic entity tagger; cannot refuse on explicit prose |
| Deps | `swift-transformers` (HF), `onnxruntime-swift-package-manager` | tokenizers + CoreML loading; ONNX inference |
| Tests | **TestKit** (in-house, `Tests/LoomCoreTests/`) — *not* XCTest | TDD red→green; stub providers + deterministic schedulers |

## 2. Solved problems — reusable internal infrastructure

### LLM transport & generation
| Problem | Solution | Files |
|---|---|---|
| Talk to KoboldCpp writer model | `KoboldClient`, `KoboldGenerating`, `KoboldCallProvider` | `Networking/` |
| Talk to Ollama with JSON-Schema constraint | `OllamaClient` (streaming `/api/chat`) | `Networking/OllamaClient.swift` |
| Per-model sampler families | `SamplerParams` (`familyOverride` maps model name → temp/minP/repPen) | `Networking/SamplerParams.swift` |
| Discover / health-check servers | `ServerProbe`, `OllamaProbe`, `AutoProbe`, `KoboldClientRegistry`, `ServerHealthMonitor` | `Networking/`, root |
| Instruct-template wrapping | `InstructTemplates` | `Generation/InstructTemplates.swift` |
| Strip `<think>` blocks from output | `ThinkBlockStripper`, `StreamingThinkBlockStripper` | `Generation/` |
| Detect & continue past a model refusal | `RefusalDetector`, `RefusalContinuation` | `Generation/` |

### Structured extraction from prose
**Check here before building any new "extract structured data from a scene" pass.**
| Problem | Solution | Files |
|---|---|---|
| Constrain JSON output (KoboldCpp) | GBNF grammar — `LedgerExtraction.gbnfGrammar` (reliable structural constraint) | `Generation/LedgerExtraction.swift` |
| Structured output from a small gemma on Ollama | **Do NOT use the `format` schema** — it flakes ~50% on gemma4_2b (degenerate buffer → empty content; HANDOFF §15.19). Run **unconstrained**, pin field names in the prompt, prefer JSONL / delimited lines, tolerant-parse, re-roll on degenerate output. Used by `OllamaContinuityExtractor`, entity/relationship discovery extractors | `Generation/OllamaContinuityExtractor.swift`, `OllamaRelationshipDiscoveryExtractor.swift` |
| Parse messy model JSON | Tolerant parser pattern — preamble/postamble tolerant, JSONL/array-agnostic, per-object recovery (`parseExtractedFacts`, `ContinuityAudit.parseClaims`) | `LedgerExtraction.swift`, `ContinuityAudit.swift` |
| Schema/length call returns empty content | **Retry-on-empty** with doubled `num_predict` — `OllamaLedgerExtractor.callWithRetry`, `OllamaContinuityExtractor` re-rolls on any degenerate result | `Generation/OllamaLedgerExtractor.swift`, `OllamaContinuityExtractor.swift` |
| Size the output token budget per scene | `OllamaLedgerExtractor.budgetForSceneWords` (8× words, 2048–8192) | same |
| Transient JSON parse-fail on NSFW prose | retry on `noJSONObjectFound` / `noJSONArrayFound` (Stage A2 / beat extractor) | `OllamaEntityDiscoveryExtractor.swift`, `OllamaBeatExtractor.swift` |
| Post-extraction noise (paraphrase dupes, hallucinated quotes, prompt leakage) | **`LedgerFilters`** (cosine dedup, evidence-quote validation, prompt-leakage) + `LedgerFilterPipeline` (async, fail-soft) | `Generation/LedgerFilters.swift`, `LedgerFilterPipeline.swift` |

### Entity recognition & discovery
| Problem | Solution | Files |
|---|---|---|
| Detect named entities in prose (deterministic, NSFW-robust) | **GLiNER** — `GLiNERDetector` + runtime/tokenizer/decoder/inputs | `Generation/GLiNER*.swift` |
| Discover new bible entities from scenes | `EntityDiscoveryPipeline` + `GLiNERCandidateDetector` / `OllamaEntityDiscoveryExtractor`, `EntityPromotionGate`, `EntityDedupEngine`, `EntityDiscoveryTrigger` | `Generation/Entity*.swift`, `GLiNER*` |
| `@`-mention indexing / hover / autocomplete | `MentionIndex`, `EntityAutocomplete`, `EntityHoverResolver`, `EntityReference` | `Editing/` |

### Embeddings, similarity & retrieval
| Problem | Solution | Files |
|---|---|---|
| Style embedding | `CoreMLEmbeddingClient` (Wegmann, native CoreML) + `CoreMLCompileCache` | `Retrieval/` |
| Embedding client abstraction | `EmbeddingClients`, `Embeddings`, `PythonEmbeddingClient` (legacy) | `Retrieval/` |
| Function-word z-score style signal | `FuncwordZEmbedder` | `Retrieval/FuncwordZEmbedder.swift` |
| Cosine similarity | `LedgerExtraction.cosineSimilarity`, `CosineMatrix` | `Generation/`, `Templates/` |
| RAG over long reference texts | `RetrievalService`, `ReferenceIngestPipeline`, `RetrievalQueryBuilder`, `RankingMetrics` | `Retrieval/` |
| Classify a passage's narrative mode | `NarrativeModeClassifier`, `KoboldNarrativeModeClassifier`, `NarrativeModeHeuristic` | `Retrieval/` |

### Knowledge & continuity tracking
| Problem | Solution | Files |
|---|---|---|
| Per-character knowledge ledger | `LedgerExtraction`, `OllamaLedgerExtractor`, `LedgerExtractionCoordinator`/`Trigger`, `LedgerDiff`, `LedgerSuggestionsQueue`, `LedgerSuggestionAcceptor` | `Generation/Ledger*.swift` |
| What a character KNOWS / does-not-know at a given scene | `LedgerKnowledge.compute` (walks `flatSceneIds`, buckets KNOWS/UNKNOWNS) | `Generation/LedgerKnowledge.swift` |
| Discover character relationships | `RelationshipDiscovery`, `OllamaRelationshipDiscoveryExtractor`, `RelationshipConflict` | `Generation/` |
| Who is present in a scene | `ScenePresence` | `Generation/ScenePresence.swift` |
| **Whole-manuscript continuity audit (L10)** | Phase B built + validated (tuning ongoing): `ContinuityAudit` (extraction + adjudication + typing + knowledge-adjudication prompts), `OllamaContinuityExtractor` (two-stage), `ContinuityClaimFilter` / `ContinuityClaimFilterPipeline`, `ContinuitySubjectResolver`, `ContinuityConflictRetrieval` (cross-scene), `ContinuityKnowledgeCheck`, `ContinuityFinding`, `ContinuityAuditEngine`, `ContinuityAuditStore`. Runs entirely on Goetia/KoboldCpp + a text embedder. Per-run coverage stochastic — see `LOOM_CONTINUITY_AUDIT.md` §19–20 | `Generation/Continuity*.swift`, `Storage/ContinuityAuditStore.swift`, `Tools/ContinuityAuditSpike` |

### Prompt assembly & generation modes
| Problem | Solution | Files |
|---|---|---|
| Build a story-shaped prompt | `PromptBuilder`, `BibleInjector`, `AuthorsNoteInjector`, `StylePrompt`, `StyleExemplarsLayer`, `RecentProseWindow` | `Generation/` |
| Translate `WritingDirection` into generation posture (NSFW §3.2/§3.5) | `WritingDirectionPrompt` — system-prompt addendum, near-cursor anti-fade directive, A/N depth, Continue word target | `Generation/WritingDirectionPrompt.swift` |
| Default Project Memory / anti-refusal presets | `ProjectMemoryPresets` (Loom-default / Heavy NSFW / Minimal) — seeded into new projects by `ProjectStorage` | `Models/ProjectMemoryPresets.swift` |
| Per-relationship kink/dynamic spec for the model | `DynamicSheet` (on `Bible`), `DynamicSheetInjector` + `DynamicSheetPrompt` (alwaysOn / participant-keyed activation) | `Models/DynamicSheet.swift`, `Generation/DynamicSheetPrompt.swift` |
| Per-scene framing block | `Scene.framing` — author scenario block, injected near the cursor | `Models/Scene.swift` |
| Curated anti-slop phrase list | `ProjectSettings.antiSlopPhrases` seeded from `AntiSlopDefaults` — data only, transport wiring deferred | `Models/AntiSlopDefaults.swift` |
| Context-budget sizing | `ContextBudgetRecommendation`, `TokenEstimator` | `Generation/` |
| Generation-mode orchestration | `GenerationCoordinator`, `TemplateGenerationCoordinator`, `OutlineDraftCoordinator`, `OutlineGenerator`, `SceneBeatPlanner` | `Generation/` |
| Scene-template imitation | `BeatExtraction`/`Pipeline`, `BeatGeneration`, `VoiceDescriptor`, `SceneExemplar` | `Templates/` |

### Persistence
| Problem | Solution | Files |
|---|---|---|
| Project-as-directory, scene-as-markdown | `ProjectStorage`, `ProjectSession` | `Storage/`, `Editing/` |
| Sidecar JSON stores (pattern) | `ProposedEntitiesStore`, `ProposedRelationshipsStore`, `SnapshotStore`, `GenerationLogStore`, … | `Storage/` |
| Schema migration | lazy / forward-load (`decodeIfPresent`); every schema test pins the old-JSON-decodes case | repo-wide convention |
| Manuscript export | `MarkdownExporter` | `Storage/MarkdownExporter.swift` |

### UI surfaces
| Problem | Solution | Files |
|---|---|---|
| Bible Workspace (entity management) | WKWebView + React; `BibleWorkspaceBridge`, `BibleWorkspaceSnapshot`, `BibleWorkspaceIntent` | `UI/`, `Models/`, `web/` |

## 3. Decided directions & dead ends — do NOT re-spike

| Topic | Verdict | Reference |
|---|---|---|
| GLiREL (relationship extraction lib) | **Dead** — do not re-spike | HANDOFF §15.25 |
| Relationship-discovery precision levers | Exhausted — every lever tried, none worked | HANDOFF §15.26–15.27 |
| StyleDistance embedder | Rejected — underperformed even the topical baseline; **Wegmann** chosen | LOOM_SCENE_EXEMPLAR §6.1 |
| Python embedding subprocess | Replaced — migrated to native CoreML (drops ~3 GB of deps) | LOOM_PLAN L8 |
| MLX port | Reverted — Xcode not installed on the build machine | LOOM_MLX_PORT_SPIKE |
| Whole-document LLM contradiction judging | Rejected — ContraDoc shows ~54% precision; the audit decomposes to pairwise instead | LOOM_CONTINUITY_AUDIT §2, §13 |
| Classic IE (OpenIE / SRL / REBEL / AMR / spaCy SVO) for claim extraction from fiction | Rejected — all trained on news/encyclopedic text, collapse on dialogue + interiority, emit untyped relations not source-attributed typed claims; would lower recall on fiction | LOOM_CONTINUITY_AUDIT §15 |
| Ollama `format` JSON schema on small gemma | Avoid — flakes ~50% (degenerate buffer → empty). Use unconstrained + pinned fields + JSONL + tolerant parse, or GBNF on KoboldCpp | LOOM_CONTINUITY_AUDIT §3.1, HANDOFF §15.19 |
| TTS / voice, multi-user collab, cloud sync, mobile | Deferred indefinitely | LOOM_PLAN §1 |

## 4. Where to look for the rest

- [`LOOM_PLAN.md`](LOOM_PLAN.md) — phase inventory (L0–L10) and status.
- [`HANDOFF.md`](HANDOFF.md) — per-session ledger; the authoritative record of what changed and why.
- `LOOM_*_SPIKE.md` / feature docs — design + empirical results per feature.

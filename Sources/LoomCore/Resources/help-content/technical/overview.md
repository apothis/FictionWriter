# Architecture overview + runtime services

Loom is a macOS desktop app written in Swift, structured as a single Swift Package: a `LoomCore` library (most of the surface area), a `Loom` executable (the AppKit shell), and a `Tools/*` directory of spike runners that compile against `LoomCore` but are gated out of the shipping app. All user-facing functionality lives in `LoomCore`; the `Loom` target is a thin launcher.

> **Posture for this book:** where this doc and the code disagree, the code wins. Every page is written from current shipped sources, with `LOOM_*.md` plan docs cited only where they're load-bearing for *why* something is the way it is. Code wins over design intent.

## The big picture

```
┌─────────────────────────────────────────────────────────────────┐
│  Loom.app  (AppKit)                                              │
│                                                                  │
│  ┌──────────────────────┐    ┌─────────────────────────────────┐ │
│  │  Editor window       │    │  Webview panels (WKWebView)     │ │
│  │  (NSTextView +       │    │   • Bible Workspace             │ │
│  │   sidebar + tray +   │    │   • Planned Project wizard      │ │
│  │   inspector + menu)  │    │   • Project tools               │ │
│  │                      │    │   • Help (this panel)           │ │
│  └─────────┬────────────┘    └──────────────┬──────────────────┘ │
│            │                                │                    │
│            │   snapshot push  /  intent post                     │
│            ▼                                ▼                    │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │  LoomCore (Swift, in-process)                               │ │
│  │   AppState ── ProjectSession ── Project (Bible + manuscript) │ │
│  │      │                                                       │ │
│  │      ├── GenerationCoordinator   ── PromptBuilder ──┐        │ │
│  │      ├── LedgerExtractionCoord.  ── OllamaLedgerExtractor    │ │
│  │      ├── EntityDiscoveryPipeline ── GLiNER + Ollama          │ │
│  │      ├── ContinuityAuditEngine                                │ │
│  │      ├── ReferenceIngestPipeline ── CoreMLEmbeddingClient     │ │
│  │      └── RetrievalService        ── style + funcword-z         │ │
│  │                                                               │ │
│  │   Storage/ — project on disk; sidecar stores per pipeline    │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                          │                  ▲                    │
│                          │ HTTP             │ HTTP               │
└──────────────────────────┼──────────────────┼────────────────────┘
                           ▼                  │
                   ┌──────────────┐    ┌──────────────┐
                   │  KoboldCpp   │    │   Ollama     │
                   │  (writer)    │    │ (extractor + │
                   │              │    │  text-embed) │
                   └──────────────┘    └──────────────┘
```

Loom is local-only. There is no cloud component, no telemetry, no auth. The only network traffic is HTTP to the user-configured model servers (typically `localhost` or LAN), wrapped by the user's macOS Local Network privacy grant.

## Runtime services

Two model servers, both user-supplied, both kept loose-coupled behind a `ServerProfile` abstraction (`Sources/LoomCore/Models/ServerProfile.swift`):

| Role | Default backend | Used for |
|---|---|---|
| **Writer** | KoboldCpp, `/api/v1/generate` | All creative prose generation (`KoboldClient`, `KoboldGenerating`, `KoboldCallProvider` in `Networking/`). Wrapped by `InstructTemplates` for per-family template emission. |
| **Extractor** | Ollama, `/api/chat` (with optional JSON Schema) | Knowledge-ledger extraction, entity discovery, relationship discovery, continuity audit, narrative-mode classification. `OllamaClient` + per-pipeline `OllamaXxxExtractor`. (Scene-template beat extraction is the exception — it runs on the *writer* with GBNF; see **Extraction pipelines**.) |

Two further inference paths run **in-process** (no server):

- **Style embedding** — Wegmann style-embedding model loaded as a native CoreML bundle (`Resources/StyleEmbedding/StyleEmbedding.mlpackage`) and driven by `Retrieval/CoreMLEmbeddingClient.swift` via `huggingface/swift-transformers` for the RoBERTa BPE tokenizer. Output: 768-dim style vectors per chunk. The Phase 8.c migration removed a previous Python subprocess.
- **NER** — GLiNER (DeBERTa-v3 backbone) via `microsoft/onnxruntime-swift-package-manager`. The model is exported offline as ONNX by `Tools/GLiNERProbe/export_gliner_onnx.py`; the runtime tokenizer + decoder live in `Generation/GLiNER*.swift`. Used by entity discovery's candidate detector — deterministic, never refuses on explicit prose, and stays in-process.

Plus a complementary CPU-only signal:

- **Function-word z-score embedder** — `Retrieval/FuncwordZEmbedder.swift`. A pure-Swift 150-axis frequency-fingerprint over project-wide z-scored function-word counts. Cheap, project-refit at every reference ingest, paired with the Wegmann vectors at retrieval time.

Server-side text embedders (`bge-large`, `mxbai-embed-large` on Ollama) are used for dedup + evidence-quote validation in the extraction pipelines.

## Swift Package structure (brief)

`LoomCore/` is the only library. Its subdirectories map roughly to subsystems:

| Subdirectory | Contains |
|---|---|
| `Models/` | Codable shapes — `Project`, `Scene`, `Bible`, `Character`, `Setting`, `BibleObject`, `LorebookEntry`, `DynamicSheet`, `ReferenceText`, `AppSettings`, `ProjectSettings`, etc. |
| `Storage/` | On-disk read/write façades — `ProjectStorage`, plus per-pipeline sidecar stores. |
| `Networking/` | HTTP clients (`KoboldClient`, `OllamaClient`), prober + registry, sampler families. |
| `Generation/` | Prompt assembly + per-mode logic + every extractor pipeline (`PromptBuilder`, `GenerationCoordinator`, `Ledger*`, `Entity*`, `Relationship*`, `Continuity*`, `BibleInjector`, `AuthorsNoteInjector`, etc.). |
| `Retrieval/` | Style retrieval — `RetrievalService`, `ReferenceIngestPipeline`, `CoreMLEmbeddingClient`, `FuncwordZEmbedder`, narrative-mode classifier. |
| `Templates/` | Scene-template skeleton extraction + per-beat generation — `BeatExtraction*`, `BeatGeneration`, `VoiceDescriptor`, `SceneExemplar`. |
| `Editing/` | In-memory editing state — `ProjectSession`, `MentionIndex`, `EntityAutocomplete`, `EntityHoverResolver`. |
| `UI/` | All AppKit + WebView host classes. |
| `Resources/` | Bundled assets — CoreML model, GLiNER ONNX, GBNF grammars, web-bundle dist/, `help-content/`. |

`AppDelegate.swift` + `AppState.swift` + `DebugLog.swift` + `ServerHealthMonitor.swift` sit at the top level of `LoomCore/`. See **T.2 — Repo layout** for the full per-file breakdown.

## App state + project session

`AppState` (`Sources/LoomCore/AppState.swift`) is the single in-memory root. It owns:

- The current `ProjectSession` (the open project + scenes-loaded map + URL).
- Persistent settings (`AppSettings`, persisted to `~/Library/Application Support/Loom/settings.json` via `Storage/AppSettingsStore.swift`).
- The `KoboldClientRegistry` and `OllamaClient` instances configured from the active server profiles.
- The active `RetrievalService` (rebuilt when the project switches), the `LedgerSuggestionsQueue`, the `ProposedEntitiesStore`, the `ProposedRelationshipsStore`.
- Notification posters for `didReplaceNotification`, `didMutateProjectNotification`, etc. — the AppKit + WebView surfaces observe these to refresh.

`ProjectSession` (`Sources/LoomCore/Editing/ProjectSession.swift`) is the working copy of the open project: in-memory `Project` + a `[UUID: Scene]` map for loaded scene prose. Mutations go through it (`setMemory`, `setScenePOV`, `replaceScene`, etc.) and propagate to disk through `ProjectStorage`.

The flow on file open:

```
File → Open Project →
  AppDelegate.openProjectClicked →
  ProjectStorage.loadProjectWithRecovery →
  AppState.currentSession.replace(project:, scenes:, url:) →
  AppState.pushRecentAndSave →
  AppState.reconfigureRetrieval(for:) →
  observers refresh AppKit + WebView UIs
```

## Three primary data-flow paths

### Generate

```
EditorViewController.handleContinue (or handle{Expand,Rewrite,…}) →
  GenerationCoordinator.start →
    PromptBuilder.build (assembles all 20 layers) →
    KoboldClient.streamingGenerate →
  acceptance-state-machine transitions →
  ProjectSession.saveCurrentScene
```

`PromptBuilder` (`Sources/LoomCore/Generation/PromptBuilder.swift`) is the load-bearing site. Layer composition + above/below-cache assignment + budget enforcement + eviction all live there. Per-mode system prompts and `modeInstruction` strings are static methods on the same type. The full per-mode prompt-shape table is in **T.4 — Generation pipeline**.

### Extract

```
ProjectSession scene-save event →
  LedgerExtractionTrigger.shouldFire (200-word delta) →
  LedgerExtractionCoordinator (debounced) →
    OllamaLedgerExtractor.extract →
    LedgerFilterPipeline (cosine dedup + evidence validation + leakage filter) →
    LedgerDiff vs existing bible →
    LedgerSuggestionsQueue (durable)

(parallel piggyback path:)
  EntityDiscoveryTrigger.shouldFire (500-word delta) →
  EntityDiscoveryPipeline (six stages — see T.6) →
    GLiNERCandidateDetector + OllamaEntityDiscoveryExtractor →
    EntityPromotionGate → EntityDedupEngine →
    ProposedEntitiesStore
```

The shared `OllamaXxx*` pattern across these pipelines (JSON-schema-constrained call → tolerant parse → retry-on-empty with doubled `num_predict`) is in **T.6 — Extraction pipelines**.

### Ingest

```
BibleWorkspace Reference → Ingest button →
  intent posted to Swift via WKWebView bridge →
  AppState.ingestReference →
    ReferenceIngestPipeline.chunkAndEmbedD →
      RagChunker (~100-word overlapping) →
      NarrativeModeClassifier (heuristic + Kobold fallback) →
      CoreMLEmbeddingClient.embed →
    refitAllEVectors (project-wide funcword z-score) →
  writes references/<id>.index sidecar
```

The two-pass shape (per-reference D + project-wide E) is intentional: D vectors are stable per-chunk; E vectors depend on the project's full reference corpus, so adding a new reference re-touches every existing one's E. See **T.5 — Style retrieval** for the math.

## Cross-cutting infrastructure

- **`DebugLog`** (`Sources/LoomCore/DebugLog.swift`) — append-only `[HH:MM:SS.mmm] [subsystem] event: data` lines at `$TMPDIR/loom-debug.log`. Single shared instance. ~30 grep-able subsystem tags; see **T.13 — Debug log subsystems** for the full list.
- **AppKit shell** — `AppDelegate` builds the main menu in code (no NIBs); `MainWindowController` + `EditorViewController` + `SidebarController` + `InspectorController` + `GenerationTrayView` host the editor surface. AppKit is the platform; new feature work generally lands as a webview (see below).
- **WKWebView panels** — `Bible Workspace`, `Planned Project wizard`, `Project tools`, and `Help` each ship as a separate Vite/React/TS bundle under `web/bible-workspace/` (the directory name is historical; it now hosts all four). Each has a snapshot/intent bridge: Swift pushes a Codable `XxxSnapshot` into JS via `window.loomXxx.applySnapshot`, JS posts a Codable `XxxIntent` back via `webkit.messageHandlers.loomXxx.postMessage`. The pattern is in **T.8 — UI architecture**.
- **`TestKit`** (`Tests/LoomCoreTests/TestKit.swift`) — in-house testing harness. Not XCTest. Discovery-by-attribute, deterministic schedulers, stub providers. Run via `swift run LoomCoreTests` (or the harness-bound `swift test` configuration). **T.9 — Build / test / run** has the operations.

## Threading + concurrency posture

- **AppKit + WebView callbacks are main-thread** by convention. UI mutations stay on main.
- **Network calls are async** via `URLSession` task closures; results bounce back to main before touching UI state.
- **Extractor pipelines** run off-main (their own dispatch queues) and post results back to main for storage + UI update.
- **No `async/await` adoption today.** Loom predates being able to mandate it given the toolchain floor; pipelines use callback completion + completion-queue dispatchers. New code should *not* introduce `async/await` until a deliberate migration. Per the project's TDD posture, test stubs for callback APIs must defer + flush rather than firing completions synchronously, or `[weak self]` lifetime bugs go invisible.

There is no GCD work pool. Each pipeline owns its own queue.

## What this overview deliberately does not cover

- Per-Codable shape (see **T.3 — Data model**).
- Per-file breakdown (see **T.2 — Repo layout**).
- Per-mode prompt assembly (see **T.4 — Generation pipeline**).
- Build / test / run mechanics (see **T.9 — Build / test / run**).

## See also

- [`LOOM_PLAN.md`](LOOM_PLAN.md) — phase ledger + master plan.
- [`LOOM_TECH_STACK.md`](LOOM_TECH_STACK.md) — solved-problem registry indexed by problem, not by subsystem. **Check here before spiking anything new.**
- [`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md) — historical data-model design intent. Cross-check against `Sources/LoomCore/Models/` before trusting.
- [`LOOM_GENERATION_MODES.md`](LOOM_GENERATION_MODES.md) — generation-mode catalogue + per-mode prompt shapes.
- [`LOOM_BIBLE_WORKSPACE.md`](LOOM_BIBLE_WORKSPACE.md) — the snapshot/intent webview pattern. Help panel reuses it directly.

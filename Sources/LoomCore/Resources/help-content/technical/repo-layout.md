# Repo layout + module breakdown

Map of the source tree. Counts are accurate as of writing; the directory shape is stable but file counts churn.

## Top-level

```
FictionWriter/                       ← repo root, working directory for all scripts
├── Package.swift                    ← SwiftPM manifest
├── Package.resolved
├── Info.plist                       ← app bundle metadata (CFBundleVersion, LSMinimumSystemVersion=14.0, etc.)
├── build.sh                         ← build to Loom.app + sign
├── run.sh                           ← launch the built binary directly
├── Sources/
│   ├── Loom/                        ← executable target (just main.swift)
│   └── LoomCore/                    ← the library; all the code lives here
├── Tools/                           ← per-spike executable targets (Tools/<Name>/main.swift)
├── Tests/LoomCoreTests/             ← TestKit suites (NOT XCTest)
├── web/bible-workspace/             ← Vite/React/TS source for all four WKWebView panels
├── scripts/
│   ├── build-bible-workspace.sh     ← builds the four web bundles; called by build.sh
│   └── create-signing-identity.sh   ← provisions "Loom Local" cert in login keychain (one-off)
├── docs/REFERENCE_PLAN.md           ← Phase A planning + Phase C writing-order map for this help system
├── LOOM_*.md                        ← plan + research + spike + session-ledger docs (~25 files)
├── HANDOFF.md                       ← rolling per-session ledger
└── Loom.app                         ← build output (gitignored)
```

Top-level `LOOM_*.md` files are plan docs and session ledgers, NOT reference. They go stale. The book you're reading right now is the authoritative reference; `LOOM_*.md` are cited for design intent only, where load-bearing.

## `Package.swift`

```swift
let package = Package(
    name: "Loom",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.0.0"),
        .package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager", from: "1.24.2"),
    ],
    targets: [
        .executableTarget(name: "Loom",         path: "Sources/Loom"),
        .target(name: "LoomCore",               path: "Sources/LoomCore", resources: [...]),
        .testTarget(name: "LoomCoreTests",      path: "Tests/LoomCoreTests"),
        // Tools/<Name> executables...
    ]
)
```

Two external dependencies:

- **`swift-transformers`** (HuggingFace) — pure-Swift RoBERTa BPE tokenizer for the Wegmann CoreML inference path. Tokenizers product only; skips Generation / Models products that would pull CoreML build steps in.
- **`onnxruntime-swift-package-manager`** (Microsoft) — drives the GLiNER DeBERTa-v3 entity-discovery model. ONNX is the runtime path because DeBERTa-v3 doesn't trace through coremltools cleanly.

Bundled resources (declared on the LoomCore target) include the four webview `dist/` bundles, the Wegmann CoreML model, the GLiNER ONNX bundle, and `help-content/`. The webview bundles + CoreML model are gitignored — regenerated locally before `swift build` by the scripts in `scripts/` and `Tools/CoreMLProbe/`.

## `Sources/Loom/`

```
Sources/Loom/main.swift              ← @main entry, instantiates NSApplication + AppDelegate
```

That's it. The executable is a thin launcher; nearly every line of code lives in `LoomCore`.

## `Sources/LoomCore/`

The library. Subdirectories map to subsystems:

### Top-level singletons

```
AppDelegate.swift                    ← NSApplicationDelegate; menu bar; window lifecycle
AppState.swift                       ← shared in-memory root (settings, current project, services)
DebugLog.swift                       ← append-only $TMPDIR/loom-debug.log writer
ServerHealthMonitor.swift            ← background probe of configured servers
```

### `Models/` — Codable shapes

The data layer. Around 50 files; every persisted shape and every webview snapshot/intent lives here.

| File | What |
|---|---|
| `Project.swift` | Top-level project — title, author, settings, bible, manuscript. |
| `Scene.swift` | Per-scene state — id, title, body lives separately, POV character, framing, generated spans, snapshots. Carries the `GenerationMode` enum and `Certainty`/`KnownFact` types. |
| `Bible.swift` | The 5-array container — characters, settings, objects, lorebook, dynamics. |
| `Character.swift`, `Setting.swift` (+ `BibleObject` in same file) | Entity types. |
| `LorebookEntry.swift`, `DynamicSheet.swift` | The other two bible entity types. |
| `Manuscript.swift`, `PartChapter.swift` | Tree of Parts → Chapters → Scenes; `flatSceneIds` walk. |
| `AppSettings.swift`, `ProjectSettings.swift` | App-wide vs per-project settings. |
| `ServerProfile.swift` | A configured backend endpoint (Kobold or Ollama). |
| `ReferenceText.swift`, `ReferenceFile.swift` | Style-reference shape + on-disk file frontmatter. |
| `AntiSlopDefaults.swift` | Seeded phrase list for KoboldCpp's `banned_strings`. |
| `*Snapshot.swift` (`BibleWorkspace`, `PlannedProject`, `ProjectTools`, `Help`) | Webview-bound projections — what Swift sends to JS. |
| `*Patch.swift` (`CharacterPatch`, `LorebookEntryPatch`, etc.) | Webview-bound mutations — what JS sends back. |
| `GenerationLog.swift` | Per-call durable log entry. |
| `InjectionMode.swift`, `CharacterRole`, `Certainty`, `LengthScenario`, `NarrativeMode`, `NarrativeStyle`, `OutlineSizing`, `PlannedProjectConfig`, … | Enums + small structs co-located with their primary entity. |
| `JSONCoders.swift` | `JSONEncoder.loom` / `JSONDecoder.loom` shared instances. |

### `Storage/` — on-disk façades

```
ProjectStorage.swift                 ← project.json + scenes/*.md atomic read/write; .bak recovery
GenerationLogStore.swift             ← generation-log/<iso-ts>.json
SnapshotStore.swift                  ← snapshots/*.json
ReferenceStorage.swift               ← references/<id>.md + .index sidecar
TemplateSceneStorage.swift           ← templates/<id>.md + .beats.json sidecar
TemplateGenStateStore.swift          ← template-gen-state/<templateId>.json
ContinuityAuditStore.swift           ← continuity-audit/audit.json
ProposedEntitiesStore.swift          ← proposed-entities/proposed-entities.json
ProposedRelationshipsStore.swift     ← proposed-relationships/proposed-relationships.json
RelationshipMapLayoutStore.swift     ← relationship-map/layout.json
AppSettingsStore.swift               ← ~/Library/Application Support/Loom/settings.json
StyleLibraryStore.swift              ← ~/Library/Application Support/Loom/styles.json (cross-project)
MarkdownExporter.swift               ← Project → single .md export
```

The sidecar-store pattern is consistent across pipelines — `directoryName` + `fileName` statics; a `directoryURL(in:)` + `fileURL(in:)` pair; atomic write through a temp + rename; defensive load with `decodeIfPresent` and forward-load defaults.

### `Networking/` — HTTP clients + sampler config

```
KoboldClient.swift                   ← /api/v1/generate streaming + non-streaming
KoboldGenerating.swift, KoboldCallProvider.swift   ← request shape + dependency-injectable call provider
KoboldClientRegistry.swift           ← maps ServerProfile.id → client instance
OllamaClient.swift                   ← /api/chat streaming (optionally JSON-schema-constrained)
ServerProbe.swift, OllamaProbe.swift, AutoProbe.swift   ← capability probes per backend
SamplerParams.swift                  ← per-model-family sampler family + overrides
```

### `Generation/` — prompt assembly + every pipeline

The largest subdirectory (~70 files). Group it as follows:

**Prompt assembly + per-mode logic**

```
PromptBuilder.swift                  ← THE central site — assembles all 20 layers + budget + eviction
InstructTemplates.swift              ← mistral/gemma/chatml/llama3/alpaca/raw adapters + detector
AcceptanceMachine.swift              ← the post-generation Accept/Reject/Redo state machine
GenerationCoordinator.swift          ← orchestrates a single generation call
ContextBudgetRecommendation.swift, TokenEstimator.swift
AnatomyGate.swift                    ← intimateAnatomy injection gate (clothed-vs-undressed)
AuthorsNoteInjector.swift, BibleInjector.swift, DynamicSheetPrompt.swift
WritingDirectionPrompt.swift         ← project-level directionDirective layer
RecentProseWindow.swift, PrefillSeed.swift
RefusalDetector.swift, RefusalContinuation.swift
ThinkBlockStripper.swift, StreamingThinkBlockStripper.swift
HelpContent.swift                    ← THIS BOOK's TOC + markdown loader
```

**Knowledge-ledger pipeline (Phase 4)**

```
LedgerExtraction.swift               ← types + GBNF grammar + tolerant parser
OllamaLedgerExtractor.swift          ← Ollama-side extractor + retry-on-empty
LedgerExtractionCoordinator.swift, LedgerExtractionTrigger.swift   ← post-scene debounced trigger
LedgerFilters.swift, LedgerFilterPipeline.swift   ← cosine dedup + evidence validation + leakage filter
LedgerDiff.swift                     ← diff candidates vs existing bible
LedgerSuggestionsQueue.swift, LedgerSuggestionAcceptor.swift
LedgerKnowledge.swift                ← compute KNOWS/UNKNOWNS as of a scene
ScenePresence.swift                  ← who's in this scene
```

**Entity discovery pipeline (Phase 9)**

```
EntityDiscovery.swift                ← types + anatomy block-list
EntityDiscoveryPipeline.swift        ← orchestrator
EntityDiscoveryTrigger.swift, EntityDiscoveryScorer.swift
EntityPromotionGate.swift, EntityDedupEngine.swift
OllamaEntityDiscoveryExtractor.swift, GLiNEREntityDiscoveryExtractor.swift, GLiNERCandidateDetector.swift
GLiNERDecoder.swift, GLiNERDetector.swift, GLiNERInputs.swift, GLiNERRuntime.swift, GLiNERTokenizer.swift
```

**Relationship discovery + continuity audit (Phase 10)**

```
RelationshipDiscovery.swift, OllamaRelationshipDiscoveryExtractor.swift, RelationshipConflict.swift

ContinuityAudit.swift                ← extraction prompts + claim shapes + tolerant parser
ContinuityAuditEngine.swift          ← orchestrator
ContinuityClaimFilter.swift, ContinuityClaimFilterPipeline.swift
ContinuityConflictRetrieval.swift, ContinuitySubjectResolver.swift
ContinuityKnowledgeCheck.swift, ContinuityFinding.swift
OllamaContinuityExtractor.swift, ContinuityEvalMetrics.swift
```

**Outline-driven generation (Planned Project mode)**

```
OutlineGenerator.swift, OutlineDraftCoordinator.swift, OutlineGeneration.swift
SceneBeatPlanner.swift               ← per-scene beat plan
```

**Scene-template generation (Phase 7 — uses Templates/ alongside)**

```
TemplateGenerationCoordinator.swift   ← Pass-B per-beat generator
LorebookRoller.swift, LorebookSceneGate.swift   ← Sphiratrioth roll path
```

### `Retrieval/` — style RAG

```
RetrievalService.swift               ← top-K retrieval entry point
RetrievalQueryBuilder.swift, RankingMetrics.swift
ReferenceIngestPipeline.swift        ← chunk → modality → embed → write .index
CoreMLEmbeddingClient.swift          ← Wegmann via huggingface/swift-transformers + native CoreML
CoreMLCompileCache.swift             ← compiled .mlmodelc cache
EmbeddingClients.swift, Embeddings.swift, PythonEmbeddingClient.swift   ← protocol + legacy paths
FuncwordZEmbedder.swift              ← 150-axis function-word z-score, in-process, CPU
NarrativeModeClassifier.swift, NarrativeModeHeuristic.swift, KoboldNarrativeModeClassifier.swift
```

### `Templates/` — scene-template skeleton + generation

```
TemplateScene.swift, TemplateSceneFile.swift   ← shape + on-disk frontmatter
BeatExtraction.swift, BeatExtractionPipeline.swift   ← Pass-A skeleton extraction
BeatGeneration.swift, BeatOutputSanitizer.swift   ← Pass-B per-beat writer prompt
BeatRetrievalQuery.swift             ← per-beat modality-aware retrieval query
VoiceDescriptor.swift                ← extracted voice fingerprint
SceneBeat.swift                      ← per-beat shape
SceneExemplar.swift, SceneExemplarFixture.swift   ← Phase 8 unified projection
CosineMatrix.swift, EmbedderReportFormatter.swift, SpikeOrchestrator.swift
```

### `Editing/` — in-memory edit state

```
ProjectSession.swift                 ← working copy of the open project; mutation entry point
MentionIndex.swift, EntityAutocomplete.swift, EntityHoverResolver.swift, EntityMentionContext.swift, EntityReference.swift   ← @-mention machinery
ManuscriptWalk.swift, SceneListOperations.swift   ← outline walks
BibleInspectorViewModel.swift, MentionSparklineLayout.swift, PlanViewLayout.swift   ← pure-data view models
GenerationModeAvailability.swift, GenerationModeBehavior.swift
SelectionTenseHeuristic.swift, WordCount.swift
```

### `UI/` — AppKit + WebView host classes

```
MainWindowController.swift, EditorViewController.swift   ← the primary editor surface
SidebarController.swift, InspectorController.swift   ← side surfaces
GenerationTrayView.swift             ← the tray under the editor
HistoryInspectorViewController.swift   ← the History tab — generation log surface
SettingsWindowController.swift, SettingsViewController.swift, ServersTabViewController.swift, ProjectSettingsTabViewController.swift
RewriteSubModeMenuBuilder.swift, ScenePOVMenuBuilder.swift, MentionPopover.swift, EntityHoverPopover.swift, MentionSparklineView.swift
LoomActionButton.swift, DesignTokens.swift, EmptyProjectState.swift, EmptyProjectStateView.swift

# WKWebView panels — each has a window controller + bridge:
BibleWorkspaceWindowController.swift, BibleWorkspaceBridge.swift
PlannedProjectWindowController.swift, PlannedProjectBridge.swift
ProjectToolsWindowController.swift, ProjectToolsBridge.swift
HelpWindowController.swift, HelpBridge.swift

PlanWindowController.swift, PlanViewController.swift   ← outline / Corkboard view
HistoryExpansionState.swift          ← per-row UI state
```

The four `*WindowController` + `*Bridge` pairs all follow the same snapshot-push / intent-post pattern. See **T.8 — UI architecture** for the bridge shape.

### `Resources/` — bundled assets

```
BibleWorkspace/                      ← Vite-built dist; copied here by scripts/build-bible-workspace.sh
PlannedProject/                      ← (likewise)
ProjectTools/                        ← (likewise)
Help/                                ← (likewise) — the React side of this very panel
StyleEmbedding/                      ← Wegmann .mlpackage + tokenizer.json/vocab.json/merges
GLiNER/                              ← exported ONNX + tokenizer.json + config.json
help-content/
  ├── user/                          ← markdown for User Help sections (one file per section id)
  └── technical/                     ← markdown for Technical Reference sections
```

`BibleWorkspace/`, `PlannedProject/`, `ProjectTools/`, `Help/`, and `StyleEmbedding/` are all gitignored — regenerated locally by their respective build scripts. `GLiNER/` ships in-repo because the offline ONNX export is a one-off.

## `Tools/`

Spike runners. Each is an `executableTarget` declared in `Package.swift`, compiled against `LoomCore` but excluded from the shipping app. Source: `Tools/<Name>/main.swift`.

| Tool | Purpose |
|---|---|
| `ContinuityAuditSpike` | Run the continuity-audit engine against a project; emit a markdown report. |
| `CoreMLProbe` | Build / smoke-test the Wegmann CoreML bundle (`build_mlpackage.py` + Swift driver). |
| `EntityDetectionProbe`, `EntityDiscoverySpike` | GLiNER + entity-discovery validation. |
| `GLiNERProbe` | Export GLiNER to ONNX (`export_gliner_onnx.py`) + smoke-test the runtime. |
| `LedgerSpike` | Run the knowledge-ledger extractor on fixtures + emit precision/recall metrics. |
| `OutlineDraftProbe`, `OutlineGenerationProbe` | Planned Project outline-generation paths. |
| `RagSpike` | Style-retrieval probe — Wegmann + funcword-z scoring against a project. |
| `RelationshipDiscoveryProbe` | Relationship-discovery validation. |
| `SceneExemplarSpike`, `SceneTemplateSpike` | Pass-A skeleton + Pass-B per-beat generation probes. |

Run with `swift run <ToolName> <args...>`. Each tool prints its argument shape on `--help`.

See **T.10 — Spike runners** for the per-tool usage table.

## `Tests/LoomCoreTests/`

TestKit (not XCTest). Files named `<Subsystem>Tests.swift` or `<Feature>Tests.swift`. The harness:

```
TestKit.swift                        ← discovery + assertions + deferred-callback helpers
```

Run all tests: `swift run LoomCoreTests`. Run via the harness — there's no `swift test` configuration today.

See **T.9 — Build / test / run** for the testing posture.

## `web/bible-workspace/`

Single bun + Vite workspace producing four IIFE bundles (one per panel). Shape:

```
web/bible-workspace/
├── package.json
├── vite.config.ts                   ← LOOM_BUNDLE env var selects which entry to build
├── tsconfig.json
└── src/
    ├── main.tsx                     ← Bible Workspace entry
    ├── App.tsx                      ← Bible Workspace root
    ├── plannedProject/              ← Planned Project wizard root + components
    ├── projectTools/                ← Project Tools panel root + components
    ├── help/                        ← Help panel root + components (this very surface)
    ├── bridge.ts                    ← Swift↔JS message types (mirrors LoomCore/Models/*Snapshot.swift)
    ├── types.ts                     ← TS-side projections of the Codable shapes
    ├── components/                  ← shared shadcn/ui primitives
    ├── views/                       ← shared editors (ReferenceEditor, etc.)
    ├── lib/                         ← utility hooks + helpers
    ├── styles.css                   ← Tailwind entry
    └── devMockSnapshot.ts           ← dev-time stub for running outside the WKWebView host
```

Each panel build is a separate `vite build` invocation (IIFE format can't code-split across multiple inputs). The post-build sed pass in `scripts/build-bible-workspace.sh` strips `crossorigin` and `type="module"` so the bundles execute under WebKit's `file://` loading rules.

## `docs/`

```
docs/REFERENCE_PLAN.md               ← Phase A planning + Phase C writing-order map for this help system
```

When the help books finish shipping, this file is archived or deleted (per its own status banner).

## `LOOM_*.md` plan-doc directory

About 25 files at the repo root. Categories:

- **Planning + research:** `LOOM_PLAN.md`, `LOOM_RESEARCH.md`, `LOOM_DESIGN_LANGUAGE.md`, `LOOM_TECH_STACK.md`.
- **Per-subsystem design intent:** `LOOM_STORY_BIBLE.md`, `LOOM_GENERATION_MODES.md`, `LOOM_MEMORY.md`, `LOOM_DATA_MODEL.md`, `LOOM_BIBLE_WORKSPACE.md`, `LOOM_NSFW.md`, `LOOM_FANFIC.md`, `LOOM_PLANNED_PROJECT.md`.
- **Spike + research-deep-dive:** `LOOM_*_SPIKE.md`, `LOOM_*_RESEARCH.md` (~10 files).
- **Session ledger:** `HANDOFF.md`. Append-only running log of what landed when.

These go stale. **Code wins where they disagree.** Cite them only for design intent or historical context.

## See also

- **Architecture overview** — the previous Technical section. Pipeline-level sketch + runtime services.
- **Data model** — every Codable shape + on-disk layout, the next section.
- **Build / test / run** — the operations for this tree.
- [`LOOM_TECH_STACK.md`](LOOM_TECH_STACK.md) — solved-problem registry keyed by problem. **Check there before spiking anything new.**

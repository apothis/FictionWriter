# Loom Data Model

> **Last code cross-check:** 2026-05-21
> **Posture:** reference doc reflecting the *current shipped* code. Where this doc and code disagree, **the code wins** — every type here cites its file path. Historical design intent lives in [`LOOM_PLAN.md`](LOOM_PLAN.md), [`HANDOFF.md`](HANDOFF.md), and the per-phase spike docs.
> **Convention:** all Codable Foundation types. UUIDs for identifiers. ISO-8601 with millisecond precision for dates (rounded on `init`, so on-disk round-trip is identity). Field added after schema-version 1 must be `decodeIfPresent` — see [Lazy versioning](#19-lazy-versioning--migration).

## 1. Top-level `Project`

`Sources/LoomCore/Models/Project.swift`

```swift
public struct Project: Codable, Equatable {
    public let id: UUID
    public var title: String
    public var author: String?
    public var createdAt: Date
    public var schemaVersion: Int          // start at 1; bump on non-additive changes
    public var kind: ProjectKind           // .originalFiction | .fanfic
    public var settings: ProjectSettings
    public var manuscript: Manuscript
    public var bible: Bible
    public var notes: String               // free-form per-project notepad (Notes inspector tab)
    public var selectedInspectorTab: InspectorTab?  // .bible | .history | .notes
    public var fanficMetadata: FanficMetadata?      // populated only when kind == .fanfic
    public var plannedConfig: PlannedProjectConfig? // non-nil when created via Planned Project flow
}
```

`ProjectKind` is `.originalFiction` (default) or `.fanfic`. `InspectorTab` is `.bible / .history / .notes`. Phase 1 ships only `.originalFiction`; fanfic kind has data-model support but no UI yet.

## 2. `ProjectSettings`

`Sources/LoomCore/Models/Project.swift`

```swift
public struct ProjectSettings: Codable, Equatable {
    public var serverProfileId: UUID?              // overrides app-level default
    public var contextBudgetTokens: Int            // default 8192
    public var generationDefaults: GenerationDefaults
    public var authorsNote: String                 // depth-N injection per NovelAI
    public var authorsNoteDepthLines: Int          // default 4
    public var memory: String                      // always-top injection per KoboldAI
    public var instructTemplate: InstructTemplate
    public var writingDirection: WritingDirection
    public var pov: POVStyle                       // default narrative POV for new scenes
    public var tense: NarrativeTense               // default narrative tense for new scenes
    public var targetWordCount: Int?
    public var antiSlopPhrases: [String]           // seeded from AntiSlopDefaults
    public var workFraming: [FramedElement]        // see WorkFraming.swift
}
```

### 2.1 `InstructTemplate`

```swift
public enum InstructTemplate: String, Codable {
    case auto         // probe server, infer from model name (default)
    case chatml       // Qwen3.x, many merges
    case mistralV3
    case mistralV7    // Mistral-Small-3.x, Goetia
    case llama3
    case alpaca
    case gemma4       // Gemma 2/3/4 family
    case raw          // pure completion, no template
}
```

`.auto` calls `InstructTemplates.detect(forModelName:)` against the live server. The detector recognises stock Mistral-Small-3.x (2501/2503/2506) → `.mistralV7` and Gemma-2/3/4 → `.gemma4`. See `Sources/LoomCore/Generation/InstructTemplates.swift`.

### 2.2 `GenerationDefaults`

```swift
public struct GenerationDefaults: Codable, Equatable {
    public var continueWordTarget: Int
    public var expandWordTarget: Int
    public var temperature: Double
    public var minP: Double
    public var dryMultiplier: Double      // DRY sampler
    public var dryBase: Double
    public var dryAllowedLength: Int
    public var xtcThreshold: Double       // XTC sampler
    public var xtcProbability: Double
    public var topK: Int
    public var maxOutputTokens: Int
}
```

Per-model sampler families live in `Sources/LoomCore/Networking/SamplerParams.swift` (`familyOverride` maps model name → temp/minP/repPen).

## 3. `WritingDirection`

`Sources/LoomCore/Models/WritingDirection.swift`

```swift
public struct WritingDirection: Codable, Equatable {
    public var kind: DirectionKind                 // literary | mainstream | romance | erotica | porn
    public var register: VocabularyRegister        // clinical | literary | colloquial | crude
    public var explicitnessLevel: ExplicitnessLevel // chaste | suggestive | explicit | graphic
    public var themes: [Theme]                     // free-form tags
    public var pacing: PacingProfile               // slowBurn | steady | accelerating | breakneck
    public var fadeToBlackPolicy: FTBPolicy        // never | sometimes | always
}
```

Translates into a system-prompt addendum + a near-cursor anti-fade directive via `Sources/LoomCore/Generation/WritingDirectionPrompt.swift`.

## 4. Manuscript hierarchy

### 4.1 `Manuscript`

`Sources/LoomCore/Models/Manuscript.swift`

```swift
public struct Manuscript: Codable, Equatable {
    public var partIds: [UUID]          // ordered
    public var parts: [Part]
    public var orphanedSceneIds: [UUID] // scenes not yet in a Part/Chapter
    public var trashedSceneIds: [UUID]  // soft-delete list; restore-from-trash supported
}
```

Phase 1 shipped a flat scene list (all `orphanedSceneIds`); Phase 3 introduced Parts/Chapters with reordering + corkboard view.

### 4.2 `Part`, `Chapter`

`Sources/LoomCore/Models/PartChapter.swift`

```swift
public struct Part: Codable, Equatable {
    public let id: UUID
    public var title: String
    public var chapters: [Chapter]
    public var notes: String
}

public struct Chapter: Codable, Equatable {
    public let id: UUID
    public var title: String
    public var sceneIds: [UUID]
    public var summary: String?
    public var summaryDirty: Bool
    public var targetWordCount: Int?
    public var notes: String
}
```

### 4.3 `Scene`

`Sources/LoomCore/Models/Scene.swift`

```swift
public struct Scene: Codable, Equatable {
    public let id: UUID
    public var title: String
    public var pov: UUID?                 // POV character → Bible.characters
    public var location: UUID?            // → Bible.settings
    public var status: SceneStatus        // todo | draft | revised | final
    public var conflict: String           // scene driver
    public var outcome: String            // how it resolves
    public var summary: String            // 2–3 sentence recap; auto-extracted Phase 2+
    public var summaryDirty: Bool
    public var targetWordCount: Int?
    public var contentPath: String        // `scenes/<id>.md`, derived from id
    public var notes: String
    public var framing: String            // scene-author scenario block (NSFW posture)
    public var explicitnessLevel: ExplicitnessLevel?  // per-scene override
    public var undressedCharacterIds: [UUID]
    public var generatedSpans: [GeneratedSpan]
    public var snapshots: [Snapshot]
    public var extraFrontmatter: [String: String]    // forward-compat sink for unknown frontmatter
    public var prose: String              // not persisted in project.json; lives in scenes/<id>.md
}
```

`prose` is part of the in-memory `Scene` but persisted separately — it lives in `scenes/<id>.md` body, while the rest of the fields go in the YAML frontmatter of that same file. See `SceneFile.swift` for the round-trip codec.

### 4.4 `GeneratedSpan`, `SceneRange`, `Snapshot`

```swift
public struct GeneratedSpan: Codable, Equatable {
    public let id: UUID
    public var generatedAt: Date
    public var mode: GenerationMode
    public var promptLogPath: String       // → generation-log/<ts>.json
    public var rangeInScene: SceneRange?   // can be nil if user accepted then heavily edited
    public var accepted: Bool
}

public struct SceneRange: Codable, Equatable {
    public var location: Int
    public var length: Int
}

public struct Snapshot: Codable, Equatable {
    public let id: UUID
    public var takenAt: Date
    public var label: String?              // user-supplied or "Before Rewrite"
    public var contentSnapshot: String     // full scene prose at time of snapshot
}
```

Snapshots are taken automatically before AI rewrites and on demand. Stored inline in `Scene.snapshots`.

### 4.5 `GenerationMode`

```swift
public enum GenerationMode: String, Codable, CaseIterable {
    case continueProse, expand,
         rewrite, rewriteVoice, rewriteTense, rewritePOV, rewriteLength,
         showDontTell, brainstorm, critique, bridge, describe, nameSuggest,
         rollOutcome, templateScene
}
```

Per-mode prompt assembly lives in [`LOOM_GENERATION_MODES.md`](LOOM_GENERATION_MODES.md). Availability per mode/cursor/selection lives in `Sources/LoomCore/Generation/GenerationModeAvailability.swift`.

## 5. Bible

### 5.1 `Bible` (collection)

`Sources/LoomCore/Models/Bible.swift`

```swift
public struct Bible: Codable, Equatable {
    public var characters: [Character]
    public var settings: [Setting]
    public var objects: [BibleObject]
    public var lorebook: [LorebookEntry]
    public var dynamicSheets: [DynamicSheet]
}
```

`Faction` and `TimelineEvent` are listed in the Phase-0 design doc but **not currently shipped** — the Bible collection lives at five entity classes today.

### 5.2 `Character`

`Sources/LoomCore/Models/Character.swift`

```swift
public struct Character: Codable, Equatable {
    public let id: UUID
    public var name: String
    public var aliases: [String]
    public var role: CharacterRole         // protagonist | antagonist | supporting | minor | narrator
    public var oneLine: String
    public var description: String
    public var personality: String
    public var appearance: String
    public var voice: String               // dialogue-style notes
    public var goals: String
    public var relationships: [Relationship]
    public var avatarPath: String?
    public var knownFactsBySceneId: [UUID: [KnownFact]]   // per-scene knowledge ledger
    public var canonBrief: String?         // Phase 5b — fandom canon snippet
    public var customFields: [CharacterCustomField]       // fandom-template extensibility
    public var injectionMode: InjectionMode               // alwaysOn | keyed
    public var kinks: [CharacterKink]                     // NSFW per-character kink stance
    public var apparentAnatomy: String                    // visible/clothed
    public var intimateAnatomy: String                    // off-page / explicit
}
```

`Relationship` carries `kind` (free-form), `status: RelationshipStatus`, `notes`, optional `sourceSceneId` (where the relationship first became canonical). `CharacterCustomField` is `label / value / kind ∈ {string,number,enum}`, designed so Phase-5 fandom templates can extend a Character without further schema migration.

#### 5.2.1 `KnownFact` (per-scene knowledge ledger)

```swift
public struct KnownFact: Codable, Equatable {
    public let id: UUID
    public var fact: String                // natural-language assertion
    public var sourceSceneId: UUID?        // where they learned it (nil = pre-story)
    public var certainty: Certainty        // asserted | suspected | unknown | mistaken
    public var addedAt: Date
}
```

The `knownFactsBySceneId` map is **Loom's distinctive engineering** — at generation time for scene N, the prompt assembler queries each character's accumulated facts up to and including N-1. Facts marked `unknown` are passed as anti-knowledge: *"Mia does NOT know that Bob betrayed her."*

Knowledge derivation logic: `Sources/LoomCore/Generation/LedgerKnowledge.swift` (walks `flatSceneIds`, buckets KNOWS/UNKNOWNS). Extraction pipeline: `LedgerExtraction.swift` + `OllamaLedgerExtractor.swift` + `LedgerExtractionCoordinator.swift`.

### 5.3 `Setting`, `BibleObject`

`Sources/LoomCore/Models/Setting.swift`

```swift
public struct Setting: Codable, Equatable {
    public let id: UUID
    public var name: String
    public var aliases: [String]
    public var description: String
    public var sensoryNotes: String           // smell, sound, light — for Describe mode
    public var significantObjectIds: [UUID]
    public var notes: String
    public var injectionMode: InjectionMode
}

public struct BibleObject: Codable, Equatable {
    public let id: UUID
    public var name: String
    public var aliases: [String]
    public var description: String
    public var significance: String           // why this object matters
    public var notes: String
    public var injectionMode: InjectionMode
}
```

### 5.4 `LorebookEntry`

`Sources/LoomCore/Models/LorebookEntry.swift`

```swift
public struct LorebookEntry: Codable, Equatable {
    public let id: UUID
    public var name: String
    public var content: String
    public var activationMode: LorebookActivationMode    // .constant | .keyed | .vectorised
    public var keys: [String]                            // primary triggers
    public var secondaryKeys: [String]                   // AND-gating
    public var enabled: Bool
    public var priority: Int                             // ties broken by recency
    public var positionMode: LorebookPositionMode        // .top | .bottom | .depthN
    public var depth: Int?                               // applies to .depthN
    public var maxRecentScenesScanned: Int               // analogous to NovelAI Search Range
    public var group: String?
    public var weight: Int?
    public var sticky: Bool                              // remains active once triggered
    public var activateFromSceneId: UUID?                // scene-bounded activation
    public var activateUntilSceneId: UUID?
}
```

Shape is intentionally close to SillyTavern's WorldInfoEntry so existing intuition transfers. `.vectorised` activation reuses the Phase-5 retrieval index.

### 5.5 `DynamicSheet`

`Sources/LoomCore/Models/DynamicSheet.swift`

```swift
public struct DynamicSheet: Codable, Equatable {
    public let id: UUID
    public var name: String
    public var participantIds: [UUID]    // characters this dynamic applies to
    public var roles: String             // free-form: "D/s", "ABO mates", "rivals-to-lovers", …
    public var wants: String
    public var softLimits: String
    public var hardLimits: String
    public var safeword: String
    public var arc: String               // trajectory of the dynamic
    public var alwaysOn: Bool
    public var enabled: Bool
}
```

A *DynamicSheet* is a per-relationship kink/dynamic spec injected via `DynamicSheetInjector` + `DynamicSheetPrompt`. `alwaysOn = true` → injected on every generation; `false` → injected when a participant character is present in the current scene window.

## 6. References (style ingestion — L5)

### 6.1 `ReferenceText`, `ReferenceTextIndex`

`Sources/LoomCore/Models/ReferenceText.swift`

```swift
public struct ReferenceText: Codable, Equatable {
    public let id: UUID
    public var name: String
    public var nsfw: Bool                      // retrieval can filter on this
    public var createdAt: Date
    public var extraFrontmatter: [String: String]
    public var body: String                    // Markdown reference prose

    public var contentPath: String { "references/\(id.uuidString).md" }
    public var indexPath: String { "references/\(id.uuidString).index" }
}

public struct ReferenceTextIndex: Codable, Equatable {
    public var schemaVersion: Int
    public var dModel: ModelFingerprint?       // Wegmann CoreML fingerprint
    public var eModel: ModelFingerprint?       // function-word-z fingerprint
    public var chunks: [Chunk]                 // ~200-word chunks; each with dVec, eVec, modality
}
```

Ingest pipeline: `Sources/LoomCore/Retrieval/ReferenceIngestPipeline.swift`. Embeddings: `CoreMLEmbeddingClient` (Wegmann mlpackage, native CoreML — Phase 8.c displaced the Python subprocess). Modality classifier: `KoboldNarrativeModeClassifier`. Retrieval at generation time: `RetrievalService.retrieve(query:modalityFilter:topK:)` returning `[StyleExemplar]`.

### 6.2 Template scenes (L7) and Scene exemplars (L8)

Template scenes are reference-text-shaped Markdown files at `templates/<id>.md` with a Pass-A beats sidecar at `templates/<id>.beats.json` (the structural skeleton — `beats`, `modality`, `tension`, pacing). See `Sources/LoomCore/Storage/TemplateSceneStorage.swift` + `Sources/LoomCore/Templates/BeatExtraction.swift`.

Scene exemplars are not a separate persisted type — they're the **L8 unified surface** where one user action creates *both* a `ReferenceText` *and* a Template under a shared UUID. Persisted to both `references/<id>.{md,index}` and `templates/<id>.{md,beats.json}`. The Bible Workspace surfaces them as a unified entity (`SnapshotSceneExemplar`); the storage layer just consults both directories.

## 7. Continuity audit (L10)

### 7.1 `ContinuityFinding`

`Sources/LoomCore/Generation/ContinuityFinding.swift`

```swift
public struct ContinuityFinding: Codable, Equatable {
    public let id: UUID
    public var kind: Kind                      // .attributeDrift | .knowledgeViolation | .timelineConflict | .spatialConflict
    public var severity: Severity              // .high | .medium | .low
    public var claimA: ContinuityAudit.Claim
    public var claimB: ContinuityAudit.Claim
    public var sceneAId: UUID
    public var sceneBId: UUID
    public var sceneDistance: Int
    public var confidence: Double
    public var explanation: String
    public var status: Status                  // .new | .accepted | .dismissed | .resolved
    public var lastSeenAuditAt: Date
}
```

Persisted via `ContinuityAuditStore` (one file per audit run; status carries forward across re-audits).

### 7.2 `ContinuityAudit.Claim` + adjudication shapes

`Sources/LoomCore/Generation/ContinuityAudit.swift`

`ContinuityAudit` is a namespace `enum` carrying:

- `Claim { type: ClaimType, subject: String, attributeKey: String, value: String, sourceSceneId: String, source: ClaimSource, evidenceQuote: String }` — the typed claim shape.
- `ClaimType { event, attribute, temporal, spatial, knowledgeState }` — five-way taxonomy of extracted facts.
- `ClaimSource { narration, dialogue }` — speaker-aware routing.
- `Adjudication / Verdict {contradiction, consistent, evolution}` — the world-fact adjudicator shape.
- `KnowledgeAdjudication / KnowledgeVerdict {violation, not_a_violation}` — the knowledge-class adjudicator's task-fit vocabulary (§24).

## 8. Proposed entities (entity discovery — L9)

`Sources/LoomCore/Storage/ProposedEntitiesStore.swift` + `Sources/LoomCore/Models/BibleWorkspaceSnapshot.swift`

The L9 pipeline produces ProposedEntity records in `proposed-entities/` (one file per entity proposal). Snapshot-side projection is `SnapshotProposedEntity { id, canonicalName, aliases, oneLine, evidenceQuote, kind ∈ {character,setting,object}, attachedFacts: [SnapshotProposedFact], status, addedAt }`. Accepting a proposal promotes it to a real `Character` / `Setting` / `BibleObject` with facts attached to `knownFactsBySceneId`.

Proposed relationships are similar (`ProposedRelationship` / `SnapshotProposedRelationship`) but currently dormant per HANDOFF §15.27.

## 9. Patches (workspace mutation intents)

Each Bible-Workspace-editable entity has a paired `*Patch` type — sparse partial-update record sent from the React webview to Swift via `BibleWorkspaceIntent`. Files:

- `CharacterPatch.swift`
- `LorebookEntryPatch.swift`
- `DynamicSheetPatch.swift`
- `ReferencePatch.swift`
- `TemplateScenePatch.swift`
- `SceneExemplarPatch.swift`

Each follows the pattern of `Patch { id: UUID; fieldA: NewValue?; fieldB: NewValue?; ...}` where nil = no change. Swift applies the patch, then re-pushes the full snapshot.

## 10. Bible Workspace snapshot

`Sources/LoomCore/Models/BibleWorkspaceSnapshot.swift`

```swift
public struct BibleWorkspaceSnapshot: Codable, Equatable {
    public var characters: [SnapshotCharacter]
    public var lorebook: [LorebookEntry]
    public var dynamics: [DynamicSheet]
    public var references: [SnapshotReference]
    public var templateScenes: [SnapshotTemplateScene]
    public var sceneExemplars: [SnapshotSceneExemplar]
    public var proposedEntities: [SnapshotProposedEntity]
    public var proposedRelationships: [SnapshotProposedRelationship]
    public var pendingSuggestions: [PendingSuggestion]
    public var discoveringSceneIds: [String]      // L9 in-flight indicator
    public var ingestingReferenceIds: [String]    // L5 in-flight indicator
    public var extractingTemplateIds: [String]    // L7 in-flight indicator
    public var scenes: [SceneSummary]             // id + title + word count for cross-refs
}
```

`SnapshotCharacter` re-keys `knownFactsBySceneId` from `[UUID: [KnownFact]]` to `[String: [KnownFact]]` for JS-friendly JSON-object form. The snapshot is JSON-serialised and pushed to the React side via `BibleWorkspaceBridge` on every mutation.

## 11. Project Tools snapshot

`Sources/LoomCore/Models/ProjectToolsSnapshot.swift`

A read-only projection for the (future) Project Tools webview surface. Currently a thin slice: `ToolsCharacter { id, name }` for the relationship-map view. Will grow with each tool added; kept separate from `BibleWorkspaceSnapshot` to avoid coupling tool surfaces to the Bible editor.

## 12. Planned Project (outline mode)

`Sources/LoomCore/Models/PlannedProjectConfig.swift` + `PlannedProjectSnapshot.swift`

```swift
public struct PlannedProjectConfig: Codable, Equatable {
    // The guided-planning record: framework choice, premise, beats, sketch, …
}
```

`PlannedProjectSnapshot` projects the config + the framework's beats for the Planned Project webview. `Sources/LoomCore/Models/StoryFramework.swift` defines `StoryFramework` (protocol) + `SaveTheCatFramework` + `StoryFrameworks` registry (currently Save-the-Cat only). `BeatSlot` is a single named beat with summary + target word count.

The whole subsystem is L9.x/Planned-Project-mode (see [`LOOM_PLANNED_PROJECT.md`](LOOM_PLANNED_PROJECT.md)).

## 13. Fanfic metadata

`Sources/LoomCore/Models/FanficMetadata.swift`

Schema landed for forward-compat migration; UI deferred to Phase 5.b/5.c.

```swift
public struct FanficMetadata: Codable, Equatable {
    public var fandoms: [Fandom]
    public var attg: ATTG                  // Author / Title / Tagline / Genre, NovelAI Erato pattern
    public var rating: AO3Rating           // .general | .teen | .mature | .explicit | .notRated
    public var warnings: [AO3Warning]      // chooseNotToWarn, majorCharDeath, etc.
    public var category: AO3Category       // .gen | .het | .slash | …
    public var ships: [Ship]               // first-class relationship records
    public var primaryCharacters: [UUID]   // → Bible.characters
    public var tropes: [Trope]
    public var aus: [AU]
}
```

Subtypes (`Fandom`, `ATTG`, `Ship` + `ShipKind`/`ShipDynamic`, `Trope` + `TropeCategory` + `TropeLength` + `TropeHints`, `AU`, three AO3 enums) all live in the same file.

## 14. App-level settings + server profiles

### 14.1 `AppSettings`

`Sources/LoomCore/Models/AppSettings.swift`

```swift
public struct AppSettings: Codable, Equatable {
    public var schemaVersion: Int
    public var servers: [ServerProfile]
    public var defaultServerId: UUID?        // default writer server
    public var extractorServerId: UUID?      // default structured-task server
    public var recentProjectURLs: [URL]
}
```

Persisted by `AppSettingsStore` to `~/.../<app-support>/settings.json`.

### 14.2 `ServerProfile`

`Sources/LoomCore/Models/ServerProfile.swift`

```swift
public struct ServerProfile: Codable, Equatable, Identifiable {
    public let id: UUID
    public var name: String
    public var baseURL: URL
    public var kind: ServerKind              // .koboldcpp | .ollama
    public var capabilities: ServerCapabilities?  // model name, trueMaxContext, version
    public var lastProbed: Date?
}
```

Probing happens via `ServerProbe`, `OllamaProbe`, `AutoProbe`; results cache into `capabilities`.

## 15. Style library (writer-prompt voice presets)

`Sources/LoomCore/Models/Style.swift` + `StyleLibrary.swift`

```swift
public enum StyleType: String, Codable {
    case voice, genre, narrativeStyle, period
}

public struct Style: Codable, Equatable {
    public let id: UUID
    public var type: StyleType
    public var name: String
    public var prompt: String       // injected as system-prompt addendum
    public var isBuiltIn: Bool
    public var descriptor: String?  // short description shown in pickers
}
```

`StyleLibrary` is the built-in registry (LitRPG genre + others). User-defined styles persist via `StyleLibraryStore` to `<app-support>/styles.json`. Distinct from the `Phase-5 Reference` retrieval pipeline — Styles are *system-prompt presets*, References are *RAG corpora*.

## 16. NSFW posture + memory presets

### 16.1 `ProjectMemoryPresets`

`Sources/LoomCore/Models/ProjectMemoryPresets.swift`

```swift
public struct ProjectMemoryPreset: Equatable {
    public let title: String
    public let text: String
}
```

`ProjectMemoryPresets` is a namespace enum with built-in `loomDefault`, `heavyNSFW`, `minimal` presets. `ProjectStorage` seeds new projects with the user-chosen preset's text into `ProjectSettings.memory`.

### 16.2 `AntiSlopDefaults`

`Sources/LoomCore/Models/AntiSlopDefaults.swift`

A namespace enum containing the curated anti-slop phrase list seeded into `ProjectSettings.antiSlopPhrases` for new projects. Fed to KoboldCpp as `banned_strings` (phrase-level backtracking sampler) via `GenerateRequest.bannedStrings`.

### 16.3 `SphiratriothStarterPack`

`Sources/LoomCore/Models/SphiratriothStarterPack.swift`

A namespace enum carrying the bundled Sphiratrioth power-user pack — pre-built characters, lorebook entries, dynamics, anti-slop phrases. Imported on demand from Settings → Resources.

### 16.4 `WorkFraming`

`Sources/LoomCore/Models/WorkFraming.swift`

```swift
public struct FramedElement: Codable, Equatable {
    public var role: String              // "literary intent", "trigger warning", etc.
    public var text: String
    public var stance: ContentStance     // .embrace | .neutral | .resist
}
```

Per-project list under `ProjectSettings.workFraming`. Each `FramedElement` becomes a system-prompt clause framing the work's stance on its own content.

## 17. Generation log

`Sources/LoomCore/Models/GenerationLog.swift`

```swift
public struct GenerationLogEntry: Codable, Equatable {
    public let id: UUID
    public let sceneId: UUID
    public let timestamp: Date
    public let mode: GenerationMode
    public let model: String
    public let serverProfileId: UUID
    public let promptAssembly: PromptAssembly
    public let response: GenerationResponse
    public var templateGenerationInfo: TemplateGenerationInfo?  // L7 only
}

public struct PromptAssembly: Codable, Equatable {
    public var contextChiclets: [ContextChiclet]   // for the History UI
    public var fullPrompt: String                   // verbatim text sent to server
    public var promptTokens: Int
}

public struct GenerationResponse: Codable, Equatable {
    public var rawText: String
    public var completionTokens: Int
    public var stopReason: String?
    public var samplerSnapshot: GenerationDefaults
    public var refusalDetected: Bool
    public var elapsedMs: Int
}
```

One file per generation event at `generation-log/<iso-timestamp>.json`. `ContextChiclet` carries `label / sourceKind: ChicletKind / sourceId / contentExcerpt / fullContent / tokenCount`; `ChicletKind` covers `recentProse, sceneSummary, chapterSummary, projectSummary, characterSheet, settingSheet, objectSheet, factionSheet, lorebookEntry, authorsNote, memory, styleSheet, sceneMetadata, knowledgeLedger, fewShotStyleExample, dynamicSheet, writingDirection`.

`TemplateGenerationInfo` carries L7's per-template generation metadata (template id, beat being generated, etc.) — set only when `mode == .templateScene`.

## 18. Narrative classification

`Sources/LoomCore/Models/NarrativeMode.swift` + `NarrativeStyle.swift`

```swift
public enum NarrativeMode: String, CaseIterable, Codable {
    case dialogue, interiority, description, action, summary
}

public enum POVStyle: String, Codable {
    case firstPerson, thirdLimited, thirdOmniscient, secondPerson
}

public enum NarrativeTense: String, Codable {
    case past, present
}
```

`NarrativeMode` is the modality taxonomy used by retrieval (chunk-level tag), Scene-Template Generation (per-beat modality match), and the heuristic classifier (`NarrativeModeHeuristic` / `NarrativeModeClassifier` / `KoboldNarrativeModeClassifier`).

`InjectionMode`, `LengthScenario`, `OutlineSizing` are smaller enums used by per-mode prompt assembly and outline generation; trivial.

## 19. Lazy versioning + migration

- **Schema version** field on `Project` and `AppSettings`. Start at 1; bump only on *non-additive* changes.
- **Additive fields** use `decodeIfPresent` with a sensible default. No explicit migration needed.
- **Field rename or type swap** → versioned migration step in the decoder's `init(from:)`. Don't add a migration step until first encountered (RPClient's lazy-versioning pattern).
- **On-disk format is the contract.** A future Loom version that can't read a current `.loom/` directory is a regression. `Phase1SchemaVersion` tests pin the round-trip property for every additive change.

The `extraFrontmatter: [String: String]` field on `Scene` and `ReferenceText` is a *forward-compat sink* — any unknown YAML frontmatter key lands there on decode and round-trips back on encode, so older versions don't lose newer-version state.

## 20. On-disk layout

```
MyNovel.loom/
├── project.json                  # everything in `Project` except scene prose + per-tool sidecars
├── project.json.bak              # last-good copy, written before each save
├── scenes/
│   └── <scene-id>.md             # YAML frontmatter (Scene minus prose) + Markdown body (prose)
├── generation-log/
│   └── <iso-ts>.json             # GenerationLogEntry, one per event
├── references/                   # L5 — references + scene-exemplar reference halves
│   ├── <id>.md                   # ReferenceText body
│   └── <id>.index                # ReferenceTextIndex (chunks + Wegmann + funcwordZ + modality)
├── templates/                    # L7 — template scenes + scene-exemplar template halves
│   ├── <id>.md                   # template prose
│   └── <id>.beats.json           # Pass-A skeleton (beats, modality, tension, pacing)
├── snapshots/                    # Manual + pre-rewrite snapshots
│   └── <iso-ts>-<sceneid>.json   # Snapshot record (full prose at time of snapshot)
├── proposed-entities/            # L9 — entity discovery proposals awaiting accept/reject
│   └── proposed-entities.json    # single store; one file holds all pending proposals
├── proposed-relationships/       # L9 — dormant per HANDOFF §15.27
│   └── proposed-relationships.json
├── continuity-audit/             # L10 — audit findings (status carries across re-audits)
│   └── audit.json                # single file; replaced on each audit, status flags preserved
├── relationship-map/             # Future relationship-graph layout state
│   └── layout.json
└── template-gen-state/           # L8 per-template generation UI state (cast mapping etc.)
    └── <template-id>.json
```

Plus app-level state at `~/Library/Application Support/Loom/`:

```
settings.json                     # AppSettings (server profiles, recent projects, defaults)
styles.json                       # User-defined entries on top of StyleLibrary built-ins
```

### 20.1 Scene markdown frontmatter

`Sources/LoomCore/Storage/SceneFile.swift`

```markdown
---
id: 9b2c4a-…
title: "The Opening"
pov: 5e7d8f-…
location: 4a3b1c-…
status: draft
targetWordCount: 1500
conflict: "Mia confronts the stranger at the door."
outcome: "Stranger leaves; Mia bolts the door."
summary: "Mia, alone in her flat, opens the door to a stranger…"
summaryDirty: false
framing: ""
explicitnessLevel: explicit
undressedCharacterIds: []
extraFrontmatter:
  customKey: "value-from-a-future-version"
---

The wind had been picking up for an hour…

[scene prose]
```

Round-trip property: any markdown editor (Obsidian, iA Writer, VSCode) opens these cleanly. Unknown frontmatter keys land in `extraFrontmatter` so a future Loom can add fields without older Loom losing them.

### 20.2 Why bible entries live inline in `project.json`

Phase 0's design proposed `bible/characters/<id>.json` per-entity files. The shipped reality is *all bible state lives inline in `Project.bible`* (a single struct in `project.json`). Reason: bible entries are denser metadata with cross-references (relationships, lorebook secondary keys, dynamic sheet participants) — single-file storage avoids the multi-file consistency problem at the cost of larger project.json. Trade-off accepted; revisit if `project.json` grows past a few MB in practice.

### 20.3 Why `generation-log` is one file per event

Append-only, easy to back up, easy to delete selectively, easy to audit. A JSON-lines file would be simpler but harder to explore in Finder / VS Code. A future "compact older logs" function could batch them.

## 21. Cross-references

- [`LOOM_STORY_BIBLE.md`](LOOM_STORY_BIBLE.md) — Character / knowledge-ledger extraction pipeline.
- [`LOOM_GENERATION_MODES.md`](LOOM_GENERATION_MODES.md) — per-mode prompt assembly that consumes these shapes.
- [`LOOM_BIBLE_WORKSPACE.md`](LOOM_BIBLE_WORKSPACE.md) — webview snapshot/patch pattern.
- [`LOOM_CONTINUITY_AUDIT.md`](LOOM_CONTINUITY_AUDIT.md) §3 — extracted-claim shape + adjudication.
- [`LOOM_FANFIC.md`](LOOM_FANFIC.md) — fanfic-metadata schema rationale.
- [`LOOM_NSFW.md`](LOOM_NSFW.md) — writing-direction / memory-preset / anti-slop posture.
- [`LOOM_PLANNED_PROJECT.md`](LOOM_PLANNED_PROJECT.md) — guided outline mode.
- [`LOOM_TECH_STACK.md`](LOOM_TECH_STACK.md) — solved-problem registry indexed by problem.

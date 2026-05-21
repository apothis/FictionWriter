# Data model

Every Codable shape Loom persists and every artefact it writes to disk. This page is the source-of-truth map. The Models/*.swift files cited are the canonical schema — this page is a reference, not a spec.

> **Code wins where LOOM_DATA_MODEL.md disagrees.** That document predates ~half of the current model — Lorebook, Dynamics, References, Templates, Scene Exemplars, Continuity Findings, Proposed Entities, Proposed Relationships, Work Framing, Writing Direction, Fanfic Metadata, Planned Project Config all post-date its last major rewrite. Use it for design intent on the parts it does cover, but always cross-check against `Sources/LoomCore/Models/`.

## On-disk catalogue

### Inside a project bundle

```
<title>.loom/                              ← package directory; Finder shows it as a file icon
├── project.json                           ← Project (top-level Codable)
├── project.json.bak                       ← last-known-good snapshot, written before each save
├── scenes/<uuid>.md                       ← Scene (frontmatter) + prose (body)
├── generation-log/<iso-ts>-<uuid>.json    ← GenerationLogEntry
├── snapshots/<uuid>-<iso-ts>.json         ← Snapshot
├── references/<uuid>.md                   ← ReferenceText frontmatter + body
├── references/<uuid>.index                ← ReferenceTextIndex (chunks + D + E vectors)
├── templates/<uuid>.md                    ← TemplateScene frontmatter + body
├── templates/<uuid>.beats.json            ← ExtractedSceneSkeleton (Pass-A output)
├── template-gen-state/<templateId>.json   ← per-template UI state (cast mapping + toggle)
├── continuity-audit/audit.json            ← ContinuityFindings collection
├── proposed-entities/proposed-entities.json
├── proposed-relationships/proposed-relationships.json
└── relationship-map/layout.json           ← UI layout (node positions)
```

### App-wide files (outside any project)

```
~/Library/Application Support/Loom/
├── settings.json                          ← AppSettings (server profiles, recents, schema)
└── styles.json                            ← StyleLibrary (cross-project named-style entries)
```

### Debug artifact (not Loom-managed)

```
$TMPDIR/loom-debug.log                     ← append-only debug log; recreated on every launch
```

## Schema versioning + forward-load posture

Loom's persistence rule: **schema migrations are lazy and forward-load-tolerant.** Every top-level Codable in the project bundle uses `decodeIfPresent` with a sensible default for every additive field. There's no migration framework; an old project.json reads cleanly into a newer schema because every newer field is optional.

Concrete shape this takes:

- New fields are added with a default that recovers the previous behaviour.
- `Project.schemaVersion` is present + reads back, but isn't gated against — load doesn't fail on a mismatched version.
- Tests pin each schema with at least one "old-JSON-decodes" case (repo convention).
- The `decodeIfPresent`-bearing `init(from:)` implementations are deliberately verbose so additive fields have an obvious place to land.

The on-disk bundle is the source of truth for prose (the .md bodies). `project.json.bak` is a one-deep backup written before each save; `ProjectStorage.loadProjectWithRecovery` falls back to it automatically on a decode failure.

## Project tree

### `Project` — `Models/Project.swift`

The top-level shape, persisted as `project.json`.

| Field | Type | Notes |
|---|---|---|
| `id` | `UUID` | Project identity. Stable across renames. |
| `title` | `String` | User-visible name. |
| `author` | `String?` | Optional. |
| `createdAt` | `Date` | ISO8601 ms-rounded. |
| `schemaVersion` | `Int` | Read but not enforced; load is permissive. |
| `kind` | `ProjectKind` | `.originalFiction` or `.fanfic`. |
| `settings` | `ProjectSettings` | See below. |
| `manuscript` | `Manuscript` | Tree of Parts / Chapters / orphaned scenes. |
| `bible` | `Bible` | Characters + Settings + Objects + Lorebook + Dynamics. |
| `notes` | `String` | Free-form per-project notepad. |
| `selectedInspectorTab` | `InspectorTab?` | Last-viewed tab (bible / history / notes). |
| `fanficMetadata` | `FanficMetadata?` | Populated only when `kind == .fanfic`. |
| `plannedConfig` | `PlannedProjectConfig?` | Set when the project was created through the Planned Project wizard. |

`InspectorTab`: `bible | history | notes`. `ProjectKind`: `originalFiction | fanfic`.

### `ProjectSettings` — same file

| Field | Type | Notes |
|---|---|---|
| `serverProfileId` | `UUID?` | Per-project override of the app-wide writer; usually nil. |
| `contextBudgetTokens` | `Int` | Default 8192. |
| `generationDefaults` | `GenerationDefaults` | Per-mode word targets + sampler defaults. |
| `authorsNote` | `String` | The Author's-Note text. |
| `authorsNoteDepthLines` | `Int` | Default 4 — depth-N from end. |
| `memory` | `String` | The Project-Memory text. |
| `instructTemplate` | `InstructTemplate` | `auto / chatml / gemma3 / gemma4 / mistralV3 / mistralV7 / llama3 / alpaca / raw`. |
| `writingDirection` | `WritingDirection` | See *Writing direction + work framing* below. |
| `pov` | `POVStyle` | Project-level POV. |
| `tense` | `NarrativeTense` | Project-level tense. |
| `targetWordCount` | `Int?` | Optional whole-project target. |
| `antiSlopPhrases` | `[String]` | Seeded from `AntiSlopDefaults.phrases` at project creation. |
| `workFraming` | `[FramedElement]` | Per-element content stance (AO3-style). |

`GenerationDefaults`: continueWordTarget (500), expandWordTarget (1500), temperature (1.0), minP (0.05), DRY multiplier (0.8) / base (1.75) / allowedLength (2), XTC threshold (0.10) / probability (0.50), topK (0), maxOutputTokens (1024).

### `Manuscript` — `Models/Manuscript.swift`

| Field | Type | Notes |
|---|---|---|
| `partIds` | `[UUID]` | Legacy Phase 1 field. Forward-load only. |
| `parts` | `[Part]` | Phase 3 ordered Part list. |
| `orphanedSceneIds` | `[UUID]` | Scenes not placed in a Chapter. |
| `trashedSceneIds` | `[UUID]` | Deleted scenes; survives close. |

### `Part`, `Chapter` — `Models/PartChapter.swift`

`Part`: id, title, `chapters: [Chapter]`, notes.

`Chapter`: id, title, `sceneIds: [UUID]`, `summary: String?` (recursive-summary slot), `summaryDirty: Bool`, `targetWordCount: Int?`, notes.

### `Scene` — `Models/Scene.swift`

Persisted as `scenes/<id>.md` — YAML frontmatter for the Codable fields below + prose body. `Scene.prose` is runtime-only (excluded from Codable).

| Field | Type | Notes |
|---|---|---|
| `id` | `UUID` | |
| `title` | `String` | |
| `pov` | `UUID?` | POV character id. |
| `location` | `UUID?` | Setting id. |
| `status` | `SceneStatus` | `todo / draft / revised / final`. |
| `conflict`, `outcome`, `summary` | `String` | Outline fields. |
| `summaryDirty` | `Bool` | Marks regen-needed when prose changes. |
| `targetWordCount` | `Int?` | |
| `contentPath` | `String` | Derived from id (`scenes/<id>.md`). |
| `notes` | `String` | Private; not injected. |
| `framing` | `String` | Per-scene scenario block; injected near cursor. |
| `explicitnessLevel` | `ExplicitnessLevel?` | Per-scene override of project-level. |
| `undressedCharacterIds` | `[UUID]` | AnatomyGate signal. |
| `generatedSpans` | `[GeneratedSpan]` | Per-generation visual + provenance record. |
| `snapshots` | `[Snapshot]` | Pre-rewrite snapshots. |
| `extraFrontmatter` | `[String: String]` | Forward-compat sink. |

`GeneratedSpan`: per-generation range + accepted flag + prompt-log back-pointer.

`Snapshot`: pre-generation prose + timestamp + mode (in `Models/Scene.swift`).

### `GenerationMode` — same file

```
continueProse | expand | rewrite | rewriteVoice | rewriteTense | rewritePOV |
rewriteLength | showDontTell | brainstorm | critique | bridge | describe | nameSuggest
```

Five of these (`brainstorm / critique / bridge / describe / nameSuggest`) have prompt code but no UI surface today; see **Generation modes** in the User Help.

## Bible

### `Bible` — `Models/Bible.swift`

Five arrays: `characters`, `settings`, `objects`, `lorebook`, `dynamics`. Holder type; the entity types are below.

### `Character` — `Models/Character.swift`

The richest entity. See **Story Bible — Characters, Settings, Objects** in User Help for the field-by-field exposition.

Fields: `id`, `name`, `aliases`, `role`, `oneLine`, `description`, `personality`, `appearance`, `voice`, `goals`, `relationships`, `avatarPath`, `knownFactsBySceneId`, `canonBrief`, `customFields`, `injectionMode`, `kinks`, `apparentAnatomy`, `intimateAnatomy`.

Sub-types in the same file:

- `CharacterRole`: `protagonist | antagonist | supporting | minor | narrator`.
- `Relationship`: `toCharacterId`, `kind`, `status` (`current | past`), `notes`, `sourceSceneId?`.
- `KnownFact`: `id`, `fact`, `sourceSceneId?`, `certainty`, `addedAt`.
- `Certainty`: `asserted | suspected | unknown | mistaken`.
- `CharacterCustomField`: `label`, `value`, `kind` (`text | multilineText`).
- `CharacterKink`: `name`, `stance` (`into | curious | softLimit | hardLimit`).

### `Setting`, `BibleObject` — `Models/Setting.swift`

`Setting`: id, name, aliases, description, sensoryNotes, significantObjectIds, notes, injectionMode.

`BibleObject`: id, name, aliases, description, significance, notes, injectionMode.

### `LorebookEntry` — `Models/LorebookEntry.swift`

See **Story Bible — Lorebook entries** in User Help.

Fields: `id`, `name`, `content`, `activationMode`, `keys`, `secondaryKeys`, `enabled`, `priority`, `positionMode`, `depth`, `maxRecentScenesScanned`, `group`, `weight`, `sticky`, `activateFromSceneId`, `activateUntilSceneId`.

Enums:

- `LorebookActivationMode`: `constant | keyed | vectorised` (vectorised treated as inactive today).
- `LorebookPositionMode`: `top | bottom | depthN`.

### `DynamicSheet` — `Models/DynamicSheet.swift`

See **Story Bible — Dynamics** in User Help.

Fields: `id`, `name`, `participantIds`, `roles`, `wants`, `softLimits`, `hardLimits`, `safeword`, `arc`, `alwaysOn`, `enabled`.

### `InjectionMode` — `Models/InjectionMode.swift`

`constant | keyed`. Shared by `Character`, `Setting`, `BibleObject`. Lorebook entries have their own (richer) activation mode enum above.

## References + Templates on disk

### `ReferenceText` — `Models/ReferenceText.swift`

Persisted as `references/<id>.md` with frontmatter for the metadata fields + prose body. `body` is runtime-only.

Fields: `id`, `name`, `nsfw`, `createdAt`, `extraFrontmatter`, `body`.

### `ReferenceTextIndex` — same file

Persisted as `references/<id>.index` (JSON sidecar).

| Field | Type | Notes |
|---|---|---|
| `schemaVersion` | `Int` | |
| `dModel` | `ModelFingerprint?` | id + dim of the D embedder (Wegmann). |
| `eModel` | `ModelFingerprint?` | id + dim of the E signal (funcword-z). |
| `chunks` | `[Chunk]` | Per-chunk text + word range + modality + dVec + eVec. |

`Chunk`: `text`, `wordRangeStart`, `wordRangeEnd`, `modality?` (NarrativeMode), `dVec: [Float]?`, `eVec: [Float]?`.

### `TemplateScene` — `Templates/TemplateScene.swift`

Persisted as `templates/<id>.md` with frontmatter + prose. Shares UUID with the paired ReferenceText (Phase 8 unification).

Fields: `id`, `name`, `nsfw`, `createdAt`, `extraFrontmatter`, `body`.

### `ExtractedSceneSkeleton` — `Templates/BeatExtraction.swift`

Persisted as `templates/<id>.beats.json`. Pass-A output. Carries: ordered beats (`SceneBeat[]`), voice descriptor, cast / setting markers extracted from the source prose. Each `SceneBeat` has a modality tag + word range + brief content sketch.

## Writing direction + work framing

### `WritingDirection` — `Models/WritingDirection.swift`

| Field | Type | |
|---|---|---|
| `kind` | `DirectionKind` | `literary / mainstream / romance / erotica / porn` |
| `register` | `VocabularyRegister` | `clinical / literary / earthy / crude / mixed` |
| `explicitnessLevel` | `ExplicitnessLevel` | `fadeToBlack / suggestive / onScreen / graphic / extreme` |
| `themes` | `[Theme]` | User-configured per-project. |
| `pacing` | `PacingProfile` | `fastPlot / balanced / slowExplicit / explicitForeground` |
| `fadeToBlackPolicy` | `FTBPolicy` | `never / userChoice / modelDecides` |

`Theme`: `id`, `name` (free-form), `description`, `alwaysOn`, `styleExemplarRefs: [UUID]`.

### `POVStyle`, `NarrativeTense` — `Models/NarrativeStyle.swift`

`POVStyle`: `firstPerson / secondPerson / thirdPersonLimited / thirdPersonOmniscient / thirdPersonObjective`.

`NarrativeTense`: `past / present`.

### `WorkFraming` — `Models/WorkFraming.swift`

`[FramedElement]` lives on `ProjectSettings.workFraming`. Each `FramedElement`: `id`, `label`, `stance` (`ContentStance`).

`ContentStance`: `playedStraight | critiquedExplored | gentleHandling | inverted | notPresent`. `playedStraight` feeds an anti-softening clause into the system prompt.

### `AntiSlopDefaults` — `Models/AntiSlopDefaults.swift`

A `static let phrases: [String]` of community-curated overused-AI phrases. Seeded onto `ProjectSettings.antiSlopPhrases` at project creation; sent to KoboldCpp as `banned_strings`.

### `ProjectMemoryPresets` — `Models/ProjectMemoryPresets.swift`

Three preset templates for `ProjectSettings.memory`: `loomDefault`, `heavyNSFW` (Marinara), `minimal`. The `loomDefault` text is seeded on new projects.

## Generation log

### `GenerationLogEntry` — `Models/GenerationLog.swift`

Persisted as `generation-log/<iso-ts>-<uuid>.json`. One file per generation event.

| Field | Type | |
|---|---|---|
| `id` | `UUID` | |
| `sceneId` | `UUID` | |
| `timestamp` | `Date` | ISO8601 ms-rounded. |
| `mode` | `GenerationMode` | |
| `model` | `String?` | Resolved at call time. |
| `serverProfileId` | `UUID?` | |
| `promptAssembly` | `PromptAssembly` | Full assembled prompt + per-layer chiclets + tokens + evictions. |
| `response` | `GenerationResponse` | Raw text + completion tokens + stop reason + refusal flag + elapsedMs. |
| `templateGenerationInfo` | `TemplateGenerationInfo?` | Non-nil for template-driven generations. |

`PromptAssembly`: `contextChiclets`, `fullPrompt`, `promptTokens`, `aboveCacheTokens`, `belowCacheTokens`, `evictedLayers: [String]`, `template`.

`GenerationResponse`: `rawText`, `completionTokens`, `stopReason?`, `refusalDetected`, `elapsedMs`.

`TemplateGenerationInfo`: `templateId`, `templateName`, `castMapping`, `beatCount`, `beatModalitySequence: [String]`, `voiceDescriptor?`, `imitateContent?`.

## Discovery + audit queues

### `ProposedEntity` — `Generation/EntityDiscovery.swift`

Persisted as `proposed-entities/proposed-entities.json`. Collection of `ProposedEntity` + `ProposedEntityFacts`.

`ProposedEntity`: `id`, `kind` (`character | place | object`), `canonicalName`, `aliases`, `oneLine`, `evidenceQuote`, `sourceSceneId`, `confidence` (clamped 0..1).

`ProposedEntityFacts`: `proposedEntityId`, `facts: [LedgerExtraction.ExtractedFact]`.

### Proposed relationships — `Storage/ProposedRelationshipsStore.swift`

`proposed-relationships/proposed-relationships.json`. Shapes in `Generation/RelationshipDiscovery.swift`.

### Continuity findings — `Generation/ContinuityFinding.swift` + `Storage/ContinuityAuditStore.swift`

`continuity-audit/audit.json`. Carries the latest audit-run output as `ContinuityFinding` rows: scene-pair references, claim pair, adjudication result, severity. Per-run; replaces on re-run.

### Relationship-map layout — `Storage/RelationshipMapLayoutStore.swift`

`relationship-map/layout.json`. UI-only — saved node positions for the relationship-map view. No semantic data.

## Webview snapshots + patches

The four webview panels each have a snapshot type (Swift → JS) and a set of patch types (JS → Swift). All Codable.

| Panel | Snapshot | Patch types |
|---|---|---|
| Bible Workspace | `BibleWorkspaceSnapshot` | `CharacterPatch`, `LorebookEntryPatch`, `DynamicSheetPatch`, `ReferencePatch`, `TemplateScenePatch`, `SceneExemplarPatch` |
| Planned Project | `PlannedProjectSnapshot` | (no Codable patch — discrete intents) |
| Project Tools | `ProjectToolsSnapshot` | (discrete intents) |
| Help (this panel) | `HelpSnapshot` | `HelpIntent` (selectSection, switchBook) |

The snapshot types are **projections** of the underlying bible — they map `[UUID: [KnownFact]]` to string-keyed dictionaries for JS-friendliness, omit prose blobs, include only the fields the view needs. They are not the source of truth; the Models/ Codables are.

The patch types are partial — every field is optional; absent = no change. The reducer-on-Swift applies the patch onto the live model.

## App-wide

### `AppSettings` — `Models/AppSettings.swift`

`~/Library/Application Support/Loom/settings.json`.

| Field | Type | |
|---|---|---|
| `schemaVersion` | `Int` | |
| `servers` | `[ServerProfile]` | Configured backends. |
| `defaultServerId` | `UUID?` | Writer role. |
| `extractorServerId` | `UUID?` | Extractor role (Phase 4 #7). |
| `recentProjectURLs` | `[URL]` | Newest first, capped at 5. |

### `ServerProfile` — `Models/ServerProfile.swift`

`id`, `name`, `baseURL`, `kind` (`ServerKind.kobold | ollama`), `capabilities: ServerCapabilities?`, `lastProbed: Date?`.

`ServerCapabilities`: `modelName?`, `trueMaxContext?`, `version?` — populated by `ServerProbe` / `OllamaProbe`.

### `StyleLibrary` — `Models/StyleLibrary.swift` + `Storage/StyleLibraryStore.swift`

`~/Library/Application Support/Loom/styles.json`. Cross-project named-style entries. `Style`: `name`, `type` (`StyleType`), preset content. Used by the Style Library menu + Rewrite → Voice.

## Cross-cutting types

- **`UUID`** — used as the stable identity primitive everywhere. Stored as RFC 4122 lowercase strings.
- **`Date`** — ISO8601 with millisecond precision. `Project.createdAt`, `GenerationLogEntry.timestamp`, etc. are rounded to ms via `LoomISO8601.roundedToMillisecond` at construction so round-trip identity holds.
- **`JSONCoders`** — `JSONEncoder.loom` (sorted keys + pretty-print + ISO8601-ms) / `JSONDecoder.loom` (matching format). All persistence uses these via `Models/JSONCoders.swift`.

## Forward-compat conventions

- **`extraFrontmatter: [String: String]`** on `Scene` / `ReferenceText` / `TemplateScene` — sink for unknown YAML keys, so a forward-loaded file that was written by a newer Loom doesn't lose data on a round trip.
- **`decodeIfPresent` everywhere new fields land** — every `init(from:)` reads new fields with `?? default`.
- **Backup-on-save**: `ProjectStorage.saveProject` writes `project.json.bak` before each save, but only after verifying the existing `project.json` round-trips through decode. A corrupted on-disk file doesn't overwrite a good backup.
- **Atomic writes**: every disk write goes through a sibling temp file + rename (`ProjectStorage.atomicWrite`).

## See also

- **Architecture overview** — runtime services + three primary data-flow paths.
- **Repo layout** — file-by-file map.
- **Generation pipeline** — how the prompt is assembled from the bible + recent prose + retrieved exemplars.
- [`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md) — historical design intent. Predates ~half the current model; cross-check before trusting.
- [`LOOM_TECH_STACK.md`](LOOM_TECH_STACK.md) — solved-problem registry. Indexed by problem, not by type.

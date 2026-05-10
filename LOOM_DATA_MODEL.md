# Loom Data Model

> **Status: Phase 0 design lock (2026-05-10).** Specifies the Codable shapes and on-disk layout. Companion to [`LOOM_PLAN.md`](LOOM_PLAN.md), [`LOOM_STORY_BIBLE.md`](LOOM_STORY_BIBLE.md). Every shape decision either points to a finding in [`LOOM_RESEARCH.md`](LOOM_RESEARCH.md) or stands as a flagged extension.
>
> **Conventions.** Swift `Codable` Foundation types. UUIDs for all identifiers. ISO-8601 dates. Per-scene metadata schema is yWriter's[J7] starting point (research §J.5) extended with Loom-specific fields. Round-trip property: any markdown file in the project must survive opening in another editor and saving back without corruption.

---

## 1. Top-level: Project

```swift
struct Project: Codable {
    let id: UUID
    var title: String
    var author: String?
    var createdAt: Date
    var schemaVersion: Int       // start at 1; bump on non-additive changes
    var settings: ProjectSettings
    var kind: ProjectKind        // .originalFiction default; .fanfic for fanfic-mode projects (Phase 5.c — see LOOM_FANFIC.md §3.1)
    var writingDirection: WritingDirection?  // Phase 2 — see LOOM_NSFW.md §3.1 (literary / mainstream / romance / erotica / porn + register + explicitnessLevel + themes + pacing + FTBPolicy)
    var fanficMetadata: FanficMetadata?      // Phase 5.c; only populated when kind == .fanfic

    // Manuscript root — Phase 1 has flat scenes; Phase 3+ adds Parts/Chapters.
    var manuscript: Manuscript

    // Bible — populated Phase 2+. Empty arrays in Phase 1.
    var bible: Bible

    // Style sheet — populated Phase 5; nil in Phase 1.
    var styleSheetId: UUID?

    // Reference texts — populated Phase 5; empty in Phase 1.
    var references: [ReferenceMeta]
}

struct ProjectSettings: Codable {
    var serverProfileId: UUID?              // overrides the global default
    var contextBudgetTokens: Int            // 8192 default; set per project
    var generationDefaults: GenerationDefaults
    var authorsNote: String                 // depth-N injection per NovelAI[C3]
    var authorsNoteDepthLines: Int          // 4 default; matches NovelAI A/N Strength
    var memory: String                      // always-top injection per KoboldAI[D1]
    var instructTemplate: InstructTemplate  // ChatML / Mistral V7 / Llama3 / Alpaca / Auto
}

enum InstructTemplate: String, Codable {
    case auto       // probe server, infer from model name
    case chatml     // Qwen, many merges
    case mistralV3
    case mistralV7
    case llama3
    case alpaca
    case raw        // no template; pure completion
}
```

Per [`LOOM_RESEARCH.md`](LOOM_RESEARCH.md) §I.4: the model's instruct template is *not* Loom's choice; it must respect the model card. `.auto` probes the server and tries to detect; user can override.

---

## 2. Manuscript hierarchy

```swift
struct Manuscript: Codable {
    var partIds: [UUID]              // ordered; Phase 3+. Phase 1: implicitly one part.
    var orphanedSceneIds: [UUID]     // Phase 1: every scene lives here.
}

// Phase 3+
struct Part: Codable {
    let id: UUID
    var title: String
    var chapterIds: [UUID]
    var notes: String                 // free-form author notes for this part
}

struct Chapter: Codable {
    let id: UUID
    var title: String
    var sceneIds: [UUID]
    var summary: String?              // recursive-summary feed (research §L.1)
    var summaryDirty: Bool            // marks regen needed when underlying scenes change
    var targetWordCount: Int?         // Scrivener-style target[J1]
    var notes: String
}

struct Scene: Codable {
    let id: UUID
    var title: String                 // human label; not displayed in prose
    var pov: UUID?                    // POV character — references Bible.characters
    var location: UUID?               // references Bible.settings
    var time: SceneTime?              // chronological positioning (Phase 4+)
    var conflict: String              // yWriter pattern[J7]: scene driver
    var outcome: String               // yWriter: how it resolves
    var summary: String               // 2-3 sentence recap; auto-extracted Phase 2+
    var summaryDirty: Bool
    var status: SceneStatus           // todo / draft / revised / final
    var targetWordCount: Int?
    var contentPath: String           // relative path to scenes/<id>.md
    var notes: String
    var generatedSpans: [GeneratedSpan]  // for History tab (§14.5.2 design language)
    var snapshots: [Snapshot]         // Phase 2+ — Scrivener[J1] pattern
}

enum SceneStatus: String, Codable {
    case todo, draft, revised, final
}

struct SceneTime: Codable {
    var narrativeOrder: Int           // sequential position in manuscript
    var chronologicalISODate: String? // optional in-fiction date
    var relativeAfter: UUID?          // "after scene X" relative ordering
}

struct GeneratedSpan: Codable {
    let id: UUID
    var generatedAt: Date
    var mode: GenerationMode
    var promptLogPath: String         // relative path to generation-log/<ts>.json
    var rangeInScene: NSRange?        // can be nil if user accepted then heavily edited
    var accepted: Bool
}

struct Snapshot: Codable {
    let id: UUID
    var takenAt: Date
    var label: String?                // user-supplied or "Before Rewrite"
    var contentSnapshot: String       // full scene prose at time of snapshot
}
```

The `generatedSpans` array is the live store of "what came from AI in this scene." After acceptance the visual badge fades, but the record persists for the History tab.

---

## 3. Bible — entity model

```swift
struct Bible: Codable {
    var characters: [Character]
    var settings: [Setting]
    var objects: [BibleObject]
    var factions: [Faction]
    var timeline: [TimelineEvent]
    var lorebook: [LorebookEntry]
    // Phase 5
    var styleSheets: [StyleSheet]
}
```

### 3.1 Character

Sudowrite Bible[A2] schema is the starting point; extended for Loom's knowledge-state-per-scene engineering (research §O.2).

```swift
struct Character: Codable {
    let id: UUID
    var name: String
    var aliases: [String]             // Novelcrafter[B3] alias-driven prompt-function injection
    var role: CharacterRole           // protagonist / antagonist / supporting / minor / narrator
    var oneLine: String               // one-sentence pitch
    var description: String           // multi-paragraph prose
    var personality: String           // multi-paragraph; "how they speak/decide"[A2]
    var appearance: String
    var voice: String                 // dialogue-style notes
    var goals: String
    var relationships: [Relationship]
    var avatarPath: String?           // optional image, like RPClient
    // Phase 4+ — knowledge ledger
    var knownFactsBySceneId: [UUID: [KnownFact]]
}

enum CharacterRole: String, Codable {
    case protagonist, antagonist, supporting, minor, narrator
}

struct Relationship: Codable {
    var toCharacterId: UUID
    var kind: String                  // free-form: "sister", "rival", "lover" — research §M.2 modular bible
    var notes: String
}

struct KnownFact: Codable {
    let id: UUID
    var fact: String                  // natural-language assertion[L4]
    var sourceSceneId: UUID?          // where they learned it (nil = pre-story knowledge)
    var certainty: Certainty
    var addedAt: Date
}

enum Certainty: String, Codable {
    case asserted     // character treats this as true
    case suspected    // character suspects but isn't sure
    case unknown      // character does NOT know — explicitly tracked
    case mistaken     // character believes a false thing
}
```

The `knownFactsBySceneId` map is **Loom's distinctive engineering**. At generation time for scene N, the prompt assembler queries each character's facts up to and including scene N-1 (chronologically, not narratively, for stories with non-linear order). Facts marked `unknown` are passed as anti-knowledge: "Mia does NOT know that Bob betrayed her."

This is the Re3 Edit module pattern[L4] extended to per-scene granularity. See [`LOOM_STORY_BIBLE.md`](LOOM_STORY_BIBLE.md) §3 for the extraction pipeline.

### 3.2 Setting

```swift
struct Setting: Codable {
    let id: UUID
    var name: String
    var aliases: [String]
    var description: String
    var sensoryNotes: String          // smell, sound, light — for Describe mode
    var significantObjectIds: [UUID]
    var notes: String
}
```

### 3.3 Object

```swift
struct BibleObject: Codable {
    let id: UUID
    var name: String
    var aliases: [String]
    var description: String
    var significance: String          // why this object matters in the story
    var notes: String
}
```

### 3.4 Faction (Phase 3+)

Borrowed from Campfire[K1] modular bible.

```swift
struct Faction: Codable {
    let id: UUID
    var name: String
    var aliases: [String]
    var description: String
    var goals: String
    var memberCharacterIds: [UUID]
    var notes: String
}
```

### 3.5 Timeline event (Phase 3+)

```swift
struct TimelineEvent: Codable {
    let id: UUID
    var title: String
    var description: String
    var chronologicalISODate: String?  // in-fiction date
    var sceneIds: [UUID]               // scenes that depict or reference this event
    var characterIds: [UUID]           // characters present
    var settingId: UUID?
}
```

Plottr[E1]-shaped 2D Timeline × Plotline grid is a Phase 4+ visualisation built on top of these events.

### 3.6 Lorebook entry

The NovelAI / KoboldAI / SillyTavern trichotomy[C1][D1][H1] (research §M.4):

```swift
struct LorebookEntry: Codable {
    let id: UUID
    var name: String
    var content: String
    var activationMode: ActivationMode
    var keys: [String]                // primary triggers
    var secondaryKeys: [String]       // AND-gating
    var enabled: Bool
    var priority: Int                 // ties broken by recency
    var positionMode: PositionMode    // top / bottom / depth-N
    var depth: Int?                   // applies to .depthN mode
    var maxRecentScenesScanned: Int   // analogous to NovelAI Search Range[C2]
}

enum ActivationMode: String, Codable {
    case constant     // always inject (highest cost)
    case keyed        // matches in recent prose trigger injection
    case vectorised   // Phase 5: semantic-similarity injection
}

enum PositionMode: String, Codable {
    case top          // memory-style: top of prompt
    case bottom       // author's note style: end of prompt
    case depthN       // N scenes/lines from end
}
```

This shape is intentionally close to SillyTavern's WorldInfoEntry — Loom users with prior SillyTavern experience can transfer intuition.

### 3.7 Style sheet (Phase 5)

```swift
struct StyleSheet: Codable {
    let id: UUID
    var name: String
    var toneDescriptors: [String]     // "noir", "wry", "lush", "spare"
    var sentenceLengthProfile: SentenceLengthProfile
    var lexicon: [LexiconEntry]
    var sampleParagraphs: [String]    // few-shot exemplars; always-on
    var derivedFromReferenceIds: [UUID]  // back-pointer to References used
}

struct SentenceLengthProfile: Codable {
    var meanWords: Double
    var stddev: Double
    var burstiness: Double            // mix of long+short sentences
}

struct LexiconEntry: Codable {
    var term: String
    var preferred: Bool               // true: prefer; false: avoid
    var notes: String
}
```

Most of these fields are auto-extracted from reference texts at Phase 5 ingestion time; user can edit afterward.

---

## 4. References (Phase 5)

```swift
struct ReferenceMeta: Codable {
    let id: UUID
    var label: String                 // user-supplied: "My past novel" / "Author X"
    var sourcePath: String            // relative path to references/<id>.md
    var indexPath: String             // relative path to references/<id>.index
    var ingestedAt: Date
    var wordCount: Int
    var sceneTypeTags: [SceneTypeTag] // counts per type (research §O.4)
}

struct SceneTypeTag: Codable {
    var type: SceneType
    var count: Int
}

enum SceneType: String, Codable {
    case action, dialogue, interiority, description, mixed, transition
}
```

The `sceneTypeTags` are populated by a side-call classifier during ingestion. Used at retrieval time to prefer same-type exemplars (research §O.4). The `<id>.index` sidecar is an embedding index format — implementation detail in Phase 5 design doc.

---

## 5. Generation modes (enum)

```swift
enum GenerationMode: String, Codable {
    case continueProse        // research [A6]
    case expand
    case rewrite
    case rewriteVoice
    case rewriteTense
    case rewritePOV
    case rewriteLength
    case showDontTell
    case brainstorm
    case critique
    case bridge
    case describe
    case nameSuggest
}
```

Full prompt templates live in [`LOOM_GENERATION_MODES.md`](LOOM_GENERATION_MODES.md).

```swift
struct GenerationDefaults: Codable {
    var continueWordTarget: Int       // ~500 default
    var expandWordTarget: Int         // ~1500 default
    var temperature: Double
    var minP: Double
    var dryMultiplier: Double         // research §I.3 sampler culture
    var dryBase: Double
    var dryAllowedLength: Int
    var xtcThreshold: Double
    var xtcProbability: Double
    var topK: Int
    var maxOutputTokens: Int
}
```

Defaults per research §I.3. Surfaced in Settings, editable per project, editable per generation in the inspector.

---

## 6. Generation log

Each generation event writes a JSON file to `generation-log/<iso-timestamp>.json`. Structure:

```swift
struct GenerationLogEntry: Codable {
    let id: UUID
    let sceneId: UUID
    let timestamp: Date
    let mode: GenerationMode
    let model: String                 // model name as reported by server
    let serverProfileId: UUID
    let promptAssembly: PromptAssembly
    let response: GenerationResponse
}

struct PromptAssembly: Codable {
    var contextChiclets: [ContextChiclet]   // for the History UI[A5]
    var fullPrompt: String                   // verbatim text sent to server
    var promptTokens: Int
}

struct ContextChiclet: Codable {
    var label: String                  // "20k recent prose", "Mia (character)", "Author's Note"
    var sourceKind: ChicletKind
    var sourceId: UUID?                // entity / lorebook / scene id
    var contentExcerpt: String         // first 200 chars
    var fullContent: String            // expandable in UI
    var tokenCount: Int
}

enum ChicletKind: String, Codable {
    case recentProse, sceneSummary, chapterSummary, projectSummary
    case characterSheet, settingSheet, objectSheet, factionSheet
    case lorebookEntry, authorsNote, memory, styleSheet
    case sceneMetadata, knowledgeLedger, fewShotStyleExample
}

struct GenerationResponse: Codable {
    var rawText: String
    var completionTokens: Int
    var stopReason: String?            // "stop_sequence" / "max_tokens" / "user_cancelled"
    var samplerSnapshot: GenerationDefaults  // captures actual values used
    var refusalDetected: Bool          // RPClient quirk detector inheritance
    var elapsedMs: Int
}
```

This log is the load-bearing artefact for transparency. The History inspector tab[§14.5.2] pages over these files.

---

## 7. On-disk layout

Per [`LOOM_PLAN.md`](LOOM_PLAN.md) §7:

```
MyNovel.loom/
├── project.json                      # Project shape minus per-scene prose
├── scenes/
│   ├── <scene-id>.md                 # YAML frontmatter + prose
│   └── ...
├── bible/
│   ├── characters/<id>.json          # Character
│   ├── settings/<id>.json
│   ├── objects/<id>.json
│   ├── factions/<id>.json
│   ├── timeline.json                 # [TimelineEvent]
│   ├── lorebook.json                 # [LorebookEntry]
│   └── style/<id>.json               # StyleSheet (Phase 5)
├── references/                       # Phase 5
│   ├── <ref-id>.md
│   └── <ref-id>.index                # embedding sidecar (binary)
├── knowledge/                        # Phase 4+
│   └── <scene-id>.json               # extracted [KnownFact] tuples
└── generation-log/
    └── <iso-timestamp>.json          # GenerationLogEntry
```

### 7.1 Scene markdown frontmatter

Each `scenes/<id>.md` opens with YAML frontmatter:

```markdown
---
id: 9b2c4a-...
title: "The Opening"
pov: 5e7d8f-...                # character id
location: 4a3b1c-...
status: draft
targetWordCount: 1500
conflict: "Mia confronts the stranger at the door."
outcome: "Stranger leaves; Mia bolts the door."
summary: "Mia, alone in her flat, opens the door to a stranger…"
summaryDirty: false
---

The wind had been picking up for an hour…

[scene prose]
```

**Round-trip property** is enforced by always reading the YAML block first, then treating everything after the closing `---` as prose. Any markdown editor (Obsidian, iA Writer, VSCode) opens these files cleanly. The Longform plugin precedent[J5] is exactly this shape.

### 7.2 Why bible entries are JSON, not markdown

Entity sheets are denser metadata — relationships, knowledge ledgers, lorebook activation modes — and don't benefit from in-editor authoring of their wire format. JSON is more honest about what they are. The Bible inspector pane is the editing UI; users don't open `bible/characters/<id>.json` in vim to edit a character.

### 7.3 Why generation-log is one file per event

Append-only log, easy to back up, easy to delete selectively, easy to audit. A single JSON-lines file would be simpler but harder to explore. Phase 6 polish may add a "compact older logs" function.

---

## 8. Migration posture

- **Schema version** starts at 1. Bump only on non-additive changes.
- **Additive fields** use `decodeIfPresent` per RPClient's pattern; no migration needed.
- **Field renames or type swaps** require a versioned migration path. Don't add one until first encountered (RPClient §6.1 lazy-versioning).
- **On-disk format is the contract.** A future Loom version that can't read a current `.loom/` directory is a regression. Tests pin the round-trip property.

---

## 9. Open data-model questions for Phase 1+

- **NSAttributedString state inside scenes.** Italics, bold are handled by markdown in the prose. But what about user-added comments (`<!-- TODO: rewrite this -->` style)? Decision deferred to Phase 1 implementation: lean toward HTML comments in prose for portability.
- **Multi-draft scene representation.** Phase 2+. Lean toward `Snapshot` covering the use case (full prose stored as a snapshot before AI rewrite).
- **References to unsynchronised state.** What if a Character is referenced (`@mia`) but the entity is later deleted? Decision: dangling references render as plain text with a warning in the History chiclet ("entity 'mia' was deleted; reference will not resolve").

---

## 10. References

**Internal:**
- [`LOOM_PLAN.md`](LOOM_PLAN.md) — phasing.
- [`LOOM_RESEARCH.md`](LOOM_RESEARCH.md) — every claim traces here.
- [`LOOM_STORY_BIBLE.md`](LOOM_STORY_BIBLE.md) — knowledge ledger extraction pipeline.
- [`LOOM_GENERATION_MODES.md`](LOOM_GENERATION_MODES.md) — per-mode prompt templates that read these shapes.
- [`LOOM_PHASE1_EDITOR_MVP.md`](LOOM_PHASE1_EDITOR_MVP.md) — Phase 1 sub-step contracts.

**External (RPClient):**
- `/Volumes/SSD1/Code/RPClient/Sources/RPClientCore/Storage.swift` — JSON-per-entity storage pattern (direct reuse).
- `/Volumes/SSD1/Code/RPClient/Sources/RPClientCore/Models/` — Codable shape conventions to follow.

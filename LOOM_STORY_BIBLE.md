# Loom Story Bible — the consistency engine

> **Last code cross-check:** 2026-05-21
> **Posture:** reference doc reflecting *current shipped* code. The knowledge-ledger conceptual design (§3) is the only part that remained authoritative from the Phase 0 design lock; everything else is rewritten against the current implementation. Where this doc and code disagree, **the code wins**.
> **Companion to** [`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md) (Bible shapes), [`LOOM_GENERATION_MODES.md`](LOOM_GENERATION_MODES.md) (injection mechanics), [`LOOM_BIBLE_WORKSPACE.md`](LOOM_BIBLE_WORKSPACE.md) (the editing surface), [`LOOM_MEMORY.md`](LOOM_MEMORY.md) (long-form context architecture).

## 1. What the Bible is, what it isn't

### 1.1 Is

- The **structured database** of everything that needs to be consistent across a long work: characters, settings, objects, lorebook entries, and per-relationship dynamic sheets.
- The **injection source** for selective context at generation time — Memory always, Bible constants always-on, keyed lorebook on recent-prose match, knowledge ledger per POV character.
- A **living artefact** — both authored (user-edited) and machine-extracted (the L4 knowledge-ledger pipeline, the L9 entity-discovery pipeline).
- **Skippable but rewarding** — projects can be used with an empty Bible. Auto-discovery surfaces characters/places/objects as proposals; the user accepts on their own pace.

### 1.2 Isn't

- A document the model writes from scratch. Sudowrite-style "Braindump → auto-fill" was in the Phase 0 design (LOOM_RESEARCH §A.2) but **never shipped** — Loom's authoring affordances are direct editing + accept/reject of machine proposals.
- A creative-writing workspace. The Bible is *metadata about* the work, not the work itself. Prose lives in scenes.
- Auto-injected wholesale. Constant entries are always-on; keyed entries trigger on recent-prose match; the knowledge ledger is queried per POV character per scene. Default posture is selective.

## 2. What's actually in the Bible today

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

That's the shape on disk. **Faction** and **TimelineEvent** were listed in the Phase 0 design as Phase 3 features — neither has shipped. Not on the active roadmap; revisit if/when a project comes to need them.

The shapes themselves (with field lists) are in [`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md) §5. This doc covers *what they're for* and *how they're used*; the data-model doc covers *what they contain*.

## 3. Knowledge ledger — the distinctive engineering

Loom's novel-territory feature: **what does Bob know at scene 12 vs scene 18**. Extends Re3's Edit module (LOOM_RESEARCH §L.2) to per-scene granularity with an explicit unknowns model.

### 3.1 Schema

`KnownFact` lives on `Character.knownFactsBySceneId: [UUID: [KnownFact]]`. The map is keyed by *the scene where each fact was first extracted*, not by which scene the fact applies to.

```swift
public struct KnownFact: Codable, Equatable {
    public let id: UUID
    public var fact: String          // natural-language assertion (third person)
    public var sourceSceneId: UUID?  // where the character learned it; nil = pre-story
    public var certainty: Certainty  // asserted | suspected | unknown | mistaken
    public var addedAt: Date
}
```

### 3.2 Extraction pipeline (shipped, Phase 4)

`Sources/LoomCore/Generation/Ledger*.swift` + `OllamaLedgerExtractor.swift`

```
[1] Trigger — LedgerExtractionTrigger
    Per-scene word-count baseline (default 200 words on top of last extraction).
    Auto-fires from LedgerExtractionCoordinator on prose change events.
    User can also force "Extract" from the editor's debug menu.

[2] Extraction call — OllamaLedgerExtractor
    Schema-constrained JSON: { character_id, fact, certainty, evidence_quote }.
    Runs on the structured-task model (default gemma4_2b on Ollama).
    Unconstrained generation + tolerant parse + retry-on-degenerate
    (gemma's `format` schema flakes ~50% on small models; HANDOFF §15.19).

[3] Filter — LedgerFilters / LedgerFilterPipeline
    Embedding-cosine dedup (paraphrases collapse).
    Evidence-quote validation — the quote must appear verbatim in the scene
    prose (drops hallucinated quotes).
    Prompt-leakage check (drops outputs that echo the prompt schema).
    Fail-soft: an embedder failure passes claims through unchanged.

[4] Diff — LedgerDiff
    Compare surviving facts against the character's existing ledger; only
    *new* facts (not already known under any certainty) become suggestions.

[5] Suggestions queue — LedgerSuggestionsQueue / LedgerSuggestionAcceptor
    Per-character pending list, surfaced in the Bible Workspace.
    User accepts/rejects per fact. Accepted facts merge into
    knownFactsBySceneId on the canonical character.
```

The extractor is a **side-call**, routed to the extractor server profile (separate from the writer server). Small fast models (gemma4_2b) are fine for extraction; the writer model stays available for prose generation.

### 3.3 Negative knowledge — derived, not extracted

LOOM_LEDGER_SPIKE §3.e measured local-model recall on *explicit* "unknown" facts at 0/2 even at 27B. So Loom doesn't try. The extractor's grammar emits **only `asserted` facts** (positive observations). Each fact is stamped with `sourceSceneId`. At query time, "does Mia know fact F as of scene N?" is computed *structurally*:

`Sources/LoomCore/Generation/LedgerKnowledge.swift`

```
LedgerKnowledge.compute(characterId, asOfSceneId, in: project, scenes:)
  → walks the project's `flatSceneIds` chronologically up to asOfSceneId
  → for each prior scene, checks ScenePresence.isPresent(characterId, in: scene)
  → KNOWS: facts whose sourceSceneId is a scene the character was present for
  → UNKNOWNS: facts whose sourceSceneId is a scene the character was NOT present for
  → returns (knows: [KnownFact], unknowns: [KnownFact])
```

ScenePresence: `Sources/LoomCore/Generation/ScenePresence.swift` — combines POV + `@`-mentions + name/alias hits in the prose.

`mistaken` and `suspected` are manual-authoring paths in the Bible Workspace — rare, user-surfaced when the prose explicitly contradicts a character's belief or when the user wants to track a hunch.

### 3.4 Querying at generation time

The `[KNOWLEDGE-LEDGER]` prompt layer is built per POV scene by `PromptBuilder.renderKnowledgeLedgerLayer` (in `Sources/LoomCore/Generation/PromptBuilder.swift`), feeding off `LedgerKnowledge.compute(...)`:

1. Resolve the scene's chronological position via `flatSceneIds`.
2. Call `LedgerKnowledge.compute(...)` for the POV character as-of-scene-N.
3. Format as natural-language `KNOWS / DOES NOT KNOW / SUSPECTS / MISTAKENLY BELIEVES` blocks.
4. Token-budget-clip (most-recent-scene wins; full eviction allowed under tight budget).
5. Inserted between `[BIBLE-KEYED]` and `[AUTHORS-NOTE]` in the prompt assembly (see [`LOOM_GENERATION_MODES.md`](LOOM_GENERATION_MODES.md)).

### 3.5 Limitations and honesty

- **Extraction precision is the dominant lever.** Phase 4 hand-graded the extractor at ~85% precision on common cases; degrades on NSFW/heavy-explicit prose (gemma4_2b sometimes refuses → `RefusalDetector` flags; user re-rolls).
- **Pronoun resolution failures are real.** A scene with three female characters and many "she" pronouns will produce attribution errors. The `evidence_quote` field exists to make these auditable in the Bible Workspace facts-examiner.
- **Contradiction resolution is naive.** Later-scene-wins is heuristic; a character may legitimately "forget" something. No structural fix in shipped code — open question on the L10 continuity-audit roadmap.
- **No live "consistency lints" surface.** Phase 0 imagined a lint surface (contradiction detection, dangling-reference warnings, mistaken-never-resolved nudges). The L10 Continuity Audit replaces that vision but is still maturing (see [`LOOM_CONTINUITY_AUDIT.md`](LOOM_CONTINUITY_AUDIT.md) §22–§28; current state is 1/4 knowledge_violation on Goetia at k=1).

## 4. Entity discovery (auto-found Bible entries — L9)

`Sources/LoomCore/Generation/Entity*.swift` + `Sources/LoomCore/Storage/ProposedEntitiesStore.swift`

Beyond the knowledge ledger (which fills in *facts* about *existing* characters), Phase 9 added a sibling pipeline that *proposes new entities* discovered in scene prose — characters / settings / significant objects the user hasn't yet added to the Bible.

Six-stage pipeline:

```
Stage A — Candidate generation (OllamaEntityDiscoveryExtractor)
  Schema-constrained JSON; gemma4_2b reads the scene, proposes
  { canonical_name, aliases, one_line, evidence_quote, kind, attached_facts }.

Stage B — Promotion gate (EntityPromotionGate)
  Proper-noun-only; anatomy block-list (drops "Anus"/"Cock"/etc. that
  Stage A occasionally proposes); place-recurrence (a place mentioned
  in only one scene with no detail is rejected as ambient setting,
  not a Bible entity).

Stage C — Cosine dedup (EntityDedupEngine)
  Wegmann-CoreML embedding of canonical_name + first description
  sentence; if cosine ≥ 0.85 with an existing bible entity, drop as
  duplicate. Filters out re-proposals of already-known entities.

Stage D — Normalisation
  Case / whitespace / Title Case normalisation on canonical_name.
  Alias merging.

Stage E — Post-D dedup
  Cross-scene dedup of proposals (two scenes can independently propose
  the same character; collapse to one).

Stage F — Persist (ProposedEntitiesStore)
  Single file at proposed-entities/proposed-entities.json. Each entry
  is a SnapshotProposedEntity awaiting user accept/reject in the Bible
  Workspace.
```

Triggers: auto via piggyback on `LedgerExtractionCoordinator.onExtractionComplete` (gated by `EntityDiscoveryTrigger` 500-word per-scene baseline), manual via Bible Workspace, demo via `swift run EntityDiscoverySpike --into <project>`.

**Accepting a proposal** promotes it to a real `Character` / `Setting` / `BibleObject`. Attached facts land on `knownFactsBySceneId` for promoted characters.

**Cross-character relationship discovery** is dormant — `ProposedRelationship` shape exists, no production pipeline. See HANDOFF §15.25–§15.27 for the GLiREL dead end and the precision-lever exhaustion that paused this direction.

## 5. Lorebook — selective injection

Per-entry shape in [`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md) §5.4. Injection mechanics:

### 5.1 Activation modes

| Mode | When injected | Token cost | Use |
|---|---|---|---|
| **`.constant`** | Always | High | Global setting, narrator persona, story-spanning lore |
| **`.keyed`** | Recent prose contains a primary key (and any secondary keys if listed) | Low | Character backgrounds, location lore, faction details |
| **`.vectorised`** | (declared in the enum; not yet wired) | — | Reserved for future RAG-against-lorebook |

### 5.2 Keyed-mode mechanics

- **Primary keys**: any one match in the recent-prose window triggers.
- **Secondary keys**: AND-gated — primary AND secondary keys both must appear (NovelAI's `&` operator pattern).
- **Recent-prose window**: configurable per entry via `maxRecentScenesScanned`.
- **Match semantics**: case-insensitive, word-boundary (no substring matches; "rat" doesn't trigger on "rate").

### 5.3 Position control

`positionMode` is `.top` (after Memory — always-top region), `.bottom` (depth-N before the cursor — Author's Note region), or `.depthN` (explicit depth controlled by `depth: Int`).

Per NovelAI's empirical finding: lower in the prompt = stronger influence. "Always-on" character voice notes go top; "remember this scene-specific tone" goes bottom.

### 5.4 Priority, budget, sticky, scene-bounded

- **Priority** + recency tie-break + budget-bounded eviction. Never silently truncate an entry's content; drop entries whole.
- **`sticky: true`** — once triggered, stays active for the rest of the audit/session (NovelAI sticky pattern).
- **`activateFromSceneId` / `activateUntilSceneId`** — scene-bounded activation. Useful for revealing-act-only lore.

The full `LorebookEntry` shape (`group`, `weight`, etc.) is editable via the Bible Workspace Lorebook section.

## 6. DynamicSheet — per-relationship spec

`Sources/LoomCore/Models/DynamicSheet.swift` + `Sources/LoomCore/Generation/DynamicSheetInjector.swift` + `DynamicSheetPrompt.swift`

A *DynamicSheet* describes a specific relationship's dynamic — the kink/role spec for one or more participating characters. Used for tagged relationships (D/s, ABO mates, rivals-to-lovers, etc.) that need structured prompt steering beyond a freeform Character.voice or LorebookEntry.

Injection mechanics:

- **`alwaysOn = true`** — injected on every generation regardless of cast.
- **`alwaysOn = false`** — injected when at least one `participantIds` character is present in the current scene window.
- **`enabled = false`** — never injected. Lets a user keep a dynamic recorded but disabled for chapters where it isn't active.

Field shape: `roles, wants, softLimits, hardLimits, safeword, arc`. The injector renders this as a `[DYNAMIC]` block in the prompt; the prompt-builder layer slots it next to the keyed-lorebook layer.

## 7. Memory + Author's Note (project-level)

NovelAI / KoboldAI / SillyTavern convention carries through unchanged from the Phase 0 spec; full mechanics in [`LOOM_MEMORY.md`](LOOM_MEMORY.md).

- **Memory** (`ProjectSettings.memory`) — free-text per project. Always injected at the top. *What is true.* Genre, premise, world rules, always-true facts.
- **Author's Note** (`ProjectSettings.authorsNote`) — free-text per project. Always injected at depth-N from the end (default `authorsNoteDepthLines = 4`). *How to write it.* Tone steering, pacing instructions, stylistic hints.

Memory presets (`Sources/LoomCore/Models/ProjectMemoryPresets.swift`) seed new projects with `.loomDefault`, `.heavyNSFW`, or `.minimal` text. Sphiratrioth pack import (Settings → Resources) drops a ready-made power-user Memory + Lorebook + Dynamics set into the project.

## 8. The assembled injection order

Per [`LOOM_GENERATION_MODES.md`](LOOM_GENERATION_MODES.md) — at generation time the Bible-related layers appear in this order, top → bottom:

```
[MEMORY]               ProjectSettings.memory                                — top
[BIBLE-CONST]          Always-on Characters/Settings/Objects + .constant lorebook
[BIBLE-KEYED]          Keyed lorebook entries that match recent-prose window
[DYNAMIC]              DynamicSheets active for the present cast
[KNOWLEDGE-LEDGER]     POV character's KNOWS / DOES NOT KNOW / SUSPECTS / MISTAKEN
[WRITING-DIRECTION]    WritingDirection system-prompt addendum                — bottom-of-system
[AUTHORS-NOTE]         ProjectSettings.authorsNote (depth-N from end)        — near cursor
```

Always-on default: every Character/Setting/BibleObject with `injectionMode: .alwaysOn` is in `[BIBLE-CONST]`. `.keyed` entities are matched against recent-prose via `MentionIndex` + alias hits. User flips per-entity injectionMode in the Bible Workspace.

## 9. The editing surface — Bible Workspace

The Phase 0 design imagined an AppKit Bible *inspector pane*. Phase 4.5 pivoted that to a **dedicated webview window** (closed the cramped-side-pane UX problem from live testing). See [`LOOM_BIBLE_WORKSPACE.md`](LOOM_BIBLE_WORKSPACE.md) for the architecture; this section is a brief surface map.

**Workspace sections:**

- **Characters** — full editor (every Character field, Kinks tab, knowledge-ledger examiner with per-scene facts grouped + delete affordance).
- **Lorebook** — all 13 power-user fields, conditional `depth` when positionMode = depthN.
- **Dynamics** — DynamicSheet editor with participant picker.
- **References** — L5 style references with chunk count badge + ingest button.
- **Template Scenes** — L7 template-scene editor + beat-extract trigger.
- **Scene Exemplars** — L8 unified surface (creates a Reference + Template under one shared id).
- **Suggestions queue** — pending knowledge-ledger fact suggestions from §3.2 step 5, cross-character.
- **Entity proposals** — pending L9 entity-discovery proposals (§4) awaiting accept/reject.

Side-pane AppKit inspector still exists for the History tab + Notes tab. Bible editing is webview-only.

## 10. Phasing — what's shipped vs deferred

| Feature | Status | Notes |
|---|---|---|
| Manual entity authoring (Characters, Settings, Objects, Lorebook, Dynamics) | ✅ Phase 2 → 4 | Bible Workspace, every field surfaced |
| Constant + keyed lorebook | ✅ Phase 2 | All 13 fields editable |
| Always-inject character paragraph in prompts | ✅ Phase 1 | `[BIBLE-CONST]` layer |
| Memory + Author's Note fields | ✅ Phase 1 | NovelAI semantics |
| Knowledge ledger (manual + extraction + ScenePresence-derived unknowns) | ✅ Phase 4 | Full pipeline |
| Entity discovery (auto-found characters / settings / objects) | ✅ Phase 9 | 100% precision / 85.7% recall / F1 92.3% on fixture set |
| DynamicSheet per-relationship spec | ✅ Phase 4 | |
| Per-character canonBrief (fandom canon snippet) | ✅ schema landed | Phase 5b ingest pipeline reuses L5 RAG |
| Custom fields (fandom-template extensibility) | ✅ schema landed | Fandom UI deferred to Phase 5.c |
| `.vectorised` lorebook activation | ✅ enum case landed | Production wiring not yet built |
| Per-field AI-assist ("Generate" buttons next to each Bible field) | ❌ not shipped | Phase 0 design intent; deferred indefinitely |
| Sudowrite-style Braindump auto-fill | ❌ not shipped | Phase 0 design intent; deferred indefinitely |
| Live consistency lints | ❌ partially replaced by L10 | The Continuity Audit (whole-manuscript) supersedes the per-edit lint idea |
| Faction | ❌ not shipped | Not on roadmap |
| TimelineEvent | ❌ not shipped | Not on roadmap |
| Relationship discovery (auto cross-character) | ❌ dormant | HANDOFF §15.25–15.27 — GLiREL dead end; precision levers exhausted |

## 11. Open questions

- **Cross-character contradiction detection.** Two characters' ledgers disagree about a shared fact. The L10 Continuity Audit is taking on this question at the whole-manuscript level, not the per-scene level. Per-scene lint surface deferred indefinitely.
- **Time travel / non-linear narrative.** `flatSceneIds` walked in *narrative* order today; chronological vs narrative is unresolved. Probably untested against a flashback-heavy manuscript. Revisit when one comes along.
- **Ensemble protagonists / shared POV.** Each character has their own ledger; "shared knowledge" is implicit overlap. Works in practice for two- and three-POV stories; not stress-tested at 5+.
- **NSFW extraction degradation.** gemma4_2b's refusal rate climbs sharply on heavy-explicit scenes; the production pipeline retries on `noJSONObjectFound` / `noJSONArrayFound` to cover the ~30% transient parse-fail rate. Open question whether a larger / less-aligned structured-task model would help. Tracked in `LOOM_TECH_STACK` "Model server flexibility" deferred item.

## 12. Cross-references

- [`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md) §5 — Bible entity shapes.
- [`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md) §10 — Bible Workspace snapshot shape.
- [`LOOM_GENERATION_MODES.md`](LOOM_GENERATION_MODES.md) — per-mode prompt assembly that consumes these layers.
- [`LOOM_BIBLE_WORKSPACE.md`](LOOM_BIBLE_WORKSPACE.md) — webview architecture + per-section editor design.
- [`LOOM_MEMORY.md`](LOOM_MEMORY.md) — long-form context architecture; supersedes injection mechanics where the two docs disagree.
- [`LOOM_NSFW.md`](LOOM_NSFW.md) — Kink / Anatomy / DynamicSheet authoring posture.
- [`LOOM_LEDGER_SPIKE.md`](LOOM_LEDGER_SPIKE.md) — knowledge-ledger pipeline empirical results (5-round spike).
- [`LOOM_ENTITY_DISCOVERY_SPIKE.md`](LOOM_ENTITY_DISCOVERY_SPIKE.md) — L9 pipeline design + measurements.
- [`LOOM_CONTINUITY_AUDIT.md`](LOOM_CONTINUITY_AUDIT.md) §22–§28 — current state of the whole-manuscript consistency engine.
- [`LOOM_TECH_STACK.md`](LOOM_TECH_STACK.md) "Knowledge & continuity tracking" — solved-problem registry.

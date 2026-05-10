# Loom — Fanfic Mode

> **Status: design proposal (2026-05-10).** New feature surfaced by the user 2026-05-10. Pick a fandom → gather enough canon detail → generate on-topic stories with user guidance. This document specifies the feature; Phase mapping in [`LOOM_PLAN.md`](LOOM_PLAN.md). All citations to [`LOOM_RESEARCH.md`](LOOM_RESEARCH.md) §S unless otherwise noted.

---

## 1. What it is

Loom's first-class **Fanfic Mode** — a project type that knows it's writing fan fiction in a specific fandom, with that fandom's canon, its community's tropes, and the conventions of fanfic-as-a-form built into the tool's primitives.

Three observations make this load-bearing:

1. **Fanfic is an enormous fraction of long-form fiction writing** — AO3 alone holds an estimated 19.6M+ works as of 2025[S.AO3-DATASET]. Most existing AI fiction tools treat it as an afterthought.
2. **Fanfic has its own primitives** — fandoms, ships, AUs, tropes, ratings/warnings — that don't fit cleanly into a "generic novel" data model.
3. **The closest existing competitor is Sudowrite's Fandom Helper, and it's shallow.** Pre-built canon for Harry Potter / Marvel / BTS, paste-a-passage-ask-a-question Q&A, no slow-burn pacing, no AU scaffolding, no ship dynamics, no trope helpers.[S.SUDOWRITE-FANDOM] Loom can blow past this on day one of the feature shipping.

The user's stated requirement: "pick a specific fanfic genre, have it gather enough details, and write on-topic stories with user-provided guidance."

## 2. Non-negotiables

- **No automated AO3 / FFN / Wattpad scraping.** The 2025 AO3 dataset removal (12.6M works, 164GB scraped without consent, permanently disabled on HuggingFace[S.AO3-DATASET]) is the controlling precedent. Loom does **not** ingest fanfic archives wholesale. Canon lookup uses publicly-licensed encyclopaedias (fandom wikis, MediaWiki dumps, user-supplied) — and even those, only at the user's explicit request per project.
- **The user owns the fandom-detail gathering.** Loom provides scaffolding to capture canon; the user decides what gets ingested. This is the same reference-text-ingestion pattern as Phase 5 style ingestion ([`LOOM_RESEARCH.md`](LOOM_RESEARCH.md) §O.1) — the fanfic version reuses the pipeline.
- **No fandom-specific filtering or content moderation.** Fanfic communities are explicit about ratings, warnings, and tags; Loom mirrors AO3's "select your tags, content is yours" posture. Heavy NSFW + extreme topics support per [`LOOM_NSFW.md`](LOOM_NSFW.md).

## 3. Architecture

### 3.1 The fanfic project type

A new `Project.kind: ProjectKind` field in [`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md):

```swift
enum ProjectKind: String, Codable {
    case originalFiction       // default; existing
    case fanfic
}

struct FanficMetadata: Codable {
    var fandoms: [Fandom]
    var attg: ATTG                 // Author/Title/Tags/Genre header (NovelAI Erato pattern[S.ERATO])
    var ratings: AO3Rating         // General / Teen / Mature / Explicit
    var warnings: [AO3Warning]     // No Archive Warnings Apply / Graphic Depictions Of Violence / etc.
    var category: AO3Category      // Gen / F/F / F/M / M/M / Multi / Other
    var ships: [Ship]              // Relationship pairings
    var primaryCharacters: [UUID]  // references Bible.characters (canon names)
    var tropes: [Trope]            // typed trope objects, see §5
    var aus: [AU]                  // alternate universe shifts, see §6
}

struct Fandom: Codable {
    let id: UUID
    var name: String                  // "Harry Potter", "Marvel Cinematic Universe"
    var canonicalName: String         // AO3-canonical form
    var aliases: [String]             // "HP", "MCU", abbreviations
    var fandomWikiURL: URL?           // user-provided source for canon lookups
    var canonReferences: [UUID]       // references ReferenceMeta for ingested canon docs
}

struct Ship: Codable {
    let id: UUID
    var characters: [UUID]            // 2+ characters from the bible
    var kind: ShipKind                // .romantic, .sexual, .platonic, .familial, .antagonistic, .friendship
    var canonicalForm: String         // "Drarry" / "Stucky" / "Destiel" — the community-canonical compound name
    var dynamic: ShipDynamic          // .established, .slowBurn, .enemiesToLovers, .friendsToLovers, etc.
    var notes: String                 // free-form
}

enum ShipKind: String, Codable {
    case romantic, sexual, platonic, familial, antagonistic, friendship
}

enum ShipDynamic: String, Codable {
    case established
    case slowBurn
    case mutualPining
    case enemiesToLovers
    case friendsToLovers
    case fakeMarriage
    case soulmates
    case otherWorks    // catch-all
}
```

The AO3 tag taxonomy (Rating, Warning, Category, Fandom, Character, Relationship, Additional/Freeform)[S.AO3-TAGS] is Loom's foundation for fanfic metadata. We don't reinvent the wheel — we use the wheel that millions of fanfic readers already understand.

### 3.2 Canon ingestion pipeline

**User-driven, project-scoped.** No background scraping. Three input paths:

1. **Drop a fandom wiki page or markdown export.** The user pastes content from `harrypotter.fandom.com/wiki/Severus_Snape` (manually copied) into a "Canon brief" field on a Character entity. Loom does NOT auto-fetch. Phase 5 reference-text ingestion pipeline reuses for this; chunked, embedded, retrievable.

2. **Use a fandom template bundle.** Loom ships a small set of **structural templates** (not canon content) for common fandoms. Templates pre-populate entity-type schemas: a Harry Potter template gives Character entities slots for `house`, `wand`, `bloodStatus`; an MCU template gives `team`, `affiliation`, `powers`. These are *schemas*, not facts. Users fill them in.

3. **Import a saved fandom bundle.** Power users export their populated bibles from one project and import to another. Format: `<fandom>.loomfandom` directory containing the entity templates + any user-authored canon notes.

Phase mapping: 5.b (after the Phase 5 reference ingestion pipeline ships).

### 3.3 ATTG header — system-prompt fanfic conventions

Borrowed verbatim from NovelAI Erato's system-prompt format[S.ERATO]:

```
[ Author: <user>; Title: <title>; Fandom: <canonical fandom>; Tags: <tags>; Rating: <rating>; Genre: <genre> ][ S: <2-4> ]
```

Examples:

```
[ Author: silver_quill; Title: The Long Road Home; Fandom: Harry Potter - J. K. Rowling; Tags: post-war, slow burn, drarry, hurt/comfort; Rating: Mature; Genre: drama, romance ][ S: 3 ]
```

```
[ Author: kjorth; Title: Coffee Run; Fandom: Marvel Cinematic Universe; Tags: coffeeshop AU, modern AU, no powers, fluff; Rating: Teen; Category: M/M; Relationship: Steve Rogers/Bucky Barnes ][ S: 2 ]
```

The Erato system found empirically that **explicit Author + Tags + Genre headers improve compliance** with the requested style/tone. Loom's fanfic header reuses this with AO3 conventions added (Rating, Category, Relationship). The S parameter is "story stage" 2-4; Loom defaults S=3 for established projects and S=2 for opening scenes.

Injected at the **top of the prompt above the cache boundary** (per [`LOOM_MEMORY.md`](LOOM_MEMORY.md) §4.1) so it stays cache-stable across generations.

## 4. Ships as first-class data

Most AI fiction tools handle relationships as free-form text. Fanfic conventions need them structured.

A `Ship` is a tuple of (≥2 characters, kind, dynamic, notes). The dynamic field carries the **trope name** of the relationship arc — "slow burn" / "enemies to lovers" / "friends to lovers" / etc.[S.FANFIC-TROPES] — and **drives generation behavior**:

- A `slowBurn` ship triggers the **Slow Burn pacing assistant** (§5.1).
- An `enemiesToLovers` ship sets the active-tension flag for the Conflict generation hint.
- A `mutualPining` ship inserts a pining-internal-monologue cue at depth-N for the POV character.

Ships are referenced in beats via `@ship/<canonical>`; the bible inspector displays them as a separate section ("Relationships") next to Characters.

## 5. Trope library

A trope is a named pattern of fictional convention — readers and writers share the shorthand. Fanfic communities have hundreds[S.FANFIC-TROPES].

### 5.1 Trope schema

```swift
struct Trope: Codable {
    let id: UUID
    var name: String                 // canonical: "Slow Burn", "Hurt/Comfort", "There Was Only One Bed"
    var aliases: [String]            // common variants
    var category: TropeCategory      // pacing / relationship / setup / resolution / kink / structural
    var description: String          // 2-3 sentence definition
    var typicalLength: TropeLength?  // word-count + chapter-count expectation
    var generationHints: TropeHints  // what the Bible/Author's Note should reflect when this is active
}

struct TropeLength: Codable {
    var minChapters: Int
    var maxChapters: Int
    var minWords: Int
    var maxWords: Int
}

struct TropeHints: Codable {
    var pacingNote: String           // injected as Author's Note when active
    var avoidances: [String]         // patterns to avoid (added to negative samplers / system)
    var beatPatterns: [String]       // common beats the trope expects
}

enum TropeCategory: String, Codable {
    case pacing, relationship, setup, resolution, kink, structural, au, character
}
```

### 5.2 Bundled trope library (Phase 5.c)

Loom ships a curated bundle of ~80-120 fanfic tropes drawn from the Fanlore canonical list[S.FANFIC-TROPES]. Examples:

| Trope | Category | Typical length | Generation hint summary |
|---|---|---|---|
| Slow Burn | pacing/relationship | 20+ chapters / 50k+ words | Defer romantic resolution; emphasise gradual emotional escalation; avoid "I love you" before structural midpoint |
| Hurt/Comfort | relationship/structural | 1-15 chapters / 5k-50k | One character injured/distressed; another tends to them; tenderness foregrounded |
| Enemies to Lovers | relationship | varies | Initial active antagonism; reluctant collaboration; grudging respect; attraction emerges from shared adversity |
| There Was Only One Bed | setup | single scene | Forced proximity; awkwardness; eventual intimacy |
| Coffeeshop AU | AU | varies | Modern setting; one character barista/customer; mundane setting drives interaction |
| Soulmates AU | AU | varies | Soulmate-marker mechanic established early (red string, name on wrist, shared dream, etc.) |
| Fake Dating | relationship/setup | 3-15 chapters | Pretense → real feelings; external pressure necessitates fake relationship |
| Royalty AU | AU | varies | Reframe characters in royal/noble setting; political intrigue layer |
| Time Travel Fix-It | structural/AU | varies | One character travels back; tries to prevent a canon tragedy |
| Bed Sharing | setup | scene | Forced proximity, smaller in scope than "Only One Bed" |

User can extend the library per-project. Tropes are *project-scoped* but exportable as bundle.

### 5.3 The Slow Burn pacing assistant

When a Ship has `dynamic: .slowBurn`, Loom activates the Slow Burn assistant:

- **Pacing target**: configurable (e.g., "first kiss at 70% completion"). User sets the structural midpoint; Loom's Author's Note reminds the model to defer resolution.
- **Per-scene pacing chip**: in the Scene metadata UI, a "Slow burn position" indicator shows where the user is in the arc (~25% through, mostly slow-burn-friendly per the configured target).
- **Author's Note injection** (depth 2-4): "this scene is the [25%/50%/75%] mark of a slow burn between {{ship.canonical}}; emotions present but not declared"
- **Conflict insertion**: at user request, Loom suggests "external obstacles to the relationship developing too fast" — common slow-burn conflict patterns (a third party, mutual misreading of signals, external threat that takes priority).

Phase 5.c.

### 5.4 AU scaffolding

```swift
struct AU: Codable {
    let id: UUID
    var name: String                 // "Coffeeshop AU", "Modern Royal AU"
    var description: String
    var setting: String              // "1920s New York", "magical school in Cyberpunk 2090"
    var canonRetained: [String]      // facts kept from canon ("characters keep names + relationships")
    var canonChanged: [String]       // facts changed ("no magic", "no powers", "all human")
    var addedElements: [String]      // ("baristas", "phones", "modern dating")
}
```

When an AU is active in the project, the bible inspector shows the canon-retained vs canon-changed split prominently. The system prompt explicitly states: "this story is an Alternate Universe; canon facts marked KEPT remain true; canon facts marked CHANGED are no longer true; ADDED elements are part of this universe." This produces dramatically better AU compliance than dropping the AU description into a free-form Memory field.

Phase 5.c.

## 6. Generation modes specific to fanfic

Beyond the generic Phase 4 modes ([`LOOM_GENERATION_MODES.md`](LOOM_GENERATION_MODES.md)), fanfic mode adds:

### 6.1 Trope insert

Selection: a beat or paragraph break. User picks a trope from the project's library. Loom expands the selection using the trope's beat patterns + generation hints.

### 6.2 Ship dynamic shift

User selects a Ship; picks a target dynamic (e.g., from `.enemiesToLovers` to `.friendsToLovers`). Loom suggests a transition scene that bridges them, using both dynamics' beat patterns.

### 6.3 Canon check

User selects a passage. Loom side-calls (summariser-role server) with: "here is the passage; here are the canon notes for the characters/places involved. Identify any facts in the passage that contradict the canon notes." Output: list of contradictions with line references. **No auto-fix** — surface only. (Sudowrite Fandom Helper's Canon Lookup is the closest precedent; Loom shows the actual fact diff rather than answering generic "canon questions"[S.SUDOWRITE-FANDOM].)

### 6.4 Tag suggest

User finishes a scene; clicks Tag Suggest. Loom side-calls with: "here is the scene; suggest AO3-style tags following the Rating / Warning / Category / Relationship / Additional schema." Output is a list of canonical-form tags (synonyms collapsed per AO3 wrangling[S.AO3-TAGS]). User accepts/rejects per tag; accepted tags update the project's `FanficMetadata.tags`.

### 6.5 Style match — author by author

Phase 5 style ingestion already handles this. Fanfic mode adds a "match my favorite author" affordance: user pastes a chapter from an existing fanfic by an author they admire (with attribution); Loom extracts a style sheet specifically tagged as "ambient style reference: <author>". This is the FanFabler approach[S.FANFABLER] applied to the user's preferred fanfic-author voice — but Loom does **not** train a LoRA; it does few-shot retrieval of paragraphs with similar surface markers (sentence length, lexicon, dialogue tag conventions).

## 7. Fanfic-specific UI affordances

[`LOOM_DESIGN_LANGUAGE.md`](LOOM_DESIGN_LANGUAGE.md) §14 surfaces extended for fanfic mode:

- **Project header** shows the ATTG metadata as a compact pill row: `[Fandom: HP] [Drarry] [Slow Burn] [Mature]` etc. Click any pill to edit.
- **Bible inspector** gains tabs: `Characters · Ships · Tropes · AUs · Settings · Lorebook · History · Notes`. Ships and AUs are first-class.
- **Trope picker popover** (`⌘⇧T`) — fast access to the project's trope library + global library; insert at cursor with one click.
- **Slow burn meter** (when active): horizontal bar in the Scene status strip showing current % through the configured slow-burn arc.
- **Canon brief panel** (Phase 5.b): when a Character is selected in the bible, a "Canon brief" pane shows the user-authored canon notes; "Add to canon brief" button on any selection in the editor pastes prose to the active character's canon brief.

## 8. Workflow walkthrough — first-time fanfic project

1. User: `File → New Project`. Modal asks: Original fiction or Fanfic?
2. User picks Fanfic. Modal asks for: Fandom name (free text + suggestion list of common fandoms with templates available).
3. User types "Marvel Cinematic Universe." Loom checks for a bundled MCU template; offers to apply.
4. User applies template. Bible is pre-populated with empty Character entities (Steve Rogers, Tony Stark, Natasha Romanoff, ...) — *names only, no canon facts; user fills in.* Ships section pre-populated with common ships in the fandom (Stucky, Stony, ClintTasha, ...) — user picks which apply.
5. User picks Stucky as primary ship; sets `dynamic: .slowBurn`. Sets Rating: Mature, Category: M/M.
6. ATTG header auto-fills: `[ Author: <user>; Title: <untitled>; Fandom: Marvel Cinematic Universe; Tags: stucky, slow burn; Rating: Mature; Category: M/M; Relationship: Steve Rogers/Bucky Barnes ][ S: 2 ]`. User can edit.
7. User opens the editor, types a paragraph sketch. Clicks Expand. Output: prose in the right voice for fanfic conventions; Slow Burn pacing meter shows ~5% (early stages); the active ship's dynamic is in context.
8. User continues writing. Periodically clicks Tag Suggest; Loom proposes additional tags ("hurt/comfort", "post-Endgame", "modern AU").
9. As the project grows, user uses the Trope Insert mode to drop in "There Was Only One Bed" at chapter 4. Slow burn tension escalates per the trope's beat pattern.
10. User exports as Markdown with AO3-conformant frontmatter for direct copy-paste-publishing.

## 9. Phase mapping

| Phase | Fanfic deliverable |
|---|---|
| Phase 1 | None. Fanfic mode does not exist yet. |
| Phase 2 | None. Bible is generic. |
| Phase 3 | None. |
| Phase 4 | None. Knowledge ledger lands; foundation for §6 modes. |
| Phase 5.b | Canon-brief storage on Character; manual canon ingestion via paste; reference-text retrieval pipeline shared with style ingestion. |
| Phase 5.c | Fanfic project type; ATTG header; Ship + AU + Trope schemas; Slow Burn pacing assistant; bundled trope library (~80-120 entries); fandom template bundles for top 5 fandoms (HP, MCU, Star Wars, BTS, generic anime); Tag Suggest, Canon Check, Trope Insert, Ship Dynamic Shift modes. |
| Phase 6 | Polish: AO3-conformant Markdown export; bundle export of populated fandom bibles; Trope library editor. |
| Phase 7+ | Optional: opt-in fandom wiki integration (user provides API key for fan-wiki sources that allow it); style-fine-tuning per favourite-fanfic-author with local LoRA when MLX tooling matures. |

## 10. What this is NOT

- **Not a content moderator.** Loom doesn't enforce any rating/warning policy. The user picks tags; the model writes accordingly. Heavy NSFW per [`LOOM_NSFW.md`](LOOM_NSFW.md).
- **Not a canon scraper.** Loom doesn't auto-fetch fandom wikis or AO3. Canon is user-supplied (paste, drop, manual entry). The AO3 dataset disablement[S.AO3-DATASET] is the controlling lesson.
- **Not a publishing tool.** Loom exports clean Markdown with AO3-conformant frontmatter; the user uploads to AO3/FFN/Wattpad themselves.
- **Not a fanfic LoRA fine-tuner.** Phase 5 is few-shot style imitation. Local LoRA training is Phase 7+ R&D; respects the FanFabler[S.FANFABLER] approach as a model but doesn't ship the pipeline today.
- **Not a community / sharing platform.** Single-user. Project files travel; nothing else does.

## 11. Open design questions

- **Trope library curation.** The Fanlore canonical-trope list is community-maintained; Loom's bundled library should mirror it but with what filtering? Lean: ship the Fanlore-derived list as-is, with a single "Hide kink/extreme tropes" toggle for users who don't want them in their picker (default off — fanfic communities don't pretend extreme content doesn't exist).
- **Fandom template scope.** Top 5 fandoms in the bundle? Top 20? Lean: top 5 in the v1 bundle (HP, MCU, Star Wars, BTS, anime-generic), expand by user demand.
- **Cross-fandom / crossover support.** A project can have `fandoms: [Fandom]` plural — yes, by design. UI: ATTG header lists all; canon checks run against all bibles. Phase 5.c.
- **Ship dynamic shifts mid-project.** Slow burn → established mid-novel? Schema supports; UI needs a "shift dynamic" action with a confirmation that the Slow Burn meter retires.
- **Canon "facts vs feelings".** When the user pastes "Harry Potter is the Boy Who Lived" canon, that's a hard fact. When the user pastes "Snape was misunderstood" — that's interpretation. Loom should surface this distinction in the Canon Brief: a "Type" field per canon note (`fact / interpretation / opinion`). Phase 5.b implementation question.

## 12. Why Loom can blow past Sudowrite Fandom Helper

The competitor analysis is brief. Sudowrite Fandom Helper offers:[S.SUDOWRITE-FANDOM]

- Pre-built canon for HP / MCU / BTS (3 fandoms).
- "Paste a passage, ask a question" Q&A.
- Trope suggestions (mentioned, not detailed).
- Integration with Sudowrite's core Write/Describe/Rewrite/Expand.

What Loom adds:

- **Structured Ship + AU + Trope as first-class data**, not generic bible entries.
- **Slow Burn pacing assistant** with structural-position tracking. None of the surveyed AI tools do this.
- **AO3-conformant tag schema** + Tag Suggest. Closest competitor: Inkfluence AI[S.INKFLUENCE]; nobody else.
- **Local kobold backend** with abliterated/uncensored model support, enabling extreme-content fanfic Sudowrite contractually can't.
- **Per-fandom template bundle** users extend; Sudowrite only has 3 pre-loaded fandoms.
- **History chiclets** showing what canon got injected (transparency).
- **No subscription**; no per-generation cost; no rate limits beyond local hardware.

The fanfic community already self-organises around these primitives (ships, tropes, AUs, slow burn). Loom is the first AI tool to take that organisation seriously.

## 13. References

**Internal:**
- [`LOOM_PLAN.md`](LOOM_PLAN.md) — phase mapping carries forward.
- [`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md) §3 — Bible entities; this doc adds Ship, AU, Trope, FanficMetadata.
- [`LOOM_DESIGN_LANGUAGE.md`](LOOM_DESIGN_LANGUAGE.md) §14 — surfaces extended.
- [`LOOM_GENERATION_MODES.md`](LOOM_GENERATION_MODES.md) — Phase 4 modes the new fanfic modes layer onto.
- [`LOOM_MEMORY.md`](LOOM_MEMORY.md) §4 — the memory architecture that powers canon retrieval.
- [`LOOM_NSFW.md`](LOOM_NSFW.md) — the heavy-NSFW posture that gives fanfic mode its differentiator vs Sudowrite.
- [`LOOM_RESEARCH.md`](LOOM_RESEARCH.md) §S — Round-4 prior-art (Sudowrite Fandom Helper, AO3, FanFabler, NovelAI Erato ATTG).

**External (cited as `[S.*]` references):** all in [`LOOM_RESEARCH.md`](LOOM_RESEARCH.md) §S.

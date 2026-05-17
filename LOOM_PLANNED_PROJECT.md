# LOOM — Planned Project Mode

**Status:** Design / planning. No code yet. Authored 2026-05-17.

**Origin:** User feature request — a guided project-creation mode that turns a
short character sketch + a few-sentence plot premise into an editable
manuscript outline (named chapters/scenes), sized by a chosen length
scenario, with assignable, mixable "styles" (genre + register) threaded into
all prose generation. The user then writes the scenes by hand and with
generation against that scaffold.

---

## §1 Scope & motivation

Today a Loom project starts blank — `createProject` seeds one empty scene and
the writer builds everything by hand. **Planned Project mode** adds a second
entry path: the app scaffolds the manuscript from a premise, so the writer
starts with a structured, named, editable outline and a locked-in style.

Four user-facing capabilities:

1. **Guided setup** — a wizard takes a character sketch + plot premise.
2. **Outline generation** — the app generates a named chapter/scene outline,
   editable before and after project creation.
3. **Length scenarios** — flash fiction → novel presets that size the outline.
4. **Style system** — assignable, mixable genre + register styles that thread
   into every generation call.

This is the largest feature since the early phases. It is planned as five
phases (§6); build sequence is chosen per-phase.

---

## §2 Locked decisions

From the scoping exchange (2026-05-17):

1. **Plan covers all four capabilities**; build sequence decided per-phase.
2. **Story framework:** Save the Cat (15 beats) is the *only* framework in v1,
   but the beat scaffold sits behind a `StoryFramework` abstraction so further
   frameworks (Hero's Journey, seven-point, etc.) are additive later.
3. **Style library:** a curated **built-in starter set that is user-editable** —
   users edit, add, and mix styles.
4. **Outline structure is length-driven:** short formats get a flat scene list,
   longer formats get chapters.
5. **UI is webview-heavy:** the outline editor and style library are built in
   the existing React Bible Workspace; only a thin entry point is AppKit. This
   deliberately limits AppKit exposure (frontend-pivot pressure — see §8).
6. **Styles** always carry a descriptor + constraint list; **exemplar passages
   are optional** (0–3 per style).
7. **The character sketch seeds a real Bible character**, so it integrates with
   the relationship / entity-discovery systems — it is not just planning config.
8. **No content filtering is baked into the feature.** The style system is a
   neutral, user-editable mechanism; built-in starter styles are ordinary
   genre/register examples.

---

## §3 Research summary

Two research passes were run on 2026-05-17 — an internal codebase audit and an
external best-practice pass. Full sources in §9.

### §3.1 Internal — what Loom already provides

- **Chapter/scene hierarchy already exists.** `Manuscript → parts: [Part] →
  chapters: [Chapter] → sceneIds: [UUID]`. `Chapter` and `Scene` both already
  carry `targetWordCount`, `summary`, and `Scene` has `SceneStatus.todo`. The
  hierarchy is opt-in — flat projects keep scenes in `orphanedSceneIds`. **A
  generated outline is literally a populated `Manuscript`** — no new container.
- **The prompt has a style slot waiting.** `PromptBuilder` already defines a
  `ChicletKind.styleSheet` and a reserved, cache-stable "style guide" layer
  stubbed in Phase 5 and never wired.
- **Schema is additive** — every model has a hand-written `init(from:)` with
  `decodeIfPresent` + defaults, so new structs land on `Project` with no
  migration.
- **`WritingDirection` / `POVStyle` / `NarrativeTense`** already exist on
  `ProjectSettings` and are already prompt-wired — partial style schema.
- **Phase 7 `TemplateGenerationCoordinator`** runs a per-beat sequential writer
  loop (prompt → generate → sanitise → log). Directly reusable for
  outline-driven per-scene generation (Phase 5).
- **Biggest gap:** project creation today is a bare `NSSavePanel` — there is no
  guided/wizard surface at all.

### §3.2 External — outline generation & style conditioning

- **Framework:** the Save the Cat 15-beat sheet is the most LLM-amenable
  scaffold — fixed, named, ordered slots turn open-ended ideation into
  fill-in-the-blanks, which small models do far more reliably. Three-act
  structure (25 / 50 / 25) is the pacing budget layered over it.
- **Never single-pass an outline on a small model.** Hierarchical staged
  expansion (premise → beats → chapter map → scenes) is markedly more reliable;
  the gap widens for small models.
- **Compute scene/chapter counts deterministically in code**, not via the LLM —
  this eliminates scene-count drift, the #1 outline failure mode.
- **Failure modes:** generic beats (mitigate by injecting premise/sketch nouns
  and requiring each beat to name an entity); pacing collapse / saggy middle
  (mitigate via the act budget + mandatory Midpoint / All-Is-Lost anchors);
  consistency drift (keep the outline as a persistent state document fed into
  later passes). Use positive structural constraints, never blacklists.
- **Style conditioning:** combine a compact natural-language descriptor with
  1–3 short exemplar passages. Put genre and register on *separate labelled
  prompt channels*; place register last and phrase it as hard structural
  constraints so a vivid genre exemplar can't drown it.
- **A good style record:** short label + 2–4-sentence descriptor + explicit
  constraint list + optional 1–3 exemplars + a type tag (genre vs register).

### §3.3 Word-count bands (industry-standard; safe to hardcode)

| Format        | Words           | ~Scenes | Chapters       |
|---------------|-----------------|---------|----------------|
| Flash fiction | < 1,000         | 1       | 0 (flat)       |
| Short story   | 1,000–7,500     | 1–6     | 0 (flat)       |
| Novelette     | 7,500–17,500    | 6–15    | optional       |
| Novella       | 17,500–40,000   | 15–35   | 8–20           |
| Novel         | 70,000–90,000   | 50–60   | 20–40          |

Sizing rule: scenes run ~1,500 words; chapters hold 3–5 scenes.

---

## §4 Architecture — the outline pipeline

Staged expansion. Each stage is small, schema-constrained, and independently
editable — the editability *is* the user's intervention point.

**Stage 0 — Size (deterministic, in code, no LLM).**
`LengthScenario → totalWords → sceneCount = round(totalWords / 1500) →
chapterCount = round(sceneCount / 4)` (0 for flat formats). Distribute scenes
across acts 25 / 50 / 25.

**Stage 1 — Beats (one LLM pass).** Premise + character sketch → the framework's
fixed beat slots (15 for Save the Cat), one sentence each, schema-constrained.
Each beat must reference a named entity from the premise/sketch.

**Stage 2 — Chapter map (one LLM pass, or code-assisted).** Assign beats to the
computed chapter count, respecting the act budget.

**Stage 3 — Scenes (one LLM pass per chapter).** Each chapter → its scenes:
title, POV, location, one-paragraph summary, per-scene word budget.

Output: a fully populated `Manuscript` (Parts/Chapters/Scenes with titles,
summaries, `targetWordCount`, `SceneStatus.todo`, empty `prose`).

**Two-model pipeline.** Outline stages (0–3) run on the small extractor-class
model (gemma-class, the existing extractor server). Prose generation (Phase 5)
uses the writer model (Goetia). Schema-constrained outline passes reuse the
entity-discovery extraction patterns (GBNF / JSON-schema, tolerant parsers).

---

## §5 Data model

All additive (lazy-decode); `PlannedProjectConfig` is optional on `Project`
(nil ⇒ an ordinary blank project).

```
enum StyleType { case genre, register }

struct Style {
    let id: UUID
    var name: String
    var type: StyleType
    var descriptor: String        // 2–4 sentences
    var constraints: [String]     // explicit do/don't
    var exemplars: [String]       // 0–3 short passages, optional
    var isBuiltIn: Bool           // starter vs user-created
}
```

`Style` records live in an **app-level library** (`styles.json` beside
`settings.json` in Application Support) so they are reusable across projects
and ship with built-in starters. Projects *assign* style ids.

```
enum LengthScenario { case flashFiction, shortStory, novelette,
                           novella, novel, custom(targetWords: Int) }

struct OutlineSizing {                 // pure; produced by Stage 0
    let totalWords: Int
    let sceneCount: Int
    let chapterCount: Int              // 0 ⇒ flat scene list
    let perSceneWords: Int
    let actSceneCounts: (Int, Int, Int)
    static func plan(for: LengthScenario) -> OutlineSizing
}

protocol StoryFramework {              // v1: one conformer
    var id: String { get }             // "save-the-cat"
    var beatSlots: [BeatSlot] { get }  // ordered, named
}
struct BeatSlot { let name: String; let actFraction: ClosedRange<Double>
                  let guidance: String }

struct PlannedProjectConfig: Codable {
    var premise: String
    var characterSketch: String        // seeds a Bible character at creation
    var lengthScenario: LengthScenario
    var frameworkId: String            // "save-the-cat" in v1
    var assignedStyleIds: [UUID]
}
```

---

## §6 Phase plan

Recommended sequence **1 → 2 → 3 → 4 → 5**. Phase 3 is independent and
independently valuable — it can move earlier.

### Phase 1 — Foundations (pure data; no UI, no LLM)
`Style` + the app-level style library with built-in starters; `LengthScenario`
+ the `OutlineSizing.plan` allocator; the `StoryFramework` abstraction +
`SaveTheCatFramework`; `PlannedProjectConfig` on `Project`. All TDD,
lazy-decode (forward-load tests per repo norm). Ships nothing visible but
unblocks everything.

### Phase 2 — Outline generation pipeline
The 4-stage premise→outline generator (§4) → a populated `Manuscript`.
Schema-constrained passes; tolerant parsers; stub-testable orchestration.
Reuses the entity-discovery extraction architecture. **Likely wants a probe /
spike** (à la `EntityDiscoverySpike`) to tune the prompts on the small model
before wiring into the app.

### Phase 3 — Style wiring
Wire a project's assigned styles into `PromptBuilder`'s reserved style slot —
genre and register as *separate labelled sections*, register last and phrased
as hard structural constraints. Makes styles actually affect prose.
**Independent of Phase 2**; improves generation for *any* project, planned or
not — a candidate to ship first.

### Phase 4 — Guided creation UI
The wizard: character sketch + premise → length scenario → style assignment →
generate → **review/edit the outline** → create project. Webview-heavy: the
outline editor and style-library editor are React (Bible Workspace); only a
thin entry point is AppKit. The character sketch seeds a Bible character on
creation.

### Phase 5 — Outline-driven writing
Per-scene generation seeded by the scene's outline summary + word budget +
project styles; `.todo → draft → revised → final` status flow. Reuses Phase 7's
`TemplateGenerationCoordinator` per-beat loop. The Plan view (NSCollectionView)
partly exists already; chapter/part section headers are a known follow-on.

---

## §7 Reuse map

| Need | Existing system | Action |
|---|---|---|
| Outline container | `Manuscript`/`Part`/`Chapter`/`Scene` | Reuse as-is |
| Per-node word budgets, summaries, todo status | `Chapter`/`Scene` fields | Reuse as-is |
| Style prompt injection | `PromptBuilder` `styleSheet` slot | Wire the stub |
| Schema growth | lazy `decodeIfPresent` pattern | Reuse — no migration |
| Outline LLM passes | entity-discovery extraction patterns | Adapt |
| Per-scene generation loop | Phase 7 `TemplateGenerationCoordinator` | Adapt |
| Editor UI surface | React Bible Workspace webview | Extend |
| Sketch → character | Bible character model + discovery | Integrate |

---

## §8 Risks & open questions

- **AppKit cost.** Even the thin entry wizard is new AppKit surface; the
  webview-heavy decision contains it but does not eliminate it. Log time costs
  against the tracked frontend-pivot pressure; do not stack brittle workarounds.
- **Two-model orchestration.** Outline on the small model, prose on Goetia —
  the pipeline must resolve both server profiles cleanly.
- **Outline quality on the small model.** Multi-pass + deterministic counts +
  schema constraints mitigate, but Phase 2 should be probe-validated before it
  is trusted in-app.
- **Open — chapter-map pass.** Stage 2 may be doable in pure code (mechanical
  assignment of beats to chapters by act budget) rather than an LLM pass;
  decide during Phase 2 design.
- **Open — style/outline interaction.** Should assigned styles also condition
  *outline* generation (a hardcore-sci-fi outline differs from a YA-fantasy
  one), or only prose? Lean yes — pass style descriptors into Stage 1–3 too.

---

## §9 Sources

External research (2026-05-17), key references:

- [A Survey on LLMs for Story Generation (EMNLP 2025)](https://aclanthology.org/2025.findings-emnlp.750.pdf)
- [Long-form Story Generation with Dynamic Hierarchical Outlining (NAACL 2025)](https://aclanthology.org/2025.naacl-long.63.pdf)
- [Lost in Stories: Consistency Bugs in Long Story Generation (Microsoft Research)](https://www.microsoft.com/en-us/research/publication/lost-in-stories-consistency-bugs-in-long-story-generation-by-llms/)
- [SCORE: Story Coherence and Retrieval Enhancement (arXiv 2025)](https://arxiv.org/html/2503.23512v1)
- [Save the Cat Beat Sheet (Kindlepreneur)](https://kindlepreneur.com/save-the-cat-beat-sheet/)
- [Story Word Count Guide (WordTally, 2026)](https://wordtally.net/guides/story-word-count)
- [Show and Tell: Prompt Strategies for Style Control (arXiv 2511.13972)](https://arxiv.org/abs/2511.13972)
- [How Examples Improve LLM Style Consistency (Latitude)](https://latitude.so/blog/how-examples-improve-llm-style-consistency)

Prior art: Sudowrite Story Engine, NovelCrafter (outlining tools, BYO local
model), PlotDrive (unrestricted long-form). No open-source tool combines
editable structured outlining with local genre-conditioned generation — that
gap is Loom's opportunity.

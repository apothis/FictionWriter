# Loom Story Bible — the consistency engine

> **Status: Phase 0 design lock (2026-05-10).** Specifies how Bible content is authored, stamped, queried, and injected into prompts. Builds on RPClient's Memory + Entity ideas; extends to fiction with the Re3 Edit pattern[L4]. The novel piece — knowledge-state-per-character-per-scene — is Loom's distinctive engineering.
>
> **Memory-architecture supersession note (2026-05-10 PM).** Sections in this doc that describe injection mechanics ([`#4`](#4-lorebook--selective-injection), §5, §6) are refined and extended in [`LOOM_MEMORY.md`](LOOM_MEMORY.md). Notable refinements after Round-2 research: (a) Subcontext-packing of multiple firing entries (NovelAI pattern), (b) Auto-summary embedding-retrieval per scene (AI Dungeon Memory Bank pattern), (c) Pinned spans alongside pinned facts (character.ai pattern), (d) Eviction-order surfacing (AI Dungeon publishes its order). Where this doc and `LOOM_MEMORY.md` disagree on injection mechanics, **`LOOM_MEMORY.md` wins**. The authoring-model and knowledge-ledger sections of this doc remain authoritative for those specific topics.
>
> Companion to [`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md), [`LOOM_GENERATION_MODES.md`](LOOM_GENERATION_MODES.md). Citations to [`LOOM_RESEARCH.md`](LOOM_RESEARCH.md).

---

## 1. What the Bible is, what it isn't

### 1.1 Is

- The **structured database** of everything that needs to be consistent across a long work: characters, settings, objects, factions, timeline events, lore.
- The **injection source** for selective context at generation time.
- A **living artefact** — both authored (user-edited) and machine-extracted (Phase 4+ knowledge ledger).
- **Skippable but rewarding**: Phase 1 ships with hand-authored character paragraphs only; the user is never required to populate the Bible to use Loom.

### 1.2 Isn't

- A document the model writes from scratch. The Bible can *seed* from a Braindump (Sudowrite[A2] auto-fill pattern, research §A.2), but only with explicit user invocation per field.
- A creative-writing workspace. The Bible is *metadata about* the work, not the work itself. Prose lives in scenes.
- Auto-injected wholesale. Constant entries are always-on; keyed entries trigger on recent prose; vectorised entries (Phase 5) retrieve on similarity. Default posture is selective, not all-on.

---

## 2. Authoring model

### 2.1 Three entry paths

1. **From scratch** — user creates an entity in the Bible inspector pane and fills fields. Like Novelcrafter's Codex[B1] — flexible, manual.
2. **Sudowrite-style auto-fill from Braindump (Phase 2+)** — user types a one-paragraph "what's the story?" Braindump; per-field "Generate" button drafts a candidate the user can edit. Mirrors RPClient's Phase 9 §5.4 AI-assist pattern (research §M.2).
3. **Auto-extracted from prose (Phase 4+)** — when a scene is written, a side-call extractor proposes new entities (a name appears, a place is mentioned). Surfaces as a "Suggestions" chip in the Bible inspector — never silently added; user accepts.

### 2.2 In-place editing

Per [`LOOM_DESIGN_LANGUAGE.md`](LOOM_DESIGN_LANGUAGE.md) §14.5.1 + §11 (Notion-pattern inline editing): every Bible field edits in place, no modal sheet. Click → cursor lands → type → click outside or `Esc` to commit. Multi-line fields use the same `body` font as the editor.

### 2.3 Aliases (load-bearing)

Every entity has a `name` and `aliases: [String]` (research §3.1). Aliases drive:

- **Keyword matching** for keyed-mode injection. "Mia," "Miss Vance," "the librarian" all match the same Character entity.
- **Inline references** when the user types `@<alias>` in the editor.
- **Reference resolution** when extracting facts from prose (Phase 4+) — the extractor disambiguates pronouns to the canonical entity by alias matching plus context.

Aliases are populated:

- **Manually** by the user.
- **Suggested** automatically post-scene-extraction (Phase 4+) when the extractor sees a name pattern that consistently co-occurs with an existing entity.

---

## 3. Knowledge ledger — the distinctive engineering

The user's stated novel-territory feature: **what does Bob know at scene 12 vs scene 18**. Loom's approach extends Re3's Edit module[L4] (research §L.2) — character-fact-attribute pairs — to **per-scene granularity with explicit unknowns and mistaken beliefs**.

### 3.1 Schema

Per [`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md) §3.1:

```swift
struct KnownFact {
    var fact: String          // natural-language assertion
    var sourceSceneId: UUID?  // where they learned it (nil = pre-story knowledge)
    var certainty: Certainty  // asserted / suspected / unknown / mistaken
    var addedAt: Date
}
```

Stored on each `Character` as `knownFactsBySceneId: [UUID: [KnownFact]]`. The map is keyed by *scene where this set was extracted*, not by the scene the facts apply to. To query "what does Mia know at scene N," Loom unions all `KnownFact`s from scenes that chronologically precede N for Mia, then resolves contradictions (later certainty overrides earlier — character "learned" something).

### 3.2 Extraction pipeline (Phase 4+)

After a scene is written or substantially edited, an asynchronous side-call runs:

```
[1] Trigger
    Scene save / edit + prose-changed-by-N-words threshold (~200 words default).
    User can also force "Re-extract" from the Bible inspector.

[2] Extraction prompt (to summarizer-role server)
    Input: scene prose + bible character list (names + aliases) + bible setting list.
    Output: structured JSON with { character_id, fact, certainty, evidence_quote }.

[3] Diff + propose
    Compare extracted facts to existing character ledgers.
    New facts surface as Suggestions in the Bible inspector.
    User accepts/rejects/edits per fact (per-field accept pattern from RPClient §5.4.b).

[4] Persist
    Accepted facts merge into bible/characters/<id>.json knownFactsBySceneId.
    Knowledge index marked dirty for affected character.
```

The extractor is a **side-call**, separate from the main generation server. Mirrors RPClient's role-routed servers pattern (research §V2_PLAN §2.4): a small fast model (e.g., Mistral Nemo 12B) is fine for extraction; doesn't have to be the user's heavyweight prose model.

### 3.3 Extraction prompt skeleton

```
Read the scene below. Extract factual claims about characters present in or referenced by the scene. For each fact, output a JSON object with:
- character_id: which character this fact is about (use {NAME or ALIAS}).
- fact: natural-language assertion (one sentence, third-person).
- certainty: "asserted" if shown clearly, "suspected" if hinted, "unknown" if explicitly NOT known by this character, "mistaken" if the character holds a wrong belief.
- evidence_quote: short quote from the scene supporting the assertion.

Distinguish what the character DID or LEARNED in this scene from what was already true.
Do not infer beyond the text. Do not invent.
Output a JSON array. Empty array if no claims extractable.

Bible characters (names + aliases):
{CHARACTER_LIST_JSON}

Scene:
{SCENE_PROSE}
```

Output is parsed and matched to the closest entity by alias; unmatched facts surface as **"this scene seems to be about a character not in your Bible — add them?"** suggestions.

### 3.4 Querying the ledger at generation time

When Loom generates a scene with a known POV character, the [KNOWLEDGE-LEDGER] context layer (per [`LOOM_GENERATION_MODES.md`](LOOM_GENERATION_MODES.md) §11) is built:

1. Resolve the chronological position of the current scene.
2. Walk all preceding scenes (chronologically, not narratively) for this POV character.
3. Union their `KnownFact` arrays; resolve contradictions (later wins; explicit `mistaken` overrides asserted).
4. Format as natural-language `KNOWS / DOES NOT KNOW / MISTAKENLY BELIEVES` blocks.
5. Token-budget-clip if necessary (most-recent-scenes wins).

The `DOES NOT KNOW` block is the most distinctive — most prior systems only track positive knowledge. Re3's Edit[L4] tracks attributes; Loom tracks the negative space *as the engineering point*.

### 3.5 Limitations and honesty

- **Extraction quality depends on the side-call model.** Phase 4 implementation should A/B test 8B / 12B / larger models on a small fixture corpus.
- **Pronoun resolution failures are real.** A scene with three female characters and many "she" pronouns will produce attribution errors. The extractor's `evidence_quote` field exists to make these auditable.
- **Negative knowledge is derived from scene-exposure, not extracted from prose.** This is the load-bearing design call (added 2026-05-11 after [`LOOM_LEDGER_SPIKE.md`](LOOM_LEDGER_SPIKE.md) §8.3 and research into SymbolicToM-style belief-graphs). The extractor's grammar emits ONLY `asserted` facts (positive observations from the prose it sees). Each fact is stamped with the `sourceSceneId` it was extracted from. At query time, "does Mia know fact F as of scene N?" is computed structurally: walk scenes chronologically ≤ N, check whether Mia was POV / present-for any scene from which F was extracted; if not, F is `unknown` to Mia by construction. This sidesteps the empirically-unsolved problem of asking a local model "what does X not know?" (LOOM_LEDGER_SPIKE §3.e: recall 0/2 on `unknown` extraction at 27B). `mistaken` stays as a manual-authoring path in the Bible inspector — rare, user-surfaced when prose explicitly contradicts a character's belief.
- **Contradiction resolution is naive in v1.** Later-scene wins is heuristic; a character may "forget" something legitimately. Phase 4+ open question for refinement.

---

## 4. Lorebook — selective injection

Per research §M.4 (NovelAI[C1] + KoboldAI[D1] + SillyTavern[H1] convergent pattern):

### 4.1 Three activation modes

| Mode | When injected | Token cost | Use |
|---|---|---|---|
| **Constant** | Always | High | Global setting, narrator persona, story-spanning lore |
| **Keyed** | Recent prose contains key | Low (only when relevant) | Character backgrounds, location lore, faction details |
| **Vectorised** (Phase 5) | Embedding-similarity to recent prose / generation prompt exceeds threshold | Medium | Style exemplars, scene-type-matched references |

### 4.2 Keyed-mode mechanics

Per `LorebookEntry` schema in [`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md) §3.6:

- **Primary keys**: any one match in the recent-prose window triggers.
- **Secondary keys**: AND-gated — primary AND secondary keys both must appear (NovelAI's `&` operator[C1]).
- **Recent-prose window**: configurable per entry; default 4000 chars (~1000 words). Mirrors NovelAI Search Range[C2].
- **Match semantics**: case-insensitive, word-boundary (no substring matches; "rat" doesn't trigger on "rate").

### 4.3 Position control

- `top` — injected after Memory (always-top region).
- `bottom` — injected at depth-N before the cursor (Author's Note region).
- `depthN` — explicit positioning; user picks depth in lines/scenes.

Per NovelAI's empirical finding[C2]: lower in the prompt = stronger influence. "Always-on" character voice notes go top; "remember this scene-specific tone" goes bottom.

### 4.4 Priority and budget

When multiple keyed entries match and budget overflows, sort by priority (descending), break ties by recency of last-edit, take until budget exhausted. Never silently truncate an entry's content — drop entries entire rather than partial.

---

## 5. Memory + Author's Note (project-level)

Carried through verbatim from the NovelAI / KoboldAI shape (research §C.2, §D.1):

### 5.1 Memory

A free-text field per project (research-borne convention). Always injected at the top of every prompt. Typical content:

- Genre and tone declaration.
- Premise / story setup.
- High-level rules of the world ("magic exists but is rare," "this is a present-tense first-person novel").
- Always-true facts the model needs to remember.

Not the same as the per-character Bible — Memory is *project-scoped narrator-instruction*. The Bible is *queryable structured entities*.

### 5.2 Author's Note

A free-text field per project, also editable per-scene (Phase 3+ override). Always injected near the *bottom* of the prompt (depth-N), where its influence is strongest[C3].

Typical content:

- Tone steering ("write with a wry, distant narrator").
- Scene-pacing instructions ("slow this down; sensory detail").
- Stylistic hints ("avoid metaphor; favour direct prose").
- POV/tense reminders.

`authorsNoteDepthLines` controls how many lines from end the Note is injected. Default 4. Closer to end (smaller depth) = stronger.

### 5.3 Why both, not one

NovelAI / KoboldAI / SillyTavern all have both because they serve different roles. Memory is *what is true*; Author's Note is *how to write it*. Combining them into one field reliably degrades output. Loom keeps the trichotomy.

---

## 6. Bible injection at generation — the assembled order

Per [`LOOM_GENERATION_MODES.md`](LOOM_GENERATION_MODES.md) §1.1, the Bible interacts with the prompt at four layers:

```
[MEMORY]               → Project Memory field (top)
[BIBLE-CONST]          → Constant lorebook + always-on character/setting summaries
[BIBLE-KEYED]          → Keyed lorebook entries that match recent-prose window
[KNOWLEDGE-LEDGER]     → POV character's known/unknown/mistaken facts (Phase 4+)
[AUTHORS-NOTE]         → Project Author's Note (depth-N from end)
```

Always-on character/setting summaries (in BIBLE-CONST) are an opinionated default: every character with `role: protagonist` or `role: antagonist` is always included. Supporting characters are keyed-only by default. Minor characters require explicit `enabled: true` to even be considered for keyed-injection.

User can override per entity via a "Always include" toggle on the entity sheet.

---

## 7. Bible inspector pane — the surface

Per [`LOOM_DESIGN_LANGUAGE.md`](LOOM_DESIGN_LANGUAGE.md) §14.5.1.

Tabs across the top: **Bible · History · Notes**. Bible tab sections (each collapsible disclosure):

- **Characters** — list of cards, expand inline to edit.
- **Settings** — locations.
- **Objects** — significant objects.
- **Factions** (Phase 3+).
- **Timeline** (Phase 3+) — chronological event list, sortable.
- **Lorebook** — entries with activation-mode chip, key list, content preview.
- **Style** (Phase 5) — style sheet.

Each section has a `+` button at the header to add. Each entity has a `⋯` overflow menu (rename / duplicate / delete / "Always include" toggle).

### 7.1 Character card layout (collapsed)

```
┌─ Mia Vance ─────────────────────── ⋯ ┐
│ Protagonist · POV in 8 scenes        │
│ "A late-thirties librarian who…"     │
│ ▾ Knowledge ledger (12 facts)        │
└──────────────────────────────────────┘
```

Click the title row to expand to full edit form (name, aliases, role, oneLine, description, personality, appearance, voice, goals, relationships, knowledge ledger).

### 7.2 Knowledge ledger (expanded)

```
┌─ Knowledge ledger — Mia Vance ──────────────────┐
│                                                  │
│ KNOWS                                            │
│   • The stranger at the door is named Anders.   │
│     [scene 4 · asserted]   Edit · Remove         │
│   • Anders is from the city.                     │
│     [scene 4 · suspected]  Edit · Remove         │
│                                                  │
│ DOES NOT KNOW                                    │
│   • That Anders is Bob's brother.                │
│     [scene 7 · explicit]   Edit · Remove         │
│                                                  │
│ MISTAKENLY BELIEVES                              │
│   • That her sister is in Paris.                 │
│     (Actually: in the basement)                  │
│     [scene 2 · authored]   Edit · Remove         │
│                                                  │
│  + Add fact   Re-extract from scene…             │
└──────────────────────────────────────────────────┘
```

Each fact is editable in place. "Re-extract from scene…" runs the Phase 4 extraction pipeline (§3.2) against a chosen scene and proposes diffs.

---

## 8. Validation — the consistency lints (Phase 4+)

Background side-call work: the Bible inspector surfaces *contradictions* and *gaps* it detects. These are signals to the user, never auto-fixes.

Examples of lints:

- **Contradiction**: scene 7 has Mia say "I never met Anders" but her ledger lists "knows Anders" from scene 4. Surfaced as a yellow chip on the relevant scene + the ledger entry.
- **Mistaken-belief never resolved**: Mia mistakenly believes X as of scene 2; ledger never has the belief corrected; story ends. Surfaced as a "Did Mia ever learn the truth?" suggestion.
- **Pronoun ambiguity**: "she said" could refer to two characters in the scene; extractor flagged uncertain attribution.
- **Dangling reference**: prose mentions `@karim` but the Karim entity was deleted. Surfaced as a soft warning.

Lints surface in the Bible inspector + in the History tab next to the relevant generation event. Implementation: post-extraction pass against accumulated ledger.

---

## 9. Bible authoring + AI-assist (Phase 2+ Sudowrite-style fill)

Adapted from RPClient Phase 9 §5.4's per-field AI-assist (research §M.2). Each Bible entity field gets a `Generate` button next to it that:

1. Reads earlier-in-dependency-order fields (Braindump → Synopsis → Genre → Style → Characters → ...).
2. Sends a context-aware prompt to the generation server.
3. Displays 2–3 candidates in a triad strip, like RPClient §5.4.a (research §A.7).
4. User clicks one to use, "Edit" to refine, or dismisses.

The dependency order matches Sudowrite's[A2] but is non-strict: user can fill out-of-order; AI-assist just won't have upstream context to draw on.

**Differences from Sudowrite:**

- Loom doesn't auto-cascade — clicking Generate on Synopsis fills Synopsis only, not subsequent fields.
- Loom never generates without explicit invocation. No "auto-fill the missing fields" autopilot in Phase 2; reconsider Phase 4+.
- Loom shows the prompt that will be sent (one-click reveal) before generating.

---

## 10. Implementation phasing

| Feature | Phase | Notes |
|---|---|---|
| Manual entity authoring (Character, Setting, Object) | 2 | The MVP for the Bible. |
| Constant + keyed lorebook | 2 | Reuses RPClient's `WorldInfoInjector` shape. |
| Always-inject character paragraph in prompts | 1 | Minimal subset — even before full Bible inspector. |
| Memory + Author's Note fields | 1 | Inherits NovelAI/KoboldAI semantics. |
| Per-field AI-assist (Generate button) | 2.5 | After core Bible UI lands. |
| Knowledge ledger (manual authoring) | 4 | Schema lands earlier; UI in Phase 4. |
| Knowledge ledger (auto-extraction) | 4 | Side-call extractor. |
| Vectorised lorebook + style sheet | 5 | RAG infrastructure. |
| Consistency lints | 4+ | After ledger lands. |
| Faction, Timeline events | 3 | Co-arrives with hierarchy phase. |

---

## 11. Open questions

- **Cross-character contradiction detection.** Two characters' ledgers disagree about a shared fact. Lint surface? Auto-resolve? **Decision: lint only; never auto-resolve.** Phase 4+.
- **Time travel / non-linear narrative**. Chronological-vs-narrative order is already in `SceneTime` schema; the ledger query uses chronological. But what about flashbacks? **Decision (provisional): the flashback's chronological position is the actual past time it depicts; the narrative position is the scene order. Ledger queries use chronological.** Verify in Phase 4 against a real flashback-heavy manuscript.
- **Ensemble protagonists**. Multiple POVs sharing a knowledge state. **Decision: each character has their own ledger; "shared knowledge" is implicit overlap.** No data-shape change required.
- **Bible is missing entities for an existing manuscript.** Phase 4 retrofit pass: extractor runs over every existing scene, proposes entities. Surfaced as a "Bible is empty; want to import from your manuscript?" one-time prompt.

---

## 12. References

**Internal:**
- [`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md) §3 — Bible schemas.
- [`LOOM_GENERATION_MODES.md`](LOOM_GENERATION_MODES.md) §1.1, §11 — context-assembly + knowledge-ledger layer.
- [`LOOM_RESEARCH.md`](LOOM_RESEARCH.md) §A, §B, §C, §H, §L — citations.

**External (RPClient):**
- `Sources/RPClientCore/Memory/WorldInfo*.swift` — keyed-injection precedent.
- `Sources/RPClientCore/Memory/Entity*.swift` — entity-stamping precedent.
- `V2_PHASE9_AI_ASSIST_RESEARCH.md` — per-field AI-assist precedent.

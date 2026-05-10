# Loom Generation Modes

> **Status: Phase 0 design lock (2026-05-10).** The load-bearing engineering doc for prompt templates and context assembly. Companion to [`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md), [`LOOM_STORY_BIBLE.md`](LOOM_STORY_BIBLE.md). Citations into [`LOOM_RESEARCH.md`](LOOM_RESEARCH.md).
>
> **Memory-architecture supersession note (2026-05-10 PM).** [`LOOM_MEMORY.md`](LOOM_MEMORY.md) is the authoritative memory-architecture spec; it inherits RPClient's six-layer model + precedence contract and extends with Round-2 research findings (AI Dungeon Memory Bank, NovelAI Subcontext, character.ai Pinned Messages, RAPTOR/LightRAG/SCORE academic patterns). Where this doc's §1 (common context-assembly) and the layer set in [`LOOM_MEMORY.md`](LOOM_MEMORY.md) §4 disagree, **`LOOM_MEMORY.md` wins**. The token-budget allocations in §1.2 below are still load-bearing; the layer order is refined in `LOOM_MEMORY.md` §4.1 + §A3.
>
> **Scope.** Each mode's prompt skeleton + context-assembly strategy + output handling. Token-budget allocation at 8k / 16k / 32k context. Phase mapping noted per mode.

---

## 1. Common context-assembly contract

Every generation, regardless of mode, follows the same overall assembly. The mode-specific delta is what *kind* of context dominates and what the system instruction asks for.

### 1.1 Standard prompt layers (top-to-bottom)

Per [`LOOM_RESEARCH.md`](LOOM_RESEARCH.md) §M.4 (NovelAI[C2] / KoboldAI[D1] / SillyTavern[H1] hierarchy):

```
[SYSTEM] System prompt (instruct-template-aware; per-mode preface)
[MEMORY] Project Memory field (always-top, NovelAI/KoboldAI Memory[C3][D1])
[BIBLE-CONST] Bible: constant-mode lorebook + always-on character/setting/object summaries
[STYLE] Style sheet sample paragraphs (Phase 5; absent earlier)
[STRUCTURE] Project / Part / Chapter summaries (Phase 3+ recursive-summary chain[L1])
[BIBLE-KEYED] Bible: keyed-mode entries that match the recent prose window
[KNOWLEDGE-LEDGER] What this scene's POV character knows-and-doesn't-know (Phase 4+)
[RECENT-PROSE] Up to N words of preceding prose (per mode budget)
[FEW-SHOT-STYLE] Phase 5: scene-type-matched style exemplars (action / dialogue / etc.)
[AUTHORS-NOTE] Author's Note at depth-N from end (NovelAI A/N Strength[C3])
[MODE-INSTRUCTION] The actual request: continue / expand / rewrite / ...
[CURSOR/SELECTION] The text immediately before the cursor or the selected passage
```

The order is deliberate: most-static (System, Memory) at top; most-dynamic + most-influential (Author's Note, mode instruction, cursor) at bottom. This matches NovelAI's "lower in prompt = stronger influence" empirical finding[C2].

### 1.2 Token-budget allocation (default)

Per `Settings.contextBudgetTokens`. Three sample budgets:

| Layer | 8k context | 16k context | 32k context |
|---|---|---|---|
| System prompt | 200 | 200 | 200 |
| Memory | 250 | 500 | 750 |
| Bible (constant) | 800 | 1500 | 2500 |
| Style (Phase 5) | 0 / 400 | 0 / 800 | 0 / 1500 |
| Structure (Phase 3+) | 0 / 400 | 0 / 800 | 0 / 1500 |
| Bible (keyed) | 600 | 1200 | 2000 |
| Knowledge ledger (Phase 4+) | 0 / 300 | 0 / 600 | 0 / 1000 |
| Recent prose | **3000** | **6000** | **15000** |
| Few-shot style (Phase 5) | 0 / 600 | 0 / 1500 | 0 / 3000 |
| Author's Note | 200 | 300 | 500 |
| Mode instruction | 150 | 200 | 250 |
| Selection / cursor | 200 | 300 | 500 |
| **Reply budget** | ~2000 | ~3000 | ~4500 |

Note: 32k recent-prose budget (15,000 tokens ≈ 11,000 words) is still well below Sudowrite's claimed 20k words[A4] — Loom is local-model-shaped, where 32k is realistic ceiling and 16k is common floor. The 20k-word recent-prose target is **aspirational; achievable on 32k+ context models**, not a default.

When the assembled context exceeds budget, layers are evicted in this priority order (lowest first): few-shot style, structure, keyed bible (lowest-priority entries), recent prose (oldest first), constant bible (lowest-priority), knowledge ledger.

The actual eviction strategy is implementation work for Phase 1; this is the contract.

### 1.3 Instruct-template handling

Per research §I.4: the model card dictates the template. Loom does **not** unilaterally pick. `InstructTemplate.auto` (the default) probes the server (`/api/v1/model` returns the model name; pattern-match against known families) and falls back to `.raw` (no template) if uncertain.

For story-mode use specifically, **the system prompt is collapsed differently per template:**

- ChatML / Llama3: `<|system|>...<|user|>[mode instruction + selection]<|assistant|>[expected continuation]`
- Mistral V3: no system tokens; system prompt prepended into first `[INST]` block
- Mistral V7: native system support via `[SYSTEM_PROMPT]`
- Alpaca: `### Instruction:` and `### Response:` framing
- raw: pure completion; system prompt is just prose-mode instruction text at top

Story-mode generations pass the **expected continuation prefix empty** so the model continues naturally rather than emitting an "assistant turn." This is the dominant story-mode-on-chat-models technique (research §H.2 SillyTavern preset culture).

---

## 2. Mode: Continue (Phase 1)

**What it does.** Continues writing from the cursor position. The model's job: extend the prose naturally, in voice, for ~500 words (configurable).

**Trigger.** Cursor in editor, no selection. Click `Continue` button or `⌘⇧E`.

**Context strategy.** Standard assembly. Recent-prose layer is the "last N tokens immediately before cursor." Mode instruction is minimal — the work is in the recent-prose continuity.

**System prompt skeleton:**

```
You are a fiction writer continuing an existing manuscript. Maintain voice, tense, POV, and tone exactly as established in the preceding text. Continue the scene naturally — do not summarize, do not break narrative voice, do not introduce meta-commentary. Continue for approximately {N_WORDS} words, ending at a natural pause (paragraph break, scene beat, or sentence boundary).
```

**Mode instruction (last layer before cursor):** *empty*. The cursor itself is the instruction.

**Output handling.** Insert at cursor. Acceptance UI per [`LOOM_DESIGN_LANGUAGE.md`](LOOM_DESIGN_LANGUAGE.md) §14.6: 6pt accent rule + Accept/Reject/Redo buttons. Auto-accept on edit.

**Phase 1 minimal version.** Recent-prose + Memory + simple character bible (always-injected). No keyed bible, no knowledge ledger. Sufficient for the MVP demo.

---

## 3. Mode: Expand (Phase 1)

**What it does.** Takes a sketch (sparse paragraph or list of beats) in the user's selection and expands it into full prose.

**Trigger.** Selection in editor. Click `Expand` or `⌘E`.

**Context strategy.** Standard assembly. Selection is the *target sketch* — passed at the bottom with explicit framing. Recent-prose still included to maintain voice.

**System prompt skeleton:**

```
You are a fiction writer expanding a sketch into prose. The selection below is a draft outline — beats, fragments, or a sparse paragraph that the author wants fleshed out. Expand it into approximately {N_WORDS} words of prose that:
- Preserves every beat in the sketch (do not skip, do not invent missing plot)
- Matches the voice/tense/POV of the surrounding manuscript
- Adds sensory detail, dialogue, and interiority appropriate to the scene
- Does not include meta-commentary or markdown headers

Sketch to expand:
{SELECTION}
```

**Mode instruction layer:** the system prompt's "Sketch to expand:" framing.

**Output handling.** Replaces selection. Same acceptance UI as Continue. The original sketch is recoverable from the GeneratedSpan record (and a Snapshot is taken automatically per Phase 2+).

**Phase 1 minimal version.** Same as Continue — recent prose + memory + minimal bible.

---

## 4. Mode: Rewrite (Phase 4)

**What it does.** Takes a selection of finished prose and rewrites it. The user picks a *flavour*: voice change, tense change, POV change, length change, formality, show-don't-tell.

**Sub-modes** (each its own prompt skeleton):

### 4.1 Rewrite — voice

```
Rewrite the selection in a different voice. Target voice: {USER_DESCRIPTOR or STYLE_REF}. Preserve all plot and dialogue beats; do not add or remove events. Match the manuscript's tense and POV. Approximately the same length as the original.
```

### 4.2 Rewrite — tense

```
Rewrite the selection in {past|present} tense. Preserve voice, POV, plot beats, dialogue verbatim where natural. Keep approximate length.
```

### 4.3 Rewrite — POV

```
Rewrite the selection from a different POV. Source POV: {CURRENT}. Target POV: {NEW_POV_CHARACTER}, {first|third|second}-person, {limited|omniscient}. Preserve plot and dialogue; the new POV character may not have access to all internal thoughts of the original — adjust interiority accordingly. {KNOWLEDGE_LEDGER_HINT}
```

The `KNOWLEDGE_LEDGER_HINT` is filled with what the new POV character does and doesn't know at this scene's chronological position (Phase 4+ knowledge ledger). Without it, POV swaps invent things the character couldn't know.

### 4.4 Rewrite — length (longer / shorter)

```
Rewrite the selection at {120%|80%|50%|150%} of its current length. Preserve all plot/dialogue beats. Adjust through {expanded sensory detail and interiority | tightened phrasing and trimmed prose}.
```

### 4.5 Show-don't-tell

```
Rewrite the selection so that emotional, internal, or summary statements are dramatised through action, dialogue, gesture, sensory detail, and concrete observation rather than told to the reader. Do not add new plot. Approximately {120%|140%} length.
```

**Output handling.** Replaces selection; acceptance UI; auto-Snapshot of the original (Phase 2+).

---

## 5. Mode: Brainstorm (Phase 4)

**What it does.** Generates ideas — plot points, character names, settings, scene seeds, "what could happen next?" Output is *not prose to insert* — it's a list to consider.

**Trigger.** No selection required (uses cursor context). Click `Brainstorm` (⌘B). Opens a **popover**, not inline insertion. Output rendered as numbered options the user can click to copy/insert.

**System prompt skeleton:**

```
You are a fiction-writing brainstorm partner. Generate {N=8} distinct, concrete options for {USER_QUESTION}. Each option should be:
- Specific (not generic; named characters, named places, concrete actions)
- Different in shape from the others (don't list variations of one idea)
- Compatible with the established manuscript context

Format: numbered list, one option per line, no preamble.
```

`USER_QUESTION` is solicited inline in the popover ("What should happen next?", "Names for the antagonist?", "How should this scene end?", or free-form).

**Output handling.** Popover-only. User clicks an option to insert at cursor (or copies). No acceptance state — Brainstorm output isn't draft prose.

---

## 6. Mode: Critique (Phase 4)

**What it does.** Reads the current scene (or selection) and produces critique notes. Modelled on AutoCrit's fiction-aware critique posture[J9] (research §J.6).

**Trigger.** Selection or scene-level (no selection = whole scene). Click `Critique` or `⌘⇧K`. Opens the critique in the **History inspector tab** (not as inserted prose).

**System prompt skeleton:**

```
You are a fiction editor reviewing the passage below. Provide critique notes in this structure:

1. **Pacing** — does it move? Drag points? Rushed beats?
2. **POV consistency** — head-hopping? Tense slips?
3. **Dialogue** — natural? Voice-distinct per character? Tag overuse?
4. **Show vs tell** — emotional summary that should be dramatised?
5. **Continuity** — does anything contradict established Bible/prior scenes?
6. **Two specific suggestions** — concrete, actionable.

Be specific: cite lines or beats, not generalities. Do not rewrite; describe.

Passage:
{SELECTION}
```

**Output handling.** Critique appears as a History entry (research §M.1: not inserted into prose, kept as a separate artefact). User can re-roll, copy individual notes into the Notes tab, or apply suggested rewrites manually.

---

## 7. Mode: Bridge (Phase 4)

**What it does.** Generates a transition between two passages. User selects passage A, then passage B (or just selects across a gap), and asks Loom to write the connective tissue.

**Trigger.** Multi-selection with intentional gap, or two scenes both highlighted. `⌘⇧B`.

**System prompt skeleton:**

```
You are a fiction writer composing a transition between two passages. Passage A ends with {LAST_300_CHARS_OF_A}. Passage B begins with {FIRST_300_CHARS_OF_B}. Write a bridge of approximately {N_WORDS=200} words that:
- Connects the two passages naturally — temporal shift, scene break, or smooth flow as appropriate
- Maintains voice, tense, POV
- Does not contradict either passage
- Ends with a clean lead-in to passage B's opening sentence

Bridge:
```

**Output handling.** Inserts at the gap (or replaces the placeholder selection). Acceptance UI.

---

## 8. Mode: Describe (Phase 4)

**What it does.** Sudowrite's Describe mode[A6] — generates rich sensory description of a thing, place, person, or feeling.

**Trigger.** Selection of a *thing* (a noun phrase or a paragraph subject). Right-click → Describe, or `⌘⇧D`.

**System prompt skeleton:**

```
You are a fiction writer expanding a brief mention into rich, sensory prose. The selection identifies what to describe. Generate approximately {N_WORDS=150} words that:
- Engage at least three of: sight, sound, smell, taste, touch, kinesthesia
- Match the manuscript's voice, tense, and POV
- Stay within the scene's emotional register (not florid prose in a tense scene)
- Stop at a natural sentence boundary

Subject:
{SELECTION}
```

**Output handling.** Inserts at cursor (just after the selection). Acceptance UI.

---

## 9. Mode: Name suggest (Phase 4)

**What it does.** Generate a list of names — characters, places, factions, items. Lightweight; replaces the popover-shape of Brainstorm with a more focused query.

**Trigger.** `⌘⇧Space N` (Loom-specific) or "+ Add character" in the Bible inspector when name is empty.

**System prompt skeleton:**

```
Generate {N=12} distinct names for a {character|place|faction|object} fitting:
- Genre: {GENRE}
- Setting: {SETTING_ONE_LINE}
- Constraints: {USER_CONSTRAINTS or "no specific constraint"}

Names should be plausible, distinct from each other, and not over-clichéd for the genre. List one per line, no preamble.
```

**Output handling.** Popover with selectable list. Click to use.

---

## 10. Mode-context matrix

Quick reference: which context layers each mode consumes by default.

| Mode | Mem | BibleC | Style | Struct | BibleK | Ledger | Recent | FewShot | A/N | Phase |
|---|---|---|---|---|---|---|---|---|---|---|
| Continue | ✓ | ✓ | (P5) | (P3+) | ✓ | (P4+) | **heavy** | (P5) | ✓ | 1 |
| Expand | ✓ | ✓ | (P5) | (P3+) | ✓ | (P4+) | medium | (P5) | ✓ | 1 |
| Rewrite (any) | ✓ | ✓ | (P5) | – | ✓ | – (POV: ✓) | light | (P5) | ✓ | 4 |
| Brainstorm | ✓ | ✓ | – | (P3+) | ✓ | (P4+) | medium | – | – | 4 |
| Critique | ✓ | ✓ | – | (P3+) | ✓ | (P4+) | medium | – | – | 4 |
| Bridge | ✓ | ✓ | – | – | ✓ | (P4+) | A+B ends | – | ✓ | 4 |
| Describe | – | ✓ | – | – | ✓ | – | light | – | ✓ | 4 |
| Name suggest | – | ✓ (genre/setting only) | – | – | – | – | – | – | – | 4 |

`(P3+)` = available from that phase onward; `(P4+)` = same; `(P5)` = Phase 5 style ingestion.

---

## 11. Knowledge-ledger context layer (Phase 4+)

Per research §O.2 / [`LOOM_RESEARCH.md`](LOOM_RESEARCH.md) §L.2 (Re3 Edit module).

When the speaking POV character is identifiable, the prompt includes:

```
[KNOWLEDGE-LEDGER]
{POV_CHARACTER} knows the following as of this scene:
- {fact 1}
- {fact 2}
- ...

{POV_CHARACTER} explicitly does NOT know:
- {fact A}
- ...

{POV_CHARACTER} mistakenly believes:
- {fact M} (actual: {fact M-truth})
```

This layer is small (~300–1000 tokens budget) but **load-bearing for consistency**. Without it, POV scenes routinely have characters reference information they couldn't have.

The ledger is built incrementally:

1. After scene completion, a side-call extractor (RPClient `summarizer` role server pattern) reads the new scene + the character list.
2. Extractor outputs JSON: `[{character_id, fact, certainty, scene_id}]`.
3. Loom merges into `bible/characters/<id>.json` `knownFactsBySceneId`.
4. User can edit/delete facts in the Bible inspector.

Implementation deferred to Phase 4. Schema lives in [`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md) §3.1.

---

## 12. Refusal handling

Per RPClient `feedback_quirk_detectors` inheritance: when the response matches refusal patterns ("I can't help with…", "As an AI assistant…"), the History tab logs `refusalDetected: true` and the generation event surfaces a yellow chip in the History UI[§14.5.2]. Loom does **not** retry, modify the prompt, or apologise — the user sees what happened, sees the prompt, decides what to do.

For uncensored local models this should be rare. When it happens, common causes are:

- Model card uses a system prompt expecting safe-content alignment (user can override Memory).
- Instruct template mismatch leading the model to revert to chat-default behaviour.
- The user has typed a content prompt the model finds disagreeable; sampler increase or model swap solves.

---

## 13. Output post-processing

Minimal. Per RPClient `feedback_postprocessing_minimalism`:

- Strip `<think>...</think>` blocks if model is thinking-mode-tuned (RPClient `ThinkBlockFilter` reuse).
- Strip leading/trailing whitespace.
- Strip leading "Sure, here's" / "Of course" / role-prefix artifacts ("Assistant:", "Author:", character name colon prefixes that aren't legitimate dialogue tags) — small allow-list of stripping patterns; conservative.

**Do not:** auto-correct grammar; auto-format markdown; auto-collapse whitespace; auto-rephrase. The model's voice is what the user wanted.

---

## 14. Mode acceptance UX summary

| Mode | Inserts at | Replaces? | UI surface |
|---|---|---|---|
| Continue | Cursor | No | Inline acceptance |
| Expand | Selection | Yes (sketch → prose) | Inline acceptance + auto-Snapshot |
| Rewrite (any) | Selection | Yes | Inline acceptance + auto-Snapshot |
| Brainstorm | Popover | – | Popover; click to insert |
| Critique | History tab | – | Inspector pane only |
| Bridge | Gap / selection | Yes | Inline acceptance |
| Describe | After selection | No (insert) | Inline acceptance |
| Name suggest | Popover | – | Popover; click to insert |

---

## 15. References

**Internal:**
- [`LOOM_PLAN.md`](LOOM_PLAN.md) — phasing.
- [`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md) — `GenerationLogEntry`, `GenerationDefaults`, `Scene` shape.
- [`LOOM_STORY_BIBLE.md`](LOOM_STORY_BIBLE.md) — knowledge ledger pipeline.
- [`LOOM_RESEARCH.md`](LOOM_RESEARCH.md) — citations.

**External (RPClient):**
- `Sources/RPClientCore/PromptBuilder.swift` — layered-injection precedent.
- `Sources/RPClientCore/Templates.swift`, `GemmaTemplate.swift`, `QwenTemplate.swift` — instruct-template handling reuse.
- `Sources/RPClientCore/ThinkBlockFilter.swift` — `<think>` strip reuse.

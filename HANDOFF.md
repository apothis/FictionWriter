# Loom — Phase 0 Handoff

> **Date:** 2026-05-10. **Status: Phase 0 complete.** All 13 design docs landed; UI research pass against gold-standard prior art done; design language §14 locked. Ready for Phase 1 implementation against [`LOOM_PHASE1_EDITOR_MVP.md`](LOOM_PHASE1_EDITOR_MVP.md).
>
> This handoff is the entry point for a subsequent context picking up Phase 1. Read **§6 ("Recommended Phase 1 entry checklist")** first; it's the smallest working set to internalise before sub-step 1.a.
>
> **Repo**: `/Volumes/SSD1/Code/FictionWriter` · pushed to [github.com/apothis/FictionWriter](https://github.com/apothis/FictionWriter) · branch `main`. RPClient (the source of inherited plumbing) at `/Volumes/SSD1/Code/RPClient`.

---

## 1. What's settled

### 1.1 Research

Citation-grounded prior-art research landed in [`LOOM_RESEARCH.md`](LOOM_RESEARCH.md). Source dates: 2026-05-10. Findings cluster into:

- **Sudowrite** — gold-standard commercial AI fiction; Story Bible schema (Braindump → Synopsis → Genre/Style → Characters → Worldbuilding → Outline → Scenes); 20k-word recent-prose context window; History chiclets transparency.
- **Novelcrafter** — deeper Codex; alias-driven prompt-function injection; BYOK; steeper onramp.
- **NovelAI / KoboldAI / SillyTavern** — Memory + Author's Note + Lorebook trichotomy; constant / keyed / vectorised activation modes; A/N depth-strength.
- **Plottr** — gold-standard 2D Timeline × Plotline grid (no AI); 40+ structure templates.
- **Scrivener** — Binder, Corkboard, Inspector, Snapshots, Compile.
- **Obsidian Longform** — scene-as-markdown-file pattern (Loom adopts).
- **AI Dungeon** — anti-pattern: server-side filtering, manual privacy review.
- **Local-model culture** — Qwen 2.5 72B + Magnum/EVA dethroned Llama 3.1; Mistral Nemo 12B is the laptop sweet spot; sampler stack `DRY → top_n_sigma → top_k → typ_p → top_p → min_p → XTC → temperature`.
- **Long-context engineering** — Wu et al. 2021 recursive summarisation; Re3 / DOC for state tracking; LlamaIndex Tree + Document Summary indices.

The research found no widely-adopted stylistic embedding model — Loom's Phase 5 sits in genuine R&D territory.

### 1.2 Design docs — landed

| Doc | What it specifies |
|---|---|
| [`LOOM_RESEARCH.md`](LOOM_RESEARCH.md) | Prior-art synthesis. Source of truth for every later citation. |
| [`LOOM_PLAN.md`](LOOM_PLAN.md) | Master plan, mirrors RPClient `V2_PLAN.md` shape. Inventory + phasing. |
| [`LOOM_MEMORY.md`](LOOM_MEMORY.md) | **Memory architecture deep-dive (added 2026-05-10 PM).** Inherits RPClient's six-layer memory + precedence contract; extends with three subagent-research findings (Sudowrite/Novelcrafter long-form, AI Dungeon/NovelAI/character.ai/ChatGPT+Claude, academic frameworks: MemGPT, RAPTOR, GraphRAG, HippoRAG, LightRAG, SCORE, ConStory, DOC, StoryWriter, NexusSum). Concrete 32k-context prompt skeleton; explicit eviction order; honest unproven caveats. |
| [`LOOM_DESIGN_LANGUAGE.md`](LOOM_DESIGN_LANGUAGE.md) | §1–§13: RPClient V2 Design Language verbatim. §14+: Loom-specific surfaces (window anatomy, Binder, editor pane, Inspector, generation tray, History chiclets, empty states, Loom-specific keyboard shortcuts). |
| [`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md) | Project / Part / Chapter / Scene / Beat shapes. Bible (Character, Setting, Object, Faction, Timeline, Lorebook, Style). Knowledge ledger schema. Generation log schema. On-disk format. |
| [`LOOM_GENERATION_MODES.md`](LOOM_GENERATION_MODES.md) | Per-mode prompt templates (Continue, Expand, Rewrite[voice/tense/POV/length], Show-don't-tell, Brainstorm, Critique, Bridge, Describe, Name suggest). Token-budget allocation at 8k/16k/32k. Knowledge-ledger context layer. |
| [`LOOM_STORY_BIBLE.md`](LOOM_STORY_BIBLE.md) | Authoring model, knowledge-ledger pipeline (Re3 Edit pattern[L4] extended to per-scene granularity), lorebook activation modes, Memory + A/N posture, validation lints. |
| [`LOOM_PHASE1_EDITOR_MVP.md`](LOOM_PHASE1_EDITOR_MVP.md) | 13 sub-step contracts (1.a–1.m), each with tasks, tests, definition-of-done. ~9.5 days serial. |
| [`LOOM_FANFIC.md`](LOOM_FANFIC.md) | **Fanfic Mode (added 2026-05-10).** Project type for fan-fiction; AO3 tag taxonomy as schema; Ship/AU/Trope as first-class data; ATTG (NovelAI Erato) system-prompt header; bundled trope library + fandom-template bundles; Slow Burn pacing assistant; fanfic-specific generation modes (Trope Insert, Ship Dynamic Shift, Canon Check, Tag Suggest). User-paste canon ingestion only — no AO3 scraping, per the disabled-dataset precedent. Phase 5.b/5.c. |
| [`LOOM_NSFW.md`](LOOM_NSFW.md) | **Heavy-NSFW + extreme-topics posture (added 2026-05-10).** Loom is plumbing; the model handles content. No moderation, no safety theatre, no refusal modals. Recommended models (abliterated Gemma 4 family + Midnight Miqu 70B), sampler defaults (Min-P + DRY + XTC), bracketed Author's Note convention, sphiratrioth lorebook-as-active-scenario for positive-bias countering, refusal-as-signal-not-block, transparency contract. **§3 (added 2026-05-10 evening): "Erotica / porn as a first-class writing direction"** — `WritingDirection` schema (kind: literary/mainstream/romance/erotica/porn + vocabulary register + explicitness level + themes + pacing + FTB policy); explicit-foreground generation behaviour when `.porn` is active (depth-2 Author's Note, longer Continue defaults, no scene-break suggestion); extreme-content support via abliterated-model recommendations + sphiratrioth positive-bias counters. |
| [`LOOM_UI_RESEARCH.md`](LOOM_UI_RESEARCH.md) | **UI research pass (added 2026-05-10).** Mirrors RPClient's `V2_PHASE11_UI_RESEARCH.md` shape but for fiction tools. Live Chrome-MCP capture of Sudowrite (sudowrite.com landing + docs) and Novelcrafter (features + Codex), prior-WebFetch fallback for tools blocked at MCP allowlist (NovelAI, Plottr, Scrivener, etc.). Captures inline-floating-action-bar-on-selection (Sudowrite + Novelcrafter both), pink-tinted AI-prose blocks (Sudowrite), History panel structure (Sudowrite), list-detail two-pane Codex with per-entity tabs + mention-frequency sparkline + inline-link hover-card-preview (Novelcrafter), pill-picker POV/Tense/Direction (Novelcrafter), Marker Timeline (Novelcrafter), Focus Mode (universal). Verdict per pattern (STEAL/ADAPT/INVERSE/IGNORE). Cross-app pattern table (10 questions). Drives concrete updates to LOOM_DESIGN_LANGUAGE.md §14. |

### 1.3 Key design decisions locked

- **Local kobold backend, no cloud, no filtering.** Direct reuse of RPClient's `KoboldClient`, `ServerProbe`, `KoboldClientRegistry`, `DebugLog`, `Storage` patterns.
- **Long-form editor surface — not chat.** No `Turn` / `Cast` / `Director` / `speakerId` carryover. Loom's `PromptBuilder` is a new module, not a port.
- **Scene-as-markdown-file on disk** (Obsidian Longform[J5] pattern). Round-trip-safe YAML frontmatter. Bible entries as JSON.
- **History chiclets visible from Phase 1.** Sets the transparency contract from day one — no later-phase regression.
- **Memory + Author's Note + Lorebook trichotomy** carried verbatim from NovelAI/KoboldAI/SillyTavern (research §M.4).
- **Knowledge ledger per character per scene** with explicit unknowns and mistaken beliefs — Loom's distinctive engineering. Schema in Phase 1; UI in Phase 4.
- **Sampler config visible and editable** — Min-P / DRY / XTC defaults per research §I.3.
- **Instruct template respects model card**, not Loom default. `auto`-probe with manual override.
- **No content moderation in Loom — ever.** Refusal-detection is a signal, not a block.
- **TestKit, not XCTest.** Pure-data helpers tests-first; UI/glue layers honest smoke. Mirrors RPClient TDD posture.
- **Memory architecture: eight-layer hybrid** ([`LOOM_MEMORY.md`](LOOM_MEMORY.md)). Inherits RPClient's six-layer model + precedence contract + path A-F empirical fixes; adds Bible-keyed and Knowledge-ledger layers Loom-specific. Cache boundary contract enforced from sub-step 1.i. Recommended hybrid (LightRAG-incremental graph + DOC outline-metadata-as-state + SCORE state-tracker + RAPTOR-style scene tree) sits as the Phase 4-5 target. Phase 1 ships the cache contract + recent prose + always-include bible + Author's Note layers only.
- **Pinned spans** (character.ai pattern, [`LOOM_MEMORY.md`](LOOM_MEMORY.md) §A2.3): user can pin raw paragraphs that never evict. Phase 2 candidate; cheap.
- **Bracketed `[...]` Author's Note** convention from AI Dungeon ([`LOOM_MEMORY.md`](LOOM_MEMORY.md) §A2.2): exploits web-fiction prior in local models. Phase 1 default framing.
- **Eviction-order surfacing in History tab** ([`LOOM_MEMORY.md`](LOOM_MEMORY.md) §A2.7): when budget pressure forces evictions, show what got cut and in what order. Phase 1 if cheap, Phase 2 floor.

### 1.4 PLAN.md superseded

`PLAN.md` retained with a header noting `LOOM_PLAN.md` supersedes it. Not deleted.

---

## 2. What's still open

### 2.1 Open within the design

These were noted in the design docs as deferred-decisions, not regressions:

- **Variant scenes / multi-draft representation.** Lean on Snapshots (Scrivener pattern); verify in Phase 2.
- **Project window vs document-based architecture.** Decision: single-window with explicit project switcher for Phase 1.
- **Markdown rendering inside the editor** (off by default in Phase 1). Phase 2+ adds a Preview toggle.
- **Corkboard view** position (replace editor pane, or tab beside?). Phase 3 question.
- **Style ingestion UI shape.** Phase 5 question; depends on what the empirical pipeline can deliver.
- **Cross-character ledger contradiction detection.** Lint-only posture committed; auto-resolution rejected.
- **Time travel / non-linear narrative**: ledger queries use *chronological* order, not *narrative* order. Verify against a flashback-heavy manuscript in Phase 4.
- **History log file proliferation.** Compaction is Phase 6 polish; Phase 1 is fine accumulating per-event files.
- **Roll Rewrite forward into Phase 1.5.** Continue + Expand are the Phase 1 minimum, but Rewrite is the most-used mode in every prior-art tool — selecting prose and reshaping it (voice / tense / POV / length / "make it more dramatic") is the dominant fiction-tool interaction beyond first-draft generation. After Phase 1 ships, before committing to the full Phase 4 mode bundle, consider landing Rewrite alone as 1.5 to validate the mode-button + sub-mode interaction surface. Cheap to implement on top of PromptBuilder; high user-value gradient.
- **Per-call instruction box on Continue / Expand / Rewrite.** Phase 1 carries persistent steering only (Memory + Author's Note). Sudowrite + Novelcrafter both have a "with this instruction:" text field that attaches a one-shot ad-hoc steering hint to a single mode call without polluting the persistent steering surfaces. Phase 4 (when Rewrite/Brainstorm/Critique land) is the natural moment to add this — those modes are meaningless without it, and the hint surface generalises back to Continue + Expand once it exists. Track as a Phase 4 prerequisite, not a Phase 1 add.

### 2.2 Open for the engineer-in-Phase-1

These need an answer before / during sub-step execution:

- **NSTextView vs TextKit 2.** Phase 1 follows RPClient (TextKit 1 / NSTextView default). Revisit if styling complexity demands TextKit 2 in Phase 5.
- **Verify RPClient's `KoboldClient` supports a single-prompt completion shape** (not the chat-shaped `messages` array). If not, sub-step 1.c needs a small adapter.
- **macOS 26 NSTextView reflow under Liquid Glass + width constraints.** Pre-test before assuming RPClient's TextKit usage transfers cleanly to a long-form editor (RPClient's text views are bounded 500-1500 chars; Loom's are 2000+ words).
- **Acceptance overlay layered over NSTextView.** Floating views over text views can be finicky on macOS — clipping, scroll-following. Plan for an iteration.

### 2.3 Open for the tooling

- **Git remote not configured.** Repo is local-only on `main`. Setting up an origin (likely a private GitHub or GitLab) is an explicit user decision; flagged here so the engineer doesn't assume it. The user will configure when ready.
- **Worktrees / branches**: per the inherited RPClient posture, GitLab-style branching (no worktrees). Phase 1 can land directly on `main` since there's no concurrent work; subsequent phases should use feature branches.

---

## 3. Phase 1 sub-step ordering and dependencies

From [`LOOM_PHASE1_EDITOR_MVP.md`](LOOM_PHASE1_EDITOR_MVP.md) §3, with dependency arrows:

```
1.a (bootstrap) ──┬─→ 1.b (storage + Codable) ──┬─→ 1.f (editor)
                  │                              ├─→ 1.g (inspector)
                  │                              └─→ 1.i (PromptBuilder + Continue)
                  │
                  └─→ 1.c (Kobold carryover) ───→ 1.i

1.d (DesignTokens + window) ─→ 1.e (sidebar) ─→ 1.f / 1.g

1.i (Continue) ──→ 1.j (Expand + acceptance) ──→ 1.k (History inspector) ──→ 1.l (export) ──→ 1.m (smoke)

1.h (generation tray) sits alongside 1.f/1.g; depends on 1.b.
```

**Critical path:** 1.a → 1.b → 1.c → 1.i → 1.j → 1.m. Roughly 6 days of serial work.

**Parallelisable** (with the right buffer):
- 1.d / 1.e / 1.f / 1.g can be interleaved once 1.b lands.
- 1.h can run alongside 1.f/1.g.
- 1.l / 1.m only need 1.j to be functional.

**Estimated total**: 9.5 days serial, ~7 days with parallelisation.

---

## 4. Where research materially changed the strawman

Original PLAN.md had a phasing strawman; research moved a few things:

- **History chiclets** moved into Phase 1 (was implicit / Phase 2+). Sudowrite's transparency precedent is strong enough that this should be the floor from day one.
- **Author's Note + Memory** confirmed as Phase 1 (was undefined). NovelAI/KoboldAI convergence makes this a "table stakes" feature, not a Phase 2+ add.
- **Knowledge ledger schema** lands in Phase 1 (was implicit Phase 4 only). Lazy-versioning posture: schema is additive; encoding into `Character` even if no data is written until Phase 4 is cheap and avoids a non-additive migration later.
- **Per-scene metadata** (POV, time, location, conflict, outcome) — yWriter[J7] schema adopted. Original PLAN.md was vague ("scene metadata"). Now explicit.
- **Sampler config** elevated to user-visible. Research §I.3 makes clear that NSFW fiction at the local-model tier *requires* user-tunable Min-P / DRY / XTC, not invisible defaults. Phase 1 settings exposes these.
- **Bible content as Phase 2** (was original) confirmed; Bible auto-fill (Sudowrite[A2] per-field-Generate) reframed as Phase 2.5 — after the core Bible UI works, AI-assist gets the same treatment as RPClient §5.4.
- **No subagent parallelism in Phase 0.** Research planned to run as 5 parallel subagents; subagents lacked web access in the sandbox. Single-context research executed instead. Findings unaffected; methodology noted in [`LOOM_RESEARCH.md`](LOOM_RESEARCH.md) §Q.

Things that *didn't* change from the strawman:

- Phase ordering (1 → 2 → 3 → 4 → 5 → 6).
- Single-user, no collab, no cloud, no TTS — confirmed and reinforced by research §F (AI Dungeon anti-pattern).
- "Scrivener with AI grafted in" north-star metaphor.
- Reuse of RPClient's kobold backend, embeddings, settings, TestKit.

---

## 5. Repo state at handoff

```
/Volumes/SSD1/Code/FictionWriter/
├── .claude/                          # session metadata
├── .git/                             # repo (main branch only, local-only, no remote)
├── HANDOFF.md                        # this file
├── LOOM_DATA_MODEL.md
├── LOOM_DESIGN_LANGUAGE.md
├── LOOM_GENERATION_MODES.md
├── LOOM_PHASE1_EDITOR_MVP.md
├── LOOM_PLAN.md
├── LOOM_RESEARCH.md
├── LOOM_STORY_BIBLE.md
└── PLAN.md                           # original meta-plan, header notes supersession
```

No code yet. Phase 1 implementation begins with sub-step 1.a (bootstrap).

---

## 6. Recommended Phase 1 entry checklist (for the next context)

1. Open [`LOOM_PHASE1_EDITOR_MVP.md`](LOOM_PHASE1_EDITOR_MVP.md). Read §1 (definition of done) and §3 (sub-step staging).
2. Skim [`LOOM_RESEARCH.md`](LOOM_RESEARCH.md) §N (load-bearing) and §O (gaps) — these inform quality-vs-completion calls during implementation.
3. Skim [`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md) §1 (Project), §2 (Manuscript), §3.1 (Character), §6 (generation log) — what 1.b + 1.i need to encode.
4. Skim [`LOOM_GENERATION_MODES.md`](LOOM_GENERATION_MODES.md) §1 (common assembly), §2 (Continue), §3 (Expand) — what 1.i + 1.j need to implement.
5. Skim [`LOOM_DESIGN_LANGUAGE.md`](LOOM_DESIGN_LANGUAGE.md) §14 (Loom-specific surfaces) — what 1.d through 1.l need to render.
6. Open `/Volumes/SSD1/Code/RPClient/` for direct-reuse files (KoboldClient, ServerProbe, DebugLog, Storage, DesignTokens). Inspect not in detail — they're inheritances.
7. Begin sub-step 1.a.

Estimated time-to-first-launch (`./run.sh` opens a window): half a day.

Estimated time-to-demo (the §1 definition of done): ~9 days of focused implementation work.

---

## 7. Memory bootstrapping

Several RPClient memory entries inform Loom's posture; they're catalogued so a subsequent context can find them quickly:

- `feedback_test_framework` — TestKit, not XCTest.
- `feedback_tdd_workflow` — pure-data tests-first; UI/glue smoke.
- `feedback_diagnostic_logging` — `[subsystem]`-prefixed `DebugLog.shared.write` from day 1.
- `feedback_postprocessing_minimalism` — strip whitespace and `<think>`, not much else.
- `feedback_quirk_detectors` — refusal patterns surface as signals, not retries.

These live in RPClient's memory; Loom's first context should re-state them as needed.

---

## 8. References

**This handoff:**
- All seven design docs cited above.
- [`PLAN.md`](PLAN.md) — historical scaffolding.

**RPClient (read-only inheritance):**
- `/Volumes/SSD1/Code/RPClient/V2_DESIGN_LANGUAGE.md` — design language source.
- `/Volumes/SSD1/Code/RPClient/V2_PLAN.md` — plan-shape precedent.
- `/Volumes/SSD1/Code/RPClient/V2_UI_OVERHAUL.md` §4.11 — sub-step format precedent.
- `/Volumes/SSD1/Code/RPClient/Sources/RPClientCore/` — direct-reuse files (KoboldClient, ServerProbe, KoboldClientRegistry, DebugLog, Storage).
- `/Volumes/SSD1/Code/RPClient/build.sh`, `/Volumes/SSD1/Code/RPClient/run.sh` — sed-and-adapt scripts.

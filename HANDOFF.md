# Loom — Handoff

> **Date:** 2026-05-11 (updated PM). **Status: Phase 1 + Phase 1.5 + Phase 2 complete.** 403 tests passing. Branch `main` ahead of origin (Phase 2 + §9.2 gaps pushed). Editor MVP shipped (Continue/Expand/Rewrite, acceptance window, History inspector, Markdown export); Phase 1.5 layered on Rewrite, per-call instruction box, Author's Note depth-N injection, Cmd-, Settings window. **Phase 2 ships Story Bible v1 — see §11 below for the ship state.** Next: **Phase 3 — Manuscript hierarchy + Plan view**. See **§9 (Phase 2 ship state)** below.
>
> **Repo**: `/Volumes/SSD1/Code/FictionWriter` · pushed to [github.com/apothis/FictionWriter](https://github.com/apothis/FictionWriter) · branch `main`. RPClient (the source of inherited plumbing) at `/Volumes/SSD1/Code/RPClient`.
>
> The original Phase 0 handoff (§§1-8 below) remains as historical reference. The post-Phase-1 additions are in §§9-10.

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
- ✅ **Roll Rewrite forward into Phase 1.5.** SHIPPED 2026-05-10. `.rewrite` mode wired through `GenerationModeAvailability` + `PromptBuilder` + tray. Same selection-replace mechanics as Expand; both Keep & Redo and Reject restore the original passage on cancel.
- ✅ **Per-call instruction box on Continue / Expand / Rewrite.** SHIPPED 2026-05-10. Single-line field in the tray; layered just above the mode-instruction in the prompt so it sits in the recency-strong slot without overriding the mode framing. Cleared on cycle end (accept/reject/implicit-accept), replayed on Keep & Redo.
- ✅ **Author's Note depth-N injection within the prefill.** SHIPPED 2026-05-10. New `AuthorsNoteInjector` splices the AN inline into the recent-prose layer N lines back from the cursor (NovelAI A/N convention). `Project.settings.authorsNoteDepthLines` defaults to 4. Standalone-AN-layer fallback kicks in when depthLines=0 or no recent prose.
- **AppKit vs WKWebView frontend reassess at Phase 3.** The current native AppKit stack is structurally correct for Phase 1-2 (NSTextView is the centerpiece; macOS-native polish; local-first / local-model alignment; 228 tests survive a future pivot since they're all on the model layer). The pivot question is genuinely worth re-asking at Phase 3 when Corkboard / Plan-view card-grid surfaces land — that's where AppKit gets verbose vs CSS-grid + dnd-kit. Run a 1-2 day NSCollectionView spike on the Plan-view layout (per [`LOOM_UI_RESEARCH.md`](LOOM_UI_RESEARCH.md) §B.2.16) when Phase 3 begins. If the spike fights the framework, that's the moment to pivot — the model layer (ProjectStorage, KoboldClient, PromptBuilder, GenerationCoordinator) is decoupled enough that a UI-only rewrite to a Tauri-shaped Swift+webview architecture is the cheapest possible pivot path. **Bumped: the Phase 1.5 session burned ~3 hours on AppKit/macOS 26 quirks (NSSegmentedControl action dispatch, `.fullSizeContentView` titlebar-drag hijacking inspector tab clicks, `NSTitlebarAccessoryViewController` triggering window auto-refit-to-104pt on attach, `.cgColor` capture not tracking appearance changes). All survivable for Phase 2, but a real signal that Phase 3 reassess matters.**
- **Floating acceptance overlay revisit.** ATTEMPTED 2026-05-10 via `NSTitlebarAccessoryViewController`; reverted to merged-tray (Accept/Reject/Keep&Redo swap into the editing-button slot when generation finishes). The titlebar-accessory approach kept fighting AppKit's macOS 26 auto-refit on attach — `minSize` was ignored, post-attach `setFrame` lost a snap-back fight. Re-revisit as Phase 2/3 polish once macOS 26's titlebar machinery is better understood or after a frontend pivot.
- **Character UX: visual save confirmation.** Background-task chip; `SaveIndicator` class added to InspectorController. Verify it's actually wired into the per-character/Notes writeback paths and behaves correctly when the user types rapidly.

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

---

## 11. Phase 2 ship state (added 2026-05-11 PM)

All 11 Phase 2 work items + 4 of 5 §9.2 gaps shipped TDD-first.
Tests: 228 → 403 (175 new). All commits pushed to origin/main.

### 11.1 What landed

| # | Item | Commit |
|---|------|--------|
| 1 | `WritingDirection` schema on `ProjectSettings` | `e3890bb` |
| 2 | `FanficMetadata` schema on `Project` | `c4e1a3f` |
| 3 | `Character.canonBrief` + `customFields` | `b84eba5` |
| 5 | `Setting` + `BibleObject` entities | `ea2c40a` |
| 4 (data) | `BibleInspectorViewModel` + Setting/Object CRUD | `a26d137` |
| 4 (UI) | List-detail two-pane Bible inspector | `982bffd` |
| 6 | Project Settings narrative-style pill-pickers | `af68061` |
| 7 | Bible-Keyed injection + per-entity Constant/Keyed pill | `9d043b0` |
| 8 | Lorebook entries (constant + keyed; group/weight/sticky) | `2bb4286` |
| 9 | Snapshots before AI rewrite | `4fc50d7` |
| 10 | @-mention autocomplete data + editor integration | `7e86939` |
| 11 | Mention index + per-entity mention caption | `8ae8a58` |
| §9.2 | editorMaxWidth doc drift fix | `<followon>` |
| §9.2 | ⌘⇧R Keep & Redo binding | `<followon>` |
| §9.2 | Esc / ⌘. cancel-mid-stream | `<followon>` |
| §9.2 | Auto-probe on server add | `<followon>` |

### 11.2 §9.4 risk #1 contract (forward-load) — met

Every schema migration includes a hand-rolled JSON test that simulates a Phase-1 bundle on disk and asserts the new field decodes to its default. The lazy-versioning posture is enforced at the suite level, not by inspection.

### 11.3 Deferred to Phase 2.5 / Phase 3 polish (called out in commit messages)

- **Bible inspector per-entity sub-tabs** (Knowledge ledger / Relationships / Mentions / Notes per §14.5.1). Most need Phase 4 data; Notes maps to Description today.
- **Lorebook editing UI** — Phase 4 Sphiratrioth surface; schema + plumbing shipped.
- **@-mention popover view** (NSPanel + NSTableView). `currentMentionContext()` / `applyMention(_:)` are wired; popover shell is the build-on-top.
- **Hover-preview popover** for resolved entity links in prose — §14.5.1 polish.
- **Mention sparkline bar with marker dots** — `perSceneByEntityId` data shipped; minimum-viable is the "N mentions" caption.
- **Inline floating selection toolbar** (§9.2) — heavy AppKit, deferred. No Phase-2 contract relies on it.
- **Live-app eyeball verification** on the new Bible inspector layout. Mount smoke is green; §9.4 fragility risk means a manual pass is still warranted.

### 11.4 What surfaced during Phase 2 — carried into Phase 3 planning

- The viewmodel split (`BibleInspectorViewModel` is pure-data; `BibleInspectorViewController` is the rendering + event-routing layer) is the right shape for the Plan-view + Corkboard Phase 3 surfaces.
- The §9.4 "list-detail Bible inspector is structurally similar to the existing inspector pane (a known-fragile area)" risk landed mostly clean — the structural change required one re-application of the class-declaration line during the rewrite, but no NSSegmentedControl-tier surprises. Verdict: the AppKit reassess can wait until Plan view (Corkboard) lands, when NSCollectionView's quirks are the live concern.
- `WholeWordMatcher` is the shared regex-word-boundary matcher for #7 + #8. Reusing it for Phase 4's knowledge-ledger extraction is the natural next call.

---

## 9. Phase 2 plan (Story Bible v1)

> **Added 2026-05-11.** Phase 2 is the **consistency engine** — Bible injection + keyed activation. Without it, Phase 3's scene-tree just multiplies content-quality problems. Bible-first ordering matches Sudowrite's evolution and Novelcrafter's design priority (per [`LOOM_UI_RESEARCH.md`](LOOM_UI_RESEARCH.md) live-capture findings).
>
> Fanfic + NSFW schemas land **now**, even though their UI/experience defers to Phases 4-5. Doing the schema migration once (when every Phase 2 item touches `Project.settings` anyway) avoids a painful repaint later. See [`LOOM_FANFIC.md`](LOOM_FANFIC.md) and [`LOOM_NSFW.md`](LOOM_NSFW.md) for the field-level requirements.

### 9.1 Work-item order (TDD-shaped)

| # | Item | Why now |
|---|------|---------|
| 1 | **`Project.kind`** (`originalFiction` / `fanfic`) + **`WritingDirection`** schema (`kind`, `register`, `explicitnessLevel`, `themes[]`, `pacing`, `fadeToBlackPolicy`) on `Project.settings` | Single migration. Every Phase 2 item touches `Project.settings`; do the schema once. |
| 2 | **`FanficMetadata`** struct (fandoms, ATTG header, ratings, warnings, ships, tropes, AUs) — populated only when `kind == .fanfic`; nil otherwise. Placeholder UUIDs for ships/tropes/aus collections. | Fanfic UI to populate this is Phase 5.b-c; the *schema* lands now so existing projects load forward cleanly. |
| 3 | Full **Character schema** (role, aliases, traits, speech, relationships, knowledge, notes, **`canonBrief: String?`**, **`customFields: [Field]`**) replacing today's `{name, description}` minimum. `description` survives as the long-form-notes free-form field. | Foundation for #4 + everything downstream. `customFields` is what lets Phase 5 fandom templates (HP `house`, MCU `team`) extend the entity without further schema migration. |
| 4 | **List-detail Bible inspector** (per [`LOOM_DESIGN_LANGUAGE.md`](LOOM_DESIGN_LANGUAGE.md) §14.5.1) replacing today's flat always-expanded stack. Left 40% category sections + filter tabs; right 60% selected entity detail with sub-tabs (Description / Knowledge ledger / Relationships / Mentions / Notes). | UI for #3. |
| 5 | **Setting + Object** entities (same shape as Character) | Schema reuses #3's pattern; small marginal cost. |
| 6 | **Project Settings pill-pickers** (POV / Tense / Direction / Vocabulary / Explicitness) wired to `WritingDirection` from #1 | Cross-cuts NSFW + original-fiction; the surface itself is shared. |
| 7 | **Bible-Keyed injection** mode (alias-keyword triggers) + per-kind constant/keyed pill | The actual consistency win — model finally sees relevant Bible entries when prose mentions them. |
| 8 | **Lorebook entries** (constant + keyed). Schema requires `group`, `weight`, `sticky` fields for the Phase 4 Sphiratrioth pattern (NSFW positive-bias counters + fanfic thematic consistency). | Reuses #7 plumbing. |
| 9 | **Snapshots** before AI rewrite (Scrivener pattern). `.loom/snapshots/<timestamp>.json` per-snapshot (matches generation-log file shape). | Insurance once Bible-edit + Direction-edit traffic ramps. |
| 10 | **`@name` autocomplete** + inline entity references in prose (Novelcrafter `{{character.name}}` grammar adapted). Hover preview popover with avatar + role + 200-char excerpt + Open / Inspector buttons. | Polish on stable schema. |
| 11 | **Mention sparkline** per entity (thin bar with marker dots at scenes; click marker → editor scrolls to scene) | Polish on inspector. |

### 9.2 Phase 1 gaps surfaced during 1.5 (rolled into Phase 2 or earlier)

These are Phase 1 contract items that didn't actually ship and turned up during live use:

- **Inline floating selection toolbar** ([`LOOM_DESIGN_LANGUAGE.md`](LOOM_DESIGN_LANGUAGE.md) §14.4.1) — formatting buttons (B/I/U/S/Highlight/Quote/Heading/List) above the active selection. Phase 1 contract; not built. AI mode buttons in the toolbar are still Phase 4.
- **`Cmd-⇧-R`** keyboard binding for Keep & Redo — the tray label promises it but no actual binding.
- **Cancel generation mid-stream** — today you have to let it finish then Reject. Real workflow annoyance; small Phase 1 gap.
- **Auto-probe on server add** — adding a new server profile in Settings doesn't probe it; capabilities only populate after the first generation.
- **HANDOFF / Phase 1 docs reference 720pt `editorMaxWidth`** but the actual value is now 1080pt (bumped during 1.5 live testing). Just doc drift.

### 9.3 Cross-cutting design commitments locked in by Phase 2

These don't ship code in Phase 2 but the schema landed in #1-#3 must support them without further migration:

- **ATTG header structure** (NovelAI Erato pattern, per [`LOOM_FANFIC.md`](LOOM_FANFIC.md)) — Phase 1 cache-boundary already places it correctly above the system prompt; just need `FanficMetadata` to carry it.
- **Refusal detection** stays a Phase 1 *signal* (yellow chip in History, no auto-retry); Phase 4's "Continue from refusal" action depends on this surface being stable.
- **`WritingDirection.kind == .porn`** triggers explicit Phase 2 behaviour (depth-2 Author's Note, longer Continue defaults, no scene-break suggestion). Not all of that is built in Phase 2 but the schema needs to distinguish the case.
- **Knowledge ledger schema** on Character (`knowledge: [LedgerEntry]`) lands in #3 even though Phase 4 owns the extractor + UI. Per `LOOM_DATA_MODEL.md` §3.1's "additive schema, encode early" posture.

### 9.4 Risks before #1 starts

- **Project schema migration.** Existing `.loom` project bundles need to load cleanly. Default `kind = .originalFiction`, default `writingDirection = .literary/.literary/.fadeToBlack`. Tests should explicitly load a Phase-1 project bundle and assert defaults populate.
- **`customFields` on Character.** Keep this minimal (label + value + kind enum). Avoid "schema for the schema" complexity — Phase 5 templates need a place to add fandom-specific fields, not a generic ORM.
- **The Phase 1.5 session burned ~3 hours on AppKit/macOS 26 layout quirks.** Phase 2's list-detail Bible inspector is structurally similar to the existing inspector pane (a known-fragile area). Budget time for layout surprises; the Phase 3 frontend-reassess gate matters more after this session.

---

## 10. Phase 2 entry checklist (for the next context)

1. Read this handoff **§9** (the Phase 2 plan) first.
2. Skim [`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md) §3 (Bible — entity model) — schema source of truth for #3.
3. Skim [`LOOM_FANFIC.md`](LOOM_FANFIC.md) §1-3 and [`LOOM_NSFW.md`](LOOM_NSFW.md) §3 — what `Project.kind` + `WritingDirection` + `FanficMetadata` need to carry. Phase 2 ships the schema; Phase 4-5 ships the experience.
4. Skim [`LOOM_DESIGN_LANGUAGE.md`](LOOM_DESIGN_LANGUAGE.md) §14.5.1 (Bible inspector list-detail two-pane) — UI grammar for #4.
5. Read this handoff **§9.4** (risks) before opening Xcode.
6. TDD posture stays: pure-data tests-first (red → green → commit), UI/glue honest smoke. The Phase 1.5 session drifted into test-after for a few items; correct course early.
7. Repo state on entry:
   - Branch `main`, 27 commits ahead of origin (pushed).
   - 228 tests passing.
   - `./build.sh` builds `Loom.app`; run with `./Loom.app/Contents/MacOS/Loom` (NOT `./run.sh` — it blocks).
   - Live server at `http://192.168.1.201:5001` with Qwen3.6-27B; defaultServerId is in `~/Library/Application Support/Loom/settings.json`.
   - Settings window: `Cmd-,` (or *Loom → Settings…*). Has working Servers + Project tabs.
8. Begin Phase 2 #1 (Project schema migration + tests).

Estimated time-to-end-of-Phase-2: 3-5 days of focused work. Phase 2 #1-#3 land first; everything else parallelises on top.

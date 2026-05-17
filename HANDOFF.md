# Loom — Handoff

> **Date:** 2026-05-11 (updated evening). **Status: Phase 1 + 1.5 + 2 + 2.5 + 3 §A–§F complete; Phase 4 in flight, ledger spike landed.** **530 tests passing**, all green; app builds clean. Branch `main` through `e153e4f`. Phase 1 + 1.5 = Editor MVP (Continue/Expand/Rewrite, acceptance window, History inspector, Markdown export, per-call instruction box, A/N depth-N, Cmd-, Settings). Phase 2 = Story Bible v1 (WritingDirection / FanficMetadata / Bible-Keyed injection / Lorebook / snapshots-before-rewrite / @-mention / sparkline). Phase 2.5 = the @-popover UI + mention sparkline-bar + hover-preview popover that completed the Phase 2 #10–#11 affordances. Phase 3 = Manuscript hierarchy (Part > Chapter > Scene) + Plan view (NSCollectionView card grid in a standalone window) + target word counts. **Phase 4 shipped slices (NSFW-anchored)**: rewriteVoice prompt layer (§14.1 #1), Continue-from-refusal (§14.1 #7), Sphiratrioth starter pack + Roll-Outcome action (§14.1 #8), knowledge-ledger feasibility spike across 5 rounds — Phase 4 #7 pipeline is unblocked with `gemma4_2b` on Ollama chosen as the production extractor (see `LOOM_LEDGER_SPIKE.md`). See **§11 (Phase 2)**, **§12 (Phase 2.5)**, **§13 (Phase 3)**, **§15 (Phase 4)** below.
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
- **AppKit vs WKWebView frontend reassess at Phase 3.** The current native AppKit stack is structurally correct for Phase 1-2 (NSTextView is the centerpiece; macOS-native polish; local-first / local-model alignment; 228 tests survive a future pivot since they're all on the model layer). The pivot question is genuinely worth re-asking at Phase 3 when Corkboard / Plan-view card-grid surfaces land — that's where AppKit gets verbose vs CSS-grid + dnd-kit. Run a 1-2 day NSCollectionView spike on the Plan-view layout (per [`LOOM_UI_RESEARCH.md`](LOOM_UI_RESEARCH.md) §B.2.16) when Phase 3 begins. If the spike fights the framework, that's the moment to pivot — the model layer (ProjectStorage, KoboldClient, PromptBuilder, GenerationCoordinator) is decoupled enough that a UI-only rewrite to a Tauri-shaped Swift+webview architecture is the cheapest possible pivot path. **Cost ledger (the user is tracking this; they have a finite tolerance):** Phase 1.5 = ~3 hours on AppKit/macOS-26 quirks (NSSegmentedControl action dispatch, `.fullSizeContentView` titlebar-drag hijacking inspector tab clicks, `NSTitlebarAccessoryViewController` triggering window auto-refit-to-104pt on attach, `.cgColor` capture not tracking appearance changes). Phase 4 2026-05-11 = **~1h+ on the inspector tab-row + filter-strip vertical-ballooning bug compounded by macOS-26's auto-refit-to-fittingSize cascade**, which snapped the window from 720pt to 127pt on every layout pass and ignored both `minSize` and `contentMinSize`. Worked around in commits `e598ce6` + `9d90635` with a `.required` 400pt min-height on the bible list scroll view to push `fittingSize` past the window-shrink threshold — brittle (raises the effective window-height minimum to ~550pt and depends on AppKit honouring required constraints over its cascade). Phase 3's NSCollectionView spike landed favourably for AppKit, but the verdict is not permanent — each new incident raises the case for revisiting.
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

---

## 12. Phase 2.5 polish ship state (added 2026-05-11 late PM)

After Phase 2 schema + plumbing landed, three polish items completed the user-visible affordances the Phase 2 work items promised. All TDD-first.

| Item | Commit |
|------|--------|
| @-mention popover UI (NSPanel + NSTableView; arrow/Enter/Tab/Esc navigation; positions below the cursor's glyph rect) | `7528f88` |
| Mention sparkline bar with marker dots (replaces the "N mentions" text caption; click a marker → `session.selectScene(id:)`) | `ceb35ad` |
| Entity-link hover-preview popover (mouseMoved → glyph → character → reference → resolver card with name + role + 200-char excerpt) | `b0e38f9` |

Also closed-out **HANDOFF §9.2 Phase 1 gaps** as part of this batch:

| Item | Commit |
|------|--------|
| editorMaxWidth doc drift (720pt → 1080pt) | `3b06966` |
| ⌘⇧R Keep & Redo keyboard binding | `3b06966` |
| Esc / ⌘. cancel generation mid-stream | `3b06966` |
| Auto-probe on server add (async + AutoProbe.applyResult) | `3b06966` |

Phase 2.5 deferrals (carried into Phase 3 / Phase 4 polish):
- Lorebook editing UI — Phase 4 Sphiratrioth territory; data + plumbing already in place.
- Per-entity inspector sub-tabs (Knowledge ledger / Relationships / Mentions / Notes per §14.5.1) — most need Phase 4 data.
- Inline floating selection toolbar — heavy AppKit, no Phase-2 contract depends on it.

---

## 13. Phase 3 ship state (added 2026-05-11 late PM)

All six work items §A–§F landed TDD-first, totalling 45 new tests (428 → 473). Pushed to origin through `95e4216`.

| § | Item | Commit |
|---|------|--------|
| A | Part + Chapter schema on Manuscript; lazy-versioned decode; Phase 1/2 forward-load contract intact | `fb04d06` |
| B | ProjectSession CRUD: add/update/delete/reorder Part; add/update/delete Chapter (across parts); placeScene / unplaceScene moves scene ids between containers | `fb04d06` |
| C | `Manuscript.flatSceneIds` walks Parts → Chapters → orphan tail; `ManuscriptWordCount.compute` folds scene counts up to chapter / part / project totals (orphan scenes count toward project total only) | `fb04d06` |
| D | Sidebar `NSOutlineView` renders Part > Chapter > Scene hierarchy; Parts + Chapters are expandable but not selectable; `+ Part` toolbar button + `New Part` / `Add Chapter to Part` context menu | `8e42134` |
| E | Plan view: `NSCollectionView` flow-layout card grid in standalone window (⌘⇧P / View menu). Each card: title · group label (chapter title) · word count + status · summary excerpt. Click routes through `session.selectScene(id:)`. Decoupled from main split view so the NSCollectionView spike doesn't touch existing layout. | `9fce49b` |
| F | `ProjectSettings.targetWordCount: Int?` (project-level target; Scene + Chapter already carried `targetWordCount: Int?` from the Phase 1 schema). Session setters for all three levels. Plan-view cards render "Nw / Tw · status" when target is set. | `95e4216` |

### 13.1 §9.4 risk #1 forward-load contract — met

Every Phase 3 schema migration includes a hand-rolled "Phase 1/2 JSON → Phase 3 decode" test. A bundle on disk in the pre-Phase-3 shape loads cleanly with `manuscript.parts = []` and `settings.targetWordCount = nil`.

### 13.2 §11.4 NSCollectionView reassess gate — preliminary verdict

Spike landed clean. `NSCollectionViewFlowLayout` + custom `NSCollectionViewItem` renderer + selection routing — no surprises during implementation. Verdict: **AppKit stays viable for Phase 3**. The pivot question can re-open if drag-rearrange between chapters/parts becomes messy in §D.2 polish, but the foundation is solid.

### 13.3 Phase 3 polish carried forward

- **Drag-rearrange between chapters / between Parts.** Current drag-rearrange still works within `orphanedSceneIds` (Phase 1 contract); chapter-aware pasteboard handling is real DnD work.
- **Inline rename for Parts + Chapters** in the sidebar (currently only scenes are inline-editable; rename is via the right-click menu's Rename which today only works for scenes).
- **Plan-view section headers per chapter** (the `groupTitle` field already drives this; just needs the supplementary-view wiring) + **Grid/Matrix/Outline view-mode toggle** (per LOOM_UI_RESEARCH.md §B.2.16).
- **Target-word editing UI**: project-target field in Settings window; per-chapter/per-scene target in a right-click menu or scene-metadata inspector.
- **Status strip showing project total / target**.
- **Live-app eyeball pass** on the new sidebar tree + Plan window. Mount smoke is green; honest UI verification is still the right next step before relying on either daily.

---

## 14. Phase 4 entry checklist (for the next context)

1. Read this handoff §11 → §12 → §13 to understand the ship state.
2. Skim [`LOOM_GENERATION_MODES.md`](LOOM_GENERATION_MODES.md) — Phase 4 ships the rest of the modes (Rewrite sub-variants / Show-don't-tell / Brainstorm / Critique / Bridge / Describe / NameSuggest) per `GenerationMode` enum + LOOM_PLAN.md L4.
3. Skim [`LOOM_STORY_BIBLE.md`](LOOM_STORY_BIBLE.md) §3 — the knowledge-ledger extraction pipeline (the distinctive Loom engineering). Schema is already on `Character.knownFactsBySceneId`.
4. Skim [`LOOM_NSFW.md`](LOOM_NSFW.md) §2.5 — Sphiratrioth lorebook-as-active-scenario; the Lorebook schema shipped with `group/weight/sticky` fields specifically for this pattern.
5. TDD posture per the saved [`feedback_tdd_always`](file:///Users/kevinappleyard/.claude/projects/-Volumes-SSD1-Code-FictionWriter/memory/feedback_tdd_always.md) memory: red → green → commit. Schema migrations include the forward-load case.
6. Repo state on entry (frozen at Phase 3 ship; §15 captures all Phase 4 work since):
   - Branch `main`, all Phase 3 work pushed to `origin/main` through `95e4216`.
   - 473 tests passing then (`swift run LoomCoreTests`); current count is in §15.5.
   - `./build.sh` builds `Loom.app`; run with `./Loom.app/Contents/MacOS/Loom` (NOT `./run.sh`).
   - Live server at `http://192.168.1.201:5001` (Qwen3.6-27B); defaultServerId in `~/Library/Application Support/Loom/settings.json`.
   - Settings window: `Cmd-,`. Plan view: `⌘⇧P` (View menu).

### 14.1 Phase 4 work-item proposal (subject to a kickoff session refinement)

1. **Rewrite sub-modes**: rewriteVoice / rewriteTense / rewritePOV / rewriteLength. Per-sub-mode system prompt + per-sub-mode `ModeInstruction` layer. Reuse the existing acceptance window + snapshot-before-rewrite plumbing.
2. **Show-don't-tell** generation mode. Selection-replace shape (like rewrite).
3. **Brainstorm** mode: blank-canvas riff. Side-panel or modal? Decide based on the History tab's grammar.
4. **Critique** mode: read-only suggestion overlay. Doesn't mutate prose; renders alongside.
5. **Bridge** mode: fills the gap between two selected paragraphs. Selection-replace.
6. **Knowledge ledger** extraction pipeline (the load-bearing distinctive item): post-generation side-call to a summariser-role server (RPClient parallel-server pattern) that extracts character-fact tuples per scene; `Character.knownFactsBySceneId` populates; the prompt assembler reads from it on next generation.
7. **Refusal-detection chip → Continue from refusal** action (LOOM_NSFW.md §5).
8. **Sphiratrioth lorebook starter pack** + Roll-Outcome generation mode (LOOM_NSFW.md §2.5 + §3.5).

### 14.2 Open before Phase 4 starts

- **Decide whether Knowledge Ledger is Phase 4.1 (early, blocks new modes) or 4.2 (after Rewrite sub-variants ship).** Per LOOM_PLAN.md L4 they're grouped; in practice the modes can ship first since they don't strictly need the ledger to function.
- **Live-app eyeball on Phase 2.5 + Phase 3 surfaces.** The mount smoke catches state transitions; layout fragility is what the §9.4 risk warns about. Recommend an explicit hour clicking around the Bible inspector / Plan window / hover popovers before Phase 4 commits start.

---

## 15. Phase 4 ship state — in-flight (added 2026-05-11)

Three NSFW-leaning + rewrite-pattern slices have landed since the §14 entry checklist. The user's standing directive: NSFW remains a strategic anchor for Phase 4 priority. Tests: 473 → 494 (21 new). All commits local on `main` pending push.

### 15.1 What landed

| § / # | Item | Commit |
|-------|------|--------|
| §14.1 #1 | **rewriteVoice prompt layer.** `GenerationModeAvailability` flips on selection; `PromptBuilder.systemPromptFor` + `modeInstructionFor` add the voice-rewrite framing per LOOM_GENERATION_MODES §4.1. Target-voice descriptor rides `PromptContext.perCallInstruction` — no schema change. **Not yet user-reachable** — tray/menu wiring deferred until rewriteTense/Length/POV prompt layers also land, so one coherent sub-mode picker covers all four. | `3101de3` |
| §14.1 #7 | **Continue-from-refusal chip action** (LOOM_NSFW §5). When `RefusalDetector.looksLikeRefusal` fires, the expanded History row now shows a "Push past refusal" button alongside "Insert again at cursor". Click → editor inserts an em-dash anchor at cursor + seeds the tray's per-call instruction field with a bracketed-Author's-Note breaking direction. User reviews and clicks Continue themselves — no auto-fire. Signal-not-block contract intact. | `e5c9abe` |
| §14.1 #8 | **Sphiratrioth lorebook starter pack** (LOOM_NSFW §2.5). New `Bible → Install Sphiratrioth Lorebook Pack` menu item adds a curated 9-entry pack: 3 anti-positive-bias constants + 2 sticky scenario anchors + 4 weighted entries in the `action_outcome` group. `ProjectSession.installSphiratriothStarterPack()` is additive-by-name; safe to re-run. Substrate for Roll-Outcome below. | `1f3836d` |
| §14.1 #8 (sibling) | **Roll-Outcome action** (LOOM_NSFW §3.5 / LOOM_MEMORY §B3). `Bible → Roll Outcome…` picks a weighted lorebook group, rolls one entry, seeds the rolled content into the tray's per-call instruction field; user fires Continue themselves. NOT a new generation mode — reuses the existing per-call instruction layer. `LorebookRoller.availableGroups` + `LorebookRoller.pick(group:from:using:)` (SplitMix64-deterministic in tests). Group picker is an NSAlert when ≥2 groups exist; auto-selects when only one. | `a3aeec4` |

### 15.2 Design calls locked in this batch

- **Sub-mode descriptors ride `perCallInstruction`** rather than a new typed field on `PromptContext`. Pattern extends naturally to rewriteTense (target tense), rewritePOV (target POV character), rewriteLength (target %). Each sub-mode gets its own system-prompt + mode-instruction case; no schema migration.
- **Sphiratrioth install is additive-by-name with NO tombstones.** A user-deleted entry comes back on re-install — install is "fill what's missing," not "honour past deletions." Documented at the installer's doc comment.
- **Continue-from-refusal does NOT auto-fire Continue.** The em-dash + breaking-instruction land in the tray; the user clicks Continue. Avoids hidden-action surprise; respects the "signal not block" contract.
- **Roll-Outcome is a Bible action, not a generation mode.** Rolls a weighted entry from a labelled group, seeds the rolled content into the tray's per-call instruction field; user fires Continue. No new `GenerationMode` case, no two-phase prompt assembly. History audit trail records what was rolled because the rolled content rides the existing per-call instruction layer.
- **Bible menu joins File / View at the top level.** Phase 4 home for project-content actions (sphiratrioth install + Roll-Outcome today; lorebook editing, knowledge-ledger import, ledger Re-extract actions as they land).

### 15.3 Re-prioritised Phase 4 work-item order (post-spike)

The §14.1 work-item list still stands. Internal ordering refined based on the corpus re-read (LOOM_RESEARCH §M.5 / §O.2 / LOOM_NSFW §3.9):

1. ✅ **rewriteVoice prompt layer** — `3101de3`.
2. ✅ **Continue-from-refusal action** — `e5c9abe`.
3. ✅ **Sphiratrioth starter pack + Bible menu** — `1f3836d`.
4. ✅ **Roll-Outcome action** — `a3aeec4`. Decision: Roll-Outcome is a Bible action, not a new generation mode. Reuses the existing per-call instruction layer; History audit trail records the rolled content via that layer.
5. ✅ **Knowledge-ledger feasibility spike** — landed 2026-05-11 across FOUR rounds. Full writeup in [`LOOM_LEDGER_SPIKE.md`](LOOM_LEDGER_SPIKE.md). **Verdict: PROCEED with Phase 4 #7 — extractor model decision: Gemma 4 4B abliterated on Ollama.** Structural wins shipped: (a) GBNF grammar-constrained decoding (KoboldCpp path) + JSON Schema constrained decoding (Ollama path), both with character_id enum restricted to bible names+aliases; (b) `unknown` knowledge derived from per-character scene-exposure graph at query time (SymbolicToM); (c) embedding endpoint (nomic-embed-text 768-d on the production KoboldCpp server) wired for cosine-similarity scoring + Phase 4 #7 fact deduplication + evidence-quote validation. **Round-4 numbers (Gemma 4 4B on Ollama, JSON-Schema-constrained, embedding scorer):** all 5 fixture scenes engaged (vs 3 of 5 under Qwen3.6-27B); aggregate recall 0.85 (vs Qwen 0.40); per-scene recall 83%/75%/100%/75%/100%; only 3 FN across 20 gold facts. The Mistral-Small-3-24B/Phi-4-14B model-swap recommendation from earlier rounds is **superseded** by this empirical result — Gemma 4 4B at a quarter of Qwen's parameters more than doubles recall, with the NSFW scene hitting 100% (the model handles explicit content). The high FP rate (60 across the fixture) is mostly valid extra prose observations beyond the selective hand-gold; the §10.5 production filters (deduplication, evidence-quote validation, prompt-leakage filter) trim before Suggestions UI display.
6. ✅ **rewriteTense + rewriteLength prompt layers + sub-mode picker UI** landed 2026-05-12. Two more siblings of the rewriteVoice template (selection-replace shape, descriptor on `PromptContext.perCallInstruction`, no schema change) — `rewriteTense` accepts "past" / "present" / freeform, `rewriteLength` accepts the §4.4 presets ("50%" / "80%" / "120%" / "150%") or freeform. Sub-mode picker is an `NSMenu` that pops up when the tray's Rewrite button is clicked: Voice (uses tray instruction field) → Tense presets → Length presets → Generic. Pure-data choice list in `RewriteSubModeMenuBuilder` so the menu shape is pinned without an AppKit dependency. Resolves the rewriteVoice "not yet user-reachable" carry-over from §15.1 — Voice, Tense, and Length are all reachable now; rewritePOV joins the menu when §14.1 #8 lands. 19 new TDD tests (6+6 prompt layers + 7 picker choices). Commits `0d65f3f`, `cc9fba5`.
7. **Knowledge-ledger pipeline** (#5 fully cleared the gate including the extractor-model prerequisite; PROCEED): post-scene side-call → diff → Bible-inspector Suggestions chip → user accept/reject → `[KNOWLEDGE-LEDGER]` prompt layer below cache boundary. The role-routed summariser server is **Ollama running abliterated `gemma4_2b`** (Round-5 result: same 0.80 recall as the larger gemma4_4b sibling but **1.86× faster** wall-clock — 43s/scene vs 80s/scene; both 100% recall on NSFW scenes). The `LedgerExtraction` module ships the JSON Schema generator + the Ollama-shaped backend in the spike runner — wire the same path into the production extractor. Compute `unknown` from per-character scene-exposure (SymbolicToM, [LOOM_STORY_BIBLE §3.5](LOOM_STORY_BIBLE.md)). Wire the §10.5 production filters (fact deduplication, evidence-quote validation, prompt-leakage filter) between extraction and Suggestions display to trim the high-FP output.
8. ✅ **rewritePOV landed 2026-05-12.** Final rewrite sub-mode (per LOOM_GENERATION_MODES.md §4.3). Selection-replace shape mirroring §14.1 #1/#6 (descriptor on `PromptContext.perCallInstruction`, no schema change), but the descriptor is structured rather than freeform: `RewritePOVDescriptor.build(...)` produces a `Target POV: {name} (third-person, limited).\n\n{name} KNOWS as of this scene:\n- ...\n\n{name} does NOT know:\n- ...` block sourced from `LedgerKnowledge.compute` — the §4.3 KNOWLEDGE_LEDGER_HINT slot finally has data to fill now that the Phase 4 #7 ledger pipeline is live. System prompt explicitly warns against inventing knowledge the new POV character couldn't have access to, leaning on the descriptor's bullets. Sub-mode picker gains one POV entry per bible character (`RewriteSubModeMenuBuilder.choices(povCharacters:)`), slotted between Length presets and the generic suffix; controller's `resolvedDescriptor(for:)` looks up the character, queries the ledger as of `session.currentSceneId`, formats, and optionally appends tray-instruction text on top (power-user override for person / limited / etc.). 19 new TDD tests (7 descriptor format + 7 prompt layer + 5 picker plumbing). Commits `f8bfbf4`, `eb09abf`.
9. ✅ **Show-don't-tell landed 2026-05-12.** Selection-replace; ~120% length target baked into the system prompt per LOOM_GENERATION_MODES.md §4.5. Same shape as the rewrite family — `SnapshotPolicy.shouldSnapshot` includes `.showDontTell` so the destructive replace is recoverable. Picker UI slots a "Show, don't tell (~120% length)" entry between the dynamic POV entries and the generic-rewrite suffix. Order is now: Voice → Tense → Length → POV (per character) → SDT → Generic. Tray-typed sensory hints ("lean into smell and texture") still ride on `perCallInstruction` for power users. 11 new TDD tests. Commit `f1169fb`.
10. ✅ **Lorebook editing UI v1 landed 2026-05-12.** `BibleCategory` gains `.lorebook` as a trailing case; the existing list-detail Bible inspector picks it up automatically via `BibleInspectorViewModel.sections(for:)`. Filter chip strip + add/delete actions wire through the standard category-routing switches. `BibleDetailEditor` branches on `.lorebook` for writeBack/snapshot and adds one new field: a comma-separated keys text field spliced between the Suggestions panel and the description scroll view. The mode popup (Constant/Keyed) maps to `LorebookActivationMode` via `ProjectSession.setInjectionMode` — the popup never produces `.vectorised` (Phase 5 R&D). v1 user-editable fields: name, content, keys, activation mode. Other LorebookEntry fields (priority, group, weight, sticky, positionMode, depth, secondaryKeys, enabled) keep their stored defaults — the sphiratrioth pack ships sensible values and a power-user editor for those knobs is a Phase 4.x polish slice. 6 new TDD tests + two Phase 2 viewmodel guards rolled forward. AppKit cost: ~15 min (single new field, no macOS-26 incidents). Commit `d6897a2`.
11. **Brainstorm / Critique / Bridge** (heavier UI surfaces: popover, History-tab-only output, multi-selection).

### 15.4 Carried forward

- **Live-app eyeball pass on Phase 2.5 + Phase 3 surfaces** is still recommended. Mount + server-probe sanity green; clickthrough QA (Bible inspector sub-tabs, @-mention popover under load, sparkline marker clicks, hover preview, Plan view, sidebar rename) needs a human pass before further visible work piles on.
- **Floating selection toolbar (§14.4.1)** stays deferred. Each new Phase 4 selection-required mode adds drift from the design grammar; reckon by Phase 6 polish.
- **Stale-arc compression** (LOOM_MEMORY §1.3 + §4.3) — not currently built; the recent-prose layer is raw verbatim. Once a manuscript crosses ~10 chapters this matters. Queue for Phase 4 late or Phase 5 early.
- **Live-app inspector layout QA** post the §15.5 inspector fix is still owed (the layout-shrink cascade fix is pinned by Phase4InspectorLayoutTests but the visible inspector hasn't been clicked through end-to-end since the fix landed).

### 15.5 Ledger spike (2026-05-11) — full writeup in [`LOOM_LEDGER_SPIKE.md`](LOOM_LEDGER_SPIKE.md)

Ran across five rounds in a single session. Commits `01ddf34` →
`e153e4f`. Headlines:

- **Phase 4 #7 is fully unblocked.** Build the ledger pipeline next.
- **Extractor model: `gemma4_2b` (abliterated) on Ollama.** 4.6B actual params, JSON-Schema-constrained via Ollama's `format` field. 0.80 recall, 100% on NSFW scenes, 43s/scene wall-clock — half the 4B sibling's latency at parity quality.
- **Loom now has two backends** — KoboldCpp for the writer (Qwen3.6-27B), Ollama for the extractor (gemma4_2b). The role-routed servers pattern from RPClient accommodates this with no plumbing changes.
- **Plumbing shipped:** GBNF + JSON Schema generators; `KoboldClient.generate(request:)` accepting `grammar`; `KoboldClient.embed(texts:)` (re-ported from RPClient); cosine-similarity scorer using the live embedding endpoint (nomic-embed-text 768-d); `Tools/LedgerSpike` backend-selectable via `LOOM_SPIKE_BACKEND=kobold|ollama`.
- **Design call:** `unknown` knowledge is derived from per-character scene-exposure at query time, NOT extracted (LOOM_STORY_BIBLE §3.5 / SymbolicToM pattern). The extractor emits `asserted` only. `mistaken` is manual-authoring.
- **Inspector + window-resize fix incident** (commits `e598ce6` + `9d90635`) added ~1h to the AppKit pivot pressure ledger (HANDOFF §2.1, memory `project_appkit_pivot_pressure.md`). Required `400pt` min-height on the bible list to defeat macOS-26's auto-refit-to-fittingSize cascade.
- **Test count: 530 passing.**

### 15.6 Carried forward — Phase 4 #7 (the next work item)

The UI surfaces are unbuilt; everything else for #7 is in place. Sub-tasks, in suggested order:

1. ✅ **`ServerProfile` Ollama-role wiring landed 2026-05-11 evening.** `ServerProfile.kind: ServerKind` (`.kobold` default, `.ollama` for the extractor) + `AppSettings.extractorServerId` sibling of `defaultServerId` + `writerServer()` / `extractorServer()` / `setExtractor(id:)` helpers. New `OllamaClient` lifted out of the spike's `ollamaExtract` into `Sources/LoomCore/Networking/OllamaClient.swift` (pure-data `makeChatRequestBody` + `parseChatResponseContent` testable wire shape; `extract(prompt:schema:completion:)` instance method for the production side-call). Sibling `OllamaProbe.probe(baseURL:)` speaks `GET /api/tags`. Settings UI gains a Kind segmented control on the Add Server sheet, a "Set as Extractor" toggle button on the row strip, and a role suffix in the cell label (`(writer, extractor)` / `[Ollama]`). Auto-probe routes by `kind`. Forward-load contract intact: pre-Phase-4 settings.json bundles on disk (no `kind`, no `extractorServerId`) decode unchanged. 33 new TDD tests; 530 → 563 total passing.
2. ✅ **Post-scene side-call coordinator landed 2026-05-11 evening.** New pure-data `LedgerExtractionTrigger.shouldFire(currentWordCount:baselineWordCount:threshold:)` (200-word default per LOOM_STORY_BIBLE §3.2; uses absolute delta so heavy deletion is also a re-extraction signal). `LedgerExtractionCoordinator` owns per-scene baselines + injectable `LedgerExtractor` / `LedgerExtractionScheduler` protocols. Production adapters: `OllamaLedgerExtractor` wraps `OllamaClient` with `LedgerExtraction.buildExtractionPrompt` + `LedgerExtraction.jsonSchema(certainties: [.asserted], characters:)` + `parseExtractedFacts`; `TimerScheduler` wraps `Timer.scheduledTimer`. AppState constructs the coordinator at init with closures reading the latest `settings.extractorServer()` + active session at fire time (so server-profile changes are picked up live, no stale snapshot). AppState subscribes to `ProjectSession.didChangeDirtyStateNotification`; on dirty→clean (post-autosave) it computes the active scene's word count and calls `evaluate`. The coordinator's `onExtractionComplete` is the entry point sub-task 3 (diff) consumes. 19 new TDD tests; 563 → 582 total.
3. ✅ **Diff vs existing ledger landed 2026-05-11 evening.** Pure-data `LedgerDiff.diff(extracted:bible:sourceSceneId:now:) -> [LedgerSuggestion]` resolves each extracted `character_id` against the bible's `name + aliases` (case-insensitive), drops facts whose text already appears verbatim on the resolved character's ledger across any scene (`§10.5` embedding-paraphrase dedup is sub-task 8), and stamps surviving `KnownFact`s with `sourceSceneId` + `addedAt` + fresh UUID. `LedgerSuggestion` carries `(characterId, fact: KnownFact, evidenceQuote)`. `LedgerSuggestionsQueue` is an in-memory per-character store with `add` (dedup by `fact.id`), `suggestions(forCharacter:)`, `remove(factId:)`, `clear(characterId:)`, `clearAll`, `totalCount`. AppState owns the queue; the coordinator's `onExtractionComplete` callback routes successful extractions through `LedgerDiff.diff` into the queue and posts `AppState.ledgerSuggestionsDidChangeNotification` (no-op when the diff is empty — important so a verbatim re-extraction doesn't flash the inspector chip). 20 new TDD tests; 582 → 602 total.
4. ✅ **Suggestions panel UI landed 2026-05-11 evening (bundled with #5 since accept-without-persist is meaningless).** Per-character `BibleDetailEditor` gains a Suggestions panel between the Inject row and Description scroll view. Shows `Suggestions (N)` header + one card per pending fact: fact text (body) + `"evidence quote"` (caption1, tertiary) + Accept / Reject inline buttons. When N=0 the panel is zero-height so Description inherits all the freed space. `BibleInspectorViewController.init(session:appState:)` takes an optional AppState (default nil for tests) and subscribes to `ledgerSuggestionsDidChangeNotification` to re-render the detail pane; `InspectorController` + `MainWindowController` updated to pass `AppState.shared` through. Edit-in-place defers to Phase 6 polish — for #7 v1 the user accepts as-is or rejects and re-edits the prose to coax a better extraction. New `SuggestionRowView` AppKit primitive uses `defaultHigh + 1` (751) height pins instead of `.required` to dodge the macOS-26 fittingSize cascade. **AppKit cost ledger this slice: ~5 min** (no incidents; the panel-becomes-zero-height-when-empty pattern was the only subtle move).
5. ✅ **Persistence into `Character.knownFactsBySceneId` landed in the same slice.** Pure-data `LedgerSuggestionAcceptor.apply(_:to:) -> Character` appends the suggestion's `KnownFact` to `knownFactsBySceneId[sourceSceneId]` (preserving existing facts on the same scene and unrelated scenes). `AppState.acceptLedgerSuggestion(_:)` resolves the character, calls the acceptor, writes back via `ProjectSession.updateCharacter` (dirties the session → auto-saves), removes the suggestion from the queue, posts `ledgerSuggestionsDidChangeNotification`. Stale-character ids are a graceful no-op for the bible write but still drop the suggestion from the queue. `AppState.rejectLedgerSuggestion(factId:)` removes-from-queue + notify only (no bible mutation, no blacklist — rejecting once doesn't prevent the next extraction from re-surfacing the same fact; that's a Phase 6 concern). 11 new TDD tests for the pure-data + AppState layer; 602 → 613 total.
6. ✅ **`unknown` derivation from scene-exposure landed 2026-05-11 evening.** Pure-data `ScenePresence.isPresent(characterId:in:character:mentions:) -> Bool` resolves "is character C present in scene S?" via three signals (any one yes = present): `scene.pov == characterId` (definitive), `MentionIndex.count(for:in:) > 0` (covers `@`-references), `WholeWordMatcher` against `[name] + aliases` (covers free-text occurrences — most fiction prose). `LedgerKnowledge.compute(characterId:asOfSceneId:in:scenes:mentions:) -> Result` walks `manuscript.flatSceneIds` truncated at `asOfSceneId` inclusive, and for each in-scope scene S buckets ALL extracted facts (across every character's `knownFactsBySceneId[S]`) into KNOWS if C was present in S, otherwise UNKNOWNS. `mentions` is optional — built lazily inside the helper if not supplied. Orphan/stranger `asOfSceneId` falls back to full-manuscript scope (defensive for draft scenes not yet placed). Chronological order = narrative order for v1; SceneTime-based ordering deferred to the flashback-heavy Phase 4.x case per LOOM_STORY_BIBLE §11.
7. ✅ **`[KNOWLEDGE-LEDGER]` prompt layer landed in the same slice.** `PromptBuilder` adds a `.knowledgeLedger` layer below the cache when the current scene has a POV character with extracted facts in scope. Format per LOOM_GENERATION_MODES §11: `[KNOWLEDGE-LEDGER]\n{POV} knows the following as of this scene:\n- ...\n\n{POV} does NOT know:\n- ...`. Empty buckets omit their sub-block. Layer is below-cache so it doesn't bust prompt caching when the ledger changes; eviction priority 70 (above bible-keyed=50, below bible-constant=100 — POV consistency is load-bearing but not mandatory). Carries `povId` as `sourceId` so the History tab can render an entity link. 24 new TDD tests across three suites; 613 → 637 total.
8. ✅ **The §10.5 production filters landed 2026-05-12.** Three pure-data filters between `LedgerDiff.diff` and `ledgerSuggestionsQueue.add`, all consuming pre-computed embedding vectors from a single batched `KoboldEmbedding.embed` call: (a) `LedgerFilters.deduplicate` (cosine ≥ 0.85 cluster collapse — catches both bible-side dupes and intra-batch paraphrases the existing verbatim diff misses); (b) `LedgerFilters.validateEvidence` (drops facts whose `evidenceQuote` has no scene sentence within cosine 0.65); (c) `LedgerFilters.filterPromptLeakage` (drops facts whose body cosine-matches `LedgerExtraction.extractionPromptInstruction` above 0.85). `LedgerFilterPipeline.apply` orchestrates the embed batch + chains all three; fail-soft on embed errors (returns input list unchanged) so a flaky writer server never costs the user a candidate. Every filter is fail-open on missing embeddings — honors the NSFW content-neutrality directive. `AppState.handleExtractionComplete` gained an injectable `embedderProvider` parameter (defaults to `registry.clientForDefault()` when a default server is configured; nil for first-launch / no-server-set tests, which skip the pipeline). New `SentenceSplitter` for evidence validation. 32 new TDD tests (14 filters + 8 pipeline + 6 sentence-splitter + 4 AppState wiring), all using deferred-completion stubs per `feedback_tdd_async_callbacks`. 664 → 697.

### 15.7 Live verification + reliability follow-ons (2026-05-11 late evening)

End-to-end pipeline now demonstrably working in the live app: paste 248-word prose into an Untitled scene with Mia + Anders in the bible → ~30-45s later the Bible inspector shows `Suggestions (12)` on Mia (9) + Anders (3) → click Accept → fact persists into `Character.knownFactsBySceneId[sceneId]`. Confirmed via `[ledger] queued 12 suggestions for scene=… breakdown={Anders=3 Mia=9} dropped=0/12` in the debug log.

Follow-on fixes shipped during live testing:

- **`ee38abb` — untitled-project trigger bug.** AppState's extraction signal was `didChangeDirtyStateNotification` dirty→clean (post-autosave), but `ProjectSession.scheduleAutoSave` is a no-op when `session.url == nil`. Untitled in-memory projects never reached the dirty→clean edge → coordinator never called. Switched to `EditorViewController.wordCountChangedNotification` (per-keystroke; carries `sceneId` + `wordCount` in `userInfo`). Coordinator's 2s debounce already handles burst collapse.
- **`ee38abb` — Servers tab button-enable bug.** macOS-26 `style = .inset` NSTableView shows the selection pill on click but doesn't reliably propagate to `tableViewSelectionDidChange`, leaving a visually-selected row paired with disabled buttons. Fixed by enabling whenever any row exists + falling back to "first ollama-kind profile" inside `setExtractorClicked` when `selectedRow == -1`.
- **`9b29895` + `589249f` + `e66a2f3` — Suggestions panel growing the window.** Unbounded panel height pushed the inspector pane's fittingSize beyond the window's, and macOS-26's auto-refit cascade grew the window vertically (HANDOFF §2.1 sibling, opposite direction). Extracted `SuggestionsPanelBuilder` (testable), capped the panel at 360pt with a `.required lessThanOrEqualTo` constraint, wrapped suggestion rows in an NSScrollView with `FlippedStackView` documentView (top-aligned content), set `borderType = .lineBorder` + `scrollerStyle = .legacy` + `autohidesScrollers = false` so the panel reads as a self-contained card with an obvious overflow affordance. `SuggestionRowView.updateLayer()` re-resolves NSColor on appearance change so backgrounds track dark/light.
- **`e66a2f3` — extraction reliability.** `OllamaClient.makeChatRequestBody` now passes `keep_alive: "30m"` to override Ollama's default 5-minute model-unload timer (writers pause longer than 5 min between sessions; default unload causes cold-load empty-content failures). `OllamaLedgerExtractor` retries once on empty `message.content` (transient sampling roll under JSON-Schema constraint). Parse failures now log raw response prefix + length.
- **`cedb37b` — critical deallocation bug.** The retry refactor's `[weak self]` URLSession callback raced the local-scope deallocation of `OllamaLedgerExtractor` (constructed fresh by `extractorProvider` and assigned to a local in `LedgerExtractionCoordinator.fire()`). When the response arrived ~30s later, self was already nil, the `guard let self` bailed, and the completion was silently dropped — `[ledger] firing side-call` logged, then nothing. Fixed with strong self capture; lifetime contract pinned in Phase4OllamaExtractorLifetimeTests using a deferred-completion stub (synchronous-completion stubs hide the bug). **TDD lesson saved as memory `feedback_tdd_async_callbacks`**: when testing async-callback APIs, the test double must defer the callback (store + flush), never invoke it synchronously — otherwise `[weak self]` and lifetime bugs are invisible.

Cumulative AppKit cost ledger for Phase 4 #7: **~30 min** (suggestions-panel cascade, button-enable + selection quirk, dark-mode reactivity). Single-digit incidents, all resolved without sinking into NSWindow / fittingSize hell.

### 15.8 Carried forward into Phase 4 #7 sub-tasks 8 + adjacent

**Phase 4 #7 is feature-complete (2026-05-12).** Both gaps that were pending after sub-tasks 1–7 landed have shipped:

- ✅ **POV picker UI.** `ProjectSession.setScenePOV(id:to:)` mirrors the sibling `setSceneStatus` / `setSceneSummary` setters (mutates, no-op on stale id, `markDirty`). Sidebar right-click menu gained "Set POV" with a submenu that `NSMenuDelegate.menuNeedsUpdate` rebuilds per-click from the clicked scene's current POV + the live bible character list. Hidden when the clicked row isn't a scene. Pure-data `ScenePOVMenuBuilder.menuItems(characters:currentPOV:)` returns the descriptor list (leading "Clear POV" entry + one per character, with `isCurrent` flagged for the checkmark). Each submenu item carries a `POVMenuClick { sceneId, characterId }` payload on `representedObject` so the action handler doesn't depend on `clickedRow` state during the menu lifecycle. 8 new TDD tests. AppKit cost ledger: ~5 min (clean NSMenuDelegate path; no macOS-26 fittingSize incidents). Commit `dfd9942`.

- ✅ **Sub-task 8: the §10.5 production filters.** See §15.6 #8 above for the full writeup. Commit `9b8b352`. 32 new tests using deferred-completion embed stubs per `feedback_tdd_async_callbacks`.

**Still pending for the Phase 4.x parking lot:**

- **Scene chunking for very long scenes** (Phase 4.x, design noted 2026-05-12). The current auto-budget (`OllamaLedgerExtractor.budgetForSceneWords`) caps `num_predict` at 8192, which covers scenes up to ~1024 words at the gemma4_2b emission rate. Real chapter-length scenes (1500–2500 words is normal at L4) will routinely exceed this and silently re-hit the length-cap empty failure mode even after the smart-retry doubles to 8192. Right next move: split scenes above ~500 words at paragraph/sentence boundaries (`SentenceSplitter` already exists), extract per chunk against the same bible character list, merge the per-chunk extraction arrays, then run the existing `LedgerDiff.diff` + `LedgerFilterPipeline.apply` pass over the combined output. **Dedup is naturally idempotent under this design** — the existing pipeline already handles cross-batch paraphrases (each chunk feeds the same diff + the same `LedgerFilters.deduplicate`, which clusters paraphrases per character regardless of which chunk surfaced them); so a paraphrase pair split across chunk-1 and chunk-3 collapses just as cleanly as a pair within one chunk. The non-trivial subtleties to think about when wiring this: (1) attribution — a fact about character X in chunk-N may reference setup from chunk-1, so each chunk's prompt should include a brief scene-prefix (opening paragraph + the active chunk) to preserve context without re-emitting facts; (2) Ollama serialises requests by default, so the simplest implementation is sequential per-chunk calls (parallel would need separate model contexts and isn't worth the complexity at Phase 4); (3) chunking must be purely word/paragraph-driven — never content-sensitive — to keep the NSFW content-neutrality directive intact; (4) the `[KNOWLEDGE-LEDGER]` prompt layer's POV gating is per-scene, not per-chunk, so chunking is invisible at the prompt-builder side. Don't ship until live use exposes a scene that breaks the auto-budget + smart-retry combo; the existing pieces will recombine cleanly when needed.

- **Extractor coverage variance.** Live testing showed gemma4_2b's character coverage is sampling-variant: some runs are all-Mia, others split (9 Mia / 3 Anders). The §10.5 filters don't address this — it's prompt-engineering territory. Phase 4.x could explore: (a) per-character extraction loop (one call per bible character), (b) richer prompt instruction emphasising "all named characters", (c) a coverage-aware extraction prompt that names characters the model should NOT skip. Defer until live use exposes the failure mode clearly.

- **rewriteTense no-op-target failure mode.** ~~Reproducible both ways: when the user picks a target tense that matches the source's current tense, the writer model invents an unrelated transformation (past+past target → present output; present+present target → future output, observed live 2026-05-13). A first-attempt fix tightening the rewriteTense system prompt with explicit no-op-target language made the failure catastrophically worse...~~ **RESOLVED upstream of the model** in this session: added `SelectionTenseHeuristic` (NLTagger-driven, dialogue-aware, abstains on weak signal) + `RewriteSubModeChoice.disabledReason` + tray glue that disables the matching `Tense — past` / `Tense — present` entry when the heuristic returns a definite verdict, plus a click-time short-circuit with tray flash-note as defence-in-depth. Live-smoke verified against past/present/split paragraphs: matching entry greys out with tooltip "Selection is already in X tense.", non-matching stays clickable, split-tense input leaves both enabled (heuristic returns `.unknown`). The click-time short-circuit path is practically unreachable through normal UI (menus close on click-out so the menu-build vs click verdicts can't diverge over the same input) — kept anyway as cheap defense-in-depth. Phase 4 §15.10 slice.

- **rewriteTense degenerate near-copy decode (Qwen3.6-27B writer).** Reproducible across two live runs 2026-05-13. The writer enters a low-entropy near-copy state on rewriteTense specifically, producing three concurrent symptoms whose severity escalates through the output stream:
  - **Tokenization / spacing corruption.** Words concatenate without spaces (*"his back toher"*, *"watchingthe lineofhishoulders"*, *"She kissedthebackofhis neck.Heshuddered."*), mid-word character loss (*"undoing"* → *"undo"*, *"speak yet"* → *"speaktet"*). Paragraph 1 typically starts clean and degrades; paragraph 2 is heavily affected.
  - **Named-entity drift.** Run 2: *"Linus"* became *"Lincoln"* in the second sentence despite the system prompt's explicit "preserve every named entity" clause. Probably the same degenerate-state symptom.
  - **Run-1 also showed single-paragraph truncation** (405 chars, EOS after paragraph 1; `reply=1024` budget was nowhere near saturated). **Run 2 produced both paragraphs (578 chars)** — so truncation did NOT reproduce; the more reliable symptom is the corruption + drift pair.

  **Diagnosis.** rewriteTense's task is "output the source with small verb-tense substitutions" — closer to copying than the other rewrite sub-modes. For Qwen3.6-27B-Uncensored, this near-copy regime collapses to a low-entropy state where high-probability BPE tokens happen to lack space prefixes. rewriteVoice (transformative) and Continue (generative) don't exhibit this; the pattern is specific to near-copy tasks. **Confirmed 2026-05-13 Test 5c**: rewriteLength on the same chunk emitted clean tokenization (no space-prefix loss, no name drift) — confirming the failure is rewriteTense-mode-specific rather than a broader writer-model issue. Other rewrite sub-modes are clean on this model.

  **Intervention ladder (untested, Phase 4.x):**
  1. **Per-mode sampler tuning** — bump temperature slightly for rewriteTense to nudge out of the near-copy trap. Smallest slice, ~10 lines + tests.
  2. **Per-mode `repeat_penalty` tweak** — lower it if the space-prefix glyph is being penalized into oblivion.
  3. **Inspect the assembled `GenerateRequest`** in `[gen]` log lines to confirm the actual sampler params that go out — may be a setting that works for Continue/Voice but breaks Tense.
  4. **Accept the limitation** — document, move on; rewriteTense stays "use with caution" for now.

  Worth pursuing once the rest of the rewrite family is validated as working on this model.

- **Rewrite-family length-anchor drift + wrong-style expansion (rewriteVoice + rewriteLength).** Pattern reproduces across both sub-modes during 2026-05-13 live testing — length anchors in the system prompts aren't load-bearing enough to hold against expansive-leaning descriptors:

  - **5a (rewriteVoice)**: descriptor `"lyrical, slow, sensory-heavy, late-Atwood"` produced ~150% of source (165 words from 109-word chunk), system prompt allowed ±20%.
  - **5c (rewriteLength)**: descriptor `"120%"` produced ~150–185% of source (~260 words from 140–165-word chunk), well over the explicit 120% target.

  **Second symptom on 5c specifically**: when the model DOES expand, the expansion is verbose paraphrase rather than the sensory detail / interiority the system prompt directs. Example: source *"She pressed her thumb against his lower lip until he stopped"* became *"She applied the gentle but firm pressure of her thumb directly against his pliable lower lip until his words ceased, effectively muting him"* — more words, same proposition, no new sensory data. The `Adjust through expanded sensory detail and interiority` clause in `PromptBuilder.systemPromptFor(.rewriteLength)` doesn't bite under Qwen3.6-27B-Uncensored. Other beats expanded similarly (*"the dramatic expansion of his pupils dilating"* — tautology not detail; *"cataloging every micro-expression, every twitch, every breath—registering the totality of his being"* — abstraction stacked on abstraction).

  Beat preservation + NSFW content-neutrality both held on every drift run. So this is a **fidelity-to-target drift** issue, not a content-bias regression.

  **Fix shape (Phase 4.x, untested):** tighten the length clauses in both `PromptBuilder.systemPromptFor(.rewriteVoice)` and `.rewriteLength` with harder language. For rewriteLength specifically, add positive examples in the prompt body: *"A correct 120% expansion adds sensory specifics — touch, smell, breath, sight, light — never redundant adjectival paraphrase of existing propositions"*. Worth testing with one positive example to see whether the model picks up the contrast before landing as a real fix.

- **showDontTell on sparse abstract sources is a structural model limit.** Live test 2026-05-13 Test 7 across three iterations against both Qwen3.6-27B and Gemma 4 31B on Scene C (a 5-sentence ~70-word told-emotion paragraph). Pattern: every run extends past source bounds (apartment arrival, key-fumbling, crossing-the-floor, heading-toward-the-bed, "her palms sliding under her clothes"), regardless of prompt language. Two distinct mitigation attempts both failed to materially help:

  1. **Generic scope-discipline clause** (the one that DID bite on rewritePOV's plot-invention failure): stopped cross-scene character pulling (no more "Marisol... Jamie..." both named) and stopped invented relationship histories (no more "their laughter"), but did NOT stop forward-extension or location-invention.
  2. **SDT-specific narrative-moment clause with targeted negative examples** (*"no 'she arrived at...', 'the key in the lock...', 'she imagined his palms...'"*): Gemma evaded the blacklist by paraphrase. Source clause said *"no 'the key in the lock'"*; Gemma produced *"her key into the deadbolt"*. Same failure, different vocabulary. **Lesson: targeted negative-example blacklists don't generalise across paraphrase — models substitute synonyms to dodge specific patterns.** Rolled back.

  **Root cause:** SDT's task fundamentally requires *inventing concrete observable material* to "show" what the source "tells". On sparse abstract sources (Scene C is 5 sentences of mostly named-emotion with almost zero concrete content), there's no existing material to make more vivid — the model has to invent. Prompt-level "do not invent" instructions cancel out against the SDT mode's "expand to show" instruction. The two demands are structurally in tension on this kind of source.

  **What still works on SDT:**
  - The generic scope clause (kept) prevents cross-scene character pulling + invented relationship histories.
  - The somatic translation of in-scope named emotion is genuinely strong (*"made her hands shake"* → *"Her fingers trembled, spilling the change from her pockets"*; *"felt aroused"* → *"Her own skin hummed beneath her coat"*).

  **User-facing implication:** SDT works best on *concrete prose with told emotion embedded* (where there's existing scene material to render more vividly), NOT on *pure named-emotion summary paragraphs* (where the model has nothing to anchor on and invents the apartment, the bed, the heels). The mode's effective scope is "make existing description more vivid", not "dramatise an abstract emotion sequence into a full scene".

  **Possible future fix (heavy):** constrained decoding / positional-anchor at the GenerateRequest layer — pass the model an explicit structural constraint that the output must start/end with the same temporal moment the source occupies. Order-of-magnitude more code than prompt-tuning; deferred to Phase 4.x or later.

- **showDontTell regresses to naming-the-emotion roughly 40% of the time.** Live test 2026-05-13 Test 7. The system prompt's *"Translate naming-the-emotion into showing-the-emotion"* clause bites well on the obvious cases (*"She wanted him desperately"* → *"A desperate want coiled tight in Marisol's belly"*; *"hands shake"* → *"clamped her trembling fingers over her keys to steady them"*; *"felt aroused"* → *"A heat pooled low in Marisol's hips, demanding attention"*), but consistently slips on three patterns: (1) **suffixed named-emotion pairs** — a perfect show ruined by a tacked-on adjective pair, e.g. *"biting down on a sudden grin that felt **both foolish and thrilling**"*; (2) **near-verbatim preservation of source telling** — source *"She felt like a teenager again"* → output *"she felt sixteen all over again, **reckless and raw**"* (preserves the *felt X* construction + adds two more names); (3) **tells about not-naming** — *"a knowing gesture that suggested a secret current neither of them had named"* explicitly names the not-naming. **Fix shape (untested, Phase 4.x):** strengthen the system prompt with explicit negative examples: *"NEVER use 'felt X' or 'X and Y' adjective pairs that name feelings. If the source uses 'felt aroused' or 'felt sixteen', the rewrite must NOT use 'felt' + any adjective. Translate to body, action, or sensory cue ONLY — no abstract labels."* Beat preservation, NSFW content-neutrality, tokenization all held — this is purely a target-fidelity drift on the SDT translation.

- **Cross-model validation against Gemma 4 27B (Phase 4.x experiment).** Most of the §15.8 model-behavior failure modes are attributed to Qwen3.6-27B-Uncensored-HauhauCS-Aggressive specifically — the rewriteTense near-copy decode collapse, the rewrite-family length-anchor drift, the wrong-style expansion under rewriteLength, the no-op-target tense-invention. Worth a comparison run against Gemma 4 27B (the user prefers Qwen for raw speed at this size but would accept Gemma's higher latency in exchange for better instruction-adherence if Gemma materially fixes these). Test protocol: swap the KoboldCpp writer endpoint to Gemma 4 27B, re-run Tests 5a / 5b / 5c / 6 (rewrite family) against the same Saoirse/Linus and Marisol/Jamie fixtures, compare: (a) length-target fidelity, (b) tokenization integrity on rewriteTense, (c) no-op-target behaviour, (d) expansion-style under rewriteLength. If Gemma materially improves any of these without regressing NSFW content-neutrality or named-entity preservation, the data informs the writer-model choice. Worth scheduling once the Phase 4 #6 rewrite family is fully tested on Qwen so we have a clean A/B baseline.

- **Gemma 4 31B over-contextualizes rewrites — pulls content from outside the selection.** Live test 2026-05-13 surfaced two related failure shapes specific to Gemma writer (Qwen3.6-27B-Uncensored doesn't exhibit either under the current system prompts):

  1. **Out-of-scene character cross-pollination (Test 7, showDontTell).** Source paragraph (Scene C) used unnamed "she"/"he" throughout — no character names, no relationship history. Gemma wrote the rewrite *"Marisol... Jamie..."* using names from Scene B in the same project, then introduced *"the sound of **their** laughter echoed louder than the city streets"* — a shared-history detail that exists nowhere in the source. Bible-aware enrichment is sometimes desirable (constant-layer characters informing the model that "she" = Marisol from the bible), but here it crossed into inventing relationship facts that the source didn't establish.

  2. **Forward-extending past source bounds (Test 7, showDontTell).** Source ends with *"She felt like a teenager again."*. Gemma's rewrite continues past that: *"Her key rattled in the lock as she fumbled blindly for it, eager to get inside before her legs gave out"* — added scene content (arriving home, key-fumbling, going inside) that the source explicitly does not include.

  Same model also exhibited the **plot-invention-from-elsewhere-in-the-same-scene** failure in Test 6 (rewritePOV) — pulled Jamie's *"tearing up the tour rider"* dialogue forward from a later beat in the source scene into the rewrite of an earlier chunk, plus ~70 words of invented surrounding dialogue.

  All three are different shapes of the same root failure: **Gemma interprets rewrite-family system prompts loosely on scope** — *"preserve every plot beat"* and *"do not add new plot"* clauses don't bite hard enough to keep Gemma from helpfully drawing on surrounding context (other scenes in the project, later beats in the same scene, plausible scene-extension content). Qwen on the same prompts stays inside the selection.

  **Fix shape (Phase 4.x, applies to all three failure modes):** tighten the rewrite-family system prompts with explicit scope language. Single positive clause: *"Rewrite ONLY the selected passage's beats, in place. Do NOT pull in events, dialogue, characters, or relationship details from earlier or later in this scene, from other scenes in the project, or from the bible's character descriptions beyond what is already present in the selection. The output's narrative span must match the selection's narrative span — no extension forward or backward in time, no implied histories not in the selection."* Worth A/B testing on both models — may help Gemma without regressing Qwen.

- **rewritePOV plot invention from elsewhere in the same scene (Gemma 4 31B writer).** Live test 2026-05-13 Test 6 on Gemma writer (same Scene B kneeling chunk, target POV Jamie, 12 KNOWS/0 DOES NOT KNOW): in addition to the cross-character interiority leak (which both models share), Gemma pulled **Jamie's *"I'm tearing up the tour rider"* declaration forward from a later beat in the source scene** into the rewrite of an earlier chunk, then invented ~70 words of dialogue around it (*"That stopped her... 'Starting tomorrow'... 'Let's not talk about that tonight'..."*). System prompt is explicit *"Preserve every plot beat, dialogue beat, and named entity from the original (do not skip, do not invent events)"* — Gemma interpreted this as "I can pull existing events from elsewhere in the scene if they connect thematically", which is the wrong reading. Distinct from Qwen's Test 6 failure on the same input (Qwen had one localised beat inversion — *"thumb on lip"* actor swapped — but no fabricated content). Gemma's failure is harder to recover from (~70 words of invented dialogue the user has to manually delete vs Qwen's single-word inversion). **Fix shape (Phase 4.x):** tighten the system prompt with explicit scope language: *"Rewrite ONLY the selected passage's beats. Do NOT pull in events, dialogue, or actions from earlier or later in the surrounding scene, even if they are thematically related to the selection."* Worth piloting on Gemma specifically — Qwen doesn't exhibit this failure mode under the current prompt. May or may not regress Qwen's performance on rewritePOV; needs A/B testing on both models.

- **rewritePOV cross-character interiority leak + occasional beat inversion.** Live test 2026-05-13 Test 6 (Scene B kneeling chunk, source POV Marisol, target POV Jamie, 12 facts in Jamie's KNOWS bucket, 0 in DOES NOT KNOW): the output leaked Marisol's interiority into Jamie's POV multiple times — *"He knew she had imagined this part too"* (Marisol's prior imagination, not in Jamie's KNOWS), *"but tonight she needed the noise to die"* (her interior need rendered as his awareness), *"She understood"* (her interior interpretation). Worst symptom: a **beat inversion** — original *"She pressed her thumb against his lower lip"* became *"He pressed his thumb against his lower lip"* — the model preserved "thumb on lip" but swapped the actor, producing nonsensical action geometry. Tokenization clean, length within ±20%, NSFW preserved, named entities preserved. The failure is specifically about cross-character interiority NOT being captured anywhere in the descriptor.

  **Root cause (structural, not just prompt wording):** `LedgerKnowledge.compute` populates KNOWS from scenes the character was present in and UNKNOWNS from scenes they weren't. The source prose's *interiority* attributed to non-target characters (Marisol's planning, decisions, internal interpretations) is NOT an extractable factual claim — so it ends up in neither bucket. The descriptor has 12 KNOWS bullets and an empty DOES NOT KNOW; the model reads the source, finds non-target interiority, and (lacking negative reinforcement) preserves it as if Jamie had access.

  **Fix shapes (both untested, Phase 4.x):**
  1. **Prompt-side mitigation (cheap).** Strengthen `PromptBuilder.systemPromptFor(.rewritePOV)` with explicit cross-character-interiority guidance: *"The source prose may contain interior thoughts, intentions, plans, or feelings ascribed to characters OTHER than the target POV character. The target POV character CANNOT access these. Translate them into observable behaviour the target POV character could perceive (gesture, expression, tone, body language) — OR omit them entirely. Do not preserve them as factual knowledge."* Worth piloting first; if it materially reduces the leak rate on a re-test, ship.
  2. **Pipeline-side fix (deeper).** A second pass on the source prose that detects non-target-POV interiority (third-person interiority markers — "she felt", "she knew", "she had imagined" with non-target subject) and either rewrites it out before the rewritePOV call OR appends it as explicit DOES NOT KNOW bullets in the descriptor. Heavier, more reliable; needs a small NLP heuristic for interiority detection.

- **ThinkBlockStripper only runs post-finish; thinking tags visible during streaming.** ~~`EditorViewController.stripThinkBlocks(in:)` is called only at generation finish, so during streaming the user sees the raw `<think>...</think>` or `<|channel>thought\n<channel|>` tokens land in the text view...~~ **RESOLVED this session:** added `StreamingThinkBlockStripper` state machine (handles both Qwen + Gemma 4 formats, tag-spanning token boundaries, stray angle brackets in prose, unclosed-block flush preservation), threaded through the editor's `didEmitTokenNotification` observer, with a separate streaming insertion-offset tracker so swallowed tokens don't drift the coordinator's raw-token offset relative to the actually-inserted text. Bonus side-effect: the tray now stays on "Thinking…" through the channel-thought block and only flips to "Streaming…" when visible prose arrives, which matches user expectation. Post-finish `ThinkBlockStripper.strip` retained as defence-in-depth. Live-smoke verified against Gemma 4 31B on Continue.

- **No UI surface to override instruct-template auto-detection.** `Project.settings.instructTemplate: InstructTemplate` exists ([Project.swift:109](Sources/LoomCore/Models/Project.swift:109)) and defaults to `.auto`, which probes the writer's model name and routes through `InstructTemplates.detect(forModelName:)` ([InstructTemplates.swift:37](Sources/LoomCore/Generation/InstructTemplates.swift:37)). If the probed name doesn't contain a recognised family substring (e.g. a Gemma 4 GGUF loaded under a generic alias like `koboldcpp/gemma-27b-q4`), detection falls through to chatml and the user has **no in-app fix path** — the only override route is editing `project.json` directly, which doesn't help with an Untitled / in-memory project. The `template=` field on `[gen]` debug lines is the only way to inspect what got selected. Surfaces during the 2026-05-13 Gemma 4 27B comparison test prep. **Fix shape:** a small Settings UI surface — server profile gains an instruct-template picker (Auto / ChatML / Gemma 4 / Gemma 1-3 / Llama 3 / Mistral V3 / Mistral V7) that overrides the auto-detection per server. Natural home is the Phase 4.5 Bible Workspace (or its sibling Servers Workspace) — would land alongside the bigger settings redesign rather than retrofitting the current cramped Servers tab.

- **Sidebar's "Set POV" vs Rewrite picker's POV target — clarify in UI.** ~~Live test 2026-05-13 Test 6 surfaced UX confusion: the user set `Scene.pov = Jamie` via the sidebar BEFORE picking *"Rewrite → POV — Jamie"* in the picker, thinking the two needed to match...~~ **RESOLVED this session:** Rewrite picker entries renamed from *"POV — X"* to *"Rewrite to X's POV"* (action phrasing rather than setter); sidebar's Set POV parent item gained a tooltip explaining that it drives Continue's KNOWLEDGE-LEDGER context and doesn't affect the Rewrite menu. Live-smoke verified.

- **Tray instruction-field wraps too early.** Live test 2026-05-13 Test 5a (UI observation): the instruction text field in `GenerationTrayView` appears to wrap at a narrow width rather than using the full horizontal space of the tray. The descriptor entered for the rewriteVoice test was visible only as a few words at a time. NSTextField/auto-layout issue, possibly a missing `lineBreakMode = .byClipping` / `usesSingleLineMode` configuration or a trailing constraint not pinning to the tray's actual width. Investigate after the test session wraps; should be a small fix.

- **Extractor subject-vs-character_id mis-attribution.** Live test 2026-05-13 (Scene A, Iris/Daniel) emitted on one run a Daniel-tagged fact whose text said "his name is Cora" — the fact's grammatical subject was Cora (the wife Daniel reveals during the scene), not Daniel. The model conflated "Daniel says Cora's name" with "the fact is about Daniel". The §10.5 filters can't catch this — evidence-quote validation passes because Daniel literally says `"Cora."` in the prose, and dedup/prompt-leakage don't address subject-vs-tag confusion. On a rerun the same prose did NOT mis-attribute, so this is a sampling artifact rather than a deterministic bug; frequency unknown. Mitigations, ranked: (a) accept/reject is the v1 answer — reject the one bad suggestion, ship the rest; (b) prompt-tuning the §3.3 extraction prompt to emphasise "the fact must be a complete proposition about character_id as the grammatical subject" — moderate-risk change, could hurt recall on legitimate facts, worth piloting with more live data before shipping; (c) a subject-match filter in §10.5 — would need semantic parsing or a second LLM call, probably overkill for the frequency.

**NSFW strategic anchor — still load-bearing.** The pipeline is content-neutral by design (LOOM_NSFW.md §3), but live-testing on explicit prose hasn't happened yet. The spike numbers (LOOM_LEDGER_SPIKE §11.4 / §12.4) showed 100% recall on the two NSFW fixture scenes; production behaviour should match. The §10.5 filters are all content-neutral by construction — no filter drops a fact for content reasons, only for technical reasons (paraphrase dedup, missing evidence in prose, prompt-text leakage). Phase 4.x should still pressure-test multi-character extraction on a sex scene where both partners have agency (the spike's `03_first_night` is the closest fixture).

**Test count: 774 passing** (since 2026-05-13 sub-task 8 + #6 picker + #8 POV + #9 SDT + #10 Lorebook + #6 rewriteTense/Length + scope-discipline clause + various §15.8 fixes landed).

### 15.9 Session ledger — 2026-05-13 (Phase 4 §14.1 #6 / #8 / #9 / #10 + live-test session)

**Code shipped (~25 commits):**

- **Phase 4 §14.1 #6 — rewriteTense + rewriteLength prompt layers + the Rewrite sub-mode picker UI.** All four rewrite sub-modes (Voice/Tense/Length/POV) plus generic Rewrite now reachable from one coherent NSMenu pop-up on the tray's Rewrite button.
- **Phase 4 §14.1 #8 — rewritePOV prompt layer + `RewritePOVDescriptor.build(...)` + per-character POV entries in the picker.** Marries the rewrite family to the Phase 4 #7 knowledge ledger — `LedgerKnowledge.compute(...)` feeds structured KNOWS/DOES NOT KNOW bullets into the descriptor at click time, threading the §4.3 `KNOWLEDGE_LEDGER_HINT` slot live for the first time.
- **Phase 4 §14.1 #9 — show-don't-tell prompt layer + picker slot.** Snapshot-policy includes the mode for selection-replace recovery.
- **Phase 4 §14.1 #10 — Lorebook v1 in the Bible inspector.** New `.lorebook` category in `BibleCategory`; full character editor branches on `.lorebook` ref to add a comma-separated keys field; Constant/Keyed activation mode flips via the existing inject popup; sphiratrioth pack is now editable in-app rather than via `bible/lorebook.json`.
- **Phase 4 #7 follow-ons** that surfaced during live testing:
  - In-flight guard per scene on the extractor coordinator (the duplicate-side-call bug).
  - Auto-budget per scene-word-count (`OllamaLedgerExtractor.budgetForSceneWords`) with smart-retry-on-empty doubling `num_predict` (the deterministic length-cap empty-content bug — Ollama's JSON-Schema mode emits empty content if `num_predict` cuts off mid-array).
  - Per-filter drop logging (`{dedup=N evidence=M leakage=K}` on the `[ledger] queued` line) — needed to diagnose which §10.5 filter is doing the work across runs.
  - Reject/redo restoration covers the new rewrite sub-modes via `GenerationMode.isSelectionReplacing` predicate (was hard-coded to `.expand || .rewrite`).
- **ThinkBlockStripper handles Gemma 4 `<|channel>thought\n<channel|>` format** in addition to the Qwen `<think>...</think>` format. Both formats stripped post-finish, both with multi-line bodies and unclosed-tag preservation.
- **Scope-discipline clause** added to every rewrite-family system prompt (`.rewrite`, `.rewriteVoice`, `.rewriteTense`, `.rewriteLength`, `.rewritePOV`, `.showDontTell`) — *"Stay strictly inside the selection... do not add events, dialogue, characters, or relationship histories from outside the selection... no extension forward or backward in time"*. Addressed three §15.8 Gemma-specific over-contextualization failures (Test 6 tour-rider dialogue pulled forward, Test 7 cross-scene character + relationship invention, Test 7 forward-extension past source bounds). Pilot retest on Test 6 showed the clause cuts the failure rate dramatically (4 of 6 prior failure modes fixed); Test 7 partial improvement (cross-scene leakage gone, forward-extension still present on sparse abstract sources — see §15.8 structural-limit entry).

**Plan changes:** **Phase 4.5 — Bible Workspace** inserted between Phase 4 and Phase 5 in [`LOOM_PLAN.md`](LOOM_PLAN.md). Dedicated second NSWindow for entity management; closes the cramped-side-pane UX gap surfaced during live testing (accepted-facts examiner, full character editor, Lorebook power-user fields, suggestions queue review). Lands BEFORE Phase 5 so RAG-for-style's reference-text management UI ships in the new architecture rather than retrofitting.

**Live testing pass — Qwen3.6-27B vs Gemma 4 31B writer comparison across Tests 1–7:**

Full test plan at [`TEST_PLAN_2026-05-13.md`](TEST_PLAN_2026-05-13.md) (NSFW-focused, includes Iris/Daniel + Marisol/Jamie + Saoirse/Linus fixtures).

| Test | Qwen | Gemma 4 31B | Notes |
|------|------|-------------|-------|
| 1 Auto-budget short scene | clean | clean | sanity baseline |
| 2 Auto-budget long scene (611 words) | clean | clean | same — extractor unchanged, writer not on this path |
| 3 §10.5 filter behaviour | clean (1/23 dropped) | clean (5/24, all dedup) | per-filter logging added; variance is pure extractor sampling, all 16/25 the morning ran was also pure dedup |
| 4 POV picker + `[KNOWLEDGE-LEDGER]` layer | clean POV; bruise drifted to "neck" | clean POV; **bruise correctly on collarbone** | Gemma stronger ledger-fact pinning on Continue |
| 5a rewriteVoice | strong shift, 151% length, correct bruise | strong shift, 165% length, **drifted bruise to "above heart"** | rough tie |
| 5b rewriteTense (no-op target) | **catastrophic** (tokenization corruption + truncation + entity drift) | **clean** near-verbatim source preservation | **Gemma decisive win** |
| 5c rewriteLength 120% | verbose paraphrase, 150-185% | **sensory expansion** + interiority, 157% | **Gemma decisive win** |
| 6 rewritePOV (target=Jamie, 12 KNOWS) | localised beat inversion ("thumb on lip") | **plot invention** + bruise drift + 164% length | Qwen wins (pre-clause); **Gemma fully fixed post-scope-clause** |
| 7 showDontTell | regression to `felt X` 40% of the time | stronger shows + invented plot + character pulling | Gemma mixed (cross-scene leakage fixed by scope clause; forward-extension is structural limit on sparse sources — §15.8) |

**Strategic verdict:** User has committed to Gemma 4 31B as the preferred writer despite ~5× latency. Gemma's structural reliability + tone-quality + instruction-following on transformative tasks materially exceed Qwen's. Scope-discipline clause closed Gemma's main weakness on rewritePOV; the remaining SDT-on-sparse-sources limit is a model-class issue, not Gemma-specific. Worth a Phase 4.x slice on per-mode sampler tuning to address Qwen's rewriteTense near-copy decode trap — but since Gemma is preferred, this is lower priority.

**§15.8 grew substantially.** Notable new entries:
- **rewriteTense no-op-target failure mode** (reproducible on both writers; needs picker/handler detection).
- **Rewrite-family length-anchor drift under verbose descriptors** (both writers, both Voice + Length + SDT).
- **rewriteTense degenerate near-copy decode** (Qwen-specific; Gemma not affected — confirmed by 5b/5c comparison).
- **rewritePOV cross-character interiority leak + occasional beat inversion** (both writers; needs prompt-side or pipeline-side fix).
- **Gemma 4 31B over-contextualization family** (cross-scene character pulling, forward-extension, plot invention from elsewhere) — **mostly fixed by the scope-discipline clause this session**, residual SDT forward-extension is the structural-limit case.
- **showDontTell on sparse abstract sources is a structural limit** (documented). Targeted negative-example blacklists don't generalise across paraphrase (saved as memory).
- **Lots of UX gaps** queued: streaming-aware thinking-tag stripper, instruct-template UI override, sidebar Set POV vs Rewrite picker disambiguation, tray instruction-field early-wrap.

**Carried into the next session:**

1. **Tests 8 + 9 still never run on either writer.** Test 8 = Lorebook v1 editor live-test (the UI shipped today, never exercised). Test 9 = cross-cutting NSFW content-neutrality audit (much of it already validated by the running commentary during Tests 1–7, but the full checklist is worth a clean pass).
2. **rewriteTense no-op-target detection** at the picker/handler — the one structural failure both Qwen and Gemma share. Detect tense in selection, disable matching-tense menu options OR short-circuit at click time.
3. **Streaming-aware ThinkBlockStripper** — visible UX paper-cut now that user is committed to Gemma (which always emits the channel-thought block).
4. **Phase 4.5 Bible Workspace** — the bigger UX redesign, multi-session.
5. **Extractor coverage variance** + **subject-vs-character_id mis-attribution** stay parking-lot; haven't reproduced enough to justify a fix slice yet.

### 15.10 Session ledger — 2026-05-12 → 2026-05-13 (Phase 4 §15.10 + Phase 4.5 Bible Workspace arc)

**Test count: 880 passing** (was 774 at end of §15.9).

**Branch on `main`, pushed clean to origin** through `4a983a0`.

#### What landed (chronological by commit)

**Phase 4 §15.10 — three slices on top of the §15.9 baseline:**

- `1b1b614` — **rewriteTense no-op-target picker guard.** `SelectionTenseHeuristic` (NLTagger-driven, dialogue-aware) classifies the selection's tense; matching-tense entry in the Rewrite picker renders disabled with a tooltip + click-time short-circuit. Resolves the §15.8 entry on both-writers no-op-target failure mode (catastrophic on Qwen, milder on Gemma). +17 TestKit. See `feedback_prompt_blacklist_evasion` memory — the prompt-side fixes that we'd previously rolled back are now permanently obsoleted by the upstream picker fix.
- `9b6edac` — **streaming-aware `ThinkBlockStripper`.** State-machine that handles both Qwen `<think>...</think>` and Gemma 4 `<|channel>thought\n...\n<channel|>` formats, including token-boundary tag splits, stray `<` in prose, unclosed-block flush preservation, trailing-whitespace cleanup post-close. Threaded into the editor's `didEmitTokenNotification` observer with a separate streaming insertion-offset tracker (the coordinator's running offset counts raw tokens; we track actually-inserted length). Side-effect: tray now stays on "Thinking…" through the channel-thought block and only flips to "Streaming…" when visible prose arrives. +16 TestKit. Resolves the §15.8 streaming-tags paper cut.
- `06c7f1a` — **Rewrite-POV vs sidebar Set-POV disambiguation.** Rewrite picker entries renamed from `"POV — X"` to `"Rewrite to X's POV"` (action phrasing); sidebar Set-POV NSMenuItem gains a tooltip clarifying the distinction. Resolves the §15.8 Test-6 UX confusion entry.

**Side-fix that surfaced mid-session:**

- `d4e4dcb` — **Inspector responder-clobber on per-keystroke writeback.** Typing into the character description text view registered one keystroke at a time, then beeped. Root cause: each keystroke fired textDidChange → writeBack → session.updateCharacter → markChanged → didChangeNotification → `BibleInspectorViewController.renderDetail` tore down the whole detail editor including the NSTextView holding first responder. Fix: when the selection ref hasn't changed, refresh field values in place via `BibleDetailEditor.refreshInPlace()` instead of rebuilding the view tree. +3 TestKit (regression suite with per-mount UUID token, since ObjectIdentifier is unreliable across heap-slot recycling). Unrelated to Phase 4.5 but shipped this session.

**Phase 4.5 Bible Workspace — full five-session arc, ~3,500 LOC, WKWebView pivot away from AppKit (scoped to the workspace only):**

The full per-session ledger lives in [`LOOM_BIBLE_WORKSPACE.md`](LOOM_BIBLE_WORKSPACE.md) §11. Highlights:

- `318c266` — **Plan landed.** [`LOOM_BIBLE_WORKSPACE.md`](LOOM_BIBLE_WORKSPACE.md) authoritative doc; pivot rationale (AppKit cost ledger trigger), tech-stack choice (Vite + React + TS + Tailwind + shadcn-style primitives + Bun), session breakdown, bridge contract, rollback path. L4.5 row in [`LOOM_PLAN.md`](LOOM_PLAN.md) + §5 Phase 4.5 section updated to point at the new doc.
- `188907d` — **Session 1: WKWebView shell + bridge + read-only entity list.** AppKit shell (`BibleWorkspaceWindowController`) hosts a `WKWebView`; `BibleWorkspaceSnapshot` Codable contract; `BibleWorkspaceBridge.encodeSnapshotPush` produces a JS call with JSON inlined as object literal (U+2028/U+2029 defensively escaped); React side renders Characters + Lorebook lists. Three file:// gotchas burned through + documented in the build script: `crossorigin` attribute breaks scripts under file://, `<script type="module">` silently no-ops in WebKit on file://, classic head scripts need explicit `defer`. Bible menu → "Open Bible Workspace…" + ⌘⇧B. +17 TestKit.
- `d91a91a` — **Session 2: full character editor + JS→Swift intent path.** Every `Character` field surfaced; debounced (250ms) `patchCharacter` intent dispatch; `CharacterPatch` Codable with `apply(to:)`; controlled inputs + local draft + reset effect keyed on `character.id` only (snapshot pushes for the same character don't clobber in-flight typing). Tiny shadcn-style primitives (Input/Textarea/Select/Button) + `useDebouncedCallback` hook. Deferred React Hook Form + Zod as overkill for the schema. +20 TestKit.
- `d2c3820` — **Session 3: full lorebook editor + add/delete CRUD + NumericField.** All 13 `LorebookEntry` fields (v1 inspector surfaces 4); conditional `depth` render when `positionMode=depthN`; "+ Add entry" creates with `"Entry N"` default name (no `window.prompt` — that's a no-op in WKWebView without UIDelegate); Delete button in the editor header. `NumericField` helper fixes the controlled-numeric-input quirk where backspacing the existing `0` immediately re-anchors it. +19 TestKit.
- `01c82cb` — **Session 4: accepted-facts examiner + UUID-key snapshot fix.** Closes the §15.9 ledger-fact-audit gap. `<Tabs>` primitive on character editor (Fields | Accepted facts). `FactsExaminer` view groups facts by source scene with certainty pills + ✕ delete buttons. `ProjectSession.removeKnownFact` mutator. **Load-bearing fix**: introduced `SnapshotCharacter` projection that re-keys `Character.knownFactsBySceneId` from `[UUID: V]` to `[String: V]` before encoding — Swift's `JSONEncoder` serializes UUID-keyed dicts as flat arrays (`[uuid, value, uuid, value]`), which the web side's `Record<string, KnownFact[]>` couldn't index. Cross-origin error sanitization on file:// hid the real trace (Safari Web Inspector via `isInspectable=true` is now canonical for React-side diagnostics). +10 TestKit.
- `d1a0f8a` — **Session 5: cross-character suggestions queue + arc closeout.** `SuggestionsQueue` view (character pill, certainty pill, scene title, fact text, evidence quote, Accept/Reject buttons). New intents `.acceptSuggestion(factId)` + `.rejectSuggestion(factId)` route to the existing `AppState.{accept,reject}LedgerSuggestion` API. New `suggestionsObserver` on `AppState.ledgerSuggestionsDidChangeNotification` so reject (which doesn't mutate the session itself) still triggers a snapshot push. Entity-list header gains a prominent blue "N pending suggestion(s) →" button when count > 0. +3 TestKit.
- `4a983a0` — **Workspace respects system light/dark.** Palette moved from inline `documentElement.style.setProperty` (always wins, kept workspace dark) to `styles.css` with `:root` dark default + `@media (prefers-color-scheme: light)` override. WKWebView mirrors the macOS app's effective appearance, so System Settings → Appearance retints inline.

**Phase 4.5 arc — honest tally.**

*What the pivot bought*: every form / list / grouped-list surface in Sessions 2-5 landed in a fraction of the AppKit-equivalent time. CSS grid + Tailwind preflight + Liquid Glass CSS vars + shadcn-style primitives = consistent visuals with near-zero layout debugging. Zero macOS-26 fittingSize cascade incidents. The architectural pieces compose: `NumericField`, `Tabs`, the patch/intent pattern got reused verbatim across editors.

*What it cost*: ~30 min of file:// + cross-origin debugging across Sessions 1 + 4 (crossorigin attribute, type=module, head-script defer ordering, UUID dict keys, script-error sanitization). One contained Bun dependency (`brew install oven-sh/bun/bun`). ~170 KB JS bundle (gzipped ~54 KB) shipped inside Loom.app. Two render systems coexist; the side-pane inspector stays AppKit, the workspace is web.

**Strategic verdict**: the WKWebView pivot was decisively the right call. Validates the AppKit pivot-pressure memory's instinct — when a fix is brittle and workarounds are stacking, the alternative path can be cheaper than continuing to grind. The pivot scope (one new window) made it locally reversible at every session boundary; Session 1's exit criteria would have triggered rollback if WKWebView had fought us catastrophically, and didn't.

#### Carried into the next session

**Primary**: **Phase 5 — Style ingestion (RAG-for-style)** ([`LOOM_PLAN.md`](LOOM_PLAN.md) L5 row + §5 Phase 5 section). Chunk reference texts, embed via RPClient embeddings server, per-scene-type retrieval (action / dialogue / interiority / description) as the differentiator vs SillyTavern's generic vectorised lorebook. Loom's largest single phase; R&D risk is real per [`LOOM_RESEARCH.md`](LOOM_RESEARCH.md) §O.4. Plan for an empirical pass first; production after. The reference-text management UI lands inside the **Bible Workspace** WKWebView stack — that's why we landed Phase 4.5 first.

**Still on the parking lot from §15.9**:

- **Tests 8 + 9 still unrun**. Test 8 = Lorebook v1 editor live-test on the side-pane inspector (partially obsoleted by Phase 4.5 Session 3's full editor — but the v1 surface still exists and could be live-tested in a few minutes). Test 9 = cross-cutting NSFW content-neutrality audit.
- **SDT-on-sparse-sources structural limit** ([`HANDOFF.md`](HANDOFF.md) §15.8). Documented; targeted negative-example blacklists in prompts don't suppress the failure (memory: `feedback_prompt_blacklist_evasion`). Would need constrained decoding / positional-anchor approach at the GenerateRequest layer. Heavy.
- **Extractor coverage variance + subject-vs-character_id mis-attribution** — haven't reproduced enough to justify a fix slice.

**New parking-lot items from Phase 4.5**:

- **Confirm-before-delete dialogs.** Facts + lorebook entries delete immediately. Facts are recoverable via re-extraction (low risk). Lorebook entries are unique authored content — a confirmation prompt would be a small follow-on if mis-clicks happen in practice.
- **Side-pane inspector's per-character suggestions chip → workspace link.** Plan §7 Session 5 deliverable #3; only the workspace side landed. The AppKit chip still surfaces suggestions inline; we'd want it to link out to the workspace's Suggestions surface instead.
- **`avatarPath` field surface** in the workspace character editor (deferred per [`LOOM_BIBLE_WORKSPACE.md`](LOOM_BIBLE_WORKSPACE.md) §8.4).
- **React-side error visibility**. WKWebView's cross-origin error sanitization shows `"Script error. @ ?:?:?"` for React-render exceptions. Safari Web Inspector is the canonical diagnostic path (isInspectable is on). Long-term: wrap React render in an in-bundle try/catch that exposes errors to the inline shim, OR relax WKWebView's same-origin policy for the bundle.
- **Workspace light-mode palette refinement.** Current values were sketched against DesignTokens semantic intent without actual sampled values. May want pixel-level matching at some point.

### 15.11 Session ledger — 2026-05-13 (Phase 5 RAG-for-style spike, S1 → S7)

Empirical eval of the Phase 5 retrieval-for-style hypothesis. Authoritative writeup lives in [`LOOM_RAG_SPIKE.md`](LOOM_RAG_SPIKE.md) §1–13. Doc commits + scaffolding landed in five stages over a single session; final verdict locked the Phase 5 architecture.

#### What landed

**S1 — pure-data scaffolding** ([`ec5bb95`](Sources/LoomCore/Retrieval/Embeddings.swift)). `EmbeddingVector` + cosine (defensive zero on degenerate cases), `RagChunker` word-window splitter with overlap, `RankingMetrics` (NDCG@k binary-relevance, style-vs-topic preference index, Kendall's tau-a). 30 new TestKit tests, all hand-computed values. Lives in `Sources/LoomCore/Retrieval/`. 880 → 910.

**S2 — fixture authorship** ([`339fc02`](Tests/LoomCoreTests/Fixtures/RagSpike/fixture.json)). 12 hand-authored excerpts (4 styles × 3 topics, ~280-330 words each) + 4 query scenes (~165-205 words). **8 of 12 NSFW** per the LOOM_NSFW §3 strategic anchor — original plan had 2/12; user pushed back ("more of them need to be nsfw, that's the main purpose of this project") which reshaped the fixture composition. Style axis gives four distinct NSFW registers for free (S1 terse-physical, S2 literary, S3 subjective-interior, S4 clinical-detached). 10 new smoke tests pin grid shape, NSFW composition, word-count bounds. 910 → 920.

**Plan revision (between S2 and S3)** ([`8be8eac`](LOOM_RAG_SPIKE.md)). Pre-S3 research pass surfaced load-bearing prior art the original plan missed: three open-weights style/authorship embedders (StyleDistance Oct 2024 SOTA, Wegmann RepL4NLP 2022, LUAR EMNLP 2021), all RoBERTa-base-sized and Apple-Silicon-runnable. The §1 premise ("no widely-adopted stylistic embedding model exists") was stale. Added Path D (purpose-built style embedder, becomes likely winner) + Path E (Burrows' Delta sanity baseline, diagnostic-only); demoted Path C (writer-distillation) from "speculative win" to "alternative hypothesis." Doc-only; 202 insertions / 36 deletions. **Lesson**: when foundational R&D literature claims an open territory, verify before sinking implementation hours into workarounds.

**S3 — embedding clients + Python sidecar** ([`f34c5f7`](Tools/RagSpike/main.swift)). Pure-data response parsers for Kobold `/v1/embeddings` + Ollama `/api/embed` (10 TestKit tests, 920 → 930). Swift orchestrator `Tools/RagSpike/main.swift` with `--smoke` mode covering Paths A (nomic/Kobold), B (mxbai + bge on Ollama), C (gemma-31B GBNF descriptor → nomic). Python sidecar `Tools/RagSpike/Python/embed_offline.py` for Paths D + E (StyleDistance primary with Wegmann fallback; faststylometry-flavoured function-word z-score implemented inline via numpy). Venv + vectors.json gitignored.

Bug-hunt note worth remembering: initial smoke crashed with SIGSEGV on `String(format: "...%s...", swiftString)`. `%s` expects a C string; passing a Swift String is undefined behavior on Apple platforms. Use interpolation + `padding(toLength:)` instead. [LedgerSpike](Tools/LedgerSpike/main.swift) uses `%@` (which works) throughout — worth a sweep there as a follow-on if any `%s` slipped in.

**S4 — full corpus eval** ([`d399b3e`](LOOM_RAG_SPIKE.md)). `--corpus` mode embeds all 16 fixture items via every path, scores per §5 metrics. Path C took ~110s for 16 items (~6.9s/item via gemma-31B GBNF); A/B/D/E essentially instant. Results table + per-query breakdown landed in [`LOOM_RAG_SPIKE.md`](LOOM_RAG_SPIKE.md) §13 (~250 lines of analysis).

Headline numbers (mean NDCG@3 / preference over 4 queries):

| Path             | dim  | NDCG@3 | preference | NSFW hit | SFW hit |
|------------------|------|--------|------------|----------|---------|
| A-nomic          |  768 | 0.809  | +0.667     | 1.000    | 0.250   |
| B-mxbai          | 1024 | 0.809  | +0.583     | 1.000    | 0.250   |
| B-bge            | 1024 | 0.809  | +0.583     | 1.000    | 0.250   |
| C-descriptor     |  768 | 0.485  | +0.167     | 0.375    | 0.500   |
| **D-styledistance** |  768 | **0.883**  | **+0.833** | 0.750  | 1.000   |
| E-funcword-z     |  150 | 0.883  | +0.750     | 1.000    | 0.500   |

**S7 — finalisation** (this commit). [`LOOM_PLAN.md`](LOOM_PLAN.md) §5 Phase 5 + L5 row updated with verdict + chosen architecture; [`LOOM_RESEARCH.md`](LOOM_RESEARCH.md) §O.4 updated with the empirical data point ("no stylistic embedder exists" claim retracted). New memory entry captures the falsification of that claim for future spike scoping.

#### The verdict + chosen architecture

[§7 decision tree](LOOM_RAG_SPIKE.md) fired the **PIVOT — D wins on NDCG but shows the §3-predicted NSFW derank** branch. User picked **D + E hybrid** when offered the choice between (single-index D, simpler) vs (hybrid D + E, balanced NSFW).

Five empirical findings, in order of weight ([§13.3](LOOM_RAG_SPIKE.md)):

(a) D wins headline but margin over A/B is smaller than the §3 prior expected (~9% NDCG).
(b) **E ties D on NDCG.** 150-dim zero-dependency function-word z-score matched a 768-dim PyTorch model. Either fixture too separable via function-word frequency, or style genuinely is function-word-dominated at corpus size. Phase 5 production must re-test E on real reference texts before locking D-as-primary.
(c) **C failed below floor.** gemma-31B GBNF descriptors collapsed to default enums ("tense past, tight_third, register literary") across wildly different prose. GBNF constrains structure; the model under-distinguishes within enums. The original-plan idea of C-as-NSFW-fallback is **dead** because of this.
(d) **A/B passed NDCG by retrieving NSFW-content, not style.** Per-query inspection: Q101 top-3 = {S1-NSFW, S3-NSFW, S2-NSFW}. The §1 "topic not style" failure mode confirmed — "topic" was "NSFW status."
(e) D has ~25% NSFW derank (§3 Reddit-skew hypothesis confirmed). A/B over-retrieve NSFW. **E is the most balanced.** E is therefore the empirically-observed NSFW-parity-balanced alternative — and it's the cheapest path in the slate.

Phase 5 architecture: reference texts index in both D and E spaces. At retrieval time the system always retrieves from both and merges by normalised score (probably Reciprocal Rank Fusion — final decision at Phase 5 design lock). Always-retrieve-from-both keeps [LOOM_NSFW §3](LOOM_NSFW.md) content-neutrality intact — no NSFW classifier, no moderation gate. E is so cheap (~50 LOC of numpy, possibly portable to pure Swift in an afternoon) that the second index is essentially free.

#### What graduates from the spike into Phase 5 production

- `Sources/LoomCore/Retrieval/Embeddings.swift` — production-ready.
- `Sources/LoomCore/Retrieval/RankingMetrics.swift` — production-ready.
- `Sources/LoomCore/Retrieval/EmbeddingClients.swift` — Kobold + Ollama parsers; needs an `EmbeddingClient` protocol abstraction in Phase 5 production for Path D's Python encoder.
- `Tools/RagSpike/Python/embed_offline.py` — keep as offline benchmarker for Phase 5 production re-tests on real reference corpora.
- The fixture — keep, extend with real reference texts.
- The spike runner (`Tools/RagSpike/main.swift`) — keep as on-demand eval tool for future model swaps.

#### What did NOT graduate

- **Path C as designed.** GBNF descriptor distillation under gemma-31B collapses style diversity. If revived in Phase 5, needs schema redesign (free-form-string fields for register/lexicon; richer enums; possibly a different/larger distillation model).
- **Chunk-size sweep ({50, 150, 400} words from the original plan).** Deferred to Phase 5 production over real multi-page reference corpora. The fixture's 300-word excerpts didn't span the sweep range cleanly.

#### Carried into the next session

**Primary**: **Phase 5 production** — five scope locks at start, per [`LOOM_PLAN.md`](LOOM_PLAN.md) §5 Phase 5:

1. StyleDistance deployment decision: bundled venv vs MLX port.
2. E (function-word z-score) Swift port: ~50 LOC, vendor `embed_offline.py`'s `embed_path_e`.
3. Reference-text entity type in the Bible Workspace (mirrors Phase 4.5 patterns).
4. Hybrid retrieval merge policy (likely RRF).
5. Per-scene-type retrieval pillar (the descriptor schema's `modality` slot is salvageable for ingest-time tagging even though full Path C distillation failed).

**Still on the parking lot**: unchanged from §15.10 — Tests 8 + 9, SDT structural limit, extractor coverage variance, the four Phase 4.5 follow-ons.

**Risk to flag at Phase 5 design lock**: §13.3(b) caveat. If E doesn't tie D on real reference texts (fixture-leakage hypothesis), the hybrid degrades to D-only and the Python-sidecar production cost is real. Worth running an E-only Phase 5 production benchmark over the user's first real reference corpus *before* committing to the StyleDistance deployment work.

933/933 tests passing throughout the spike (no regressions across S1-S7). The spike's TDD discipline held — every Swift module has pure-data tests; network glue and orchestration are integration-test territory and that's intentional.

### 15.12 Session ledger — 2026-05-13 (Phase 5 production, all five scope-locks + C step)

Big session. Phase 5 went from "five empirical scope-locks closed in spike form" to "production retrieval engine end-to-end, pipeline wired into the writer prompt, one app-level injection point away from a runnable demo." 16 commits, 1075 tests passing.

#### What landed (chronological by commit)

**Phase 5 sub-spike: StyleDistance MLX conversion validity** ([`6e50328`](LOOM_MLX_PORT_SPIKE.md))

User confirmed the spike doc proposal (Paths D + E, RRF k=10, hybrid index). Picked D + E hybrid over single-D. Pre-implementation research found StyleDistance had no direct MLX port but the `mlx-embeddings` Python tool handles RoBERTa-base architecturally (XLM-RoBERTa class works for plain RoBERTa once `model_type` is patched). Conversion succeeded; both numerical (cosine 1.000000 across all 16 fixture items vs PyTorch baseline) and behavioural (4 of 4 identical top-3 rankings, zero NDCG/preference drift) gates passed. Phase 5 production scope-lock #1 closed against MLX.

**Phase 5 scope-lock #2: Path E Swift port** ([`0abc34d`](Sources/LoomCore/Retrieval/FuncwordZEmbedder.swift))

Pure-Swift port of `Tools/RagSpike/Python/embed_offline.py::embed_path_e`. ASCII-only `[a-z]+` tokenisation, top-N most-frequent tokens by global frequency with first-encountered tie-break (matches Python `Counter.most_common`), per-text rel-freq over the top-N vocab, z-score per dim across the corpus with `<1e-9` std guard. 13 TestKit tests including a hand-computed symmetric [a,b,c] corpus and a cross-check via `RagSpike --funcword-z-dump`: Swift output matches Python at cosine 1.000000, max element diff 1e-6 across all 16 fixture items. Pure-Swift, no external deps.

**Phase 5 scope-lock #3: reference-text storage** ([`d6d6e51`](Sources/LoomCore/Storage/ReferenceStorage.swift))

`<project>/references/<id>.md` (YAML frontmatter + body, mirrors `scenes/<id>.md`) + `<id>.index` (JSON sidecar with per-chunk D + E vectors). `ReferenceText` / `ReferenceFile` (encode/decode) / `ReferenceStorage` (save/load/delete/list). The index schema includes optional `dVec`, `eVec`, and `modality` per chunk so pre-embed and partial-embed states are model-able without migrations. `schemaVersion: 1` anchored for future forward-load tests. `ProjectStorage.createNewProject` scaffolds `references/` alongside `scenes/` and `generation-log/` from day one. 29 new TestKit tests.

**Phase 5 scope-lock #4: hybrid retrieval merge** ([`894003f`](Sources/LoomCore/Retrieval/RankingMetrics.swift))

Pre-implementation research pass surveyed RRF / DBSF / convex-combination / cross-encoder rerank prior art. The "two complementary dense embedders both targeting style" niche turned out to be under-served in the literature (dense+sparse is the standard hybrid case); the closest practitioner advice supports RRF when score distributions are incommensurable (our situation). Implementation: `RankingMetrics.reciprocalRankFusion(rankings:k:weights:)`, 30 LOC. Defaults: `k=10` (not Cormack's 60 — Loom retrieves top-3 over ~50-chunk small corpora, not TREC top-1000), equal weights (D + E tie on NDCG in the spike fixture; no learned weights to overfit on 16 decisions). Empirically validated against the [LOOM_RAG_SPIKE](LOOM_RAG_SPIKE.md) §13.1 fixture via `RagSpike --hybrid`: hybrid NDCG@3 0.926 vs individual 0.883, preference +0.917 vs +0.833 / +0.750, NSFW hit 0.875 vs D-alone 0.750. Strictly Pareto-better. 9 new TestKit tests including hand-computed score-formula verification.

**Phase 5 scope-lock #5: narrative-mode tagging** ([`ed60eb7`](Sources/LoomCore/Retrieval/NarrativeModeClassifier.swift))

User chose Option B (LLM-classified at ingest) over A/C/D. Pre-spike research surfaced two load-bearing changes before any code: (1) extend the taxonomy from LOOM_RESEARCH §O.4's four modes to **six** — added `summary` (Marshall 1998 / Card 1999 — scene-vs-summary pace axis) and `mixed` (gold's noise floor + classifier opt-out); (2) acceptance bar of 70% not 90% (Zehe et al. EACL 2021 γ ≈ 0.7 IAA ceiling). 52-chunk hand-labeled gold set: 32 re-chunked from the RAG fixture + 20 hand-authored targeting summary + edge cases. NSFW 56%. Tested three configs: heuristic 55.8% (below floor; 100%/87.5% precision/recall on dialogue), zero-shot LLM **73.1%** (above floor; dialogue recall weak at 37%), 4-shot LLM 51.9% with 31.7% NSFW parity gap (DROPPED — violates spec). Verdict: PIVOT to two-pass hybrid (`NarrativeModeClassifier`) — heuristic dialogue-gate first (100% precision, 87.5% recall), zero-shot LLM for the residual. Projected hybrid accuracy ~80%. Three surprises documented: (a) few-shot backfired ~21 accuracy points + violated NSFW parity (likely GBNF + in-context label exposure interaction), (b) zero-shot gemma-31B exceeds human IAA ceiling, (c) heuristic dialogue-gate decisively beats LLM dialogue recall.

**Phase 5 production B: ingest orchestrator** ([`bd1d7e6`](Sources/LoomCore/Retrieval/ReferenceIngestPipeline.swift))

`ReferenceIngestPipeline` composes all five scope-locks. Two-pass design: `chunkAndEmbedD(referenceId:)` for per-reference (load .md → chunk → classify modality → embed via injected D `EmbeddingClient` → write sidecar) and `refitAllEVectors()` for project-wide (gather every chunk across every reference → fit FuncwordZ on the full corpus → re-transform → update every sidecar). Split exists because Path E is corpus-relative; adding a new reference shifts the distribution and requires re-transforming every existing reference. `EmbeddingClient` protocol abstraction lets production wrap MLX/venv/whatever; tests use a stub. 10 new TestKit tests.

**Phase 5 production: RetrievalService** ([`024e1c2`](Sources/LoomCore/Retrieval/RetrievalService.swift))

Mirror of ReferenceIngestPipeline on the query side. Reads `.index` sidecars; runs Path D embed via injected client + per-call FuncwordZ refit-and-transform; per-path rank by cosine; RRF merge with the §13.8 lock (k=10, equal weights); returns top-K `StyleExemplar` with full provenance metadata. Graceful degradation: D embed nil → E-only; no eVec stored → D-only; both fail → empty result. `.mixed` modality filter is a no-op (the "classifier unsure" output shouldn't be preferentially retrieved). 8 new TestKit tests.

**Phase 5 production: KoboldNarrativeModeClassifier** ([`873432f`](Sources/LoomCore/Retrieval/KoboldNarrativeModeClassifier.swift))

Pure-data Kobold ↔ NarrativeMode wiring. Mirrors `KoboldEmbeddingsRequest/Response` pattern. Flat-enum GBNF (`root ::= "action" | "dialogue" | ...`), zero-shot prompt with 6-category gloss, low-temperature + tight max_length sampling per LOOM_NARRATIVE_MODE_SPIKE §10 verdict. `makeClosure(baseURL:)` returns a synchronous `(String) -> NarrativeMode?` closure suitable for `ReferenceIngestPipeline.modalityLLM` (URLSession + DispatchSemaphore; blocking; must run off-main). 9 new TestKit tests.

**MLX → venv pivot** ([`217f1ef`](Sources/LoomCore/Retrieval/PythonStyleDistanceClient.swift))

Wrote a Swift `MLXStyleDistanceClient` against `ml-explore/mlx-swift-lm` per the §11 research. Compiled clean. Failed at runtime with `MLX error: Failed to load the default metallib`. Root cause documented in mlx-swift's own README: "SwiftPM (command line) cannot build the Metal shaders so the ultimate build has to be done via Xcode." User's machine has CLT only, no full Xcode. Disk check: 87% full (29 GB free / 228 GB total) — Xcode's ~15-20 GB minimal install was infeasible without significant cleanup.

User pivoted to bundled-venv. Implementation: a long-lived Python subprocess (`Tools/RagSpike/Python/embed_subprocess.py` — loads StyleDistance once, serves stdin/stdout JSON-line protocol) wrapped by `PythonStyleDistanceClient`. Subprocess is parent's child — dies automatically when stdin closes; no daemon, no port management, no separate code-signing pipeline for a launcher. End-to-end validated: cosine 1.000000 against canonical Python baseline. ~7.65s cold start + 0.05-0.2s per warm embed. Reuses existing `Tools/RagSpike/Python/.venv`; bundling Python + venv into Loom.app is a Phase 5.5 deployment task. 9 new TestKit tests for the wire-format. LOOM_MLX_PORT_SPIKE §12 documents the full pivot rationale + re-test path if Xcode ever arrives.

**Phase 5 production C: writer-prompt integration** ([`df11e9f`](Sources/LoomCore/Generation/StyleExemplarsLayer.swift), [`62834e3`](Sources/LoomCore/Generation/GenerationCoordinator.swift))

Step 1: `StyleExemplarsLayer.format(_:)` produces a `[STYLE EXEMPLARS] ... [END]` block with per-exemplar reference name + modality + verbatim text + load-bearing voice-cues-not-content guidance (counter to the LOOM_RAG_SPIKE §13.3(d) plagiarism risk when retrieval surfaces same-NSFW-vocabulary chunks). `PromptContext.styleExemplars: [StyleExemplar]` field added, default empty (backwards compat). PromptBuilder appends a `fewShotStyleExample` layer below cache, after bible/lorebook/knowledge layers, before recent-prose, eviction priority 30 (nice-to-have; budget pressure drops it first). 13 new TestKit tests.

Step 2: `RetrievalQueryBuilder.queryText(for:)` extracts query text per-mode (`.continueProse` → last N words before cursor; selection-modes → selected text; `.brainstorm`/`.critique`/`.bridge`/`.describe`/`.nameSuggest` → nil). `GenerationCoordinator.styleRetriever: ((String) -> [StyleExemplar])?` optional closure dep. When set, `start()` extracts the query, blocks on retrieval, threads `styleExemplars` into PromptContext. Default nil preserves pre-Phase-5 behaviour exactly. 10 new TestKit tests for the query builder.

#### What Phase 5 production has now

**Architecturally complete.** All five spike scope-locks have production conformers; the ingest pipeline + retrieval service + writer-prompt integration are all wired end-to-end.

```
ingest:    ReferenceText.md → RagChunker → NarrativeModeClassifier (heuristic + Kobold LLM)
                                          → PythonStyleDistanceClient (D)
                                          → ReferenceTextIndex.json sidecar
                                          → FuncwordZEmbedder.refitAllEVectors (project-wide E)

retrieve:  query → PythonStyleDistanceClient (D) + FuncwordZEmbedder.transform (E)
                  → per-path rank-by-cosine
                  → RankingMetrics.reciprocalRankFusion (RRF k=10)
                  → top-K StyleExemplar with provenance

generate:  GenerationCoordinator.start
              → RetrievalQueryBuilder.queryText (per-mode)
              → styleRetriever closure (RetrievalService.retrieve)
              → PromptContext.styleExemplars
              → PromptBuilder ([STYLE EXEMPLARS] layer)
              → Kobold gemma-31B writer
```

Every step is TDD'd at the pure-data layer; integration is validated end-to-end via `Tools/RagSpike` subcommands.

#### What's MISSING for a runnable demo

**The app-level injection.** Nothing currently *creates* a `RetrievalService` per project + *injects* it into the coordinator's `styleRetriever`. Expected location: `AppState` (or somewhere in the project-open lifecycle). ~20-30 LOC. Probably:

```swift
// Pseudo-code
extension AppState {
    func styleRetriever(for project: ProjectSession) -> (String) -> [StyleExemplar] {
        let pythonExec = URL(fileURLWithPath: ".../Tools/RagSpike/Python/.venv/bin/python3")
        let script = URL(fileURLWithPath: ".../Tools/RagSpike/Python/embed_subprocess.py")
        let d = PythonStyleDistanceClient(...)
        let service = RetrievalService(projectURL: project.projectURL, dClient: d)
        return { query in
            (try? service.retrieve(query: query, topK: 3)) ?? []
        }
    }
}

// At coordinator construction:
coordinator.styleRetriever = AppState.shared.styleRetriever(for: session)
```

This is small enough to do in a follow-on session start; documenting it as **the** primary entry point.

**No reference texts in the UI.** Phase 5 production work A — Bible Workspace surface for managing reference texts — has not started. Today the only way to add a reference text to a project is to write `references/<uuid>.md` directly on disk. The Workspace surface would mirror Phase 4.5 Sessions 2-5 patterns: snapshot kind + view + intent dispatch + storage hookup.

**Reference-text ingest UX.** Once references exist, the user needs a way to trigger `ReferenceIngestPipeline.chunkAndEmbedD(referenceId:)` and `refitAllEVectors()`. Could be an explicit "ingest" button per reference, or implicit on save. Subprocess cold-start is ~7.65s; UI needs to surface progress.

#### Phase 5.5 deployment hardening (deferred)

These are concerns for when Loom ships to other users, not blockers for self-use:

- **Bundle Python + venv into `Loom.app/Contents/Resources/Python/`** (~1 GB inside .app, no user setup). Today the spike reuses `Tools/RagSpike/Python/.venv`.
- **ML-native-lib code-signing** for hardened-runtime + notarisation. ~1 day of build.sh pipeline work.
- **4-bit quantisation** of StyleDistance weights (242 MB fp16 → ~125 MB) — same Swift API, weight-file swap.
- **MLX re-test path** if Xcode is installed later. Restore from git (LoomMLX target was deleted in the pivot commit; predecessor commit `873432f` had it). Documented in LOOM_MLX_PORT_SPIKE §12.5.

#### Carried into the next session

**Primary**: **App-level RetrievalService injection** (small) + **A — Bible Workspace reference-text surface** (mirrors Phase 4.5 patterns, ~half-day to ~full session).

**Secondary** (Phase 5 cleanup):
- Reference-text ingest UX in the workspace (button + progress).
- LOOM_PLAN.md: add Phase 5 production sub-items to the inventory table.

**Still on the parking lot** (unchanged from §15.11):
- Tests 8 + 9 unrun.
- SDT structural limit.
- Extractor coverage variance.
- The four Phase 4.5 follow-ons.

**New parking-lot from this session**:
- `.app` bundle Phase 5.5 work (Python + venv bundling, ML-native-lib code-signing).
- MLX re-test if Xcode is ever installed.
- The MLX research-verification lesson: **research agents can verify library state but cannot verify local toolchain state**. Worth a memory note (added this session).

933 → 1075 tests passing across the Phase 5 production arc. The TDD discipline held — every Swift module has pure-data tests; subprocess management, MLX runtime, network glue, and orchestration are integration-test territory and that's intentional.

### 15.13 Session ledger — 2026-05-13 (Phase 5 production close-out A1+A2 + Phase 7 design lock + Phase 7.a spike)

This session shipped three discrete arcs:

**1. Phase 5 production close-out** — the two remaining items from §15.12's punchlist:

- **A1** (`964f242`) — `AppState.styleRetriever()` closure injection into `GenerationCoordinator`. Lazy `PythonStyleDistanceClient` (subprocess spawns on first `embed`, ~7.65s cold start), explicit shutdown on project switch (release service → deinit closes stdin → subprocess exits). 4 new tests; full Phase 5 retrieval pipeline now active for any project with ingested references.
- **A2.1** (`cd9a476`) Swift side — Bible Workspace References entity. `ReferencePatch`, `SnapshotReference`, `references: [SnapshotReference]` snapshot field, 4 intent cases (`createReference` / `patchReference` / `deleteReference` / `ingestReference`), `ProjectSession` reference proxies, `BibleWorkspaceWindowController` dispatch + snapshot push wiring, `AppState.ingestReference` background-queue pipeline run + finish notification. 19 new tests.
- **A2.2** (`3081579`) React side — `SnapshotReference` + `ReferencePatch` TS types, References section in `EntityList.tsx` with chunk-count badge + nsfw chip + word count, `ReferenceEditor.tsx` with name / NSFW / body fields + Ingest / Re-ingest / Delete header actions, `App.tsx` reference Selection branch + intent dispatch. Smoke-tested via Vite-dev server + injected fake snapshot (preview tool); list renders, editor opens, Ingest fires `{kind:"ingestReference",id}` intent, NSFW toggle fires `{kind:"patchReference",id,patch:{nsfw:true}}` intent — both round-trip correctly through Swift wire format.

**2. Phase 7 design lock** (`c3a8f87`) — Scene-Template Generation feature. Major-feature-win candidate: ingest a scene-sized prose chunk as a *template*, then generate a new scene preserving its structure, pacing, and modality flow but with new characters and surface content. Backed by extensive 2026-05-13 prior-art research (academic + commercial + technical + in-codebase, 4 parallel agents). Key research finding: **no current tool ships a "scene-as-structural-blueprint" primitive** distinct from outline-down planning (Sudowrite Story Engine, NovelCrafter Codex) or voice-only style matching (Sudowrite Match-My-Style — 2k cap; NovelAI Modules — defunct Oct 2024). The market third row is empty. Doc: [`LOOM_SCENE_TEMPLATE.md`](LOOM_SCENE_TEMPLATE.md) (532 lines). LOOM_PLAN.md §1 / §4 / §5 updated.

**3. Phase 7.a spike — empirical validation pass** — three sub-rows landed:

- **7.a.1** (`31aeb5a`) Extraction quality. 5 hand-authored fixtures (dialogue/interiority/description/action/summary, 450–600w each); CLI runner `swift run SceneTemplateSpike --extract-all` hits Ollama gemma4_2b with GBNF-constrained schema; Markdown reports + hand-grading. Verdict SHIP to 7.a.2: STRAP content stripping (D4) perfect on 5/5 fixtures (zero name leakage); schema decoding 5/5 clean; modality match 76% / 43% / 83% / 38% / 0% (interiority + summary reproduce the Phase 5 narrative-mode floor). 8 new pure-data tests.
- **7.a.2** (`5d2a3e2`) Generation quality. 3 fixtures, deliberately-distant cast mappings (tech-office IP / abandoned-shipyard / flooded-data-centre). Pass B per-beat loop, 5 new tests. **31/31 beats zero source-character leakage** (D4 confirmed under generation pressure). Cast substitution renders cleanly. BUT 6/31 empty beats from `[` stop sequence + model echoing future-beat enumeration verbatim + `***` scene-break emission. Voice transfer weak (gemma's default register dominates in both arms).
- **7.a.3** (`7f5b219`) Long-exemplar ablation. A/B on 2 fixtures: template included (Arm A) vs skeleton-only (Arm B). **Tripto 2025 hypothesis NOT reproduced.** Arm A wins on words generated, empty-beat rate, modality match across both fixtures, AND pacing fidelity on fixture 03. Template prose acts as task anchor not style donor. Voice transfer weak in both arms — not a Tripto effect. **v2 voice-weight dial DEFERRED.** D3 (template as first-class slot) empirically confirmed across 2 fixtures × 2 arms × 18 beats. 2 new pure-data tests.

**Phase 7.a complete. SHIP to 7.b production.** 6-item mandatory prompt-revision punchlist queued for 7.b:

1. Hide beats N+1..M from the prompt (model echoes future-beat enumeration verbatim).
2. Remove `[` prefix from stop sequences (catches `[silence]` openings).
3. Retry-on-empty.
4. Drop `pacingStats` from Pass A schema; compute from source.
5. Rename `tensionDelta` → `beatTensionChange`.
6. Investigate explicit voice-descriptor injection as v2 voice-transfer mechanism (instead of v2 voice-weight dial).

Test count: 1075 → 1116 across this session's arcs.

#### Pending live-app smoke tests (carried into the future)

This session's work has been verified at the test-suite + spike-runner level (1116/1116 tests green; spike CLI hits live extractor + writer servers). The following paths have **NOT** been driven end-to-end inside the actual `Loom.app`. Each is a known-good-on-paper-but-unverified-in-the-GUI flow that needs a real user-driven exercise before being declared shipped:

1. **A1 — full retrieval pipeline in the running app.** Open the app → create or open a project → Bible Workspace → References → add a reference → click Ingest → wait for subprocess cold start (~7.65s) → confirm the index sidecar appears on disk → write a scene → trigger Continue or Expand → watch debug log for `[gen] style-retrieval: N exemplars (Xms)` and `[ingest] completed id=...`. **Without this run, we don't know the Bible Workspace ingest button actually fires the production pipeline + that the writer prompt actually receives style exemplars.**
2. **A2.2 — React UI in the real WKWebView.** The dev-server smoke (Vite + injected snapshot) confirms rendering + intent wire format, but the production WKWebView path through `webView(_:didFinish:)` snapshot push timing is unchanged from Phase 4.5 — low risk but worth confirming.
3. **A2.1 — `AppState.ingestReference` end-to-end.** Background-queue pipeline run + `referenceIngestDidFinishNotification` posting. Reads the snapshot back from disk on completion. Not exercised against the writer-server-side Kobold modality classifier in any test.
4. **Phase 5 retrieval cold-start UX.** The 7.65s cold-start latency was characterised in the Phase 5 spike, but no UX surface signals it. First-generation in a project with references should show some "loading retrieval…" feedback; today it just sits silent for ~8s on first call.
5. **Phase 7 Scene-Template Generation** is not yet integrated into `Loom.app` at all. The spike runner stays as a CLI tool. Phase 7.b is where production wiring lands.

#### Carried into the next session

Phase 7.b production v1. Inherits the 6-item prompt-revision punchlist from §15.13 above. Anticipated scope (mirrors §15.12 Phase 5 production discipline):

- 7.b.1: `TemplateScene` entity + `TemplateSceneStorage` (mirrors `ReferenceText`/`ReferenceStorage`).
- 7.b.2: `BeatExtractionPipeline` (mirrors `ReferenceIngestPipeline`).
- 7.b.3: `.generateFromTemplate` mode in `GenerationMode` + `PromptBuilder` branches.
- 7.b.4: Per-beat generation loop in `GenerationCoordinator`.
- 7.b.5: Bible Workspace Template Scenes surface (mirrors Phase 5 A2 References).
- 7.b.6: In-editor flow (generation tray entry + inline picker).
- 7.b.7: Empirical validation pass (3 templates × 3 cast mappings, hand-grade).

### 15.14 Session ledger — 2026-05-13 (Phase 7 production v1 + 7.a.4 voice-descriptor followup)

This session shipped the remaining Phase 7.b production architecture (5 sub-rows) plus an unplanned 7.a.4 spike that addressed §7.a.3's weakest finding.

**Phase 7.b production v1 — all sub-rows landed:**

- **7.b.1 + 7.b.2** (`05b4f99`) — prompt-revision punchlist items 1, 4, 5 from §7.a applied to pure-data layer (hide-future-beats, drop pacingStats, rename tensionDelta→beatTensionChange); `TemplateScene` entity + `TemplateSceneFile` + `TemplateSceneStorage` mirroring Phase 5 A2 References pattern; `BeatExtractionPipeline` with async-callback `BeatExtractor` protocol + tests using deferred-completion stubs. 13 new tests.
- **7.b.3** (`f84f254`) — `OllamaBeatExtractor` production wrapper mirroring `OllamaLedgerExtractor` (scaled num_predict, retry-on-empty, strong-self capture). Spike runner refactored to use it via semaphore wrap — confirmed parity. `AppState.extractTemplateScene(id:)` background-queue entry point mirroring `ingestReference`. 5 new tests with snapshot-then-clear-then-fire stub pattern (fixed a latent test-stub bug where `removeAll()` dropped retry completions).
- **7.b.4** (`b75474c`) — `TemplateGenerationCoordinator`. Per-beat loop, M sequential writer calls via injected `KoboldGenerating`, prose accumulated in rolling buffer, each beat emitted as one `didEmitToken` with the same userInfo shape as `GenerationCoordinator` (editor's existing token-inserter handles it verbatim). Punchlist items 2 + 3 (drop bare `[` stop, retry-on-empty + `***`-only detection). 7 new tests.
- **7.b.5** (`3fa6cb0`) — Bible Workspace surface for Template Scenes. Swift: `TemplateScenePatch`, `SnapshotTemplateScene`, snapshot field, 4 intent cases, `ProjectSession` proxies, `BibleWorkspaceWindowController` dispatch. React: TS types, EntityList Template Scenes section with beat-count badge, `TemplateSceneEditor.tsx`, `App.tsx` route. Smoke-tested via Vite preview tool — intents round-trip cleanly through `BibleWorkspaceBridge.decodeIntent`. 18 new tests.
- **7.b.6** (`510c1f5`) — EditorViewController owns `TemplateGenerationCoordinator` parallel to its existing `GenerationCoordinator`; 3 parallel observers share insertion logic (same userInfo shape by design). `requestStartTemplateGenerationNotification` trigger channel. `startTemplateGeneration(templateId:castMapping:)` public method. AppDelegate Bible menu → "Write Scene From Template…" with NSAlert + NSStackView accessory containing NSPopUpButton + cast-mapping NSTextField.

**Unplanned 7.a.4 spike — voice descriptor:**

- (`254e462`) `VoiceDescriptor` struct (5 fields: 3 enums + register + bullets). Pass A schema now requires it. Pass B prompt injects `[VOICE TARGET]` block at recency when present. Empirical A/B on fixtures 01 + 03 via `--ablate-voice` subcommand: voice descriptor measurably moves prose toward target style (fixture 01 mean sentence 5.7w vs 7.6w baseline; fixture 03 mean 11.3w vs 19.6w baseline) but increases empty-beat rate (35% vs 13% on fixture 01). Verdict: SHIP with documented empty-beat caveat. 9 new tests. Full writeup in [`LOOM_SCENE_TEMPLATE_SPIKE.md`](LOOM_SCENE_TEMPLATE_SPIKE.md) §4.

**Phase 7 commit chain on top of `838292d`:**

| # | Commit | Slice |
|---|---|---|
| 1 | `c3a8f87` | Phase 7 design lock — `LOOM_SCENE_TEMPLATE.md` (532 LOC) |
| 2 | `31aeb5a` | 7.a.1 extraction-quality spike (5 fixtures, hand-graded) |
| 3 | `5d2a3e2` | 7.a.2 generation-quality spike (3 fixtures × Pass B) |
| 4 | `7f5b219` | 7.a.3 long-exemplar ablation (Tripto 2025 NOT reproduced; D3 confirmed) |
| 5 | `05b4f99` | 7.b prep + TemplateScene entity + BeatExtractionPipeline |
| 6 | `f84f254` | 7.b.3 OllamaBeatExtractor + AppState.extractTemplateScene |
| 7 | `b75474c` | 7.b.4 TemplateGenerationCoordinator |
| 8 | `3fa6cb0` | 7.b.5 Bible Workspace Template Scenes (Swift + React) |
| 9 | `510c1f5` | 7.b.6 In-editor trigger (menu + NSAlert picker) |
| 10 | `254e462` | 7.a.4 voice-descriptor extraction + injection |

Test count: 1161 → 1170 across this session's arcs. Cumulative for the multi-session day: 1075 → 1170 (+95 tests).

#### Updated pending live-app smoke tests

The §15.13 list carries forward, augmented with Phase 7 production wiring:

**Phase 5 carry-over (unchanged from §15.13):**
1. A1 — full retrieval pipeline in the running app
2. A2.2 — React UI in the real WKWebView (not just Vite-dev preview)
3. A2.1 — `AppState.ingestReference` end-to-end
4. Phase 5 retrieval cold-start UX surfacing

**Phase 7 production wiring — NEW:**
5. **Template scene extraction in the running app.** Bible Workspace → add a Template Scene → paste prose → click Extract → wait ~40–60s → confirm "N beats" badge appears in the list view + voice descriptor present in the on-disk `.beats.json` (peek with `jq` if needed).
6. **In-editor template generation.** Editor with cursor placed → Bible menu → "Write Scene From Template…" → pick template + type cast → click Generate → confirm beats accumulate at cursor over ~30–90s. Watch debug log for `[template-gen] beat N/M` lines + the `[gen] style-retrieval` lines if the project also has references ingested (the Phase 5 retrieval pipeline composes with template generation on the same generation event).
7. **Voice-descriptor end-to-end.** Pick a clearly-voiced template (e.g. Hemingway-clipped). Confirm prose output IS in that voice (subjective) AND that Pass A's `voiceDescriptor` in the .beats.json sidecar matches your read of the source.
8. **Cancel mid-generation.** Esc / ⌘. during a template generation → confirm in-flight beat completes (KoboldGenerating doesn't expose `cancel()`) but subsequent beats don't fire. `isGeneratingForTesting` returns false after.
9. **No-template gate.** Open the menu with no extracted templates → confirm the "no extracted templates available" alert fires.
10. **Concurrent-generation gate.** Trigger a Continue while a template generation is in flight (or vice versa) → confirm the second is rejected (`startTemplateGeneration` no-ops when either coordinator is busy).

The §15.13 + §15.14 smoke-test queue is now the single coherent live-app validation pass that gates Phase 7's "actually ships" claim.

#### Carried into the next session

Either (a) you-driven empirical validation pass against the live app, OR (b) more pre-validation polish:

- ~~**TemplateGenerationCoordinator generation-log entry on finish**~~ — landed `434da8f`. Every successful template gen now writes a `GenerationLogEntry` (mode = `.continueProse`, with `templateGenerationInfo` side-table carrying template/cast/beat/voice metadata). Per-beat prompts concatenated into the entry's `fullPrompt` with `=== BEAT N ===` separators.
- **Section/Field layout primitives hoist** — Character/Lorebook/Reference/TemplateScene editors inline identical Section + Field components. With this 4th user, hoisting into `web/bible-workspace/src/components/EditorLayout.tsx` is now overdue.
- **Cancel-task improvement** — `KoboldGenerating` doesn't expose `cancel()`. Adding it (or a parallel cancellable channel) would let `TemplateGenerationCoordinator.cancel()` abort the in-flight beat's URLSession task, not just prevent subsequent beats.
- **Punchlist item 7 (added in §4.6)** — drop the example bullets from `BeatExtraction.buildExtractionPrompt` to test whether voice-descriptor `distinctiveTechniques` are model-invented or prompt-echo on fixtures where the examples don't fit. Cheap to test.
- **History tab rendering of template gens** — the `GenerationLogEntry` now carries `templateGenerationInfo`, but `HistoryInspectorViewController` still renders the entry as "Continue" (since mode is `.continueProse`). The data is on disk; the UI just doesn't pull from the new side-table yet. Small follow-up: add a "Template: {name}" subheader when `templateGenerationInfo != nil`.

**Architecturally complete.** Phase 7's design — Pass A extraction with structured voice fingerprint, Pass B per-beat generation with template-as-anchor + voice-as-positive-constraint + STRAP-stripped skeleton — is fully in production code. The live-app pass is the next gating step.

### 15.15 Session ledger — 2026-05-14 (Phase 8.a + 8.b — Unified Scene Exemplar)

Single-session arc from "Phase 8 design proposal, not yet locked" to "Phase 8.b code complete + ready for live smoke." See [`LOOM_SCENE_EXEMPLAR.md`](LOOM_SCENE_EXEMPLAR.md) for the locked design, [`LOOM_SCENE_EXEMPLAR_RESEARCH.md`](LOOM_SCENE_EXEMPLAR_RESEARCH.md) for the §6.6 audit, [`LOOM_SCENE_EXEMPLAR_SPIKE.md`](LOOM_SCENE_EXEMPLAR_SPIKE.md) for the empirical findings.

#### Phase 8.a — design lock

1. **§6.6 prior-art + embedder audit** (19 cited 2024-2026 sources): no prior-art surfaced that obsoletes the unified-exemplar concept. iBERT (the audit's primary additional candidate) turned out paper-only — April 2026 release slipped; HF user has 0 public models. Substituted with `AnnaWegmann/Style-Embedding` (the SBERT baseline iBERT positions against on STEL) + added LUAR as a predicted negative control.
2. **20 hand-authored fixtures** at `Tools/SceneExemplarSpike/fixtures/` — 10 NSFW × 5 register axes + 10 SFW × 5 matched style axes. ~400 words each.
3. **§6.1 4-candidate embedder probe** at `Tools/SceneExemplarSpike/` (Swift runner + parameterized `embed_st.py` over the bundled venv). `style_axis` separation:
   - **Wegmann +0.285** ← winner
   - LUAR +0.173 (predicted-failure framing was partially wrong)
   - mxbai +0.162 (topical baseline)
   - **StyleDistance +0.086** ← Phase 5 incumbent, lost to all three alternatives including the topical baseline. NSFW-only: Wegmann +0.183 / StyleDistance +0.048.
4. **Pass-A on NSFW smoke**: gemma4_2b extracts cleanly across all 5 NSFW registers when given a retry. ~30% single-attempt JSON-parse failure rate — sampling, not refusal (gemma4_2b is fully uncensored). Flagged for a Phase 8.b.x follow-up: extend `OllamaBeatExtractor.callWithRetry` to cover `noJSONObjectFound`.
5. **D-decisions all locked**: D4 = Wegmann (empirical); D5 = per-beat retrieval default; D6 = beat-aligned chunks with sentence-window fallback; D7 = user-controllable "imitate content" toggle, default-off; D8 = "Scene Exemplars" rename + soft-merge per §5.1 Option C.

#### Phase 5 retrieval migration (mid-arc)

The §6.1 result motivated migrating Phase 5 retrieval from StyleDistance to Wegmann in the same session. `PythonStyleDistanceClient` → `PythonEmbeddingClient` (parameterized via `--model`); `embed_subprocess.py` deleted in favour of one `embed_st.py` that serves production + the spike. Existing References on disk are now stale (`ModelFingerprint.id` mismatch) — user re-ingests via the new Scene Exemplar pane (or the legacy References pane) to refresh `.index` sidecars under Wegmann.

#### Phase 8.b — production code

End-to-end "Write Scene From Template" now uses per-beat retrieval, beat-aware filtering, and an optional "imitate content" toggle:

- **8.b.3** `BeatGeneration.buildBeatPrompt` accepts `styleExemplars: [StyleExemplar]` (default empty preserves Phase 7); renders `[STYLE EXEMPLARS]` via `StyleExemplarsLayer` immediately before `[INSTRUCTION]`.
- **8.b.4** `BeatRetrievalQuery.build` (pure-data) produces per-beat queries from beat modality+function+summary, cast mapping, last-prior-sentence anchor. `TemplateGenerationCoordinator` accepts a `styleRetriever` closure called once per beat. `EditorViewController` wires `AppState.styleRetriever()` at instantiation.
- **8.b.5** Closure signature extends to `(String, NarrativeMode?) -> [StyleExemplar]`; `RetrievalService.retrieve` gains soft-fallback semantics (zero same-modality matches → unfiltered top-K rather than empty result).
- **8.b.6** Bible Workspace: new "Scene Exemplars" pane at top of entity list; `SceneExemplarEditor.tsx` mirrors ReferenceEditor + adds dual status pills (chunks/beats). Bridge gains `createSceneExemplar` / `patchSceneExemplar` / `deleteSceneExemplar` / `ingestSceneExemplar` intents. `ProjectSession.addSceneExemplar` writes a Reference + Template with shared UUID; `AppState.ingestSceneExemplar` fans out to both pipelines.
- **8.b.7** Unified in-flight indicator: `AppState.ingestingReferenceIds` parallel to `extractingTemplateIds`; React derives `isIngesting` from EITHER set so the unified editor shows one "Ingesting…" state across the full fan-out.
- **8.b.8** D4 soft-toggle: `BeatGeneration.buildBeatPrompt` accepts `imitateContent: Bool = false`. When true, the SYSTEM framing drops the strict "Do NOT reuse plot, characters, settings, or specific events" prohibition and uses positive-constraint phrasing instead. UI: checkbox on the Write-Scene-From-Template NSAlert.
- **8.b.2 deferred to 8.c**: Pass-A on References at ingest. Chunk-level modality from `NarrativeModeClassifier` suffices for v1 beat-aware filtering; running Pass-A on every reference body is an optional accuracy improvement that can land if smoke surfaces a need.

Tests at 1253/1253. ~30 commits in the arc.

#### Smoke-test queue — live-app validation pending

The §15.14 list (items 1-10) carries forward unchanged. Phase 8 adds:

**Phase 8 smoke checklist:**
11. **Add scene exemplar end-to-end.** Bible Workspace → "+ Add scene exemplar" at the top of the entity list → opens the new editor with `name`, `nsfw`, and `body` fields. Paste an NSFW exemplar (one of the `Tools/SceneExemplarSpike/fixtures/` pieces works well). Confirm status pills show "no chunks / no beats" before ingest.
12. **Unified ingest.** Click "Ingest" → button flips to "Ingesting…" + disabled. The fan-out fires both `ingestReference` (Wegmann embed) and `extractTemplateScene` (Pass-A) on background queues. Watch debug log for `[scene-exemplar] ingest fan-out` + the two sub-pipeline lines. Expect ~30-90s end-to-end depending on writer/extractor latency.
13. **Pass-A retry behaviour.** If Pass-A fails with `noJSONObjectFound` (~30% transient sampling per the §6.1 spike), the current extractor doesn't retry that error case — the user has to hit "Re-ingest" manually. Flag for a Phase 8.b.x follow-up: extend `OllamaBeatExtractor.callWithRetry` to cover JSON-parse failures.
14. **Both sidecars present.** After ingest completes, confirm status pills flip to "N chunks ✓ / M beats ✓" in both the editor and the list row.
15. **Generate from scene exemplar.** Editor at cursor → "Write Scene From Template…" → confirm the new exemplar appears in the template picker → pick it + type a cast → click Generate. Confirm per-beat retrieval fires (watch for `[STYLE EXEMPLARS]` blocks in the prompt via debug log or History tab) and that retrieved chunks come from THIS exemplar's reference side.
16. **Imitate-content toggle.** Re-run #15 with the "Imitate content" checkbox **on**. Confirm output carries source vocabulary + content register (the strategic-anchor case: NSFW act patterns transfer). Cast names should still substitute correctly — the STRAP content-stripping in Pass-A is independent of the soft toggle.
17. **Legacy Reference re-ingest under Wegmann.** Existing Phase 5 References ingested under StyleDistance are now stale (`ModelFingerprint.id` mismatch from the current Wegmann client). Open one in the legacy References pane → click "Re-ingest" → confirm it re-runs against Wegmann and the cosines update. Subsequent retrievals should be Wegmann-cosine.
18. **Legacy orphan visibility.** A Reference with no matching Template UUID should appear in the new Scene Exemplars pane with "no beats" badge; clicking it opens the unified editor; clicking "Ingest" runs Pass-A to fill in the missing beats sidecar (and re-runs the embed pass — that's the unified ingest behaviour).

#### Carried forward — open follow-ups

- **`OllamaBeatExtractor` retry-on-JSON-parse**: one-line change to `callWithRetry`; flagged in #13 above + spike doc §2.2.
- **Phase 5 → Wegmann re-ingest UX**: `RetrievalService` doesn't currently check `ModelFingerprint.id` at retrieval time, so stale StyleDistance vectors silently retrieve. Adding a fingerprint check + a "needs re-ingest" UI badge is Phase 8.c material.
- **Pass-A on References (8.b.2)**: deferred. Could improve beat-aware retrieval if chunk-level modality from `NarrativeModeClassifier` turns out under-accurate in live smoke.
- **Generation-grade probes (§6.2 / §6.4 / §6.5)**: deferred to 8.c. They validate locked decisions (D5, D7) and require live exercise of Phase 8.b code to be meaningful.

**Architecturally complete (modulo smoke).** Phase 8.b's design — unified data model + per-beat retrieval + beat-aware filtering + soft-D4 toggle — is fully in production code. The live-app pass is the next gating step.

### 15.16 Session ledger — 2026-05-14 → 2026-05-15 (Phase 8.b smoke + iterations + CoreML migration)

Single-session arc continuing immediately after §15.15. Three rounds of live-smoke feedback against `/Volumes/SSD1/test2` (Emily-Maya NSFW scene exemplar; gemma-4-31B-Deckard-Heretic-Thinking writer; Pass-A via gemma4_2b). Each round produced a concrete gen-log JSON in `/Volumes/SSD1/test2/generation-log/`; the forensics-driven fix list grew from "looks ok" through three layered defenses + a unified end-of-gen reconciler. Plus a side-arc: drop the Python venv from runtime via CoreML conversion of Wegmann.

#### Per-call hint feature

Added BEFORE the smoke rounds. The Write-Scene-From-Template menu gains a third textarea (`Additional instructions (optional)`) and the BeatGeneration prompt assembly renders an `[ADDITIONAL INSTRUCTION — user-supplied hint for this generation]` block immediately before `[INSTRUCTION]` (after `[STYLE EXEMPLARS]`). 4 TDD tests; default empty string preserves Phase 7 byte-for-byte. Plumbed through TemplateGenerationCoordinator (start) + EditorViewController + AppDelegate's NSAlert + the notification userInfo.

#### CoreML migration (drop Python venv at runtime)

Pre-arc question: "now that we're on Wegmann, can we run inference without the Python venv?" Answer was yes via CoreML + huggingface/swift-transformers 1.0.

1. **Cosine-equivalence probe** at `Tools/CoreMLProbe/probe_wegmann_coreml.py` validates the conversion path: torch wrapper around `AutoModel.from_pretrained("AnnaWegmann/Style-Embedding")` does mean-pool + L2-norm, trace via `torch.jit.trace`, convert via `coremltools.convert(convert_to="mlprogram", minimum_deployment_target=macOS14)`, load the `.mlpackage` via Apple's CoreML, compare cosines against the sentence-transformers reference path. Result: **min 0.999993, max 0.999998 cosine across 5 register-spanning test strings; ~3s end-to-end conversion; FP16 mlpackage ≈ 250MB**. Within 1e-4 = byte-equivalent for production. Existing `.index` sidecars stay valid (no forced re-ingest).
2. **Production build script** at `Tools/CoreMLProbe/build_mlpackage.py` outputs `Sources/LoomCore/Resources/StyleEmbedding/` containing `StyleEmbedding.mlpackage` + HuggingFace fast-tokenizer files (`tokenizer.json` + `tokenizer_config.json` + special-tokens). Resource bundle gitignored; regenerated before `swift build` (same pattern as the BibleWorkspace dist directory). Total bundle 253 MB.
3. **Swift client** at `Sources/LoomCore/Retrieval/CoreMLEmbeddingClient.swift` (~190 LOC + 3 TDD tests). Conforms to existing `EmbeddingClient` protocol. Lazy-loads the mlpackage via `MLModel.compileModel(at:)` + the tokenizer via `swift-transformers` `AutoTokenizer.from(modelFolder:)`. DispatchSemaphore bridges the async tokenizer load to the synchronous embed contract. Per-call: BPE-tokenize → pad/truncate to 128 tokens (RoBERTa pad token resolved from the loaded tokenizer) → `MLModel.prediction(from:)` → 768-vec output.
4. **AppState factory**: `defaultEmbeddingClientFactory` returns `CoreMLEmbeddingClient` when `Bundle.module.url(forResource: "StyleEmbedding", ...)` resolves; falls back to `PythonEmbeddingClient` if the bundle is missing (fresh-clone bootstrap before the build script has been run).
5. **Loom.app bundle**: 257 MB total (248 MB of which is the mlpackage). CLT-only compatible at runtime (no Xcode required for MLModel + xcrun coremlcompiler). Per-embed latency: ~5–15 ms (vs Python's 50–80 ms).
6. **`Package.swift`** gains `.package(url: "https://github.com/huggingface/swift-transformers", from: "1.0.0")` + `.product(name: "Tokenizers", ...)` on LoomCore. `Resources/StyleEmbedding` declared as a `.copy` resource alongside `Resources/BibleWorkspace`.

#### Smoke round 1 — meta-block leakage cascade

First live gen with the new Phase 8 pipeline. User reported "weird paragraph spacing, strangeness in the text, and some odd blocks." Forensics on the gen-log:

- The writer LLM hallucinated `[VALIDATE BEAT]` + `Length check: ...` + `Pacing: Sentences = [1, 6, 7,` blocks at beat tails (Phase 7's stop list didn't catch them — none of the literal patterns matched).
- Leakage **cascaded**: once it landed in `insertedText`, every subsequent beat saw it in `[BEATS BEFORE THIS]` and learned to repeat. 6 of 10 beats poisoned.
- Beat 0 truncated mid-word at "Emily" (writer hit `numPredict = max(64, beat.targetWords * 2)` = 80 tokens; wanted ~95).
- First gen's `castMapping` came across with leading "S" missing ("arah is 18..." instead of "Sarah is 18..."). Reproducible race in `TemplateGenCastMappingPlaceholderDelegate.textDidBeginEditing` — the placeholder cleared AFTER AppKit's first keystroke had been committed.
- User-requested polish: Write-Scene-From-Template fields should **persist** so the user can iterate on cast/hint/toggle without re-typing 200+ chars each time.

Six-fix commit (576ee4b):
- `BeatOutputSanitizer.strip` (new pure-data, 9 TDD tests): truncates at first bracket-meta-header OR first header-less meta-line; collapses `\n{3,}` → `\n\n`; trims trailing whitespace.
- TemplateGenerationCoordinator sanitizes each beat's tail of `insertedText` on completion; posts a new `didSanitizeBeatNotification` carrying `{beatIndex, deleteFromOffset, deleteCount}` so the editor's NSTextStorage can drop the rubbish.
- EditorViewController observes the notification + calls `textStorage.deleteCharacters(in:)`.
- Stop sequences extended.
- SYSTEM framing gets explicit anti-leakage clause ("do NOT emit any prompt-shaped headers like `[VALIDATE BEAT]`, …") applied to all four variants.
- `numPredict` bumped from `max(64, target*2)` → `max(256, target*4)`.
- Placeholder delegate switched from `textDidBeginEditing` → `textShouldBeginEditing` so the clear fires BEFORE AppKit commits the keystroke. Fixes the leading-S loss.
- `TemplateGenStateStore` (new + 6 TDD tests): per-template sidecar at `<project>/template-gen-state/<id>.json` holding `{castMapping, extraInstruction, imitateContent, savedAt}`. AppDelegate's NSAlert gains a `TemplateGenMenuStateController` that wires the NSPopUpButton's target/action so picker-change pre-fills fields from disk; save-on-Generate writes back.

#### Smoke round 2 — backfill from gen-log

User reported the per-template state wasn't restoring. Root cause: the user's earlier gens (round 1 forensics) predated the sidecar mechanism — nothing was on disk under the new schema, so menu opens showed empty fields.

Fix (b99f0a8): `TemplateGenStateStore.loadOrBackfill(templateId:in:)` tries the sidecar first, falls back to scanning `<project>/generation-log/*.json` for the most recent entry whose `templateGenerationInfo.templateId` matches. Synthesises a `TemplateGenState` from its `castMapping` (+ `imitateContent` / `extraInstruction` if the entry carries them; legacy entries default to `false` / `""`). Schema bump: `TemplateGenerationInfo` gains optional `imitateContent` and `extraInstruction` fields; back-compat decode tolerant. 4 additional TDD tests on the backfill path.

#### Smoke round 3 — pattern generalisation + new leakage shape

Second live gen surfaced a new leakage shape: `[CHECK BEAT]` (word-order reversed from `[BEAT CHECK]`) plus a totally different inner format — `Is Beat 4 written above? YES` / `Modality: action? YES` / `Function: reveal? YES` / etc. The enumerated literals in `bracketHeaderPatterns` didn't match. Cascade propagated to beats 5-9 again.

Fix (e97517d): switched from enumerated string literals to a **vocabulary-anchored** detector. Any `[<META_WORD> ...]` line-start gets cut, where META_WORD ∈ {`BEAT`, `CHECK`, `VALIDATE`, `LENGTH`, `PACING`, `VOICE`, `DIALOGUE`, `SCENE`, `PROSE`, `OUTPUT`, `NOTE`, `META`, `SELF`, `VERIFY`}. False-positive guard: only fires when the bracket's FIRST word is in the vocabulary — prose-shaped brackets like `[OUTSIDE THE OFFICE]`, `[LATER]`, `[CHAPTER 2]`, `[FLASHBACK]` are preserved (tested). Stop sequences extended with the same vocabulary as prefix-shape stops. 3 additional TDD tests.

#### Smoke round 4 — editor-coordinator divergence + end-of-gen reconciler

Third live gen surfaced a different problem: the editor textView showed mid-word truncations ("her" instead of "hers.", "hungr" instead of "hungrily.", "Emily m" instead of "Emily murmurs.", "craving mo" instead of "craving more.") — but the gen-log's `rawText` had the **complete** prose. Editor was 2-7 chars short at each beat boundary. Also a writer-model gender slip ("him" referring to Maya) — content quality issue, out of scope for an automatic fix.

Root cause analysis: the streaming-time pipeline (StreamingThinkBlockStripper + sanitize-delete + token observer in editor) can drift from the coordinator's canonical `insertedText` in subtle ways — hold-backs across beat boundaries, sanitize-delete bounds-check skips, race conditions in token-event ordering. Hard to fully untangle.

Fix (97ffa42): **end-of-gen reconciliation**. At `didFinishNotification`, `EditorViewController.reconcileTemplateGenEditorWithCoordinator()` calls `storage.replaceCharacters(in: editorRange, with: templateCoordinator.insertedText)`. Idempotent — no-ops when the editor already matches (the common clean case), corrects when streaming drifted. Bypasses every layer between streaming and final view. The editor's content is now guaranteed byte-equivalent to the gen-log's `rawText` at the moment of finish.

#### State at session end

- **Tests**: 1286/1286 pass. New tests across `BeatOutputSanitizer`, `TemplateGenSanitize`, `TemplateGenStateStore`, `CoreMLEmbeddingClient`, `BeatPromptExtraInstruction`, `BeatPromptStyleExemplars` — total +35 since §15.15.
- **Loom.app**: built, signed, launching cleanly. CoreML path verified live. Per-template state persistence + gen-log backfill working.
- **Branch**: ~14 commits added since §15.15 close. Local-only until the user pushes.
- **Phase 8.b sub-rows**: all 8 implemented + smoked. 8.b.2 stays deferred (Pass-A on References at ingest) — Phase 8.c if smoke surfaces a quality gap.

#### Open follow-ups carried forward

1. **Pronoun consistency** (smoke round 4): the writer used "him" once when referring to a female-female cast. Mitigations: explicit pronoun line in `Additional Instructions`, or stronger SYSTEM clause ("Use pronouns implied by the cast description consistently"). Not landed — user said "it's fine, leave it" for now.
2. **History tab one-liner** (carryover from §15.14): `templateGenerationInfo` is on disk but `HistoryInspectorViewController` renders the entry as "Continue". Small follow-up: surface `templateName` + beat count when `templateGenerationInfo != nil`.
3. **`OllamaBeatExtractor` retry-on-`noJSONObjectFound`**: one-line `callWithRetry` extension to cover the ~30% transient JSON-parse failure rate on NSFW Pass-A extraction. Surfaced in §15.15 Phase 8.a closeout; still pending.
4. **Phase 5 → Wegmann re-ingest UX**: existing Reference `.index` sidecars under the old StyleDistance fingerprint are stale. `RetrievalService` doesn't currently check `ModelFingerprint.id` at retrieval time. Add a fingerprint-mismatch warning + "needs re-ingest" badge on stale References — Phase 8.c material.
5. **Pass-A on References at ingest** (8.b.2): chunk-level modality from `NarrativeModeClassifier` suffices for v1 beat-aware retrieval; deferred.
6. **Generation-grade probes** (§6.2 / §6.4 / §6.5): deferred to 8.c. They validate locked decisions and require live Phase 8.b code to be meaningful.

**Phase 8.b smoked + iterated to clean output.** Editor view + gen-log are now byte-equivalent post-reconcile. Per-template state persistence (with gen-log backfill) lets the user iterate without re-typing. Native CoreML inference replaces the Python subprocess. The strategic-anchor NSFW use case generates cleanly with the `Imitate content` toggle on.

### 15.17 Session ledger — 2026-05-15 → 2026-05-16 (Phase 9 entity discovery + writer-model A/B + §15.16 carryover sweep)

Single-day arc producing 37 commits across three threads: writer-model selection research, the entire Phase 9 entity-discovery feature spike-to-production, and a sweep of the §15.16 carryover follow-ups (#1, #2, #3, #4 all shipped). Tests grew from 1286 to 1448 (+162) — entire Phase 9 surface plus four targeted regressions. All on `main`, all pushed to `origin`.

#### Writer-model A/B (3 commits)

User asked for research on uncensored fiction-writing models for 24GB VRAM. Spawned a research agent that surveyed UGI Leaderboard, EQ-Bench Creative v3, TheDrummer / DavidAU / MuXodious / ReadyArt finetune lineages, and r/LocalLLaMA consensus. Top picks: DavidAU Qwen3.6-27B Heretic2 Finetune Thinking; Gemma-4 31B Deckard Heretic (already in use); TheDrummer Cydonia-24B-v4.3 + the MuXodious "absolute heresy" abliteration of it; Goetia-24B-v1.3-absolute-heresy (DELLA merge of every Mistral-Small-3.x prose-tuned variant). User downloaded Goetia.

Two code changes to support the swap:
- `c4c6205 feat: auto-detect Mistral-Small-24B finetunes → mistralV7` — `InstructTemplates.detect` now recognises Cydonia / Goetia / Magidonia / Harbinger / Hearthfire / Skyfall as Mistral V7 Tekken (their filenames don't contain "mistral" so the existing detector fell through to .raw, producing garbage at gen time).
- `413a5fb feat: per-model-family sampler override at request-construction time` — `SamplerParams.familyOverride(forModelName:)` returns Drummer-recommended (`temp 0.8, min_p 0.025, rep_pen 1.05`) for the Mistral-Small-3.x family. Applied in `GenerationCoordinator.makeSamplerParams` after the project's `GenerationDefaults` so the family override wins on detection. Logged to DebugLog when applied so it's not silent magic.

#### Phase 9 entity discovery — full spike-to-production arc (28 commits)

User asked: can the existing fact extractor also detect new characters/places and propose them for the bible? Plan + research synthesis landed in `LOOM_ENTITY_DISCOVERY_SPIKE.md` (committed `32046f2`); §9 post-spike appendix added after the third live run (`e7cdef2`).

**Spike phase** — pure-data scaffolding TDD, then live eval runner (`Tools/EntityDiscoverySpike`) against gemma4_2b on 8 hand-graded fixture scenes (5 reused from LedgerSpike, 3 newly authored NSFW scenes for entity-discovery signals — "the redhead behind the bar" anatomy distractor, "Marius Thorn / Dr Thorn" dedup test, "Brussels / Edinburgh" passing-mention place distractor, etc.). Five live runs:

| Run | Precision | Recall | F1 | Latency | Notes |
|---|---|---|---|---|---|
| 1 | 33.3% | 85.7% | 48.0% | 49.2s | Three structural failure modes identified |
| 2 | 75.0% | 85.7% | 80.0% | 32.2s | + Fix 1/2/3 (known-filter, dedup-wire, place-recurrence) |
| 3 | **100%** | **85.7%** | **92.3%** | 30.7s | + Fix 4/5 (token-expansion, post-Stage-D dedup) — GO threshold cleared |
| 4 | 100% | 85.7% | 92.3% | 34.8s | Parallel Stage D + over-eager retry — *worse* (Ollama serialises on the model load slot anyway; retry on "all known" was wrong) |
| 5 | 100% | 85.7% | 92.3% | 33.2s | Conservative retry (errors only) — kept |

§6.4 decision: GO. Recall miss at eds-01 (Karim) is upstream of all filters — gemma4_2b consistently doesn't emit Karim regardless of prompt or temperature. Documented as a model-behaviour limitation; addressed later by Stage A2 retry-on-`noJSONArrayFound` (commit `e2ff8f3`) which catches the parse-fail variant of the same class of issue.

**Production phase** — six commits land the §4 UI vertical slice (slice option 4 from the user's choice):
- `4d75b69` `ProposedEntitiesStore` (sidecar JSON) + `BibleWorkspaceSnapshot.proposedEntities` field
- `c20affb` Bridge intents `acceptEntityProposal` / `rejectEntityProposal` + `AppState` handlers (promote to `Character` / `Setting` / `BibleObject` with attached facts)
- `cbe1103` Snapshot wiring through `BibleWorkspaceWindowController`
- `beaf512` TS types + `EntityProposalsQueue.tsx` view + emerald header badge — vite-dev-verified with mock snapshots, intent payloads inspected via mock postMessage
- `6bd6883` `EntityDiscoverySpike --into <project>` flag — runner writes proposals into a real project's store; demo-grade (synthesised scene IDs render as "(unknown scene)" in the UI)

**Editor-triggered live discovery** — five more commits make discovery actually fire in the running app:
- `abdc03e` `OllamaEntityDiscoveryExtractor` — async wrapper around Stages A2+B+C+D+post-Stage-D dedup, mirrors `OllamaLedgerExtractor`'s shape, full TDD via deferred-stub provider
- `1620ba8` `AppState.runEntityDiscovery(for sceneId:)` — single editor-callable entry point
- `3ee6b97` Bible menu item "Discover Entities in Current Scene"
- `8a900ea` Auto-trigger via `LedgerExtractionCoordinator.onExtractionComplete` piggyback (avoids needing a separate Phase 9 coordinator)
- `67f6ff1` `EntityDiscoveryTrigger` (per-scene 500-word baseline) so substantial rewrites re-fire

**Polish** — three more:
- `2b171de` Object discovery (BibleObject) — third `Kind` enum value, additive (gate already handled it; place-recurrence shorts on kind != .place; AppState acceptance + UI badge added)
- `be4537e` In-flight indicator — amber pulsing-dot pill in EntityList header while discovery is running
- `e2ff8f3` Stage A2 retry-on-`noJSONArrayFound` — closes the recall-gap path for the eds-01-style Karim miss

Final state: end-to-end working in Loom.app. User opens scene → ledger fires → discovery auto-fires (or manual via menu) → in-flight pill appears → ~30s later proposals queue gets entries → user reviews / edits / accepts → bible row materialises with attached facts. Three trigger paths (auto, menu, demo `--into` for a CLI bootstrap), three entity kinds (character/place/object), retry on parse fail, dedup against existing bible, all pure-data tested + live-verified.

#### §15.16 carryover follow-ups — all four shipped

- `6b6e714` **#1** `OllamaBeatExtractor` retries on `noJSONObjectFound` — same fix shape later mirrored to `OllamaEntityDiscoveryExtractor`.
- `f01ecc2` **#2** History tab template-gen surfaces beat count — "Template: Doorway test · 3 beats" (singularises "1 beat" correctly).
- `9909d2d` **#3** Wegmann re-ingest UX — `SnapshotReference.computeDModelStale` derives staleness from persisted `dModel` vs `CoreMLEmbeddingClient.expectedModelId`; amber "needs re-ingest" badge in EntityList for stale references; only renders when `dModelStale === true` (not for fresh or not-yet-ingested).
- `807183d` **#4** Pronoun-consistency SYSTEM clause — appended `"Use the pronouns specified in the NEW CAST block consistently for each character throughout the beat."` to all four `BeatGeneration.buildBeatPrompt` framings (template-body × imitateContent matrix). Positive-constraint framing per `feedback_prompt_blacklist_evasion`.

#### Open follow-ups carried forward

1. **#5 Pass-A on References at ingest** — still deferred per §15.16 ("only worth doing if live smoke shows the chunk-level modality is missing beats").
2. **#6 Generation-grade probes** — still deferred to 8.c. Heavy work (~3-5 hours of writer-LLM time + hand-grading by user); requires sustained user attention.
3. **Phase 9 v2 deferred items** (per `LOOM_ENTITY_DISCOVERY_SPIKE.md` §5):
   - Cross-scene coref (needs Python NER like BookNLP — toolchain-pressure risk per `feedback_verify_local_toolchain`)
   - Lorebook auto-discovery (different concept shape; abstract not entity)
   - Relationship-fact discovery (extends Pass-B fact format)
   - Faction discovery (similar to lorebook)
   - Bulk import (whole-manuscript runner — useful when importing existing prose)
4. **Live smoke of Phase 9 in the user's actual project** — the unit tests don't prove the auto-trigger fires correctly with real ledger events. Highest-value next step is using the feature, not building more.
5. **Writer-model A/B against Goetia** — user has Goetia downloaded; needs to load in koboldcpp at the writer URL and exercise to confirm prose quality vs the current Gemma-4 31B Deckard Heretic. Mistral-V7 template + per-family samplers should auto-apply.

**Phase 9 entity discovery is shippable.** The full feature loop works in `Loom.app`. The plan-doc reads "PROCEED" at §6.4. 1448/1448 tests green. Next session's load-bearing question is no longer "build this?" — it's "does it surface useful entities on real prose?"

### 15.18 Session ledger — 2026-05-16 (Phase 10 Character Relationships — Part B webview)

Picked up Phase 10 with the entire relationship-discovery backend already
shipped (commits `fb5baf8` → `e9fae52`): temporal `Relationship` model,
`RelationshipDiscovery` prompt/schema/parser, the Ollama extractor,
`RelationshipConflict` (exclusive-kind heuristic + `conflictingCurrent` +
`applyAccepted` with never-delete temporal demotion), `ProposedRelationshipsStore`,
`AppState.runRelationshipDiscovery`, and `BibleWorkspaceSnapshot.proposedRelationships`.
Part B — the React webview — was the only thing left. Three commits, all on
`main`. Tests 1524 → 1535 (+11).

- `302fc97` **B/2 — accept/reject bridge intents.** New `BibleWorkspaceIntent`
  cases `acceptRelationshipProposal(proposalId:, demoteConflicting:)` +
  `rejectRelationshipProposal(proposalId:)`, the `BibleWorkspaceWindowController`
  dispatcher cases, and `AppState.acceptRelationshipProposal` /
  `rejectRelationshipProposal`. Accept resolves the proposal's from/to names to
  bible Character UUIDs (new pure `RelationshipConflict.resolveCharacter` —
  name/alias, case-insensitive), merges the edge via `applyAccepted`, updates the
  from-character, removes the proposal. `SnapshotProposedRelationship` gained
  `conflictsWithCurrent: [String]` — resolved Swift-side in
  `buildProposedRelationshipSnapshots` via `RelationshipConflict.conflictingCurrent`
  so the exclusive-kind classifier never gets duplicated into TS. TDD: intent
  encode/round-trip suite + `resolveCharacter` cases + the `conflictsWithCurrent`
  forward-load case.
- `0394534` **B/3 — relationship-proposals review view.**
  `RelationshipProposalsQueue.tsx` mirrors `EntityProposalsQueue` — flat
  accept/reject list (`from → kind → to`, current/past pill, evidence). Accepting
  a proposal with non-empty `conflictsWithCurrent` opens an **in-React**
  demote-confirm modal (demote-to-past / keep-both / cancel) — an in-React modal
  rather than `window.confirm` because the workspace `WKWebView` has no
  `WKUIDelegate`. Sky-toned header badge in `EntityList`.
- `afe85d0` **B/4 — N×N relationship matrix.** `RelationshipMatrix.tsx` — rows =
  from-character, cols = to-character, cells the directed edges; current = accent
  pill, past = struck-through muted pill; cell click opens the row character's
  editor. Reached via a "Relationship matrix →" action on the Characters section
  header (≥2 characters). Also brought the stale TS `Relationship` mirror up to
  date with the Phase 10 Swift model (optional `status` + `sourceSceneId`).

All three React views vite-dev smoke-verified with mock snapshots: queue render,
demote-dialog 3-way resolution, intent wire shapes inspected via mock
`postMessage`, matrix render across current/past/empty/diagonal cells, cell-click
→ CharacterEditor. No console errors.

#### Open follow-ups carried forward

1. **Live smoke of Phase 10 in the user's actual project** — the unit tests +
   vite mocks don't prove the discovery→queue→accept→matrix loop fires correctly
   against real ledger events and a real on-disk bible. Highest-value next step.
2. Phase 9 carryovers #5 / #6 / v2 items and the Phase 9 live-smoke item (§15.17)
   still stand.
3. **Writer-model A/B against Goetia** — still open from §15.17.

**Phase 10 Character Relationships is feature-complete.** Backend (Part A) +
webview (Part B) both shipped; 1535/1535 tests green. The loop — discover
relationships in a scene → review queue → accept (with demote-on-conflict) →
matrix grid — works end to end in code. Load-bearing next question: does it hold
up on real prose in the user's project?

### 15.19 Session ledger — 2026-05-16 (discovery-reliability fixes + GLiNER entity-detector, phases 1–4a)

Continuation of the §15.18 session. Started from live-testing Phase 10 in the
`test2` project, which surfaced that entity discovery produced **zero**
proposals on a real scene. That kicked off a long reliability arc and the start
of a GLiNER-based replacement for the generative-LLM entity detector. 10
commits, all on `main`. Tests 1524 → 1574.

#### Entity/relationship discovery reliability (2 commits)

Diagnosed live against `test2`'s explicit beach scene:

- `b6c7a97` **Drop the Ollama `format` schema constraint.** Live repro proved
  Ollama's `format`-constrained generation flakes ~50% into a non-terminating
  buffer that hits `num_predict` and returns empty content (`done_reason:
  length`). Stage A2 + relationship discovery now run unconstrained; prompts pin
  the JSON field names; parsers tolerate synonym keys; `num_predict` raised to
  4096; both extractors re-roll on a degenerate zero-result.
- `d4df07e` **Stream Ollama responses + line-based discovery output.** The
  deeper finding: Ollama's *non-streaming* `/api/chat` with gemma4
  intermittently returns empty `message.content` despite a full generation —
  `stream: true` + concatenating the chunk bodies dodges it (helps every
  extractor). And Stage A2 / relationship discovery now ask for a delimited
  **line list** (`kind | surface | quote`) instead of a JSON array — a small
  model emits lines far more reliably than nested JSON. New tolerant line
  parsers; entity discovery retries on any zero-candidate result.

Honest outcome: mild scenes (e.g. `test1`) are now consistently clean; the
dense explicit scene stays noisy (~20–80% per call across many measurements) —
that floor is gemma4_2b itself derailing on explicit prose, not a format/prompt
problem. Confirmed the real fix is a non-generative detector → GLiNER.

#### GLiNER research (3 parallel research agents + 1 verification spike)

- **Models** — A/B'd two user-downloaded GGUFs against gemma4_2b: `Qwen3.5_4B`
  (aggressive-heretic) is 4–6× slower and runs away even with `/no_think`;
  `NuExtract_4B` (a Qwen2.5-VL model textified to GGUF) is effectively broken
  via Ollama. Neither beats gemma. Model-swap avenue closed.
- **Techniques** — strongest evidence for task decomposition + line output +
  streaming (all since shipped). Confirmed the Ollama empty-content bug class
  against upstream issues (#15428, #15502, …).
- **Chunking** — map-reduce over `RagChunker` (already exists) for long scenes;
  deferred until the detector is solid.
- **GLiNER→native spike** — verdict GO via **ONNX Runtime, not CoreML**: GLiNER's
  DeBERTa-v3 backbone will not trace through `coremltools` (two attempts failed).
  ONNX export + ONNX Runtime inference verified locally (~40 ms).

#### GLiNER entity detector — phases 1–4a (4 commits)

GLiNER is a ~50M-param bidirectional NER encoder — deterministic, refusal-proof,
~40 ms/call. Replacing the generative Stage A2 with it is the structural fix for
the explicit-scene floor. ONNX Runtime is a new SPM binary dependency; zero
runtime Python (the model is exported offline).

- `2f24107` **Phase 1** — `Tools/GLiNERProbe/`: build-time export of
  `urchade/gliner_small-v2.1` to a quantized ONNX bundle (~184 MB, gitignored,
  regenerated locally like the Wegmann CoreML bundle) + a verifier.
- `ef17cc6` **Phase 2** — ONNX Runtime (`microsoft/onnxruntime-swift-package-
  manager` 1.24.2) linked into LoomCore; `GLiNERRuntime` opens an inference
  session. Linkage proven by tests; full app builds.
- `844cad2` **Phase 3** — `GLiNERTokenizer`: GLiNER's DeBERTa-v3 SentencePiece
  tokenizer in Swift. The export script rewrites `tokenizer_class` →
  `XLMRobertaTokenizer` so swift-transformers loads it as a generic Unigram
  tokenizer. Byte-for-byte parity with the Python tokenizer pinned by a fixture
  (10 probe strings incl. accented + explicit content) — all identical.
- `9cd5a63` **Phase 4a** — `GLiNERInputs`: the word splitter + `span_idx` /
  `span_mask` builders, verified against a ground-truth fixture dumped from the
  real Python GLiNER ONNX pipeline (`Tests/LoomCoreTests/Fixtures/gliner_inference_fixture.json`).

#### GLiNER — remaining phases (next session)

The full algorithm spec + a verified ground-truth fixture are in hand.

1. **Phase 4b — per-word tokenization + `words_mask`.** GLiNER tokenizes each
   word separately (`is_split_into_words`); `words_mask` marks the first subword
   of each content word with its 1-based index. Needs a per-word tokenization
   path verified to reproduce the fixture's exact `input_ids` — watch the
   Metaspace `▁`-prefix handling.
2. **Phase 4c — ONNX session run + decode.** Obstacle: the `span_mask` ONNX
   input is `tensor(bool)` and the ORT Objective-C API exposes **no bool element
   type**. Fix: graph surgery in `export_gliner_onnx.py` — retype that input to
   int64 + insert a `Cast`-to-bool (~15 lines + re-export + re-verify). Then
   build the 6 input tensors, run, sigmoid the `logits[1,words,12,classes]`,
   threshold (0.5, strict), validity-filter (`start+width+1 ≤ numWords` — load-
   bearing, the quantized model emits garbage probs on invalid spans), greedy
   non-overlapping span selection, map word spans → char offsets.
3. **Phase 5 — wire GLiNER into discovery** as the entity-*detection* step; the
   LLM keeps only normalisation (Stage D) + relationships.

Algorithm spec details, config constants (max_width 12, max_len 384,
`<<ENT>>`=128002, `<<SEP>>`=128003), and the decode are all captured in the
phase-4a commit + the fixture; the GLiNER source is in the spike venv at
`/tmp/gliner_spike/venv/lib/python3.9/site-packages/gliner/`.

#### Other open follow-ups carried forward

- **Long-scene chunking** — the deferred map-reduce over `RagChunker`; becomes
  relevant once GLiNER lands (the user added a longer 1658-word scene to `test2`
  for testing). GLiNER's speed makes per-chunk extraction cheap.
- Phase 9 / Phase 10 live-smoke, the writer-model A/B against Goetia — all still
  open from §15.17–15.18.

**1574/1574 tests green.** Phase 10 is feature-complete; discovery reliability
is much improved but gemma-limited on explicit prose; GLiNER phases 1–4a are
committed and verified, with 4b/4c/5 well-specified for the next session.

### 15.20 Session ledger — 2026-05-16 (GLiNER entity detector — phases 4b/4c/5)

Continuation of §15.19. Completed the GLiNER native entity detector and wired
it into entity discovery. 5 commits, all on `main`. Tests 1574 → 1587.

#### GLiNER detector — phases 4b/4c (3 commits)

- **Phase 4b** — per-word tokenization + `words_mask`. `GLiNERTokenizer`
  `encodeWord` encodes one word to subwords with no `[CLS]`/`[SEP]`;
  `GLiNERInputs.assembleSequence` lays out
  `[CLS] (<<ENT>> label)* <<SEP>> word* [SEP]` with the matching `words_mask`.
  The Metaspace `▁`-prefix concern was a non-issue — `prepend_scheme: always`
  means per-word encoding reproduces HF's joined `is_split_into_words` path.
  A real-tokenizer test reproduces the inference fixture's `input_ids` exactly.
- **Phase 4c graph surgery** — `export_gliner_onnx.py` now retypes the
  `span_mask` input bool → int64 and splices a `Cast`-to-bool node (ONNX
  Runtime's ObjC API has no bool element type). Applied in-place to the
  current bundle; verified lossless — the patched graph reproduces the
  fixture's logits with **zero** difference. The strict `onnx.checker` is
  skipped: the quantized export already trips it inside an `If` subgraph
  (pre-existing, unrelated).
- **Phase 4c decode** — `GLiNERDecoder` (sigmoid → strict threshold →
  validity-filter `s+k+1≤numWords` → greedy flat-NER selection → word-span →
  char offsets) and `GLiNERDetector` (tokenizer + input construction + ONNX
  session + decode). End-to-end test through the real ONNX session reproduces
  the fixture's decoded entities exactly (Marek/dagger/cathedral).

#### Phase 5 — GLiNER wired into discovery (2 commits)

- The shared filter + Stage D tail moved to `EntityDiscoveryPipeline`
  (`applyFilters` + `runStageD`); `OllamaEntityDiscoveryExtractor` now calls it
  (behaviour unchanged, existing tests green). `GLiNEREntityDiscoveryExtractor`
  composes GLiNER detection with that tail — the LLM keeps only Stage D
  normalisation. `GLiNERCandidateDetector` maps detected spans to discovery
  candidates, each carrying its enclosing sentence as evidence.
  `EntityCandidateDetecting` protocol abstracts detection for stub-testing.
- `AppState.runEntityDiscovery` resolves a lazily-loaded, cached `GLiNERDetector`
  off-main and runs discovery through the GLiNER extractor; a missing model
  bundle falls back once to the all-LLM extractor.

#### Open follow-ups carried forward

- **Long-scene chunking** — still deferred; the map-reduce over `RagChunker`.
  The user added a 1658-word scene to `test2` for testing. GLiNER's speed makes
  per-chunk extraction cheap. Worth doing next — `GLiNERDetector` truncates
  nothing yet (GLiNER's `max_len` is 384 words; long scenes need chunking
  before the detector, or the tail is silently dropped).
- Live-smoke GLiNER discovery against `test2`'s explicit scene — not yet run.
- Phase 9 / Phase 10 live-smoke, the writer-model A/B against Goetia — still
  open from §15.17–15.18.

**1587/1587 tests green.** GLiNER entity detector is complete and wired into
discovery; the generative Stage A2 is replaced. Long-scene chunking is the
clear next step (the detector currently has no length guard).

### 15.21 Session ledger — 2026-05-16 (GLiNER long-scene chunking + live eval)

Continuation of §15.20. Added long-scene windowing, ran the GLiNER-vs-LLM
eval on real scenes, and fixed the two issues it surfaced. 5 commits on
`main`. Tests 1587 → 1596.

- **Long-scene windowing.** `GLiNERInputs.wordWindows` splits a scene into
  ≤300-word windows at sentence boundaries; `GLiNERDetector.detect` runs
  inference per window and concatenates. Entities never cross a sentence edge,
  so per-window results need no boundary dedup, and char offsets stay absolute.

- **EntityDiscoverySpike — GLiNER mode + a bug fix.** `LOOM_SPIKE_DETECTOR=gliner`
  runs the eval's detection step through GLiNER; `LOOM_SPIKE_FIXTURE` overrides
  the fixture path. The spike's inline filtering never deduped candidates by
  surface — fine for the LLM (few candidates) but GLiNER emits one per *mention*
  ("Chantal" ×40), so ~90 Stage D LLM calls fired per scene. Added
  `dedupCandidatesBySurface` as the first filter, matching production's
  `EntityDiscoveryPipeline.applyFilters`.

- **Eval results.** On the 8-scene graded fixture: GLiNER **100% / 100% / 100%**
  (P/R/F1) vs the LLM's flaky 60–92% F1 (two same-config LLM runs scored 42.9%
  and 85.7% recall — that swing *is* the gemma instability). On `test2`'s two
  explicit scenes (the ones that derailed gemma in §15.19): the LLM produced
  **zero** candidates both times (Stage A2 refused/derailed); GLiNER detected
  **all 7** entities.

- **Two fixes from the test2 eval.** (1) On dense prose the quantized model
  occasionally emits a high-confidence *wide* span (one crossed a sentence
  boundary); `GLiNERDecoder` now caps entity width at `maxEntityWords` (8).
  (2) gemma's Stage D normalisation listed every name in the scene as an alias
  of whichever entity it was normalising ("Miss Abby" as an alias of "Megan");
  `EntityDiscovery.sanitizeAliases` keeps an alias only if it shares a
  significant (non-title, non-determiner) word token with the canonical name.
  With both fixes, test2 went **71.4% → 100% F1**.

#### Open follow-ups carried forward

- **Stage D latency** — discovery on a dense scene is ~75–110s, all of it Stage
  D (one gemma normalisation call per survivor, long `one_line` generations).
  Detection itself is instant. The ≤30s/scene target is now purely a Stage D
  throughput problem — candidates for a faster path: shorter `one_line`, a
  smaller/faster model, or batching.
- Phase 9 / Phase 10 live-smoke, the writer-model A/B against Goetia — still
  open from §15.17–15.18.

**1596/1596 tests green.** GLiNER entity detection is production-quality —
100% F1 on both the graded fixture and `test2`'s explicit scenes. The residual
discovery cost is Stage D latency, not correctness.

### 15.22 Session ledger — 2026-05-16 (Stage D latency)

Continuation of §15.21. Attacked Stage D normalisation latency on the `test2`
explicit scenes. 2 commits on `main`. Tests 1596 → 1599. F1 stayed 100%
throughout.

- **Batch Stage D — tried, reverted.** Folded all survivors into one LLM call
  (scene sent once) with a delimited-line output. gemma ignored the line
  format, emitted JSON, and normalised only the *first* candidate — it will
  not complete a multi-entity normalisation in one call. Reverted; the
  per-candidate path stands.
- **Trim — committed.** The normalisation instruction now caps `one_line` at
  20 words; gemma was emitting paragraph-long descriptions. ~20-30s/scene
  saved, and the descriptions are genuinely better.
- **Scene windowing — committed.** `EntityDiscovery.sceneWindow` clips the
  Stage D prompt to ±150 words around the entity's first mention instead of
  re-sending the whole scene per candidate. That per-candidate prompt-eval of
  a long scene was the dominant cost.

Cumulative: test2 Stage D latency **93.6s → 52.5s/scene** (Scene 1, 2
survivors: 33.7s; Scene 2, 5 survivors: 71.3s). Still over the §1 ≤30s target
on high-survivor scenes — discovery is a background, non-blocking operation so
this is tolerable, but the next lever is dropping Stage D's `format` schema
constraint (grammar-constrained sampling is slower; §15.19 already dropped it
for Stage A2) or a faster Stage D model.

**1599/1599 tests green.**

### 15.23 Session ledger — 2026-05-16 (relationship reliability + visual mapper)

Continuation of §15.22. Verified the GLiNER discovery wiring is complete in the
shipped app, measured relationship-discovery reliability, researched the SOTA,
and began a visual relationship mapper. 3 commits + this ledger. Tests
1599 → 1603.

#### GLiNER discovery wiring — confirmed shipped

`AppState.runEntityDiscovery` uses `GLiNEREntityDiscoveryExtractor` + a cached
`GLiNERDetector` (LLM fallback if the bundle is absent); the ONNX bundle ships
inside `Loom.app/Contents/Resources/Loom_LoomCore.bundle/GLiNER/`; discovery
auto-fires when a scene grows ≥500 words. Nothing half-wired.

#### Relationship-discovery reliability — measured + a cheap fix

Ran relationship discovery live on `test2`'s two scenes (3 runs each). Verdict:
reliable on the simple 2-character scene, **noisy on the dense 5-character
explicit scene** — it hallucinates edges between unrelated characters, misses
the central relationship (the mother–daughter premise, every run), invents
character names not in the input list ("Narrator"), and is unstable run-to-run.
Same gemma floor GLiNER fixed for entities — but GLiNER can't help (it's NER,
not relation extraction).

- `RelationshipDiscovery.filterToKnownCharacters` drops edges whose endpoints
  aren't both in the known-character list (kills the invented "Narrator"); the
  extractor applies it before the empty-check so an all-invented response
  re-rolls. The parser never filtered to known names, so invented endpoints
  would otherwise have leaked into the app.

#### Relationship extraction — research outcome (the roadmap)

A far-reaching research pass (see the agent report) found **GLiREL** — GLiNER's
relation-extraction sibling: same DeBERTa-v3 encoder family, zero-shot, scores
entity-pairs against relation labels with a sigmoid (so "no relation" is a
threshold), refusal-proof, takes entity spans as input (Loom already has them).
But unlike GLiNER it is **not turnkey**: weights are **CC BY-NC-SA
(non-commercial — a hard license gate to resolve first)**, no official ONNX
export, and it's trained on news/Wikipedia so fiction transfer is unproven.

Recommended plan: **spike GLiREL** (license gate → Python accuracy spike on the
test scenes → ONNX export only if accuracy holds), but **ship a two-stage
pairwise LLM classifier as the baseline** — enumerate character pairs, classify
each pair independently ("A→B: lover / sister / none?"). 2025 RE literature
converged on this to fix LLM relation hallucination; it needs no new
dependencies and makes invented/hallucinated edges structurally far less
likely. GLiNER2 / GLiClass are alternative encoders if GLiREL's license blocks.

#### Visual relationship mapper — increment 1

A drag-and-drop relationship mapper was confirmed as wanted regardless of the
discovery work. Increment 1: `RelationshipGraph.tsx` — a React Flow
(`@xyflow/react`) graph view, characters as draggable nodes, each
`Character.relationships` entry a directed labelled edge (current vs past
styled), zoom/pan/minimap, double-click a node to edit. Reachable from the
character list alongside the matrix. Read-only so far.

Remaining mapper increments: (2) node-layout persistence — a
`relationship-map-layout.json` sidecar + Swift store + bridge intent;
(3) in-graph edge editing — create by drag / edit kind+status+notes / delete,
routed through a new intent that runs `RelationshipConflict.applyAccepted` (the
existing `patchCharacter` path bypasses romantic-exclusive demotion);
(4) discovery integration — proposed relationships as dashed ghost edges
accepted/rejected on the map.

#### Open follow-ups carried forward

- **Relationship-discovery reliability** — the GLiREL spike + two-stage pairwise
  LLM classifier, per the research outcome above.
- **Mapper increments 2–4** as listed.
- Stage D latency (~52s on dense scenes), Phase 9/10 live-smoke, Goetia A/B.

**1603/1603 tests green.**

### 15.24 Session ledger — 2026-05-16 (visual relationship mapper — increments 2–4)

Continuation of §15.23. Completed the drag-and-drop relationship mapper. 3
commits. Tests 1603 → 1615.

- **Increment 2 — node-layout persistence.** `RelationshipMapLayoutStore` is a
  per-project sidecar (`relationship-map/layout.json`) of dragged node
  positions — view state, kept out of the bible. A `setRelationshipNodePosition`
  bridge intent upserts one node on drag-stop (no snapshot re-push); the saved
  layout rides the snapshot and seeds initial node placement.
- **Increment 3 — in-graph edge editing.** Drag character→character to create
  an edge; click an edge to edit kind/status/notes or delete. Two intents:
  `setRelationshipEdge` upserts via `RelationshipConflict.applyAccepted`
  (`demoteConflicting: true` — a manual romantic edge demotes a prior current
  one, never deletes); `deleteRelationshipEdge` removes a `(from,to,kind)`
  edge. The React Flow graph re-syncs from each snapshot so edits show
  immediately while persisted positions hold.
- **Increment 4 — discovery ghost edges.** Pending relationship-discovery
  proposals render as dashed amber edges (proposal names resolved to bible
  characters by name/alias). Clicking one opens a review modal — evidence,
  source scene, romantic-conflict warning — with Accept/Reject routed through
  the existing `acceptRelationshipProposal` / `rejectRelationshipProposal`
  intents. Webview-only; no new Swift.

The mapper is feature-complete: a React Flow graph reachable from the
character list, with draggable persisted nodes, full edge CRUD, and inline
discovery review.

A **dev-mode browser-preview harness** was then added (`web/bible-workspace/
src/devMockSnapshot.ts` + a `bridge.ts` hook): under `vite dev` with no Swift
host, the webview feeds itself a mock snapshot. `import.meta.env.DEV`-gated +
dynamic-imported, so it is dead-code-eliminated from the production bundle.
This made the mapper browser-verifiable — all four increments + the edge and
proposal modals were confirmed via the preview, and a cramped auto-layout was
caught and fixed. In-app exercise against a real Loom project (the Swift
round-trip — persistence, `applyAccepted` demotion) is still the one
un-verified slice.

#### Open follow-ups carried forward

- **Relationship-discovery reliability** — the GLiREL spike + two-stage
  pairwise LLM classifier (§15.23).
- In-app exercise of the relationship mapper.
- Stage D latency (~52s on dense scenes), Phase 9/10 live-smoke, Goetia A/B.

**1615/1615 tests green.**

### 15.25 Session ledger — 2026-05-16 (GLiREL spike — NO-GO)

Ran the GLiREL accuracy spike the §15.23 research recommended as the go/no-go
for a GLiNER-style deterministic relationship extractor. No repo commits — the
spike lives in a throwaway venv (`/Volumes/SSD1/glirel_spike/`).

#### Toolchain

glirel 1.2.1 needs Python ≥3.10 (PEP-604 syntax) — the machine only has system
Python 3.9. Unblocked cleanly with `uv` (already installed): `uv python install
3.12` + an isolated venv on the big volume, no system change. glirel pins no
dependency versions, so `uv` pulled bleeding-edge `transformers 5.8.1` which
broke loading three ways (hub-mixin signature, tiktoken mis-detection, then a
normal missing `protobuf`/`sentencepiece`). Resolved by pinning
`transformers==4.49.0` (glirel's era) + a one-line patch making glirel's
`_from_pretrained` args optional. Dependency-rot — exactly the "one
researcher's project, moderate maturity" risk the research flagged.

#### Accuracy verdict — NO-GO

GLiREL `glirel-large-v0` runs, is deterministic, and is refusal-proof (it
processed the explicit scene without issue — an encoder). But zero-shot
accuracy on fiction prose is **too poor to use**:

- **Sanity example** ("Marek loved his sister Yelena, but he despised Anders,
  who had once been Yelena's boyfriend") — got Marek↔Yelena *sister* ✓ and
  Anders↔Yelena *boyfriend* ✓, but **hallucinated** a Marek↔Anders *boyfriend*
  edge (0.54 — scored *above* some correct edges). On a trivial one-sentence
  case.
- **test2 Scene 2** (Judy/Allie/Megan) — collapsed: it labelled **every** pair
  "sister" (0.36–0.45), including Megan (not anyone's sister). Missed the
  Judy/Allie lover relationship and Megan's role entirely.
- Score ranges of correct vs hallucinated edges overlap, so no threshold
  cleanly separates them.

This confirms the research's central unknown: news/Wikipedia-trained zero-shot
RE does **not** transfer to fiction character relationships. GLiREL is not the
GLiNER-style win. The encoder path is dead unless someone fine-tunes weights on
fiction relationship data — out of scope.

#### Path forward

The research's fallback stands and is now the recommendation: **two-stage
pairwise LLM classifier** — enumerate character pairs, classify each pair
independently against a relation label set ("A→B: lover / sister / none?").
Bounded classification, not open generation; no new dependencies; invented
edges structurally impossible. Combined with the §15.23 name-list filter, this
is the realistic relationship-discovery improvement. Not yet built.

**1615/1615 tests green.**

### 15.26 Session ledger — 2026-05-16/17 (two-stage relationship classifier)

Built the two-stage pairwise relationship classifier (the §15.25 / research
recommendation), live-probed it, and fixed two bugs the probe caught. 2 commits.
Tests 1615 → 1601 (net — the dead single-call path + its tests removed).

#### The classifier

`OllamaRelationshipDiscoveryExtractor` no longer makes one open "list every
relationship" call. Instead: stage 1 enumerates the character pairs that
co-occur in the scene (`candidatePairs`); stage 2 fires one bounded "what is A
to B?" call per pair (`buildPairClassificationPrompt` / `parsePairClassification`)
— the model names the single relationship or answers "none". Per-pair calls
fan out; a pair whose call derails contributes no edge rather than poisoning
the scene; the parser restricts each answer to the asked pair, so invented
endpoints are structurally impossible. The dead single-call prompt / JSON /
line-list functions and their tests were removed.

#### Live-probe findings (test2 Scene 2 — the dense explicit scene)

Two bugs surfaced and were fixed:
- **num_predict 256 too low** — gemma emits a reasoning preamble before the
  answer and hit the length cap with *empty content* on every call. Raised to
  2048.
- **Prompt placeholder echo** — "from | to | kind | status" made gemma echo the
  literal words instead of substituting names. Replaced with a worked example
  using the real character names.

With both fixed, the probe recovered **all four** of the scene's Abby
relationships (mother/Judy, mother/Allie, lover/Megan, wife/Lucas) — the
parent/spouse edges the old single-call approach missed *every run*. Real recall
win. Residual: gemma still over-eagerly invents edges for ~3 genuinely
unrelated pairs (the Megan/Judy, Megan/Allie, Megan/Lucas pairs) — bounded
classification *reduces* but doesn't *eliminate* small-model hallucination.

#### Open follow-ups — consolidated next steps

1. **Relationship-discovery precision.** The two-stage classifier now recalls
   well but gemma still over-eagerly invents edges for unrelated pairs.
   Untried levers: a stricter binary "is there ANY relationship?" pre-filter,
   self-consistency voting (3× per pair, majority), or a stronger Stage model.
2. **In-app exercise.** GLiNER entity discovery, two-stage relationship
   discovery, and the relationship mapper are all unit-tested and (the mapper)
   browser-verified — but none has been exercised in the *running* `Loom.app`
   against a real on-disk project. That Swift-round-trip smoke is the
   highest-value verification left.
3. **Stage D latency** — ~52s on dense scenes (§15.22). Levers: drop Stage D's
   `format` schema constraint, or a faster Stage D model.
4. **Carried from §15.17–15.18:** Phase 9/10 live-smoke; the writer-model A/B
   against Goetia (Mistral-V7 template + per-family samplers should auto-apply).

Closed this arc: GLiREL is **dead** — do not re-spike (§15.25). The relationship
mapper is **feature-complete** (§15.24). GLiNER long-scene chunking is **done**
(§15.21).

#### Investigation cleanup

Removed the GLiNER/GLiREL spike clutter: `/tmp/gliner_spike` (1.1 GB), the
GLiNER HF cache entries (0.6 GB), the uv package cache (2.5 GB), the pip cache
— ~4.7 GB off the system disk — plus the throwaway GLiREL venv on SSD1
(4.2 GB). All regenerable.

**1601/1601 tests green.**

### 15.27 Session ledger — 2026-05-17 (relationship-discovery precision — levers exhausted)

Picked up §15.26 next-step #1 (relationship-discovery precision). The in-app
smoke (#2) was deferred by the user — it needs the AppKit GUI + a live local
LLM, which can't be driven autonomously. Tests 1601 → 1618. Outcome: every
precision lever was tried and live-probed; none works (see verdict below).

#### Self-consistency voting

The two-stage classifier recalls well but gemma still over-eagerly invents
edges for genuinely unrelated pairs (§15.26: ~3 per dense scene). Of the three
untried levers, **self-consistency voting** was chosen: it is structural (not
prompt-tuning — `feedback_prompt_blacklist_evasion` warns against the latter),
reuses the already-probed prompt unchanged, and is fully deterministically
unit-testable.

- `RelationshipDiscovery.voteOnPair` — pure function: given K independent
  per-pair classification results, returns the edge only if a *strict
  majority* of runs found any relationship. Among the edge-finding runs the
  modal `(from, to, kind, status)` wins; ties break toward the earliest run.
  K=1 degrades to "keep any edge" (the pre-voting behaviour).
- `OllamaRelationshipDiscoveryExtractor` gained a `votingRounds` init param
  (default **3**, production via the `init(client:)` convenience init). Each
  pair now fans out `votingRounds` calls; results collect per `(pair, round)`;
  `voteOnPair` reduces each pair. Total calls = `pairs × rounds`. Existing
  orchestration tests pinned to `votingRounds: 1` (they test fan-out
  mechanics, not voting).

Rationale: gemma's residual edge invention is *unstable run-to-run* (§15.23),
so a minority vote is almost always a hallucination. A majority vote drops it
without touching recall for edges the model reliably finds.

#### Live probe — voting buys recall, not precision

Built `RelationshipDiscoveryProbe` (a committed `Tools/` runner) and probed
voting on `test2` Scene 2 (the dense 5-character explicit scene) against live
gemma4_2b. Baseline (`votingRounds=1`, 3 runs): 8/7/6 edges — visibly
unstable; 11 distinct edges, 7 in ≥2 runs, 4 in only 1. Voting (`rounds=3`)
recovered all 5 real character-pairs (recall 100% vs baseline ~87%) but
precision stayed ~62% — because the residual hallucination is **not** purely
unstable. It splits two ways: an unstable tail voting drops, and a **stable
mis-classification core** (gemma reliably calls Megan the "sister" of
Judy/Allie, in a *majority* of runs) that voting structurally cannot touch.
At 3× latency (~150s → ~432s/scene) for a recall-only gain, voting was turned
**off by default** (`votingRounds` default 3 → 1); the machinery is kept for
pairing with a precision lever.

#### Evidence gate — built, probed, does not work

Added a binary evidence gate as the precision lever:
`RelationshipDiscovery.buildRelationshipGatePrompt` asks a conservative "do
these two have a relationship?" question; `parseGateResponse` admits a pair
only if the model cites a sentence that genuinely occurs in the scene
(whitespace/case-insensitive substring check, ≥12 chars). Pure functions,
TDD'd, **not wired into the production extractor**.

Probed n=2 on Scene 2: **unstable and structurally flawed.** Run 1 looked
great (gate precision 100%, gated edges 4/4 real). Run 2 collapsed (gate
admitted 2 real + 3 unrelated, dropped 3 real; gated recall 2/5). The flaw:
the substring check kills *fabricated* quotes but not *misattributed real*
ones — run 2 admitted both Judy↔Lucas and Megan↔Lucas by citing the **same**
real sentence about *Abby's* marriage to Lucas (it contains "Lucas", so it
verifies). The gate inherits the base model's instability.

#### Stronger model (gemma4_4b) — worse, not better

Probed the §15.26 "stronger model" lever. gemma4_4b is **worse**: it never
answers "none", asserts an edge for all 10 pairs (precision 50%), and the gate
admits all 10 because 4b will always cite *some* sentence. More compliant, not
more discriminating.

#### Verdict — precision is not fixable with the available tooling

None of the levers — self-consistency voting, the evidence gate, a stronger
local model — reliably fixes relationship-discovery precision on dense
multi-character scenes. Root cause is the §15.23 verdict standing firm
(small local models too unstable here) plus the §15.25 GLiREL spike (encoder
path dead). A real fix needs a fundamentally better model or fiction-fine-
tuned weights — out of scope. **The shipped design already backstops this:**
discovery output is *proposals*, surfaced as reviewable ghost edges on the
mapper with accept/reject (§15.24). A noisy-but-complete proposal stream the
writer curates is the design — the §15.26 two-stage classifier's recall win
is the part that matters and it stands. Precision work stopped here at
empirical diminishing returns.

#### State of the committed code

- Voting machinery (`voteOnPair`, `votingRounds`) — kept, **default off**.
- Evidence gate (`buildRelationshipGatePrompt`, `parseGateResponse`) — kept as
  tested opt-in pure functions, **unused by production**, in case a future
  better model makes the gate viable.
- `OllamaRelationshipDiscoveryExtractor` production behaviour is unchanged
  from §15.26 (one typed call per pair, no gate).
- `Tools/RelationshipDiscoveryProbe` — committed; the record of the above.

#### Open follow-ups carried forward

- In-app smoke — GLiNER discovery, relationship discovery, the mapper — the
  Swift round-trip against a real on-disk project (§15.26 #2). Still the
  highest-value verification left.
- Stage D latency (~52s on dense scenes); Phase 9/10 live-smoke; Goetia A/B.

**1618/1618 tests green.** (1601 → 1618: +6 `voteOnPair`, +3 voting
orchestration, +8 evidence-gate; the extractor was not refactored.)

### 15.28 Session ledger — 2026-05-17 (entity-detection fixes + writer-model A/B)

Continuation of §15.27. An in-app session: the user ran the carried-forward
writer-model A/B (Goetia vs gemma 4 31B) on a fresh ~490-word seed scene in
the running `Loom.app`, which incidentally exercised entity discovery against
real on-disk projects and surfaced three real bugs. Tests 1618 → 1627. The
app was rebuilt + relaunched twice as fixes landed.

#### Entity detection — three fixes from live use

The seed scene was run through entity discovery in two fresh projects (test3,
test4). Three bugs surfaced; each was TDD'd and re-validated via
`EntityDiscoverySpike` against the 8-scene graded fixture + test2 (the spike's
inline Stage D was updated alongside so the harness keeps mirroring
production).

1. **GLiNER threshold 0.5 → 0.45.** First run found only 1 of the scene's 2
   characters. The new `EntityDetectionProbe` (committed `Tools/`) dumps every
   span's sigmoid score: "Della" scored **0.492** on both mentions — GLiNER's
   0.5 Python-default cutoff rejected it by 0.008, while pronoun noise sat far
   below (~0.31), leaving a clean gap. `GLiNERDetector.defaultThreshold`
   lowered to 0.45. Graded fixture + test2 both stay 100% F1.

2. **Stage D normalisation runs unconstrained.** Next run: both names
   detected, but "Marcus" lost — `Stage D parse failed: malformedJSON`. The
   §15.19/§15.22 pathology: Ollama's `format`-constrained sampling
   intermittently degenerates on gemma4_2b, truncating the JSON object.
   `EntityDiscoveryPipeline.runStageD` now passes `schema: [:]` and pins the
   shape in-prompt via a worked example (the §15.19 Stage A2 fix). 0 Stage D
   parse failures after.

3. **Generic-label drop.** The unconstrained Stage D, being more *consistent*,
   surfaced a latent FP: a first-person narrator GLiNER tags gets normalised
   to a generic role label ("The Character" / "The Narrator").
   `EntityDiscovery.isGenericPersonLabel` flags a canonical name composed
   wholly of generic person/role nouns (after a leading determiner);
   `runStageD` drops those survivors. Both fixtures returned to **100%
   precision / recall / F1**.

Net: entity discovery on the seed scene now proposes both Della + Marcus
cleanly. Residual by-design behaviour: single-mention places ("Pell Lake")
are still dropped by the place-recurrence filter, and "the Hartley house"
(GLiNER score 0.303) stays below threshold — pronoun noise sits at that
level, so the threshold can't cleanly recover settings.

#### Writer-model A/B — Goetia vs gemma 4 31B

Both models continued the identical seed (cut on a deliberate *manual* beat —
"His hand moved against her, slow and deliberate"). Verdict: **Goetia is the
better fit as the writer model for this app's purpose (explicit fiction).**

- **Continuation-point fidelity** — Goetia continued the manual thread the
  seed actually stopped on (slow build → her climax → "Your turn" → penetration).
  gemma skipped it, jumping straight to intercourse — it overrode the handoff.
- **Explicit register** — Goetia writes the strong-NSFW payoff fluently and
  specifically; gemma stays euphemistic and reticent ("pushed through her
  resistance" is its peak), fading toward the literary/suggestive.
- **Continuity** — Goetia reused an established trait, calling Marcus's
  hesitation "another one of those old-fashioned courtesies" — a callback to
  the seed's "the gentleman in him, always asking first."
- **gemma's edge** — more elevated literary prose and stronger interiority
  (it found a genuine emotional beat: "I don't want you to leave / I know.
  Me too."). Worth not losing if a register switch is ever wanted.

**Decision (2026-05-17): Goetia is now the default writer model**; gemma 4
31B is the noted alternative. There is no Loom-side writer-model setting —
the kobold "Default" server serves whatever GGUF is loaded in KoboldCpp, and
`SamplerParams.familyOverride` already maps "goetia" to the Mistral-Small
sampler family, so the switch needed no code change.

#### Tooling added (committed)

- `Tools/RelationshipDiscoveryProbe` — §15.27's relationship precision probe.
- `Tools/EntityDetectionProbe` — runs GLiNER on a scene file at a low
  threshold, dumps every span's sigmoid score; how the "Della" miss was
  diagnosed.

#### Open follow-ups carried forward

- In-app smoke of relationship discovery + the mapper (§15.26 #2) — entity
  discovery is now the only one of the three exercised live.
- Stage D latency (~52s, ~100s on the dense test2 scene); Phase 9/10
  live-smoke beyond what this session covered.

**1627/1627 tests green.** (1618 → 1627: +1 threshold pin, +2 Stage D
unconstrained, +6 generic-label.)

### 15.29 Session ledger — 2026-05-17 (Planned Project mode — design + Phase 1)

A new major feature was scoped, researched, designed, and its first
phase built. Tests 1627 → 1665.

#### Design

**Planned Project mode** — a guided project-creation path: a character
sketch + plot premise → an editable manuscript outline (named
chapters/scenes), sized by a length scenario, with assignable, mixable
genre/register "styles" threaded into all generation. Full design in
[`LOOM_PLANNED_PROJECT.md`](LOOM_PLANNED_PROJECT.md) — five phases,
locked decisions, the staged outline pipeline, data model, reuse map.
Two research passes informed it (internal codebase audit + external
best-practice); a third verified the style-corpus claim (§3.4 of the
doc). Key reuse finding: the `Manuscript → Part → Chapter → Scene`
hierarchy and a stubbed `PromptBuilder` style slot already exist.

#### Phase 1 — Foundations (shipped, 8 commits)

Pure-data spine, fully TDD, no UI and no LLM:

- `LengthScenario` — five format presets with word-count bands.
- `OutlineSizing` — deterministic scene/chapter allocator + 25/50/25
  act split (counts computed in code, never asked of the LLM).
- `StoryFramework` protocol + registry + `SaveTheCatFramework` (15
  beats) — extensible for more frameworks later.
- `Style` / `StyleType` — typed (genre/register) style record,
  forward-load tolerant.
- `StyleLibraryStore` — app-level `styles.json`, seeded on first run,
  writer-owned after; mirrors `AppSettingsStore`.
- `StyleLibrary.builtInStarters` — 12 genres + 10 registers; constraint
  lists cross-checked against EQ-Bench criteria (MIT) + SillyTavern
  explicit-writing craft patterns.
- `PlannedProjectConfig` — guided-planning record, additive-optional
  on `Project` (forward-load contract pinned).

#### Process note

One claim ("no downloadable style corpus exists") was asserted without
research, caught by the user, then verified by a focused pass — it
held, but two adaptable open sources were folded into the starter
constraints. `feedback_verify_research_claims` applies: verify negative
gap claims *before* scoping work around them.

#### Open follow-ups

- Phase 2 — the outline-generation pipeline (premise → beats → chapter
  map → scenes); likely wants a probe/spike to tune prompts on the
  small model first.
- Phases 3–5 — style wiring, the guided-creation UI, outline-driven
  writing.

**1665/1665 tests green.** (1627 → 1665: +33 across the seven Phase 1
work items.)

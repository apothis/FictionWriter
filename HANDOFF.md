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

- **rewriteTense no-op-target failure mode.** Reproducible both ways: when the user picks a target tense that matches the source's current tense, the writer model invents an unrelated transformation (past+past target → present output; present+present target → future output, observed live 2026-05-13). A first-attempt fix tightening the rewriteTense system prompt with explicit no-op-target language made the failure **catastrophically worse** — the model entered a degenerate sampling cascade with synonym-runaway and meta-commentary leakage ("What follows next is a continuation of the scene as described below:..." into pure token soup). That prompt change has been rolled back (commit `TBD`). Diagnosis: asking the writer (Qwen3.6-27B-Uncensored-HauhauCS-Aggressive) to "rewrite to be what it already is" is meaningless to it as a task; prompt engineering with negative framing + self-referential clauses pushed it from confused output into degenerate decoding. **Right fix is upstream of the model:** detect the source tense at the picker/handler layer, either (a) disable the matching-tense option in the Rewrite menu when the source clearly already uses that tense, OR (b) short-circuit at click time with a tray message ("This passage is already in past tense — nothing to rewrite"). Both require an English tense-detection heuristic (regex over past-tense markers vs present-tense forms across the selection) — tractable but non-trivial. Phase 4.x slice. In the meantime: don't pick a matching-tense option in the menu; pick the OTHER tense to verify the genuine transformation path (which works correctly).

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

- **ThinkBlockStripper only runs post-finish; thinking tags visible during streaming.** `EditorViewController.stripThinkBlocks(in:)` ([EditorViewController.swift:885](Sources/LoomCore/UI/EditorViewController.swift:885)) is called only at generation finish, so during streaming the user sees the raw `<think>...</think>` or `<|channel>thought\n<channel|>` tokens land in the text view as the model emits them. They get cleaned the moment the stream ends, but for the 60–120s of a Gemma 4 31B Continue the noise is visible. Surfaced during 2026-05-13 Gemma 4 31B comparison testing. Cosmetic — final output is clean, no data loss — but a real UX paper-cut, especially when the channel-thought block consumes the first several seconds of the stream and the user can't tell whether anything useful is coming. **Fix shape (Phase 4.x, ~30 min):** streaming-aware buffering in the editor's token-insert path. State machine: when an opening tag (`<think>` or `<|channel>thought`) starts appearing in the stream, buffer subsequent tokens off-view until the matching close (`</think>` or `<channel|>`) is seen, then resume inserting from the stream after the close. Unclosed tag at finish: defer to the post-finish stripper (which already preserves unclosed tags as a visible signal).

- **No UI surface to override instruct-template auto-detection.** `Project.settings.instructTemplate: InstructTemplate` exists ([Project.swift:109](Sources/LoomCore/Models/Project.swift:109)) and defaults to `.auto`, which probes the writer's model name and routes through `InstructTemplates.detect(forModelName:)` ([InstructTemplates.swift:37](Sources/LoomCore/Generation/InstructTemplates.swift:37)). If the probed name doesn't contain a recognised family substring (e.g. a Gemma 4 GGUF loaded under a generic alias like `koboldcpp/gemma-27b-q4`), detection falls through to chatml and the user has **no in-app fix path** — the only override route is editing `project.json` directly, which doesn't help with an Untitled / in-memory project. The `template=` field on `[gen]` debug lines is the only way to inspect what got selected. Surfaces during the 2026-05-13 Gemma 4 27B comparison test prep. **Fix shape:** a small Settings UI surface — server profile gains an instruct-template picker (Auto / ChatML / Gemma 4 / Gemma 1-3 / Llama 3 / Mistral V3 / Mistral V7) that overrides the auto-detection per server. Natural home is the Phase 4.5 Bible Workspace (or its sibling Servers Workspace) — would land alongside the bigger settings redesign rather than retrofitting the current cramped Servers tab.

- **Sidebar's "Set POV" vs Rewrite picker's POV target — clarify in UI.** Live test 2026-05-13 Test 6 surfaced UX confusion: the user set `Scene.pov = Jamie` via the sidebar BEFORE picking *"Rewrite → POV — Jamie"* in the picker, thinking the two needed to match. They don't — the two are genuinely different operations: sidebar's *Set POV* assigns the scene's editorial POV (drives Continue's `[KNOWLEDGE-LEDGER]` prompt layer, permanent until changed); the picker's *POV — X* is the target POV for THIS rewrite only (doesn't change Scene.pov, doesn't read Scene.pov). The classic use case for rewritePOV is *swap*: Scene.pov = X, picker = Y. Worth a small tooltip / menu label clarification so the distinction is visible at the picker: e.g. *"Rewrite to Jamie's POV"* rather than *"POV — Jamie"*, AND a tooltip on the sidebar's Set POV explaining "drives Continue's knowledge-ledger context; doesn't affect Rewrite operations". Trivial fix once we have a free moment.

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

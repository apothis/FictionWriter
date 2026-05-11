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
6. **rewriteTense + rewriteLength prompt layers** + one coherent sub-mode picker UI covering Voice/Tense/Length.
7. **Knowledge-ledger pipeline** (#5 fully cleared the gate including the extractor-model prerequisite; PROCEED): post-scene side-call → diff → Bible-inspector Suggestions chip → user accept/reject → `[KNOWLEDGE-LEDGER]` prompt layer below cache boundary. The role-routed summariser server is **Ollama running abliterated `gemma4_2b`** (Round-5 result: same 0.80 recall as the larger gemma4_4b sibling but **1.86× faster** wall-clock — 43s/scene vs 80s/scene; both 100% recall on NSFW scenes). The `LedgerExtraction` module ships the JSON Schema generator + the Ollama-shaped backend in the spike runner — wire the same path into the production extractor. Compute `unknown` from per-character scene-exposure (SymbolicToM, [LOOM_STORY_BIBLE §3.5](LOOM_STORY_BIBLE.md)). Wire the §10.5 production filters (fact deduplication, evidence-quote validation, prompt-leakage filter) between extraction and Suggestions display to trim the high-FP output.
8. **rewritePOV** (after ledger lands — §4.3 `KNOWLEDGE_LEDGER_HINT` slot has data to fill).
9. **Show-don't-tell** (independent, selection-replace pattern).
10. **Lorebook editing UI** in the Bible inspector — schema + injection plumbing already shipped Phase 2; the inspector list-detail surface gains a Lorebook section with per-entry edit form. (Without this, the sphiratrioth pack is installable but not customisable in-app — users currently edit via `bible/lorebook.json`.)
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
6. **Compute `unknown` from scene-exposure** at query time. Pure-data; needs scene-presence per character (Phase 2 mention-index gives us this for free).
7. **Render the `[KNOWLEDGE-LEDGER]` prompt layer** below the cache boundary at generation time (LOOM_MEMORY §4.1).
8. **The §10.5 production filters** — fact deduplication (embed → cluster cosine ≥ 0.85), evidence-quote validation (drop facts whose evidence has no high-cosine sentence in the prose), prompt-leakage filter — between extraction and Suggestions display.

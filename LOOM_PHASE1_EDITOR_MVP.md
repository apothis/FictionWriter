# Loom Phase 1 — Editor MVP

> **Status: Phase 0 design lock (2026-05-10).** Sub-step contracts mirror `/Volumes/SSD1/Code/RPClient/V2_UI_OVERHAUL.md` §4.11 format. Companion to [`LOOM_PLAN.md`](LOOM_PLAN.md), [`LOOM_DESIGN_LANGUAGE.md`](LOOM_DESIGN_LANGUAGE.md), [`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md), [`LOOM_GENERATION_MODES.md`](LOOM_GENERATION_MODES.md).
>
> **Goal:** ship a minimal but coherent editor where a user types a sketch, clicks Expand, and gets prose. Or types a paragraph, clicks Continue, and gets prose. Saves as Markdown.

---

## 1. Definition of done (Phase 1)

The end-state demo:

1. User runs `./run.sh`, app launches.
2. `File → New Project` (or empty-state button) → file picker → user names `MyNovel.loom`. Directory created on disk per [`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md) §7.
3. Empty editor + sidebar with "Scene 1" + Bible inspector with placeholder.
4. User types a paragraph sketch in the editor.
5. User selects the sketch and clicks **Expand** in the generation tray.
6. Acceptance UI appears with generated prose; user clicks Accept.
7. User adds a character (name + description paragraph) in the Bible inspector.
8. User positions cursor at end, clicks **Continue**. New prose appended; user accepts.
9. User clicks the **History** disclosure → sees a chiclet for "20k recent prose" + "Mia (character)" + "Author's Note (empty)" + "Memory (empty)" → expands one to see the full content sent.
10. User saves. Closes the project. Reopens via `File → Open Project`. Everything intact.
11. User exports → single `.md` file with frontmatter; project Markdown opens cleanly in iA Writer / Obsidian.

That's the demo. Anything beyond this is Phase 2+.

---

## 2. Out of scope for Phase 1

To stay shippable:

- Full Bible inspector (Settings, Objects, Factions, Timeline, Lorebook). Phase 1 has Characters only, with name + paragraph description.
- Knowledge ledger. Phase 4+.
- Style ingestion. Phase 5.
- Rewrite, Brainstorm, Critique, Bridge, Describe modes. Phase 4.
- Snapshots. Phase 2.
- Hierarchical Parts/Chapters. Phase 1 ships a flat scene list under the project root.
- Corkboard view. Phase 3.
- Variant scenes. Phase 2+.
- Per-scene metadata UI (POV / time / location / conflict / outcome editing). The schema exists; UI is Phase 2.
- Markdown preview mode toggle (`⌘⇧P`). Phase 2 polish.
- Project-wide search (`⌘⇧F`). Phase 6.
- Auto-save / version history. Auto-save will land in 1.j (cheap); explicit version history is Phase 6.

---

## 3. Sub-step staging

Sub-steps named `1.a` through `1.m`. Each is a focused diff with clear test posture. Every pure-data helper gets tests-first (TestKit, not XCTest, per the user's environment).

| Sub | Title | Status | Estimate |
|---|---|---|---|
| 1.a | Project bootstrap (Package.swift + build/run scripts + AppDelegate) | pending | ~½ day |
| 1.b | Storage layer + Project / Scene Codable + on-disk format | pending | ~1 day |
| 1.c | KoboldClient + ServerProbe carryover from RPClient | pending | ~½ day |
| 1.d | DesignTokens + EmptyState + main window scaffold | pending | ~½ day |
| 1.e | Sidebar (Binder) — flat scene list, NSOutlineView | pending | ~1 day |
| 1.f | EditorView — NSTextView + scroll + width | pending | ~½ day |
| 1.g | Inspector pane — tabs + Bible (Characters only) + History stubs | pending | ~1 day |
| 1.h | Generation tray + GenerationMode plumbing | pending | ~½ day |
| 1.i | PromptBuilder + Continue mode end-to-end | pending | ~1.5 days |
| 1.j | Expand mode + acceptance UI + auto-save | pending | ~1 day |
| 1.k | History inspector + chiclets + generation-log writes | pending | ~1 day |
| 1.l | Markdown export | pending | ~½ day |
| 1.m | Smoke + polish (open/close/reopen, error handling, missing-server states) | pending | ~½ day |

Total: ~9.5 days serial; can compress to 7–8 with parallel-able sub-steps once the data model and storage land (1.b unblocks 1.f, 1.g, 1.i; 1.c unblocks 1.i).

---

## 4. Sub-step contracts

### 1.a — Project bootstrap

**What.** Stand up the Swift Package + build scripts + AppDelegate. Empty NSWindow opens via `./run.sh`.

**Tasks:**
- Copy RPClient's `Package.swift` shape; rename modules `LoomCore` (replaces `RPClientCore`), `Loom` (replaces `RPClient`), `LoomCoreTests`.
- Copy `build.sh` + `run.sh`, sed `RPClient` → `Loom`. Verify ad-hoc signing works against `Loom.app`.
- New `AppDelegate.swift` with `NSApplicationDelegateAdaptor`-style entry point (or pure AppKit equivalent — RPClient is pure AppKit).
- Empty `MainWindowController` showing a blank window.
- `DebugLog.shared.write("[loom] launched")` on first launch.

**Test posture:** smoke only. `./build.sh && ./run.sh` opens an empty window.

**Definition of done:** `Loom.app` launches, displays an empty window, exits cleanly. No crash on second launch.

---

### 1.b — Storage layer + Codable

**What.** Implement `Project`, `Scene`, `Character` (minimal) Codable shapes from [`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md). Implement project-on-disk read + write + create.

**Tasks:**
- `Project.swift`, `Scene.swift`, `Character.swift`, `Bible.swift` — Codable structs.
- `ProjectStorage.swift` — `createNewProject(at: URL, title: String) throws -> Project`, `loadProject(from: URL) throws -> Project`, `saveProject(_ project: Project) throws`.
- Scene save: write `scenes/<id>.md` with YAML frontmatter + prose body.
- Scene load: parse YAML frontmatter + prose body.
- Round-trip property: load + save + load yields identical `Project`.

**Tests (TestKit, tests-first):**
- `Phase1ProjectCodable` — round-trip of empty Project, populated Project.
- `Phase1SceneFrontmatter` — YAML frontmatter encoding/decoding; preserves user-edited prose; tolerates external edits to non-Loom-managed YAML keys (forward-compat).
- `Phase1ProjectStorage` — create new project, save scenes to it, load back. Verify directory shape.
- `Phase1SchemaVersion` — `decodeIfPresent` migration smoke; legacy missing fields default cleanly.

**Definition of done:** ~12 tests pass. Round-trip of a 3-scene + 2-character project works on disk.

---

### 1.c — KoboldClient + ServerProbe carryover

**What.** Direct copy of RPClient's `KoboldClient.swift`, `KoboldClientRegistry.swift`, `ServerProbe.swift`, `KoboldGenerating.swift` protocol with namespace adjustments.

**Tasks:**
- Copy files; replace `import RPClientCore` with `LoomCore` self-references.
- Adapt `Settings` to Loom's smaller settings shape (no chat-specific fields; per [`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md) §1).
- `LoomCore.AppState` minimal singleton holding `[ServerProfile]` and the registry.
- Smoke: connect to a running koboldcpp on localhost; verify `/api/v1/model` returns name; `/api/extra/version` returns version; `/api/extra/true_max_context_length` returns ctx.

**Tests:**
- `Phase1KoboldClientSmoke` — happy path against a live koboldcpp (smoke-only; no faked tests per `feedback_tdd_workflow`).

**Definition of done:** Loom can probe a running koboldcpp instance and report model name + ctx in a debug log line.

---

### 1.d — DesignTokens + main window scaffold

**What.** Bring over `DesignTokens.swift` (the in-code embodiment of [`LOOM_DESIGN_LANGUAGE.md`](LOOM_DESIGN_LANGUAGE.md) §1–§13) plus add the Loom-specific tokens for the editor surface.

**Tasks:**
- Copy RPClient's `DesignTokens.swift` (typography names, spacing tokens, color helpers, motion durations).
- Add `Editor` namespace tokens: `editorMaxWidth = 720`, `sidebarMinWidth = 180`, `sidebarDefaultWidth = 240`, `inspectorMinWidth = 240`, `inspectorDefaultWidth = 320`.
- `MainWindowController` lays out an `NSSplitViewController` with three split items: sidebar / editor / inspector.
- Default sizes per tokens; persist resized widths to `~/Library/Application Support/Loom/window-state.json`.

**Tests:**
- `Phase1DesignTokens` — token aliasing rules (Editor.editorMaxWidth not duplicated against existing tokens).

**Definition of done:** window opens with three-pane split. User can drag-resize. Widths persist across app relaunches.

---

### 1.e — Sidebar (Binder)

**What.** Flat scene list (no Parts/Chapters yet). NSOutlineView. Add scene, rename, delete (to Trash). Drag-rearrange.

**Tasks:**
- `SidebarController` wrapping `NSOutlineView`.
- `NSOutlineViewDataSource` + `NSOutlineViewDelegate`.
- Row content: scene title (`headline`), word count subline (`subheadline secondary`).
- Add scene: `+` button at sidebar bottom, or context menu "New scene." Lands at end of list; cursor moves into editor.
- Rename: click title twice (or right-click → Rename). Inline edit (Notion pattern §11 of design language).
- Delete: right-click → Delete → confirms → moves to Trash group.
- Drag-rearrange: native NSOutlineView pasteboard support.
- Persist order to `Project.manuscript.orphanedSceneIds`.

**Tests:**
- `Phase1SidebarOrdering` — pure-data: reorder operations on `[UUID]` produce expected sequences.
- `Phase1SidebarDelete` — delete moves to Trash, doesn't remove from disk.

**Definition of done:** can add 5 scenes, rearrange, rename, delete one. Reopens project with intact order.

---

### 1.f — Editor pane

**What.** NSTextView with scroll, width-constrained centred content, per [`LOOM_DESIGN_LANGUAGE.md`](LOOM_DESIGN_LANGUAGE.md) §14.4.

**Tasks:**
- `EditorViewController` with `NSTextView` inside `NSScrollView`.
- Text-storage backed by `Scene.prose` (loaded from `scenes/<id>.md` body).
- Width constraint: 720pt centred via leading/trailing constraints + container view.
- Default font: `NSFont.preferredFont(forTextStyle: .body)`. Line height 1.45.
- `usesFindBar = true` (free find/replace).
- Auto-saves prose to disk on a debounce (500ms) — sub-step 1.j adds the file-write.
- Word count updates emit a `wordCountChanged` notification.

**Tests:**
- `Phase1EditorWordCount` — pure helper for counting words in prose; handles markdown headers, blockquotes, italics correctly.

**Definition of done:** typing in editor updates the model in memory. Switching scenes in sidebar swaps the editor's text content.

---

### 1.g — Inspector pane (Bible: Characters only + History stubs)

**What.** Tabbed inspector per [`LOOM_DESIGN_LANGUAGE.md`](LOOM_DESIGN_LANGUAGE.md) §14.5. Phase 1 has only Characters under Bible; History is plumbed but stubbed; Notes works.

**Tasks:**
- `InspectorController` with `NSSegmentedControl` for tab switching: Bible / History / Notes.
- Bible tab: collapsible "Characters" section; `+` button adds; click row to expand to inline-edit form (name + description paragraph).
- History tab: empty state "No generations yet." Real implementation in 1.k.
- Notes tab: simple `NSTextView` wired to `Project.notes` (a String field on `Project`).

**Tests:**
- `Phase1CharacterAdd` — pure: adding a character to a `Project` produces expected Bible state.
- `Phase1InspectorTabPersistence` — selected tab persists per project across reopens.

**Definition of done:** can add 3 characters, edit them, save, reopen, see them. Notes persists.

---

### 1.h — Generation tray + GenerationMode plumbing

**What.** Bottom-pinned generation tray below editor. Mode buttons. Token estimate. Disabled-when-cant-generate logic.

**Tasks:**
- `GenerationTrayView` — horizontal `NSStackView` with `Continue`, `Expand`, `Rewrite (disabled, Phase 4)`, `Brainstorm (disabled)`, `Critique (disabled)` buttons. RPClient `DesignTokens` styling.
- Token estimate label trailing-edge; updates on selection or cursor move (debounced 200ms).
- Mode-button enable logic: Continue when cursor present, prose non-empty; Expand when selection non-empty.
- History disclosure beneath buttons (collapsed by default; expands inline).

**Tests:**
- `Phase1GenerationModeAvailability` — pure: given a `(prose, selection)` state, which modes are enabled?

**Definition of done:** tray renders correctly, buttons enable/disable per state. Clicking does nothing yet (1.i wires it).

---

### 1.i — PromptBuilder + Continue end-to-end

**What.** The load-bearing sub-step. New `PromptBuilder` for story-mode (not chat-mode); Continue mode wires through to KoboldClient and inserts prose.

**Tasks:**
- New `PromptBuilder.swift` (NOT a copy of RPClient's chat-shaped one — see [`LOOM_RESEARCH.md`](LOOM_RESEARCH.md) §O.6).
- Implements the layered assembly per [`LOOM_GENERATION_MODES.md`](LOOM_GENERATION_MODES.md) §1.1.
- Phase 1 layers wired: System / Memory / Bible-Constant (always-include characters) / Recent-prose / Author's Note / Mode-instruction.
- Token-budget allocation per [`LOOM_GENERATION_MODES.md`](LOOM_GENERATION_MODES.md) §1.2 at user's `contextBudgetTokens` setting.
- Instruct-template handler: Phase 1 supports `chatml`, `mistralV3`, `mistralV7`, `llama3`, `alpaca`, `raw`, `auto` (probe-and-detect on `auto`).
- Continue mode: user clicks button → PromptBuilder assembles → KoboldClient streams → tokens land in editor as ghost text → completion fires Acceptance UI.
- `[gen] continue: ctx=4500 reply=512 model=Qwen2.5-72B` debug log line.

**Tests:**
- `Phase1PromptBuilderLayers` (~12) — pure: each layer renders correctly; budget eviction works.
- `Phase1InstructTemplate` (~6) — pure: each template wraps correctly; `auto` detection from model name.
- `Phase1RecentProseWindow` (~4) — pure: extract last N tokens of prose given cursor position.

**Definition of done:** click Continue with prose in editor → prose continues. Output is in the right voice. History chiclets recorded (even if UI is stubbed in 1.k).

---

### 1.j — Expand mode + acceptance UI + auto-save

**What.** Expand mode wired. Acceptance UI for both Continue and Expand. Auto-save to disk.

**Tasks:**
- Expand mode: same PromptBuilder pipeline; selection becomes the "Sketch to expand" framed at bottom.
- AcceptanceOverlayView: 6pt accent rule, `Accept`, `Reject`, `Keep & redo` buttons floating above the inserted prose.
- `⏎` accepts (in acceptance state); `⌫` rejects; `⌘⇧R` re-rolls.
- Type-to-accept: typing into the inserted block implicitly accepts and dismisses the overlay.
- Auto-save: 500ms debounce after each text change writes scene's `.md` file; project metadata writes on scene-add/delete/rename only (not per-keystroke).

**Tests:**
- `Phase1AcceptanceState` (~6) — pure: state machine for Accept / Reject / Implicit Accept / Redo.
- `Phase1AutoSaveDebounce` (~3) — pure: debounce coalesces rapid edits to one write.

**Definition of done:** Expand on a sketch produces 1500–2500 words. Accept/Reject works. Closing app and reopening shows the saved prose.

---

### 1.k — History inspector + chiclets + generation-log writes

**What.** History tab now functional. Each generation writes a log file; History tab pages over them.

**Tasks:**
- `HistoryInspectorController` reads `<project>/generation-log/*.json`.
- Each log entry renders as a row: timestamp · mode · model · token counts · status.
- Click row → expands inline to show chiclets (`ContextChiclet[]` from log) + full prompt (collapsed, click to expand) + raw response (collapsed).
- Buttons per row: `Re-roll` (resends the recorded prompt), `Insert again` (pastes the response at cursor).
- `[gen] log-written: <path>` debug log line per write.

**Tests:**
- `Phase1HistoryLogReadWrite` (~5) — pure: round-trip GenerationLogEntry.
- `Phase1ChicletExpansion` (~3) — pure: expand-collapse state.

**Definition of done:** complete a generation → History tab shows the row → expanding it reveals the chiclets and full text.

---

### 1.l — Markdown export

**What.** `File → Export as Markdown` produces a single `.md` of the entire manuscript.

**Tasks:**
- `MarkdownExporter.swift`: walks `Project.manuscript`, concatenates scenes in order with `# Chapter` separators (Phase 1: flat, so just `## Scene N` separators or unset).
- Frontmatter at top: title, author, exported-at.
- File picker → write → reveal in Finder.

**Tests:**
- `Phase1MarkdownExport` (~4) — pure: ordering, frontmatter, separator format.

**Definition of done:** export produces a `.md` file that opens cleanly in iA Writer / Obsidian / Marked.

---

### 1.m — Smoke + polish

**What.** Final pass: open / close / reopen, error states, missing-server states, edge cases.

**Tasks:**
- `File → Recent Projects` (last 5).
- "Server unreachable" inline in the generation tray when `ServerProbe` fails.
- "Project file is corrupt" alert with "Open backup?" option (one-time backup written before each save — cheap insurance).
- Refusal detection wired: yellow chip on the generation event in History; no error dialog.
- Empty-project state per [`LOOM_DESIGN_LANGUAGE.md`](LOOM_DESIGN_LANGUAGE.md) §14.7.
- Status-strip word counts working.
- Final smoke test: full demo scenario (§1) runs end-to-end against a live koboldcpp.

**Tests:**
- `Phase1ProjectCorruption` — one-shot smoke for the backup-restore path.
- `Phase1EmptyState` — pure data-shape verification.

**Definition of done:** every step in §1 ("Definition of done") works without manual workarounds.

---

## 5. Risks tracked

- **1.i — PromptBuilder is the highest-risk sub-step.** Story-mode prompt assembly diverges enough from RPClient that direct reuse fails. Budget extra time; the empirical "does the output read right?" test is subjective and may require 2-3 iterations.
- **1.c — KoboldClient assumptions.** RPClient's KoboldClient is chat-shaped in places (assumes `messages` array). Loom's calls go raw-completion-shaped or instruct-template-wrapped, but **single-prompt**. Verify the existing client supports a single-prompt flow without hacks.
- **1.f — NSTextView + width constraints + macOS 26 Liquid Glass.** RPClient §4.8 layout-stability invariants exist for chat panes; Loom's editor pane has different reflow rules (resize → re-wrap). Pre-test against macOS 26's NSTextView before assuming RPClient's TextKit usage transfers.
- **1.j — Acceptance overlay layered over NSTextView.** Floating-view-above-textview rendering on macOS can be finicky (clipping, scroll-following). Plan for an iteration here if first attempt has visual artefacts.
- **1.k — History log file proliferation.** Each generation = one file. A long writing session produces hundreds of files. Phase 6 polish should add compaction; Phase 1 is fine with the count.

---

## 6. TDD posture

Per the user's environment (TestKit, no XCTest):

- Pure-data helpers (PromptBuilder layers, frontmatter parsing, instruct templates, token counting, word counting, log file shapes, chiclet rendering) get tests-first.
- UI/glue layers (NSOutlineView wiring, sidebar drag-rearrange, NSTextView + width constraints, acceptance overlay) get **honest smoke tests**: a CLT-runnable test that constructs the controller, exercises a code path, asserts on observable state — but accepts that visual rendering can't be unit-tested.
- No faked tests. No pixel-snapshot diffs without a stable harness.

Estimated test count after Phase 1 lands: ~80–100 across the sub-steps. Pinned in `Tests/LoomCoreTests/Phase1*.swift` files mirroring RPClient's `Phase11*Tests.swift` convention.

---

## 7. Diagnostic logging

Every new subsystem emits `[subsystem] event: data` log lines from the first commit. Phase 1 subsystems:

- `[loom]` — app lifecycle.
- `[project]` — open / close / save / corruption events.
- `[editor]` — text changes (debounced summary), scene swaps, word counts.
- `[bible]` — entity adds / edits / saves.
- `[gen]` — every generation: mode / context-bytes / reply-tokens / model / elapsed-ms / refusal-detected.
- `[storage]` — disk writes.

Lines are grep-able from day one (per the user's `feedback_diagnostic_logging` posture inherited from RPClient).

---

## 8. After Phase 1

The next phase decision is between:

- **Phase 2: Story Bible v1** — full Bible inspector with all entity types; selective injection (constant/keyed); Author's Note depth-N; Sudowrite-style per-field AI-assist. The natural follow-on, builds on Phase 1's foundation.
- **Phase 3: Hierarchical structure** — Parts / Chapters / Scenes; Corkboard view; word-count goals; per-scene metadata UI.

Recommendation in [`LOOM_PLAN.md`](LOOM_PLAN.md): **Phase 2 first.** Bible content is the consistency engine; without it, Phase 3's "lots of scenes" navigation surfaces a content quality problem. Bible-then-structure matches Sudowrite's[A2] product evolution and Novelcrafter's[B1] design priority.

---

## 9. References

**Internal:**
- [`LOOM_PLAN.md`](LOOM_PLAN.md) — overall phasing.
- [`LOOM_DESIGN_LANGUAGE.md`](LOOM_DESIGN_LANGUAGE.md) §14 — Loom-specific surfaces.
- [`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md) — Codable shapes.
- [`LOOM_GENERATION_MODES.md`](LOOM_GENERATION_MODES.md) — prompt assembly.
- [`LOOM_STORY_BIBLE.md`](LOOM_STORY_BIBLE.md) — Bible mechanics.
- [`LOOM_RESEARCH.md`](LOOM_RESEARCH.md) — research citations.

**External (RPClient):**
- `Sources/RPClientCore/KoboldClient.swift` — direct reuse with namespace adjust.
- `Sources/RPClientCore/ServerProbe.swift` — direct reuse.
- `Sources/RPClientCore/KoboldClientRegistry.swift` — direct reuse.
- `Sources/RPClientCore/DebugLog.swift` — direct reuse.
- `Sources/RPClientCore/Storage.swift` — pattern reuse.
- `Sources/RPClientCore/UI/DesignTokens.swift` — direct reuse.
- `V2_UI_OVERHAUL.md` §4.11 — sub-step format precedent.
- `build.sh`, `run.sh` — sed-and-adapt.

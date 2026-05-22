# How to add: a new generation mode

A worked checklist for adding a generation mode (a new verb in the tray / menu). The enum is `CaseIterable` and switched exhaustively across the codebase, so **step 1 breaks the build at every site you need to touch** — follow the compiler.

Read **Generation pipeline** first for how modes assemble into prompts.

## 1. Add the enum case

`Models/Scene.swift` → `GenerationMode`:

```swift
public enum GenerationMode: String, Codable, Equatable, CaseIterable {
    case continueProse
    …
    case yourNewMode      // ← add here
}
```

Adding the case is deliberately load-bearing: every `switch mode` in the codebase is exhaustive, so the build now fails at each site that must handle the new mode. Compile, and let the errors be your to-do list. The main sites:

## 2. Availability rule

`Editing/GenerationModeAvailability.swift` → `isEnabled(_:in:)`. Decide what editor state the mode needs:

```swift
case .yourNewMode:
    return state.hasSelection     // or .hasProse, or true
```

`EditorState` is `{ hasProse, hasSelection }`. This drives whether the tray button / menu item is enabled.

## 3. System prompt

`Generation/PromptBuilder.swift` → `systemPromptFor(mode:continueWordTarget:)`. Add the case with the mode's system preamble — what the model is being asked to do, structurally. Keep it positive (what the prose should do), include the scope-discipline clause if it's a selection-replace mode (prevents over-contextualisation).

## 4. Mode instruction

`Generation/PromptBuilder.swift` → `modeInstructionFor(mode:context:)`. This is the load-bearing layer — it lands **after** the prose in the user block, the strongest-steering slot. For a selection mode, frame the selection here (`selectionText(in: context)`); for a cursor mode, the terminal "continue from here / output only X" instruction.

## 5. Snapshot policy (if destructive)

`Storage/SnapshotStore.swift` → `SnapshotPolicy.shouldSnapshot(beforeMode:)`. If the mode **replaces** existing prose (like the rewrite family), return `true` so a pre-mode snapshot is captured. Additive modes (insert at cursor) return `false`.

## 6. UI trigger

Three places a mode can be triggered — pick one:

- **A tray button** — `UI/GenerationTrayView.swift`: add a `makeModeButton`, an `on…Clicked` closure, and include it in `editingButtons.setViews([...])`. (Note: Brainstorm + Critique buttons exist but are inert — don't model new work on them until they're wired.)
- **A Rewrite sub-mode** — `UI/RewriteSubModeMenuBuilder.swift`: add a `RewriteSubModeChoice` to the static prefix/suffix. Best if the mode is selection-replace and conceptually a "rewrite flavour."
- **A Bible-menu item** — `AppDelegate.swift`: add an `NSMenuItem` + `@objc` handler. Best for project-content actions (like Roll Outcome / Discover Entities).

## 7. Click handler

`UI/EditorViewController.swift`: wire the trigger's closure to a `handleYourNewMode()` that resolves the editor state and calls `GenerationCoordinator.start(mode:context:)`. For sub-mode triggers, the existing `handleRewriteSubMode(_:)` is the template — it converts a `RewriteSubModeChoice` into a mode + per-call instruction.

The coordinator handles the rest: prompt build, streaming, think-strip, refusal detection, log-write, the acceptance machine.

## 8. Tests (first, per TDD)

Red → green → commit. The pure-data sites have direct unit coverage:

- **Availability** — `GenerationModeAvailability.isEnabled(.yourNewMode, in: state)` for each `EditorState`.
- **Prompt assembly** — build a `PromptContext` with `mode: .yourNewMode` and assert the system prompt + mode instruction land in the assembled prompt (the layers are inspectable on `AssembledPrompt`).
- **Snapshot policy** — `SnapshotPolicy.shouldSnapshot(beforeMode: .yourNewMode)`.
- **Sub-mode picker** (if applicable) — `RewriteSubModeMenuBuilder.choices` includes your entry with the right mode + descriptor.

`PromptBuilder` is pure, so prompt-assembly tests need no network or AppKit — construct a context, call `build`, assert on the chiclets.

## What you do NOT need to touch

- `GenerationCoordinator` — it's mode-agnostic; it calls `PromptBuilder.build` and streams. (Unless your mode needs a fundamentally different orchestration — like the template path's per-beat loop, which warranted its own `TemplateGenerationCoordinator`.)
- `GenerationLogEntry` — `mode` is already a `GenerationMode`, so it logs your new case for free.
- The History tab — renders any logged entry generically.

## The honest gotcha

The five enum cases without a UI surface (`brainstorm`, `critique`, `bridge`, `describe`, `nameSuggest`) show the trap: you can add the enum case + prompts + availability and the mode still does nothing if you don't wire a working trigger + click handler. Steps 6–7 are where a mode actually becomes reachable. Don't ship a half-wired mode that renders an inert button.

## See also

- **Generation pipeline** — how the mode's prompt is assembled.
- **Generation modes** (User Help) — the user-facing catalogue you're extending.
- **Conventions + dead ends** — the TDD + positive-prompt conventions this follows.

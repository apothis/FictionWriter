# Loom — Phase 4.5 Bible Workspace (WKWebView pilot)

> **Status: planned, not started (2026-05-12).** Five-session arc.
> First session ships the build pipeline + bridge + read-only entity
> list. See §7 *Session plan* for the work breakdown and §11 *Status
> ledger* for what's landed.
>
> **Reference back:** [`LOOM_PLAN.md`](LOOM_PLAN.md) row L4.5 +
> [`LOOM_PLAN.md`](LOOM_PLAN.md) §5 *Phase 4.5 — Bible Workspace*
> point at this doc as the authoritative scope.
>
> **Repo state at plan-start:** main branch on `06c7f1a`, 808/808
> tests passing. Three Phase 4 §15.10 slices shipped this session
> (rewriteTense no-op-target guard, streaming-aware ThinkBlockStripper,
> POV picker disambiguation). Bible Workspace is the next major arc.

---

## 1. What this is

A **second NSWindow** ("Bible Workspace") rendered via **WKWebView** for
deep entity editing. Opens on demand from the Bible menu (⌘⇧B). The
existing AppKit side-pane inspector stays for always-glanceable
mode + inject-pill workflow; the workspace is for the long-form
editing the side-pane can't fit.

Surfaces, in landing order (§7):

1. **Window shell + bridge** + read-only entity list
2. **Full character editor** — every `Character` field (relationships,
   canon-brief, custom fields, etc.)
3. **Lorebook full editor** — all 11 `LorebookEntry` fields (current
   v1 surfaces only 4 of 11)
4. **Accepted-facts examiner** — per-character KNOWS grouped by
   sceneId, with delete affordance (fills the §15.9 audit gap)
5. **Suggestions-queue review** — cross-character pending suggestions

---

## 2. Why a webview pivot (and why now, and why only here)

### 2.1 The pivot trigger

The AppKit pivot-pressure memory
([`memory/project_appkit_pivot_pressure.md`](file:///Users/kevinappleyard/.claude/projects/-Volumes-SSD1-Code-FictionWriter/memory/project_appkit_pivot_pressure.md))
has been tracking accumulating UI-bug debugging cost:

- **Phase 1.5**: ~3h on NSSegmentedControl dispatch +
  `.fullSizeContentView` titlebar-drag hijacking + auto-refit-to-104pt
  + appearance-tracking bugs.
- **Phase 4 (2026-05-11)**: ~1h+ on macOS-26's auto-refit-to-fittingSize
  cascade (window snapping from 720pt to 127pt). Worked around with a
  `.required` 400pt min-height on the bible scroll view —
  **explicitly flagged as brittle** in the memory.

Total ~4+ hours on UI bugs that are not feature work. The
fixes are stacking workarounds, not converging.

The pivot-pressure memory's instruction:
*"If a fix is brittle (multiple workarounds stacked, AppKit fighting
back), say so out loud and offer the pivot reassess as an alternative
path before sinking another hour."*

The original Phase-3 reassess gate
([`HANDOFF.md`](HANDOFF.md) §2.1) deferred the decision because the
NSCollectionView Plan-view spike landed cleanly. That verdict is
explicitly **not permanent** — *"each new incident raises the case for
revisiting."* The Bible Workspace's surface area — multi-pane forms
with deeply-nested schemas, grouped lists, eventually a corkboard —
is precisely the case where AppKit's per-feature cost compounds.

### 2.2 Why this is a contained pilot, not a rewrite

The original WKWebView pushback ([`HANDOFF.md`](HANDOFF.md) §2.1) was
specifically about **the editor surface**. NSTextView is the
centerpiece: native streaming inserts, undo/redo, find/replace,
autocorrect, dictation, accessibility, focus-mode — months of work to
re-implement in `contenteditable`. The "AppKit-default" decision was
load-bearing **for the editor**, not for forms.

This pivot is intentional and scoped:

- **Main editor**: stays AppKit indefinitely.
- **Side-pane inspector**: stays AppKit (already there, works for
  glance mode).
- **Plan view + Manuscript sidebar**: stays AppKit (NSCollectionView
  spike landed clean).
- **Bible Workspace**: WKWebView pilot.
- **Future corkboard**: lives in the workspace stack if the pilot
  succeeds (CSS grid + dnd-kit is unambiguously superior to
  NSCollectionView pasteboards for that use case).

### 2.3 Why this surface is the right pilot

Five reasons, in priority order:

1. **Zero existing AppKit code to migrate.** New window from scratch.
   No risk to anything that's shipped.
2. **No editor-immediacy concerns.** CRUD forms, not prose typing —
   the original NSTextView argument doesn't apply.
3. **Schema is already pure-data Swift.** `Character`, `LorebookEntry`,
   `KnownFact` are all `Codable`. JSON over `WKScriptMessageHandler`
   is trivial — Swift owns persistence, the web side renders + sends
   intent messages back.
4. **Failure mode is bounded.** If the bridge fights us we throw it
   away and ship AppKit forms — losing maybe Session 1's effort, no
   downstream damage. Pivot is locally reversible.
5. **Tests don't care.** Pure-data viewmodels stay Swift, still
   tested via TestKit. TDD discipline (§6) is preserved.

---

## 3. Strategic scope — what's in, what's out

**In scope (Phase 4.5):**

- `BibleWorkspaceWindowController` (AppKit shell, ~50 LOC,
  WKWebView contentView)
- JS↔Swift bridge: `WKScriptMessageHandler` + JSON marshalling
- Bible Workspace web bundle: Vite + React + TS + Tailwind +
  shadcn/ui (§4)
- Pure-data Swift snapshot type (`BibleWorkspaceSnapshot`) + mutation
  message types, both Codable, both TDD'd
- Five-session feature arc (§7)

**Out of scope (do NOT scope-creep into these):**

- Rewriting the main editor in webview.
- Rewriting the side-pane inspector. It stays AppKit and remains
  the glance-mode surface (mode/inject pill workflow).
- Rewriting Plan View / Manuscript sidebar.
- Adding Vitest / React Testing Library. React side is render-only
  (§6).
- Cloud sync, multi-user, anything from the [`LOOM_PLAN.md`](LOOM_PLAN.md)
  "deferred indefinitely" set.

**Deferred to Phase 5+ but designed-for:**

- Corkboard view inside the workspace (Phase 5+ scene cards;
  CSS-grid + dnd-kit).
- Factions / Timeline events / Style sheets entity types
  ([`LOOM_PLAN.md`](LOOM_PLAN.md) §5 phase-4.5 description).
- Reference-text management UI for Phase 5 RAG-for-style.

---

## 4. Tech stack — choices + rationale

| Choice | Picked | Alternatives considered | Why |
|---|---|---|---|
| Window host | WKWebView in `NSWindow` | Pure AppKit, SwiftUI form | AppKit cost ledger (§2.1); SwiftUI's macOS-26 form ergonomics are not measurably better. |
| Framework | **React 18** | Vue 3, Svelte, Solid, Lit | dnd-kit (corkboard) + shadcn/ui (forms) are React-first. Vue/Svelte have second-tier equivalents. Lit forces hand-rolling state mgmt + forms by Session 3. |
| Build tool | **Vite** | esbuild, webpack, parcel | Fast HMR, mature, zero-config-ish for React+TS. |
| Language | **TypeScript** | JS | Mirrors Swift's strictness; pays for itself the first time we refactor a field name across the bridge. |
| Styling | **Tailwind CSS** | CSS Modules, vanilla CSS, styled-components | Pairs with shadcn; utility-first means no parallel design-system files; restyling is in-place. |
| Components | **shadcn/ui** | Radix UI, Headless UI, MUI, Chakra | Copy-paste-into-repo Tailwind+Radix primitives. No framework lock-in, no `node_modules` bloat from one-off button widgets. Restyling to match Liquid Glass is editing files in our own codebase. |
| Forms | **React Hook Form + Zod** | Formik, hand-rolled | Industry standard for complex schemas; Zod schemas can mirror Swift Codable struct shapes 1:1. |
| Drag-drop (Phase 5+) | **dnd-kit** | react-dnd, sortable.js | Best keyboard-accessible drag-drop in the JS ecosystem. Future corkboard target. |
| Animations (Phase 5+) | **Framer Motion** | CSS transitions only | When accept/reject + corkboard rearrange land. Defer adding the dep until needed. |
| State mgmt | **vanilla React** (useState/useReducer/Context) | Redux, Zustand, Jotai | Bridge IS the state — Swift `ProjectSession` is source of truth. React side is rendering + intent dispatch, doesn't need a store. |
| Package manager + runtime | **Bun** | Node + npm/pnpm, Deno | Faster, self-contained, handles TS/JSX without separate tsc/esbuild. Single dev project; fewer moving parts. |

**Tradeoff to be honest about**: React + Vite + Tailwind + shadcn adds
a build step + a Bun dependency. That's the up-front tax (~2 extra
hours in Session 1). Payback starts Session 2 — shadcn primitives +
RHF/Zod reduce per-feature cost meaningfully.

---

## 5. Architecture

### 5.1 File layout

```
/Volumes/SSD1/Code/FictionWriter/
├── Sources/
│   └── LoomCore/
│       └── UI/
│           ├── BibleWorkspaceWindowController.swift   # AppKit shell
│           └── BibleWorkspaceBridge.swift              # WKScriptMessageHandler
│       └── Models/
│           └── BibleWorkspaceSnapshot.swift            # JSON contract Codable
├── Tests/
│   └── LoomCoreTests/
│       ├── Phase4_5BibleWorkspaceBridgeTests.swift     # bridge marshalling
│       └── Phase4_5BibleWorkspaceSnapshotTests.swift   # snapshot shape
├── web/
│   └── bible-workspace/
│       ├── package.json                # bun deps
│       ├── bun.lockb
│       ├── vite.config.ts
│       ├── tsconfig.json
│       ├── tailwind.config.js
│       ├── index.html                  # vite entry
│       ├── src/
│       │   ├── main.tsx                # React mount
│       │   ├── bridge.ts               # JS↔Swift messaging contract
│       │   ├── types.ts                # mirrored Swift Codable shapes
│       │   ├── components/
│       │   │   └── ui/                 # shadcn primitives (copy-pasted)
│       │   ├── views/
│       │   │   ├── EntityList.tsx      # Session 1
│       │   │   ├── CharacterEditor.tsx # Session 2
│       │   │   ├── LorebookEditor.tsx  # Session 3
│       │   │   ├── FactsExaminer.tsx   # Session 4
│       │   │   └── SuggestionsQueue.tsx# Session 5
│       │   └── styles/
│       │       └── liquid-glass.css    # DesignTokens parity
│       └── dist/                       # gitignored; built into Loom.app
├── scripts/
│   └── build-bible-workspace.sh        # cd web/bible-workspace && bun install && bun run build
├── build.sh                            # gains a pre-step that calls the above
└── Package.swift                       # add web/bible-workspace/dist as bundled resource
```

### 5.2 Bridge contract

**Direction 1 — Swift → JS: snapshot push.**
On every change to `session.project.bible` (or scene list, for the
facts examiner's scene-title rendering), Swift serializes a
`BibleWorkspaceSnapshot` to JSON and calls
`webView.evaluateJavaScript("window.loom.applySnapshot(...)")` with
the JSON string. The web side is purely reactive.

```swift
public struct BibleWorkspaceSnapshot: Codable, Equatable {
    public let projectTitle: String
    public let characters: [Character]
    public let lorebook: [LorebookEntry]
    public let scenes: [SceneSummary]   // id + title — for facts examiner grouping
    public let suggestions: [PendingSuggestion]
}
```

Snapshots are full-replace, not diff. Bible payloads are small
(typically <50KB JSON for a working novel) — diffing isn't worth the
complexity at this scale. If it ever is, we revisit.

**Direction 2 — JS → Swift: intent messages.**
Web side never mutates locally — it dispatches *intent* messages, Swift
applies them to `ProjectSession`, and the resulting state-change posts
a new snapshot back. This keeps Swift as the single source of truth
and preserves the existing dirty-tracking + undo machinery.

```swift
public enum BibleWorkspaceIntent: Codable, Equatable {
    case patchCharacter(id: UUID, patch: CharacterPatch)
    case patchLorebookEntry(id: UUID, patch: LorebookEntryPatch)
    case deleteKnownFact(characterId: UUID, sceneId: UUID, factId: UUID)
    case acceptSuggestion(id: UUID)
    case rejectSuggestion(id: UUID)
    // Sessions 2+ extend this enum
}
```

`CharacterPatch` / `LorebookEntryPatch` are partial-update structs
(every field Optional) so the web side can send just-changed fields
rather than the whole entity. Both shapes are TDD'd before any UI
work.

**Message channel**: a single `WKScriptMessageHandler` named
`"loom"`. Web side calls
`window.webkit.messageHandlers.loom.postMessage({intent: "patchCharacter", ...})`.
Swift side decodes the JSON into `BibleWorkspaceIntent` and routes
through a single dispatch function.

### 5.3 Persistence flow

```
                ┌──────────────────────┐
                │  ProjectSession      │
                │  (source of truth)   │
                └──────┬─────────┬─────┘
                       │         │
                  observes    mutates
                       │         │
       ┌───────────────▼──┐   ┌──▼───────────────┐
       │  Bridge snapshot  │   │  Intent dispatch │
       │  push (Swift→JS)  │   │  (JS→Swift)      │
       └───────────┬───────┘   └──────────────────┘
                   │
                   ▼
       ┌───────────────────┐
       │  React render     │
       │  (read-only view  │
       │  of snapshot)     │
       └───────┬───────────┘
               │
               ▼
       (user clicks "save")
               │
               ▼
       (intent message back via channel)
```

**`ProjectSession.didChangeNotification`** is the existing observer
hook (the Bible inspector already subscribes). The window controller
attaches one more observer, builds a snapshot, posts it. No new
notification types.

### 5.4 Liquid Glass parity

The web side gets a `liquid-glass.css` that defines CSS custom
properties mirroring [`Sources/LoomCore/UI/DesignTokens.swift`](Sources/LoomCore/UI/DesignTokens.swift):

```css
:root {
  --loom-bg-primary: rgb(...);    /* mirrors DesignTokens.Background.primary */
  --loom-bg-secondary: rgb(...);
  --loom-fg-primary: ...;
  --loom-fg-accent: ...;
  /* spacing scale, typography scale, radii */
}
```

A small Swift utility in `BibleWorkspaceWindowController` reads the
current `NSAppearance` and emits an updated CSS payload via
`evaluateJavaScript("document.body.style.setProperty(...)")` on
appearance change. This is the only place we have to actively
synchronize visual tokens; everything else inherits.

### 5.5 Build pipeline

`./build.sh` gains a pre-step:

```sh
# build.sh — new pre-step
echo "Building bible workspace web bundle..."
bash scripts/build-bible-workspace.sh
echo "Continuing Swift build..."
swift build -c release ...
```

`scripts/build-bible-workspace.sh` runs `bun install --frozen-lockfile`
+ `bun run build`. Output goes to `web/bible-workspace/dist/`,
which is referenced by `Package.swift` as a `.copy()` resource on the
`LoomCore` target. SPM copies it into the `LoomCore_LoomCore.bundle`
inside `Loom.app`.

The window controller loads `index.html` from the bundle via:
```swift
let url = Bundle.module.url(
  forResource: "index",
  withExtension: "html",
  subdirectory: "BibleWorkspace"
)!
webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
```

**`bun` dependency**: new prerequisite. The README (when we write one)
will note this; CI/clean-clone instructions add a `curl -fsSL
https://bun.sh/install | bash` step.

---

## 6. TDD discipline

The TDD-always rule
([`memory/feedback_tdd_always.md`](file:///Users/kevinappleyard/.claude/projects/-Volumes-SSD1-Code-FictionWriter/memory/feedback_tdd_always.md))
holds, with a deliberate carve-out:

**What's TDD'd (Swift, via TestKit):**

1. `BibleWorkspaceSnapshot` Codable shape — encode/decode round-trip,
   field presence, defaults.
2. `BibleWorkspaceIntent` Codable shape — every case round-trips,
   bad payloads decode-error cleanly.
3. `CharacterPatch` / `LorebookEntryPatch` application logic — given a
   patch, applying it to a `Character` produces the expected mutated
   `Character`.
4. Intent dispatcher — given an intent + a `ProjectSession`, the
   correct mutation lands on the session (mock the session if needed;
   prefer real session with in-memory project).
5. Snapshot builder — given a `Project` + scenes, produces the
   correct snapshot.

**What's NOT TDD'd (React side):**

React components are treated as **render-only**:

- They render the snapshot JSON they receive.
- They fire intent messages on user action.
- They hold no business logic worth testing — anything that would
  be lives in the Swift side and is tested there.

No Vitest, no React Testing Library. Honest manual smoke testing
of each session's UI as it lands.

**Tradeoff being honest about**: ~500 LOC of React UI without
automated tests. If this bothers us in practice (regressions during
Sessions 3-5), we can add Vitest in a focused half-session — but I
don't want to spend Session 1 setting up two test runners.

**Async-callback TDD discipline**
([`memory/feedback_tdd_async_callbacks.md`](file:///Users/kevinappleyard/.claude/projects/-Volumes-SSD1-Code-FictionWriter/memory/feedback_tdd_async_callbacks.md))
applies in full to bridge code: WKScriptMessageHandler callbacks fire
async, so any test that stubs the message channel must defer the
callback (store + flush), never invoke synchronously.

---

## 7. Session plan

Each session: failing TestKit tests → green → live smoke → commit
(per session ledger style §15.x in HANDOFF.md). Pure-data first,
React glue last. **Mark each session in §11 *Status ledger*** as it
lands.

### Session 1 — Build pipeline + bridge + read-only entity list (~5h)

**Goal**: a working window that shows the live bible content from a
React renderer. No editing yet. End-of-session you can open the
workspace, see characters + lorebook entries, and watch them update
when you edit a character via the existing AppKit inspector.

**Deliverables**:
1. `web/bible-workspace/` scaffold: Vite + React + TS + Tailwind +
   shadcn/ui baseline. `bun install` + `bun run build` produces
   `dist/`.
2. `scripts/build-bible-workspace.sh` + `build.sh` pre-step.
3. `Package.swift` change: bundle `dist/` as a resource on
   `LoomCore`.
4. `BibleWorkspaceSnapshot.swift` + Codable tests.
5. `BibleWorkspaceWindowController.swift` (AppKit shell, ~50 LOC).
6. `BibleWorkspaceBridge.swift` (WKScriptMessageHandler — Session 1
   only handles snapshot pushes; intent handling stubbed for
   Session 2).
7. React side: `EntityList.tsx` rendering characters + lorebook
   entries as plain lists. shadcn `<Card>` primitive for each
   entity. No edit affordances.
8. Bible menu item: "Open Bible Workspace…" + ⌘⇧B.
9. Liquid Glass CSS variable bridge for light/dark + accent.

**Tests added (TestKit)**: ~15-20 covering snapshot Codable,
bridge message marshalling, window controller mount.

**Honest smoke**: open workspace, open existing inspector in main
window, edit a character name, verify workspace re-renders.

**Exit criteria for "yes, continue with Sessions 2-5"**:
- Build pipeline didn't fight us catastrophically.
- Snapshot-push round-trip latency is imperceptible (<50ms).
- macOS-26 WKWebView quirks didn't surface anything worse than
  AppKit's would have.
- shadcn primitives render correctly under Liquid Glass.

If any of those four fail clearly, this is the decision point to
abandon the pivot, throw away `web/bible-workspace/`, and ship the
remaining four sessions as AppKit forms.

### Session 2 — Full character editor (~3h)

**Goal**: clicking a character in the entity list opens the full
editor; every field is editable; changes round-trip through the
intent channel and persist.

**Deliverables**:
1. `CharacterPatch` Codable + apply-patch tests.
2. `intent.patchCharacter` dispatcher + tests.
3. React `CharacterEditor.tsx` — form with every `Character` field.
   RHF + Zod schema mirroring the Swift type.
4. shadcn primitives: `<Input>`, `<Textarea>`, `<Select>` (for
   `role`), `<Combobox>` (for relationship targets).
5. Array editors for `aliases`, `relationships`, `customFields`.

**Honest smoke**: edit each field, see prose-side bible injection
update on next generation. Verify dirty tracking + autosave still fire.

### Session 3 — Full lorebook editor (~2.5h)

**Goal**: edit all 11 `LorebookEntry` fields including the power-user
knobs (priority, group, weight, sticky, positionMode, depth,
secondaryKeys, enabled).

**Deliverables**:
1. `LorebookEntryPatch` Codable + apply-patch tests.
2. `intent.patchLorebookEntry` dispatcher.
3. React `LorebookEditor.tsx` — form with all 11 fields. Conditional
   render: `depth` only shown when `positionMode == .depthN`.
4. Affordance for adding/removing lorebook entries entirely (the
   v1 inspector only edits existing; this surface adds CRUD).

**Honest smoke**: tune a Sphiratrioth pack entry's `weight`, observe
Roll-Outcome behavior change.

### Session 4 — Accepted-facts examiner (~3h)

**Goal**: per-character KNOWS list grouped by sceneId, with delete
affordance. Closes the [`HANDOFF.md`](HANDOFF.md) §15.9 audit gap.

**Deliverables**:
1. `ProjectSession.removeKnownFact(characterId:sceneId:factId:)` +
   tests (mutates, no-op on stale ids, marks dirty).
2. `intent.deleteKnownFact` dispatcher + tests.
3. React `FactsExaminer.tsx` — `<Tabs>` switches between
   character/lorebook/facts views. Facts view groups by scene title;
   each fact shows text + certainty pill + delete button. Confirm
   delete with shadcn `<AlertDialog>`.
4. Snapshot includes `scenes: [SceneSummary]` so the web side can
   resolve sceneId → title without an extra query.

**Honest smoke**: extract facts via existing ledger pipeline, accept
some, open workspace, verify they appear grouped by scene, delete one,
verify it disappears from `Character.knownFactsBySceneId`.

### Session 5 — Suggestions queue review (~2.5h)

**Goal**: central place for pending suggestions across all
characters, with inline accept/reject. Moves the per-character chip
from the side-pane inspector into the workspace.

**Deliverables**:
1. Existing `LedgerSuggestionAcceptor` interfaces already provide
   accept/reject — wire intent messages to them.
2. React `SuggestionsQueue.tsx` — cross-character pending list with
   character pill + fact text + scene context + accept/reject
   buttons.
3. Inspector side-pane: shrink the per-character chip to a link that
   opens the workspace's Suggestions tab.

**Honest smoke**: run an extraction, see all pending suggestions
across the queue in one view.

### Aggregate

| Session | Effort | Cumulative | LOC (Swift) | LOC (TS/TSX) |
|---|---|---|---|---|
| 1 | ~5h | 5h | ~250 | ~400 |
| 2 | ~3h | 8h | ~150 | ~350 |
| 3 | ~2.5h | 10.5h | ~120 | ~300 |
| 4 | ~3h | 13.5h | ~150 | ~350 |
| 5 | ~2.5h | 16h | ~80 | ~250 |

Totals are estimates; real numbers go in §11 *Status ledger* as each
session lands.

---

## 8. Open design questions

Decisions deferred to the session that surfaces them rather than
front-loaded:

1. **Snapshot-push throttling.** First implementation pushes on every
   `didChangeNotification`. If we observe re-render thrash during
   rapid typing in the workspace itself, debounce 16ms. Defer until
   Session 2 lets us measure.
2. **Empty-state UX.** Workspace opened with no characters / lorebook
   entries — what's the empty state? Probably matches the editor's
   `EmptyProjectStateView` posture (call-to-action + create button).
   Decide in Session 1 when we render the entity list.
3. **Window state persistence.** Should the workspace remember which
   entity was selected last, across app launches? Probably yes —
   `NSWindow.setFrameAutosaveName` handles size+position; selected
   entity is one more `AppSettings` field. Decide in Session 1.
4. **Avatar/image handling.** `Character.avatarPath` exists but isn't
   surfaced anywhere yet. Workspace could finally render avatars.
   Defer to a follow-up post-Phase-4.5 — out of scope for the audit
   gap that motivates this work.
5. **Keyboard shortcuts within the web side.** Cmd-W closes the
   window (free from AppKit); Cmd-S autosave (free, ProjectSession
   handles it); what about Cmd-N for "new character"? Decide in
   Session 2.

---

## 9. Risks + rollback

**Risk 1**: macOS-26 WKWebView has unknown ergonomics. *Mitigation*:
Session 1's exit criteria (§7) explicitly checks for this; one of the
four failure modes triggers a clean abandon back to AppKit forms with
no downstream loss.

**Risk 2**: Build-pipeline coupling adds friction. *Mitigation*:
Document the Bun dependency clearly; `scripts/build-bible-workspace.sh`
is a single, idempotent script; `dist/` is gitignored but
reproducibly buildable.

**Risk 3**: Snapshot-push performance degrades for very large bibles.
*Mitigation*: not a current scale concern (working novels have <50KB
bible JSON). If it ever becomes one, switch to a diff protocol —
straightforward refactor.

**Risk 4**: Visual divergence between AppKit and web surfaces makes
the app feel inconsistent. *Mitigation*: CSS-custom-property bridge
(§5.4) keeps the palette synchronized; shadcn primitives are
deliberately understated and pair well with native chrome.

**Risk 5**: Two-test-runner cost if React side later needs tests.
*Mitigation*: explicitly deferred (§6); when/if it bites, Vitest
setup is ~30 min and the bridge already isolates business logic to
Swift.

**Rollback path**: if Session 1 fails the exit criteria, delete
`web/`, `scripts/build-bible-workspace.sh`, the Package.swift
resource entry, and the four new Swift files. Bible Workspace
continues as a 5-session AppKit form-fest (Sessions 2-5 of the
original plan). Cost lost: Session 1's effort (~5h). No downstream
damage.

---

## 10. References

**Within this repo:**
- [`LOOM_PLAN.md`](LOOM_PLAN.md) — main plan, L4.5 row points here.
- [`HANDOFF.md`](HANDOFF.md) §2.1 — original AppKit-vs-WKWebView
  framing.
- [`HANDOFF.md`](HANDOFF.md) §15.9 — the live-test session that
  surfaced the cramped-side-pane UX gap.
- [`LOOM_UI_RESEARCH.md`](LOOM_UI_RESEARCH.md) §B.2.16 — Plan-view
  card-grid research (later corkboard target).
- [`LOOM_DESIGN_LANGUAGE.md`](LOOM_DESIGN_LANGUAGE.md) — Liquid
  Glass palette + spacing scale (mirrored to CSS).
- [`Sources/LoomCore/Models/Character.swift`](Sources/LoomCore/Models/Character.swift) — schema for the
  character editor.
- [`Sources/LoomCore/Models/LorebookEntry.swift`](Sources/LoomCore/Models/LorebookEntry.swift) —
  schema for the lorebook editor.
- [`Sources/LoomCore/UI/PlanWindowController.swift`](Sources/LoomCore/UI/PlanWindowController.swift) —
  pattern for the AppKit window shell.

**Memory entries (load-bearing):**
- `project_appkit_pivot_pressure` — the cost ledger that justified
  this pivot.
- `feedback_tdd_always` — TDD rule (preserved, with §6 carve-out).
- `feedback_tdd_async_callbacks` — applies to bridge code.
- `feedback_no_worktrees` — work in-place.

**External (no MCP fetch needed; standard refs):**
- React 18 docs, Vite docs, Tailwind v3, shadcn/ui, React Hook Form,
  Zod, dnd-kit, Bun, WKWebView Apple docs.

---

## 11. Status ledger

Append a dated entry per session as it lands. Mirror the
[`HANDOFF.md`](HANDOFF.md) §15.x style. The first line of each entry
should be a one-liner suitable for the L4.5 row in
[`LOOM_PLAN.md`](LOOM_PLAN.md) (so the high-level plan stays
self-summarizing without re-reading this doc).

_(empty — plan not started)_

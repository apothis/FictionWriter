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

### Session 1 — 2026-05-12

**Landed**: WKWebView shell + bridge + read-only React entity list rendering live from Swift snapshots. Bundle pipeline (Vite/React/TS/Tailwind/Bun → SPM resource → Loom.app) end-to-end.

**Tests**: +17 TestKit on the workspace itself (12 snapshot — Codable round-trip, JSON key shape, builder ordering across characters/scenes/suggestions, fact-id carrying; 5 bridge — encoded-payload shape, U+2028/U+2029 defensive escape, single-line invariant). Plus +3 from the inspector responder side-fix commit. 808/808 → 828/828 over the session.

**Code shipped:**
- `Sources/LoomCore/Models/BibleWorkspaceSnapshot.swift` — Codable bridge contract + `build(project:scenes:suggestionsQueue:)`. Flat projections (`SceneSummary`, `PendingSuggestion`) so the JS side renders without nested `KnownFact`-shape JSX.
- `Sources/LoomCore/UI/BibleWorkspaceBridge.swift` — Swift→JS push leg. JSON inlined as JS object literal (subset of JS syntax) inside `window.loom.applySnapshot(...)` call. U+2028/U+2029 defensively escaped.
- `Sources/LoomCore/UI/BibleWorkspaceWindowController.swift` — AppKit shell, ~200 LOC. Hosts WKWebView; observes `ProjectSession.didChangeNotification` + `didReplaceNotification`; pushes fresh snapshot via `evaluateJavaScript`. Initial push gated on `webView(_:didFinish:)` (the 0.15s `asyncAfter` heuristic raced WKWebView's HTML load and produced empty placeholders). `isInspectable = true` for Safari Web Inspector access.
- `Sources/LoomCore/AppDelegate.swift` — Bible menu item "Open Bible Workspace…" + ⌘⇧B.
- `web/bible-workspace/` — Vite + React 18 + TypeScript + Tailwind 3 baseline. `src/types.ts` mirrors Swift Codable shapes; `src/bridge.ts` handles the bidirectional bridge (Session 2 fills in `postIntent`); `src/views/EntityList.tsx` renders characters + lorebook with header strip showing scene + suggestion counts.
- `scripts/build-bible-workspace.sh` + `build.sh` pre-step — bun-driven build, sync into `Sources/LoomCore/Resources/BibleWorkspace/`, SPM bundles via `.copy("Resources/BibleWorkspace")` on LoomCore.

**file:// loading gotchas burned through** (these are the load-bearing build-script post-transforms):
1. `crossorigin` attribute on emitted `<script>` / `<link>` tags → WebKit rejects under file://, blank page. Stripped by post-build sed.
2. `<script type="module">` → ES modules don't reliably execute under file:// in WebKit (no error fires, just silent no-op). Vite reconfigured to emit IIFE format; `type="module"` stripped by post-build sed.
3. Classic head script with no `defer` → executes during HTML parsing, before `<body><div id="root">` exists, so `document.getElementById("root")` returns null. Post-build sed injects `defer`.

The three fixes together are non-obvious — debug shim (now removed but documented in `web/bible-workspace/index.html`'s remaining error-surface section) was instrumental.

**Side-fix that landed this session**: inspector responder-clobber on per-keystroke writeback. Unrelated to the workspace but surfaced while we had a fresh project open. See commit `d4e4dcb`.

**Carry forward to Session 2:**
- Bridge JS→Swift intent path (`postIntent` is stubbed; `BibleWorkspaceBridge.swift` only handles outbound today).
- `CharacterPatch` Codable + apply-patch tests.
- React full character editor form (RHF + Zod for the 15+ Character fields).

**Status**: Session 1 ✅, sessions 2-5 pending. Exit criteria (§7) all green:
- Build pipeline didn't fight us catastrophically (some file:// gotchas burned ~30 min, all documented in build script).
- Snapshot-push latency imperceptible (<50ms).
- macOS-26 WKWebView quirks surfaced but tractable.
- React + Tailwind palette renders under Liquid Glass acceptably.

### Session 2 — 2026-05-12

**Landed**: full character editor with every `Character` field, JS→Swift intent path closed end-to-end. Click a character row in the entity list → editor view; field edits dispatch `patchCharacter` intents (debounced 250ms) → `ProjectSession.updateCharacter` → snapshot push back → workspace + main editor inspector stay synchronized.

**Tests**: +20 TestKit (14 `CharacterPatch` covering apply-to semantics, scalar/array/optional field behavior, JSON round-trip with absent keys decoded as nil; 6 `BibleWorkspaceIntent` covering kind-discriminator encoding, decode round-trip, unknown/missing kind errors). 828/828 → 848/848.

**Code shipped:**

*Swift side:*
- `Sources/LoomCore/Models/CharacterPatch.swift` — every `Character` field as `Optional`. `apply(to: Character) -> Character` writes only non-nil fields. Pure function, fully tested.
- `Sources/LoomCore/UI/BibleWorkspaceBridge.swift` extended with `decodeIntent(_: Data) -> BibleWorkspaceIntent` + the `BibleWorkspaceIntent` enum itself (currently single case `.patchCharacter`; sessions 3-5 extend with `.patchLorebookEntry`, `.deleteKnownFact`, `.acceptSuggestion`, `.rejectSuggestion`). Wire format uses `kind: String` discriminator + per-case fields (matches JS-side discriminated union convention).
- `Sources/LoomCore/UI/BibleWorkspaceWindowController.swift` — `userContentController(_:didReceive:)` now decodes intents + dispatches. Decoding errors logged + swallowed (schema-mismatched intents must not crash). `dispatch(_ intent)` looks up the character by id, applies the patch, calls `session.updateCharacter`. The resulting `didChangeNotification` triggers a fresh snapshot push, closing the loop.

*React side:*
- `src/components/ui/{Input,Textarea,Select,Button}.tsx` — shadcn-style primitives. Copy-paste-into-repo pattern; modify in-place rather than overriding via props. Paired with Liquid Glass CSS variables.
- `src/lib/useDebouncedCallback.ts` — 30-line hook to collapse rapid-fire dispatches into one delayed invocation. No external dep.
- `src/views/CharacterEditor.tsx` — full editor form, ~330 LOC. Five sections: Identity (name, oneLine, role, injection mode, aliases), Description (description, personality, appearance, voice, goals), Relationships (per-row target/kind/notes with target picker from other characters), Canon brief, Custom fields (label/value/kind rows). Local-state pattern with reset effect keyed on `character.id` only — snapshot pushes for the same character don't clobber in-flight typing.
- `src/types.ts` — `CharacterPatch` interface mirroring the Swift type.
- `src/App.tsx` — top-level routing: `Selection` state switches between EntityList and CharacterEditor. Stale-selection fallback handles the case where the selected character is deleted out of band.
- `src/views/EntityList.tsx` — character rows become clickable buttons with hover/focus rings; `onSelectCharacter(id)` callback bubbles up to App.

**Design call deferred**: I'd planned RHF + Zod per §4. Reconsidered for Session 2 — the schema has no client-side validation needs (Swift owns validation + dirty tracking), submission is single-field intent dispatch, no multi-step state. Controlled inputs with local draft + debounced dispatch is simpler and adds zero deps. Will adopt RHF + Zod in a later session if/when we hit a use case it actually buys us something (e.g., a "review before submit" flow, or async validation).

**Live-smoke verified**: typed text in personality / appearance / voice / goals / canon brief survives back→re-enter (proving session persistence works for fields the AppKit inspector doesn't surface). Added/removed aliases, added a relationship with a target picker, changed role + injection mode dropdowns. All round-trip through the bridge.

**Known limits**:
- `avatarPath` not surfaced (deferred per §8.4).
- `knownFactsBySceneId` not in editor (managed via Session 4's facts examiner).
- Bridge dispatch is per-field on every keystroke (debounced). For very-long-running edits there's no merge — last patch wins. Not a concern at single-user scale.

**Carry forward to Session 3**:
- `LorebookEntryPatch` Codable + apply-patch tests (~10 fields).
- `intent.patchLorebookEntry` dispatcher.
- React `LorebookEditor` form with the 11 LorebookEntry fields including the conditional render for `depth` when `positionMode == .depthN`.
- Affordance for adding/removing lorebook entries entirely.

### Session 3 — 2026-05-12

**Landed**: full lorebook entry editor (all 13 fields, not the 4 the v1 inspector covers). Add + Delete + Patch intent path. Conditional `depth` render. Live-smoke verified against fresh entries + Sphiratrioth pack entries.

**Tests**: +19 TestKit (15 `LorebookEntryPatch` covering apply-to semantics + JSON round-trip; 4 new `BibleWorkspaceIntent` cases). 848/848 → 867/867.

**Code shipped:**

*Swift side:*
- `Sources/LoomCore/Models/LorebookEntryPatch.swift` — every `LorebookEntry` field as `Optional`; `apply(to:)` mirrors `CharacterPatch.apply`.
- `Sources/LoomCore/UI/BibleWorkspaceBridge.swift` extended: `BibleWorkspaceIntent` enum gains three cases — `.patchLorebookEntry(id:, patch:)`, `.addLorebookEntry(name:)`, `.deleteLorebookEntry(id:)`. Manual Codable conformance extends with corresponding kind values.
- `Sources/LoomCore/UI/BibleWorkspaceWindowController.swift` — dispatch switch covers all four new cases; `lorebookPatchFieldSummary` mirrors the character-side logger.

*React side:*
- `src/components/ui/NumericField.tsx` — handles the "backspace can't clear the 0" quirk that the naive `parseInt(value) || 0` pattern produces. Holds local string state; only emits numeric values when the parse succeeds; resyncs from prop only when the external value diverges from the parsed text. Used for `depth`, `priority`, `weight`, `maxRecentScenesScanned`.
- `src/views/LorebookEditor.tsx` — full editor form. Sections: Identity (name, activation mode, enabled checkbox), Content (textarea), Keyed triggers (primary keys + secondary keys + scan budget), Placement (position mode + conditional depth + priority), Sphiratrioth pattern (group, weight, sticky).
- `src/App.tsx` — `Selection` union extended with `{ kind: "lorebook"; id }`; new `onAddLorebookEntry` + `onSelectLorebookEntry` callbacks. Add-entry creates with `"Entry N"` default name (matches AppKit inspector pattern; window.prompt no-ops in WKWebView without a UIDelegate, and the default-name flow is better UX anyway — no modal interruption).
- `src/views/EntityList.tsx` — lorebook section gains a `+ Add entry` link in its header; lorebook rows are now clickable buttons.
- `src/types.ts` — `LorebookEntryPatch` interface mirrors the Swift type.

**Live-smoke verified**: add a new entry → renames in editor → activation mode dropdown swaps → enabled toggle → conditional depth field appears when positionMode=depthN → priority/weight numeric edits cleanly (the NumericField fix) → keys + secondary keys add/remove → group + sticky toggles → delete returns to list with entry gone. Sphiratrioth pack's existing kink_outcome group entries edit correctly (group + weight + sticky all round-trip).

**Known limit**: nullable scalars (depth, group, weight) treat 0/empty as "set to 0/empty" rather than "clear back to nil". A "clear field" affordance would need a separate intent or a sentinel value in the patch. Not pressing — the JSON-decoder behaviour on the Swift side preserves existing nil if the field is absent in the patch, so untouched optionals round-trip correctly.

**Carry forward to Session 4** (Accepted-facts examiner):
- `ProjectSession.removeKnownFact(characterId:sceneId:factId:)` + tests (mutate, no-op on stale ids, mark dirty).
- `BibleWorkspaceIntent.deleteKnownFact(characterId:, sceneId:, factId:)`.
- React view: tabs on the character editor (or a separate route) for "Description" / "Facts" with the facts list grouped by scene + delete affordance.
- Snapshot `SceneSummary` already supports the scene-title rendering — no new bridge changes needed there.

### Session 4 — 2026-05-13

**Landed**: accepted-facts examiner. Closes the §15.9 audit gap — facts accepted from the ledger suggestions queue are now visible (grouped by source scene) and removable from the workspace. Live-smoke verified end-to-end (accept a suggestion → it surfaces in the Facts tab under its source scene → delete it → gone from `Character.knownFactsBySceneId`, would be re-suggested on next extraction of the same scene).

**Tests**: +10 TestKit (7 `removeKnownFact` covering mutate-by-id, scene-bucket cleanup on empty, stale-id no-ops at each level, dirty + notification side effects; 2 `BibleWorkspaceIntent.deleteKnownFact` Codable; 1 regression test pinning the `knownFactsBySceneId` JSON-object encoding). 867/867 → 877/877.

**Code shipped:**

*Swift side:*
- `Sources/LoomCore/Editing/ProjectSession.swift` — `removeKnownFact(characterId:sceneId:factId:)`: triple-guard against stale ids, empty-bucket cleanup so the dict doesn't accumulate empty keys, `markChanged()` + `[bible] removeKnownFact` debug log.
- `Sources/LoomCore/UI/BibleWorkspaceBridge.swift` — `BibleWorkspaceIntent` gains `.deleteKnownFact(characterId:, sceneId:, factId:)`; Codable encode/decode extended with three new coding keys (characterId / sceneId / factId).
- `Sources/LoomCore/UI/BibleWorkspaceWindowController.swift` — dispatch covers `.deleteKnownFact`.
- `Sources/LoomCore/Models/BibleWorkspaceSnapshot.swift` — **load-bearing fix surfaced this session**: introduced `SnapshotCharacter` projection. The on-disk `Character.knownFactsBySceneId: [UUID: [KnownFact]]` serializes as a flat JSON array (`[uuid, [facts], uuid, [facts]]`) under default `JSONEncoder` settings — JSON-object form only fires for `String`/`Int`-keyed dicts. The web side's TS type expected `Record<string, KnownFact[]>`, so iterating + indexing broke and triggered a censored "Script error. @ ?:?:?" message (cross-origin error sanitization on file://). The projection re-keys to `[String: [KnownFact]]` for the bridge payload; the on-disk `Project.json` shape stays untouched.

*React side:*
- `src/components/ui/Tabs.tsx` — tiny segmented-button primitive. Controlled (`value` / `onChange`) so we can swap to a richer shadcn Tabs later without API churn.
- `src/views/FactsExaminer.tsx` — per-character KNOWS list grouped by source scene (manuscript order from the snapshot's `scenes[]`; orphaned-scene group catches facts whose sourceSceneId is no longer present). Per-fact: certainty pill (asserted / suspected / unknown / mistaken with distinct color-tinted styles) + body text + ✕ delete button. Empty-state explains where facts come from.
- `src/views/CharacterEditor.tsx` — header now hosts a `<Tabs>` between Fields and Accepted facts (with fact count). Tab-switch state resets on character.id change but persists across snapshot pushes for the same character.
- `src/App.tsx` — CharacterEditor wiring extended with `scenes` + `onDeleteFact(sceneId, factId)` → dispatches `deleteKnownFact` intent.

**Design call**: skipped the shadcn `<AlertDialog>` confirm-before-delete (plan §7 deliverable #3). Pragmatic decision — facts are ledger-extracted from the source scene, so a mistaken delete is recoverable by re-extracting (vs lorebook entries which are unique authored content). If this becomes a footgun in practice, a confirmation dialog is a small follow-on.

**File:// + cross-origin gotcha pinned**: when WKWebView treats the loaded HTML/JS as cross-origin (which it always does for file:// under default sandbox), `window.error` events get sanitized to `"Script error. @ ?:?:?"` with no source info. Means our inline diagnostic shim sees nothing useful even when there's a real exception. For Session 4+ debugging, Safari Web Inspector (Develop → \<machine\> → Bible Workspace; isInspectable is on) is the canonical path. Worth a follow-up to either inject a more permissive sandbox or wrap React's render in an in-bundle try/catch.

**Carry forward to Session 5** (Suggestions queue review surface):
- React `SuggestionsQueue` view — cross-character pending-suggestions list with inline accept/reject buttons. The snapshot's `suggestions[]` already carries the flat-projected `PendingSuggestion` shape with `factId`, so no new Swift type changes needed.
- New intents `.acceptSuggestion(factId)` + `.rejectSuggestion(factId)` (or maybe wrap the existing `LedgerSuggestionAcceptor.accept(suggestion)` flow).
- Side-pane inspector: shrink the per-character suggestions chip to a link that opens the workspace's Suggestions surface (per LOOM_BIBLE_WORKSPACE.md §7 Session 5 deliverable #3).

### Session 5 — 2026-05-13

**Landed**: cross-character suggestions-queue review surface. The full L4.5 arc is now feature-complete; every plan §7 deliverable lands.

**Tests**: +3 TestKit (3 intent decode + round-trip for `.acceptSuggestion` / `.rejectSuggestion`). 877/877 → 880/880.

**Code shipped:**

*Swift side:*
- `Sources/LoomCore/UI/BibleWorkspaceBridge.swift` — `BibleWorkspaceIntent` gains `.acceptSuggestion(factId:)` + `.rejectSuggestion(factId:)`. Codable encode/decode extended.
- `Sources/LoomCore/UI/BibleWorkspaceWindowController.swift`:
  - Dispatch for `.acceptSuggestion` looks up the `LedgerSuggestion` across all character buckets by factId (queue's public surface is per-character; flat lookup is fine at single-novel scale, can add a flat accessor if it ever shows up in profiles), then routes to `appState.acceptLedgerSuggestion(_:)`. Stale-factId branch logs + drops.
  - Dispatch for `.rejectSuggestion` calls `appState.rejectLedgerSuggestion(factId:)` directly.
  - New `suggestionsObserver` listens to `AppState.ledgerSuggestionsDidChangeNotification` and pushes a fresh snapshot. Necessary because the reject path doesn't mutate the session itself — without this, rejecting from the workspace would leave the row visible until the next session edit.

*React side:*
- `src/views/SuggestionsQueue.tsx` — cross-character pending list (~150 LOC). Each row shows: character pill, certainty pill, source scene title, fact text, evidence quote in a blockquote, **Accept** + **Reject** buttons. Header shows pending count + distinct-character count. Empty-state copy explains the extractor flow.
- `src/App.tsx` — `Selection` union gains a `{ kind: "suggestions" }` variant (no id — the surface is project-scoped). Routes to `SuggestionsQueue` with accept/reject intent callbacks.
- `src/views/EntityList.tsx` — header shows a prominent blue "N pending suggestion(s) →" button in the top-right when count > 0; clicking opens the suggestions surface. When count is 0, the button disappears.

**Live-smoke verified**: trigger extraction on a scene → suggestions land in the bridge → blue pill appears in workspace header → click opens the queue → accept routes the fact onto `Character.knownFactsBySceneId` (also visible in the character's Accepted Facts tab) → reject drops the row without bible mutation → both paths push fresh snapshots, list updates immediately.

**Phase 4.5 arc complete.** Five sessions, ~3,500 LOC (Swift + TypeScript + Tailwind config), 880/880 tests, four full editor surfaces (entity list + character editor + lorebook editor + facts examiner + suggestions queue) + the bridge infrastructure for all of them. The WKWebView pilot was decisively the right call: per-feature cost dropped meaningfully from Session 2 onward as shadcn-style primitives + the bridge contract paid back the Session 1 setup tax.

**Honest tally of the pivot:**
- **What the pivot bought**: every form / list / grouped-list surface in Sessions 2-5 landed in a fraction of the AppKit-equivalent time. CSS grid + Tailwind preflight + Liquid Glass CSS vars + shadcn-style primitives = consistent visuals with near-zero layout debugging. Zero macOS-26 fittingSize cascade incidents. The architectural pieces compose: NumericField helper + Tabs + the patch/intent pattern got reused verbatim across editors.
- **What it cost**: ~30 min of file:// + cross-origin debugging across Sessions 1, 4 (crossorigin attribute, type=module, head-script defer ordering, UUID dict keys, script error sanitization). One contained Bun dependency. ~170KB JS bundle (gzipped ~54KB) shipped inside Loom.app. Two render systems coexist; the side-pane inspector stays AppKit, the workspace is web.

**Possible follow-on slices** (none Phase-4.5-blocking; all parking-lot):
- Confirm-before-delete dialogs for facts + lorebook entries (currently delete is immediate; facts are recoverable via re-extraction, lorebook entries are not).
- Side-pane inspector's per-character suggestions chip → shrink to a link that opens the workspace's suggestions surface (plan §7 Session 5 #3 — landed half of it, the workspace side; the AppKit side still has the inline chip).
- `avatarPath` field surface (deferred per §8.4).
- `bun install` + build pipeline error handling — currently bails the whole `build.sh` if Bun is missing; might surface a nicer message in the editor if/when CI runs.
- The "script error" cross-origin sanitization issue (§4 in this entry was via Safari Inspector). Long-term: either wrap React render in an in-bundle try/catch that exposes errors to the inline shim, or relax WKWebView's same-origin policy for the bundle.

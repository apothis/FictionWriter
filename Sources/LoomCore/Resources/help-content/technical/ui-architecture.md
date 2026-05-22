# UI architecture — AppKit / WKWebView split

Loom's UI is two technologies stitched together: **AppKit** for the editor surface and **WKWebView + React** for the entity-management panels. This page is the split, the snapshot/intent bridge that connects them, and how to reason about it.

## The split

| Surface | Tech | Why |
|---|---|---|
| Main editor window (sidebar / NSTextView / inspector / tray / menu) | **AppKit**, code-built (no NIBs) | The prose editor wants native text handling, native menus, native split-view persistence. |
| Bible Workspace, Planned Project wizard, Project Tools, **Help** | **WKWebView + React + Vite + TS + Tailwind + shadcn/ui** | Dense form-heavy entity editing was cramped + slow to build in AppKit. The Phase 4.5 pivot moved it to web. |

The rule for new work: **new feature UI lands as a webview panel**, using the snapshot/intent pattern below. The AppKit editor surface is stable and rarely grows. Don't build a new AppKit form; add a panel.

## The four webview panels

Each is a separate Vite-built IIFE bundle, all from `web/bible-workspace/src/` (the directory name is historical):

| Panel | Window controller | Bridge | JS snapshot global |
|---|---|---|---|
| Bible Workspace | `BibleWorkspaceWindowController` | `BibleWorkspaceBridge` | `window.loom` |
| Planned Project | `PlannedProjectWindowController` | (inline) | `window.loomWizard` |
| Project Tools | `ProjectToolsWindowController` | (inline) | `window.loomTools` |
| Help (this panel) | `HelpWindowController` | `HelpBridge` | `window.loomHelp` |

Note the snapshot globals are *not* uniformly named (`window.loom` for the Bible Workspace, `window.loomWizard` for Planned Project, etc.) — historical, not principled. The **message-handler** name, however, *is* uniform: every panel registers its `WKScriptMessageHandler` as `"loom"` (see the shared-handler note below).

Each panel's `dist/` is synced into `Resources/<Panel>/` by `scripts/build-bible-workspace.sh` and bundled via `Bundle.module`. The window controller loads `Resources/<Panel>/<panel>.html` with `webView.loadFileURL`.

## The snapshot / intent pattern

The whole bridge is two directions of typed, Codable messages:

```
        Swift                                    JS (React)
   ┌──────────────┐   snapshot push (S→JS)    ┌──────────────┐
   │  AppState +  │ ─────────────────────────▶│  applySnapshot│
   │  Bridge enum │   evaluateJavaScript(      │  → re-render  │
   │              │     window.loomX.apply…)   │              │
   │              │                            │              │
   │              │◀───────────────────────── │  postMessage  │
   │  decodeIntent│   intent post (JS→S)       │  (intent)     │
   └──────────────┘   webkit.messageHandlers   └──────────────┘
```

### Swift → JS: snapshot push

The host builds a Codable **snapshot** (a projection of the model — everything the view needs, nothing it doesn't) and pushes it:

1. `Bridge.encodeSnapshotPush(snapshot)` JSON-encodes it and wraps it as a one-line JS statement: `window.loomHelp.applySnapshot({...});`. JSON is a syntactic subset of JS object-literal notation, so the JSON is inlined directly rather than embedded as an escaped string. U+2028/U+2029 are escaped defensively.
2. The window controller hands that string to `webView.evaluateJavaScript(...)`.
3. The React side's `applySnapshot` global stores it in state and re-renders.

Snapshots are pushed on: the panel finishing load (`webView(_:didFinish:)`), the user acting (after an intent is handled), and AppState mutations the panel observes (so an edit in the editor reflects in an open workspace).

### JS → Swift: intent post

The React side posts a Codable **intent** back:

1. JS calls `webkit.messageHandlers.loom.postMessage({ kind: "selectSection", ... })`.
2. The window controller's `userContentController(_:didReceive:)` (it's the `WKScriptMessageHandler`) receives it, re-serialises the body to `Data`, and calls `Bridge.decodeIntent(data)`.
3. Intents are a discriminated union — a `kind` string field + per-case payload, custom `Codable`. The Swift handler switches on the case, mutates AppState, and pushes a fresh snapshot.

**One shared handler name.** All panels post to the message handler named `"loom"`. A controller decodes only *its* intent type and silently ignores anything that doesn't parse (a Bible-workspace intent landing on the Help controller's handler while both are open). This is why `decodeIntent` failures are swallowed, not logged loudly.

### The shapes mirror across Swift + TS

The Codable snapshot/intent types in `Models/*Snapshot.swift` have hand-mirrored TypeScript counterparts in `web/bible-workspace/src/types.ts` + `bridge.ts`. There's no codegen — when you add a field, you change both sides. The `kind`-discriminator convention is shared across all four panels so the JS bridge code has one shape.

## A concrete trace — Help panel

The simplest panel, end to end:

1. **Open** — `HelpWindowController` builds a `WKWebView`, registers itself as the `"loom"` message handler, injects the `window.loomHelp.applySnapshot` shim, loads `Resources/Help/help.html`.
2. **First snapshot** — on `didFinish`, the controller builds a `HelpSnapshot { book, toc, selectedSectionId, selectedSectionMarkdown }` (markdown read from `Resources/help-content/<book>/<id>.md`) and pushes it.
3. **User clicks a TOC entry** — React posts `{ kind: "selectSection", sectionId, book }`.
4. **Swift handles it** — `decodeIntent` → `.selectSection` → update `selectedSectionId` → `pushSnapshot()` with the new section's markdown.
5. React re-renders the content pane.

`HelpContent` (`Generation/HelpContent.swift`) owns the TOC registry + the `Bundle.module` markdown loader. Adding a help section is: register a `HelpSection` there + drop a `.md` under `Resources/help-content/{user,technical}/`. (Which is exactly how this book is built.)

## Why this shape — the file:// constraints

The panels load from `file://` URLs (bundled resources), which WebKit treats stringently. `scripts/build-bible-workspace.sh` post-processes each panel's HTML to make it work:

- **Strip `crossorigin`** — CORS is enforced even on `file://`; a marked script silently fails to execute → blank page.
- **Strip `type="module"`** — ES modules don't reliably execute under `file://` (silent no-op). Vite is configured to emit **IIFE** format instead, so the module attribute is wrong anyway.
- **Add `defer`** — the classic (non-module) script needs to wait for the body to parse.

This is also why each panel is a separate `vite build` invocation (selected by the `LOOM_BUNDLE` env var): IIFE output can't code-split across multiple entry inputs.

## Dev affordances

- **`devMockSnapshot.ts`** — lets a panel run in a normal browser (`bun run dev`) outside the WKWebView host, with a stubbed snapshot, for fast React iteration without rebuilding Loom.
- **Markdown content hot-path** — for the Help panel specifically, the markdown bodies are bundled separately from the React build, so editing a `.md` only needs a Swift rebuild, not a `vite build`.

## See also

- **Architecture overview** — where the panels sit in the whole system.
- **Repo layout** — the `web/bible-workspace/src/` tree + the `Resources/<Panel>/` bundles.
- **How to add a Bible entity field** (T.15) — the practical change-both-sides walkthrough.
- [`LOOM_BIBLE_WORKSPACE.md`](LOOM_BIBLE_WORKSPACE.md) — the Phase 4.5 pivot rationale + per-session ledger.

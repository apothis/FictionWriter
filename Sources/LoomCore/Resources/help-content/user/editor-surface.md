# Editor surface

The main Loom window is a three-pane layout with a status strip along the bottom. This page is the map — what each pane does, plus the full keyboard-shortcut reference.

## The three panes

```
┌───────────┬──────────────────────────────┬──────────────┐
│  Sidebar  │  Editor                      │  Inspector   │
│           │                              │              │
│  project  │  your prose (NSTextView)     │  Bible /     │
│  tree     │                              │  History /   │
│           │  ┌────────────────────────┐  │  Notes tabs  │
│           │  │  generation tray       │  │              │
│           │  └────────────────────────┘  │              │
├───────────┴──────────────────────────────┴──────────────┤
│  status strip (word count, etc.)                         │
└──────────────────────────────────────────────────────────┘
```

All three panes are resizable; drag the dividers. Your layout persists across launches. The sidebar and inspector can be collapsed by dragging their divider fully closed if you want a distraction-free editor.

### Sidebar (left) — project structure

The project tree: Parts → Chapters → Scenes, or just a flat list of scenes for an unstructured project. Click a scene to open it in the editor. See **Project structure** for how the hierarchy works.

**Right-click a scene** for its context menu — including the **Set POV** submenu, which assigns the scene's POV character (the load-bearing input to the knowledge ledger; see **Knowledge ledger**).

### Editor (center) — where you write

A normal rich-text prose editor (`NSTextView`). You type here; AI generations insert at the cursor. Two things live inside it:

- **The generation tray** — the row of mode buttons (Continue / Expand / Rewrite / Brainstorm / Critique) plus the per-call instruction field and the History disclosure. See **Generation modes**.
- **The acceptance overlay** — appears after a generation, with Accept / Reject / Keep & Redo. See **Your first scene + first generation**.

**@-mentions:** type `@` in the editor to get an autocomplete popover of your Bible entities (characters, settings, objects). Arrow keys to move, Return/Tab to commit, Esc to dismiss. Mentions link the prose to the entity for hover-preview and the mention sparkline.

### Inspector (right) — context about the project

Tabbed:

- **Bible** — a compact view of your characters + entities; quick reference while writing. The full editor is the separate Bible Workspace (**⌘⇧B**).
- **History** — the generation log. Every generation, newest first; expand an entry to see the full assembled prompt (every layer) + the response + token counts. This is the transparency surface — what was sent, what came back.
- **Notes** — the project's free-form notepad.

The inspector remembers which tab you had open per-project.

## Plan view (Corkboard)

**View → Plan View** (**⇧⌘P**) opens a separate window with the Corkboard — a card-per-scene overview for restructuring at the outline level (reordering, seeing the shape of the manuscript). See **Project structure**.

## Other windows

Loom is multi-window. Beyond the main editor:

- **Bible Workspace** (**⌘⇧B**) — full entity editing.
- **Settings** (**⌘,**) — servers + project settings.
- **Plan View** (**⇧⌘P**) — the Corkboard.
- **Help** (**⌘?**) — this panel.
- Project-tools panels (Scene Framing, Anti-slop, Work Framing) open from the **Bible** menu.

## Keyboard shortcuts

The complete current set, swept from the menu definitions:

### File

| Shortcut | Action |
|---|---|
| **⇧⌘N** | New Project |
| **⌘O** | Open Project |
| **⇧⌘S** | Save As |
| **⇧⌘E** | Export as Markdown |
| **⌘W** | Close |

(New Planned Project, Style Library, and Open Recent have no shortcut — File menu only.)

### Edit

| Shortcut | Action |
|---|---|
| **⌘Z** | Undo |
| **⇧⌘Z** | Redo |
| **⌘X / ⌘C / ⌘V** | Cut / Copy / Paste |
| **⌘A** | Select All |

### View / Bible / Help

| Shortcut | Action |
|---|---|
| **⇧⌘P** | Plan View (Corkboard) |
| **⌘⇧B** | Open Bible Workspace |
| **⌘,** | Settings |
| **⌘?** | Loom Help (this panel) |

### After a generation (acceptance)

| Shortcut | Action |
|---|---|
| **⏎** | Accept the generation |
| **⌫** | Reject (restores the pre-generation state) |
| **⌘⇧R** | Keep & Redo — accept the current text and immediately re-run |
| **Esc** or **⌘.** | Cancel a generation mid-stream |

### @-mention popover

| Key | Action |
|---|---|
| **↑ / ↓** | Move selection |
| **⏎ / Tab** | Commit the highlighted entity |
| **Esc** | Dismiss |

There are **no keyboard shortcuts that fire a generation mode directly** — Continue, Expand, etc. are clicked in the tray. The shortcuts above are for navigation, file ops, and the acceptance loop.

## See also

- **Generation modes** — the tray buttons.
- **Your first scene + first generation** — the write → generate → accept loop.
- **Project structure** — the sidebar tree + Corkboard.
- **Story Bible — Characters, Settings, Objects** — what @-mentions link to.
- **Settings — app-level + per-project** — the Settings window.

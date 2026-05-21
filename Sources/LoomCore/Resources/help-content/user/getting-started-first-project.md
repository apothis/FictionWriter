# Your first project

A Loom project is a single directory on disk that holds everything about one piece of writing — the prose, the story bible, references, settings, snapshots. You'll have one project per novel, novella, or stand-alone short. They're plain folders; you can put them in your Documents folder, iCloud Drive, a Dropbox, a thumb drive — Loom doesn't care.

This page makes one.

## Two ways to start

| | What you get | When to pick it |
|---|---|---|
| **New Project…** | An empty project with a blank Scene 1, ready to type into. | Almost always, especially your first time. |
| **New Planned Project…** | A guided wizard that generates a multi-scene outline from a one-page sketch you write. Lands you in a populated manuscript. | When you have a sketch but no scenes yet, and you want the AI to draft the structure for you. Can be used later, too — make a normal project first, get a feel for Loom, then try this. |

For your first time through, use **New Project…**. The Planned Project flow has its own page in the Reference half once you're ready.

## Create the project

**File → New Project…**, or press **⇧⌘N**.

A save dialog appears. Pick where you want the project to live and give it a filename. By default Loom suggests `MyNovel.loom`, but you can name it anything — `WizardSchool.loom`, `Chapter1Draft.loom`, `untitled.loom`. The **.loom** extension matters; keep it.

A few notes on the location:

- **Documents folder** is fine. iCloud Drive is fine. Synced folders (Dropbox, OneDrive) are fine — Loom writes plain files, no databases.
- **Avoid the desktop** if you sync it with iCloud and your other Macs — projects can be large once you add references, and you'll be syncing a lot.
- The project is a folder, not a single file. macOS might show it as a "package" (file-like icon). You can right-click → **Show Package Contents** in Finder if you ever want to peek inside (more on this in **Where your work lives on disk** later).

Click **Save**. Loom creates the project directory, drops in a blank Scene 1, and switches the editor window onto it.

## What just happened

Three things changed in the window:

1. **A project sidebar appeared** on the left. It's currently showing one entry — "Scene 1" — under the manuscript root.
2. **The editor pane** in the middle is now active and empty, cursor blinking at the top.
3. **The window title** updates to your project's name.

And on disk, Loom made this directory structure inside your `.loom` folder:

```
MyNovel.loom/
├── project.json           ← project metadata + story bible + settings
├── scenes/                ← one markdown file per scene
│   └── <Scene 1's id>.md
├── generation-log/        ← per-call history (empty for now)
└── references/            ← style-reference texts (empty for now)
```

You don't need to touch any of this yourself — Loom owns the directory while it's open — but it's worth knowing that there's nothing magic about it. Each scene is a real `.md` file; if Loom ever goes away, your manuscript is sitting in plain markdown next to anything else you write.

## Sensible defaults Loom set for you

Two things you'd otherwise have to configure are pre-filled:

- **Project Memory** — a short system prompt that tells the model "you're a fiction writer helping me draft prose; don't refuse subject matter; don't break voice." Loom's default is gentle; you can edit or replace it in the project settings (see **Settings — app-level + per-project** in the Reference half).
- **Anti-slop phrases** — a list of overused fiction-AI phrases ("voice barely above a whisper", "sent shivers down her spine", etc.) that the writer model is told to avoid. You can edit this per-project too.

You don't need to do anything with these now; they're just doing their job in the background.

## Reopening later

- **File → Open Project…** (**⌘O**) — pick a `.loom` folder.
- **File → Open Recent →** — the last five projects you touched, newest first.

Open Recent is rebuilt every time you click the File menu, so you don't have to think about it.

## What's next

You have a project with one empty scene. Next stop: **Your first scene + first generation** — write some prose, ask the model to continue it, and watch the loop close.

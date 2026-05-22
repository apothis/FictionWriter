# Project structure — Parts, Chapters, Scenes, Corkboard

A Loom project organises your manuscript into a tree: **Parts → Chapters → Scenes**. The hierarchy is **opt-in** — you can ignore it entirely and just keep a flat list of scenes, or layer in structure as the manuscript grows.

## Scenes are the unit

The scene is the atom. Everything else is organisation around it. A scene is one prose file (`scenes/<id>.md`); generations happen in scenes; the bible, ledger, and retrieval all operate at scene granularity.

The smallest valid project is a single scene (which is what **New Project** gives you — "Scene 1"). You can write a whole novella as a flat pile of scenes and never make a Part or Chapter.

## Flat vs structured

- **Flat project** — scenes live directly under the manuscript root (internally, `manuscript.orphanedSceneIds`). The sidebar shows a simple ordered list. Fine for short work or early drafting.
- **Structured project** — scenes are grouped into Chapters, Chapters into Parts. Use it when the manuscript is long enough that a flat list stops being navigable, or when you want Part/Chapter boundaries to mean something (acts, volumes, POV blocks).

You can mix: a project can have some scenes placed in chapters and others still loose at the root. Structure is additive — adding a Part doesn't force you to file every scene into it.

## Working in the sidebar

The left sidebar is where you build and navigate the tree. Top-of-sidebar buttons:

- **+ Scene** — add a new scene.
- **+ Part** — add a new Part.

Right-click any row for its context menu:

- **New Scene** / **New Part**
- **Add Chapter to Part** — only meaningful on a Part row; adds a Chapter under it.
- **Set POV** — assign the scene's POV character (feeds the knowledge ledger).
- **Rename**
- **Delete**

Click a scene to open it in the editor. Reordering is done here in the sidebar.

## Scene metadata

Beyond title and prose, each scene carries fields that show up in the inspector + Corkboard:

- **POV** — the viewpoint character (set via Set POV).
- **Status** — todo / draft / revised / final. A workflow marker; doesn't affect generation.
- **Summary** — a one-paragraph recap. Used by adjacent-scene context + (in Planned Projects) as the draft-from-outline source.
- **Target word count** — optional per-scene goal.
- **Conflict / outcome** — outline fields for the scene's dramatic shape.
- **Framing** — the per-scene scenario block injected near the cursor (Bible → Edit Scene Framing…).

Chapters and Parts have their own titles + optional summaries + target word counts.

## Trash

Deleting a scene doesn't destroy it immediately — deleted scenes move to the manuscript's trash (`trashedSceneIds`) and survive closing the project, so an accidental delete is cheap to undo. (There's no "empty trash" affordance in the UI yet; deleted scenes simply stop appearing in the sidebar.)

## The Corkboard (Plan View)

**View → Plan View** (**⇧⌘P**) opens the Corkboard — a card-per-scene grid in manuscript order. It's the bird's-eye view for seeing the shape of the whole manuscript at once.

Each card shows the scene's title, status, and summary. From the Corkboard you can:

- **Click a card** to jump to that scene in the editor.
- **Right-click a card** for:
  - **Draft From Outline** — generate the scene's prose from its summary (Planned Project mode; the scene needs an outline summary to draft from).
  - **Status** — set the scene's status (todo / draft / revised / final) without opening it.

The current Corkboard is a flat grid in manuscript order. It's a planning + status overview, not a drag-to-restructure surface — reordering still happens in the sidebar.

## Word counts

The **status strip** along the bottom of the main window shows live word counts as you write. Per-scene, per-chapter, and per-project targets (where set) let you track progress against a goal.

## How structure maps to disk

The tree is metadata in `project.json` (`manuscript.parts` → `chapters` → `sceneIds`); the scene *prose* is always in flat `scenes/<id>.md` files regardless of where a scene sits in the tree. Restructuring the manuscript moves id references around in `project.json` — it never moves or renames the prose files. See **Where your work lives on disk**.

## See also

- **Editor surface** — the sidebar + Plan View in the window layout.
- **Your first project** — creating a project + the starter scene.
- **Knowledge ledger** — why per-scene POV matters.
- **Generation modes** — Draft Scene From Outline + how adjacent-scene context is used.
- **Where your work lives on disk** — the on-disk manuscript layout.

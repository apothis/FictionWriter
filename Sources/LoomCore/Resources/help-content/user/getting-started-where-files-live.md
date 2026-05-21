# Where your work lives on disk

Loom doesn't lock your writing into a proprietary database. Everything you do — prose, characters, settings, style references, generation history — sits on disk as plain JSON and Markdown files inside the project directory you created. You can back it up with `cp -R`, sync it through Dropbox, open it on a different Mac, read individual scenes in any text editor. If Loom were to disappear tomorrow your manuscripts wouldn't.

This page is a tour of what's in there. You don't need to know any of this to use Loom — but it's useful to know it's all in plain sight.

## Inside a project

A project is `<YourTitle>.loom/` — a normal macOS folder that Finder shows as a "package" (a file-like icon). Right-click → **Show Package Contents** to look inside.

Top-level structure once you've used the project for a while:

```
YourNovel.loom/
├── project.json              ← Project metadata, story bible, settings
├── project.json.bak          ← Backup written before every save
├── scenes/
│   └── <uuid>.md             ← One file per scene: YAML frontmatter + prose
├── generation-log/           ← Per-call history: prompt sent, response received
├── snapshots/                ← Version snapshots taken before AI rewrites
├── references/               ← Style-reference texts (R.9) — Markdown + an .index sidecar per reference
├── templates/                ← Scene exemplars (R.10): the source .md + an extracted beats.json
├── template-gen-state/       ← Per-template UI state (cast mapping, etc.) so iterating remembers
├── continuity-audit/         ← Latest continuity-audit findings
├── proposed-entities/        ← Entity-discovery queue waiting for accept/reject
├── proposed-relationships/   ← Relationship-discovery queue
└── relationship-map/         ← Saved layout (node positions) for the relationship map view
```

A fresh project only has the first three (`project.json`, `scenes/`, plus empty `generation-log/` and `references/` directories). The rest spring into existence as you use the features that need them — e.g. `snapshots/` appears the first time you let Loom take a pre-rewrite snapshot, `proposed-entities/` once entity-discovery runs against your prose.

### What's in `project.json`

The big one. Inside it:

- The **story bible** — every Character, Setting, Object, Faction, Lorebook entry, and Dynamic relationship sheet.
- The **manuscript outline** — the Parts / Chapters / Scenes hierarchy. (The scene *prose* is in the `.md` files; this just holds structure.)
- **Project settings** — the Project Memory text, the Author's Note, the anti-slop phrases list, the writing direction, max-reply-tokens, AN depth.
- The **knowledge ledger** — accepted facts about each character grouped by source scene.

It's a single JSON file. You could open it in any text editor (`bbedit YourNovel.loom/project.json`, `code YourNovel.loom/project.json`) and read every word of it. Don't edit it by hand while Loom is running — Loom is the writer of that file and will overwrite your changes on the next save.

### What's in `scenes/<uuid>.md`

One Markdown file per scene, with a small YAML frontmatter block at the top for the scene's title and id, then the prose itself as plain text:

```markdown
---
id: 1A2B3C4D-…
title: Chapter 1 — The Lighthouse
---

The lighthouse keeper had not spoken to another person…
```

If you ever want to read a scene without launching Loom — on your phone, on another machine, in a markdown viewer — this is the file. UUID filenames look unfriendly, but cross-referencing them against `project.json`'s manuscript outline tells you which one is which scene.

## App-wide files (outside the project)

A few things are app-wide rather than per-project. They live at:

```
~/Library/Application Support/Loom/
├── settings.json             ← Server profiles, recent projects, schema version
└── styles.json               ← Style library (cross-project named style entries)
```

`settings.json` is where the model-server profiles you set up in **Configure your model servers** are persisted. Delete it and Loom starts clean on next launch with no servers configured — useful if you've made a mess and want to redo from scratch without affecting any project.

## Backing up

Three honest options:

- **Copy the `.loom` folder**, anywhere. To another disk, another folder, into Time Machine's path, into a cloud sync folder. Plain files; `cp -R YourNovel.loom backup/` works.
- **Sync with iCloud / Dropbox / OneDrive.** Put the `.loom` folder inside the synced location. Loom doesn't open file handles in a way that conflicts with sync clients.
- **Version control.** Initialise the `.loom` directory as a Git repository — JSON is diffable, scene prose is plain Markdown, the directory layout is stable. Commit before every long writing session; you'll have a per-commit history.

For most users option 1 or 2 is enough. If you're already comfortable with Git and want commit-grain history beyond Loom's own snapshots, option 3 is the most powerful.

## If something goes wrong

- **Project won't open / corrupted error.** Loom keeps a `project.json.bak` written just before each save. If the live `project.json` is broken, Loom automatically falls back to the backup on next open and tells you in the debug log. You usually won't need to intervene.
- **You want to start a project completely over.** Close it in Loom (open a different project, or quit), then delete the `.loom` folder in Finder. No reference to it lingers anywhere except the Recent menu, and that self-heals.
- **You accidentally edited a file while Loom was running and your changes vanished.** Loom owns the project files while it has them open and will overwrite. Edit only when Loom isn't running, or use snapshots / version control for the kinds of changes you want to durably make.

## What's next — the Reference half

That's the end of Getting Started. From here, the Reference half of this book is non-linear — pick what you need:

- **Editor surface** — pane layout, sidebar, inspector, keybindings.
- **Generation modes** — full catalogue (Continue, Expand, Rewrite sub-modes, Brainstorm, Critique, Bridge, Roll-Outcome, Show-Don't-Tell).
- **Story Bible** — Characters, Settings, Lorebook entries, Dynamics, knowledge ledger, entity discovery.
- **References + Scene exemplars** — adding style references, ingesting them, scene templates.
- **NSFW / dark-fiction posture** — model picks, Marinara preset, writing-direction primitive.
- **Anti-slop phrases**, **Settings** (project + app), **Troubleshooting**, and the **Sphiratrioth pack** for power users.

The Reference TOC is on the left.

# Snapshots + version history

Loom protects your prose from destructive AI edits with **automatic snapshots**. Before any generation that *replaces* text, Loom saves a copy of the scene's prose to disk first. This page is an honest account of what that protection covers today — and what it doesn't yet.

## What's protected automatically

The generation modes split into two kinds:

- **Additive** (Continue, Expand) — insert new prose at the cursor. Nothing of yours is overwritten, so no snapshot is needed.
- **Replacing** (the Rewrite family: Voice / Tense / Length / POV / Generic, plus Show-Don't-Tell) — take your selected prose out and put new prose in. This *is* destructive, so Loom snapshots the scene's prose **before** the rewrite runs.

The snapshot is taken before the network request even fires, so cancelling a rewrite mid-stream still leaves the snapshot intact. Each is written to:

```
<YourNovel>.loom/snapshots/<timestamp>-<uuid>.json
```

A self-contained JSON file with the scene id, the timestamp, an optional label, and the full prose as it was. The timestamp prefix means the directory sorts chronologically with a plain `ls`.

## Your everyday undo paths

For the common case — "the AI rewrote my paragraph and I don't like it" — you usually don't need the snapshot at all:

1. **Reject (⌫)** in the acceptance overlay restores the original passage immediately. This is the first and best line of defence; a rejected rewrite puts your exact original text back.
2. **Undo (⌘Z)** works on the editor like any text editor, including after you've accepted.

The on-disk snapshot is the deeper safety net — for when you accepted a rewrite, kept writing, and only later realised you want the older version back.

## The honest gap: no in-app restore yet

Here's the part the rest of this help system would gloss over if it weren't grounded in the actual code: **Loom captures snapshots but does not yet have an in-app surface to browse or restore them.** There's no version-history panel, no "snapshots" list in the inspector, no revert button. The capture half shipped; the restore half hasn't.

So today, recovering from a snapshot is a manual, on-disk operation:

1. Close the project in Loom (or quit) — Loom owns the project files while it's open.
2. Open the `snapshots/` folder inside your `.loom` bundle (right-click the bundle in Finder → **Show Package Contents** → `snapshots/`).
3. The files are sorted by timestamp. Open the one you want in any text editor — the prose is in the `contentSnapshot` field.
4. Copy the prose you want back into the corresponding `scenes/<id>.md` file (match the `sceneId`), or back into the scene in Loom once you reopen.

It's clunky, but the data is there and it's plain JSON — nothing is lost, and a future Loom build will add the browse/restore UI on top of these exact files.

## What this means in practice

- **You're protected against destructive AI rewrites** — the snapshot exists before the rewrite touches your prose.
- **Routine "undo a bad rewrite" is instant** — just Reject, or ⌘Z.
- **Deep recovery is possible but manual** — via the JSON files, until the restore UI ships.
- **Snapshots accumulate** — every rewrite adds one. The `snapshots/` folder grows over a long project. It's safe to delete old snapshot files you don't need (each is independent; deleting one doesn't affect the others or the scene).

If you want belt-and-suspenders version history *now*, the most robust option is to put the whole `.loom` folder under Git and commit before long sessions — see **Where your work lives on disk**. That gives you full, browsable, restorable history at commit granularity, independent of Loom's own snapshots.

## See also

- **Generation modes** — which modes are additive vs replacing.
- **Your first scene + first generation** — the Reject / Accept / Keep & Redo loop.
- **Where your work lives on disk** — the `snapshots/` folder + the Git-history option.

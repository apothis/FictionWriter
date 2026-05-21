# Settings — app-level + per-project

Loom has two layers of settings: **app-level** (travel with your Mac, shared across every project) and **per-project** (saved inside the project, different per novel). This page maps where each thing lives.

## The Settings window

Open with **⌘,** or **Loom → Settings…**. Two tabs:

- **Servers** — your model-server profiles. App-level. Covered in **Configure your model servers**.
- **Project** — everything about the currently-open project. Per-project.

A few per-project things live *outside* the Settings window, in the **Bible** menu — covered at the end.

## App-level settings (Servers tab + recents)

Persisted to `~/Library/Application Support/Loom/settings.json`. These are shared across all projects:

| Setting | What |
|---|---|
| **Server profiles** | Your configured Kobold + Ollama endpoints. Add/remove/edit. |
| **Default server** | Which profile is the writer. |
| **Extractor server** | Which profile is the extractor (optional). |
| **Recent projects** | The last five projects you opened (drives File → Open Recent). Maintained automatically. |

That's the whole app-level surface today. Loom is deliberately light on global preferences — almost everything that matters is per-project.

## Per-project settings (Project tab)

Persisted inside the project's `project.json`. Different per project. The Project tab is a single scrolling page with these sections:

### Narrative Style

- **POV** — first / second / third-limited / third-omniscient / third-objective. The project's default narrative POV (distinct from a scene's POV *character*, which you set per-scene via the sidebar).
- **Tense** — past / present.
- **Direction kind** — literary / mainstream / romance / erotica / porn.
- **Vocabulary** (register) — clinical / literary / earthy / crude / mixed.
- **Explicitness** — fade-to-black / suggestive / on-screen / graphic / extreme.

The last three are the writing-direction dials — see **Author's Note, instructions, writing direction** for what each does to the prompt. (The writing direction also has *pacing* and *fade-to-black policy* dials in the data model, but those aren't surfaced as controls here yet — they sit at their defaults.)

### Project Memory

The system-prompt text the model sees on every generation. New projects are seeded with Loom's anti-refusal default; edit or replace it here. See **NSFW / dark-fiction posture** for the heavier presets.

### Author's Note

- The note text — a persistent bracketed directive injected near the cursor.
- **AN depth (lines from cursor)** — a stepper; lower = closer to the cursor = stronger steering. Default 4.

### Token Budgets

- **Context budget (tokens)** — how much prompt Loom will assemble before evicting layers. Default 8192.
- **Use server max** — a button that sets the context budget to (probed server max) − (max reply tokens) − a 256-token safety margin. Click it after configuring your server so the budget matches the model you actually loaded.
- **Max reply tokens** — how much room is reserved for the model's output (subtracted from the context budget to give the usable prompt budget).

## Per-project settings outside the Settings window

A few project-scoped tools live in the **Bible** menu rather than Settings — they have richer editing surfaces (webview panels) than a settings field:

| Menu item | Edits | Covered in |
|---|---|---|
| **Bible → Edit Anti-slop List…** | The project's banned-phrase list | **Anti-slop phrases** |
| **Bible → Edit Work Framing…** | Dark-content elements + your authorial stance on each (AO3 "Dead Dove"–style) | below |
| **Bible → Edit Scene Framing…** | The current scene's scenario block (injected near the cursor) | **Story Bible**, scene-level |

**Work Framing** is worth a note: it's a list of content elements you declare for the work, each with a stance (played straight / critiqued-explored / gentle-handling / inverted / not-present). Elements you mark "played straight" feed an anti-softening clause into the system prompt — Loom's structural answer to "this work depicts X without flinching; don't have the model editorialise it."

## What's *not* in Settings

- **Samplers** (Min-P, DRY, XTC, temperature, etc.). Loom ships fiction-tuned defaults baked into the build; there's no in-app sampler editor today. Tune them in KoboldCpp's own UI, on the model server. See **NSFW / dark-fiction posture** for the default values and rationale.
- **Instruct template.** The project carries an instruct-template field (`auto` by default, which detects from the model name), but it's not surfaced as a settings control today — `auto` is correct for the supported model families. If you're running an exotic merge that mis-detects, that's a code-level change.
- **Theme.** No app-level appearance/theme settings. Loom uses a single design language.

## Where settings are stored

```
App-level:   ~/Library/Application Support/Loom/settings.json
Per-project: <YourNovel>.loom/project.json   (the "settings" object inside it)
```

Deleting `settings.json` resets app-level state (servers, recents) on next launch without touching any project. Per-project settings travel with the project folder — copy the `.loom` to another Mac and its settings come with it. See **Where your work lives on disk**.

## See also

- **Configure your model servers** — the Servers tab in depth.
- **Author's Note, instructions, writing direction** — the Narrative Style dials + Author's Note.
- **Anti-slop phrases** — the banned-phrase list.
- **NSFW / dark-fiction posture** — sampler defaults + Project Memory presets.
- **Where your work lives on disk** — the storage layout.

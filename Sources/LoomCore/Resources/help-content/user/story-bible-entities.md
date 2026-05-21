# Story Bible — Characters, Settings, Objects

The Story Bible is the structured reference data Loom threads into every generation. When the model writes, it sees your characters' descriptions, the places they're in, and the significant objects around them — not as something you have to remember to paste, but as part of the prompt every time.

Three entity types share this shape today: **Characters**, **Settings** (places), and **Objects** (significant artefacts). Two related layers — **Lorebook entries** (free-form keyed snippets) and **Dynamics** (relationship sheets) — have their own pages further down in the Reference TOC.

## Where to edit

The full editing surface is the **Bible Workspace** — a separate window with the complete schema for each entity. Open it with **⌘⇧B** or **Bible → Open Bible Workspace…**

The small **Inspector** panel inside the main editor window also exposes a subset of bible state (the names + one-liners; quick character switching), but the per-field editing happens in the Workspace.

## Characters

The richest entity type. Every character carries:

| Field | What goes in it |
|---|---|
| **Name** | The canonical name. What the model calls them by default. |
| **Aliases** | Other things the prose calls them — first names, last names, nicknames, titles. Critical: aliases are matched against recent prose to trigger keyed injection (below) and are how the entity-discovery pipeline merges synonyms. |
| **Role** | Protagonist / Antagonist / Supporting / Minor / Narrator. Influences how prominently the character is foregrounded; doesn't gate anything hard. |
| **One-line** | A single-sentence "who is this person." Used for compact summaries and the entity-discovery + relationship-discovery pipelines. |
| **Description** | The freeform full sketch. This is the main injection content — the model reads this verbatim. |
| **Personality** | Tone, manner, signature traits. |
| **Appearance** | Visible-from-outside features. |
| **Voice** | How they talk — speech patterns, register, verbal tics. |
| **Goals** | What they want, openly or otherwise. |
| **Avatar** | Optional image path. Cosmetic only — not sent to the model. |

Plus several specialised sub-fields:

- **Relationships** — directional edges to other characters (kind + status + notes). See **Story Bible — Dynamics** for the richer per-relationship sheets.
- **Knowledge ledger** — per-scene facts the character knows / suspects / does not know / is mistaken about. Threaded into prompts so the model doesn't have a character reveal information they don't have. See **Knowledge ledger** in the Reference half.
- **Custom fields** — free-form label+value pairs for genre-specific extension (HP "house", MCU "team", etc.).
- **Canon brief** — fanfic-specific. Notes pasted from a fandom wiki for canon-faithful generation. Nil for original fiction.
- **Injection mode** — Constant or Keyed. See **Constant vs keyed** below.
- **Kink profile** — a list of named entries with a stance (Into / Curious / Soft limit / Hard limit). Free-form names, no enforced taxonomy. Rendered into the character's bible block so the model writes consistently across scenes.
- **Apparent anatomy** — physically obvious traits (build, breast size, hips, posture). Treated as ordinary description; always injected.
- **Intimate anatomy** — non-obvious detail (nipples, genitals, anything not visible when clothed). **Deliberately kept out of the always-on description** and injected only when the scene is depicted and the character is shown undressed (an automatic gate Loom applies). This split is so the explicit detail doesn't leak into non-explicit scenes.

You won't fill every field for every character. Protagonists usually get most of the fields; a one-line minor character can be just a name + role + one-line + description. Loom uses what's there and skips what's empty.

## Settings (places)

Lighter shape than Characters; the writing-relevant subset:

| Field | What goes in it |
|---|---|
| **Name** | Canonical name of the place. |
| **Aliases** | Other names — "the lighthouse" / "Sable Point Light" / "the keeper's tower" all point at the same Setting. |
| **Description** | The freeform full sketch — geography, history, atmosphere. The model reads this verbatim. |
| **Sensory notes** | Smell, sound, light, temperature. Authored separately from description so it's there when the writing wants sensory texture. |
| **Significant objects** | Pointer list into your Objects — chairs, journals, weapons that live in this place. Mostly an organisational aid; the prompt reads the Objects directly. |
| **Notes** | Anything else — alternate spellings, real-world references, author-only notes. |
| **Injection mode** | Constant or Keyed. |

If you write a multi-location project, Settings are how you keep the lighthouse from feeling like the kitchen which is how you keep the kitchen from feeling like the cabin. The model doesn't carry over place-feel across generations by itself; this is what holds it stable.

## Objects (significant artefacts)

Lighter still. Anything significant enough that the prose will mention it more than once and benefit from a consistent name + description:

| Field | What goes in it |
|---|---|
| **Name** | The canonical noun phrase. |
| **Aliases** | Other ways the prose names it. |
| **Description** | What it is and what it looks like. |
| **Significance** | Why it matters — narratively, thematically, mechanically. Useful for the model to motivate references back to it. |
| **Notes** | Anything else. |
| **Injection mode** | Constant or Keyed. |

A Setting can name Objects that live inside it (via Significant objects above); Objects don't reciprocate.

## Constant vs keyed injection

Every entity has an **injection mode**: **Constant** (the default) or **Keyed**.

- **Constant** — the entity's content is in the prompt on every generation. Use for: your protagonist, the one place 80% of the scenes happen in, your antagonist's MacGuffin.
- **Keyed** — the entity is injected only when its name or any alias appears in your recent prose. Use for: minor characters who only matter in their scenes, the side location you'll mention twice in the whole novel, the McGuffin's previous owner.

The keyed convention is from the NovelAI / KoboldAI / SillyTavern lorebook tradition. It keeps the context budget honest in long projects where a constant-injection-everywhere approach would silently start evicting the prose tail. A 20-character novel with everyone marked Constant will burn its token budget on people who aren't in the current scene; flipping half of them to Keyed buys back room for the prose itself.

Aliases matter for keyed entries. If your character is registered as "Eleanor" with no aliases and the recent prose only calls her "Nell," she won't trigger. Add "Nell" to her aliases and she will.

## What the model actually sees

For each generation, Loom assembles:

- A **bibleConstant** layer — every Character / Setting / Object marked Constant, formatted as an entity block with one-line + description + the specialised fields (kinks, anatomy when applicable, etc.).
- A **bibleKeyed** layer — entities whose name or alias just appeared in the recent prose, even if marked Keyed. Same formatting.

Both layers sit above the prose itself in the prompt. The model reads them, then continues your prose. You can audit exactly what was sent in the **▸ History** disclosure at the bottom of the tray — each entry expands to show every prompt layer.

For the assembled-prompt architecture (layer ordering, eviction rules, what's above-cache vs below-cache), see **Generation pipeline** in the Technical Reference book.

## Adjacent surfaces

- **Story Bible — Lorebook entries** — free-form keyed snippets that aren't full entities (worldbuilding details, faction history, magic-system rules, named events).
- **Story Bible — Dynamics** — structured per-relationship sheets (roles, wants, limits, safeword, arc) for cast pairs.
- **Knowledge ledger** — what each character knows when. Extracted automatically from your prose by the Ollama side-task.
- **Entity discovery** — auto-finding new characters / places / objects in your prose and surfacing them for accept/reject.

All four have their own pages further down the Reference TOC.

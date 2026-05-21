# Author's Note, per-call instructions, writing direction

Loom gives you three ways to steer the model, layered by how long they last:

| Tool | Lifespan | Where you set it |
|---|---|---|
| **Per-call instruction** | One generation, then cleared | The tray's instruction field |
| **Author's Note** | Persists across every generation | Settings → Project |
| **Writing direction** | Persists; shapes the whole project's posture | Settings → Project |

They stack — a generation can be steered by all three at once. This page covers all three and when to reach for each.

## Per-call instruction (one-shot)

The single-line **Instruction** field in the generation tray. Whatever you type lands in the prompt for the *next* generation only, in a strong-steering position (just before the mode's own instruction), then clears.

Use it for one-off steers:

- Tone: `more dramatic`, `keep it terse`, `lighten this up`.
- Beat direction: `end on a cliffhanger`, `she's lying`, `they get interrupted`.
- Must-mentions: `mention the lighthouse`, `bring back the knife from chapter 2`.

This is the surgical tool — when you want *this* generation to do something specific and then go back to normal. It's covered in **Generation modes** too, since it's part of the tray.

## Author's Note (persistent, near-cursor)

The **Author's Note** is a short directive that gets injected into *every* generation, close to the cursor. Set it once in Settings → Project; it stays in force until you change it.

It uses the bracketed convention from AI Dungeon / NovelAI: Loom wraps your note in `[ ... ]` and splices it into the prose a few lines back from the cursor. Models trained on long-form fiction read bracketed text as out-of-band authorial direction rather than story content — which makes it a more effective steering channel than a plain instruction, and why it's bracketed rather than written as a sentence.

What goes in an Author's Note:

- A standing tone or mood: `tense, claustrophobic, every exit closing`.
- A persistent stylistic constraint: `short sentences. no semicolons. concrete nouns.`
- An ongoing situational fact the model should keep in mind: `it is raining; everyone is exhausted`.

Two controls:

- **The note text** — Settings → Project → Author's Note.
- **The depth** — *AN depth (lines from cursor)*, default 4. This is how many lines back from the cursor the note is spliced. Lower = closer to the cursor = stronger steering (recency wins). Depth 0 places it right at the cursor.

**Per-call vs Author's Note:** the per-call instruction is for "do this once"; the Author's Note is for "keep doing this." If you find yourself typing the same per-call instruction every generation, promote it to the Author's Note.

## Writing direction (project posture)

The **writing direction** is the project-level dial set that tells the model what kind of fiction this is and how explicitly to render it. It's the difference between a project that fades to black and one that doesn't — and Loom translates it into concrete prompt changes rather than leaving it as a label.

Set it in Settings → Project. The dials:

| Dial | Options | Effect |
|---|---|---|
| **Kind** | literary / mainstream / romance / erotica / porn | The overall posture. `erotica` and `porn` foreground explicit content in the prompt; the others don't. |
| **Register** | clinical / literary / earthy / crude / mixed | The vocabulary register for intimate/explicit content. Captured and stated in the prompt; not enforced word-by-word. |
| **Explicitness** | fade-to-black / suggestive / on-screen / graphic / extreme | The master dial. How directly intimate content is depicted. `fade-to-black` suppresses all explicit-foreground behaviour regardless of the other dials. |
| **Pacing** | fast-plot / balanced / slow-explicit / explicit-foreground | How much room explicit scenes get relative to plot. |
| **Fade-to-black policy** | never / user-choice / model-decides | Whether the model is allowed to close the door on an intimate scene. |
| **Themes** | free-form, per-project | Named themes you can mark always-on (injected as constants). |

### What the dials actually do

The writing direction isn't just metadata — `WritingDirectionPrompt` turns it into real generation changes:

- **System-prompt posture.** For `erotica` / `porn` (and `on-screen` / `graphic` / `extreme` explicitness), positive, structural clauses are appended to the system prompt: "graphic sensory and anatomical description is the substance of the scene," "stay in the scene through escalation and climax; do not fade out." These are *positive* directives about what the prose depicts — never a list of forbidden words (blacklists get paraphrase-evaded; see the NSFW posture section).
- **Author's Note pulled closer.** `porn` pulls the AN to depth ≤2, `erotica` to ≤3 — closer to the cursor, stronger steering. (A shallower depth you set yourself is kept.)
- **A near-cursor directive.** For explicit-foreground projects, a short bracketed reminder is injected right at the cursor: `[ Authorial direction: stay in the scene at the established intensity… do not fade out, summarise, or cut away. ]` — because the system prompt sits far from the generation point and the model drifts back toward safe defaults over a long generation. This restates the posture in the recency-strong slot.
- **Longer Continue target.** `porn` raises the Continue word target to ~1200, `erotica` to ~750 (default 500), so the model doesn't stop short of the scene.

A default (literary) project gets *none* of this — the prompt is unchanged. The machinery only engages when you turn the dials.

### Per-scene explicitness override

A single scene can opt out of (or into) the project's explicitness via `Scene.explicitnessLevel` — set it on the scene to override the project default. A `fade-to-black` override on one scene fully suppresses the explicit-foreground posture for that scene even in a `porn` project. Useful for the aftermath chapter, the flashback, the one tender beat in an otherwise graphic work.

## How they combine

For a single generation, all three can be live at once:

1. **Writing direction** sets the system-prompt posture + Continue length + AN depth + the near-cursor directive (above-cache + near-cursor).
2. **Author's Note** splices your standing directive near the cursor.
3. **Per-call instruction** lands just before the mode instruction — the strongest-steering, most-recent slot — for this one generation.

You can see exactly what each contributed in the **▸ History** disclosure: the assembled prompt shows the system block (with the direction addendum), the Author's Note bracket, and the per-call instruction as separate, inspectable layers.

## See also

- **Generation modes** — the per-call instruction field in the tray flow.
- **NSFW / dark-fiction posture** — the framing behind the writing-direction dials + why constraints are positive, not blacklists.
- **Settings — app-level + per-project** — where the Author's Note + writing direction live.
- **Anti-slop phrases** — the one place Loom *does* use a phrase list (a backtracking sampler), and why that's different from a prompt blacklist.

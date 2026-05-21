# Generation modes

Loom's modes are the verbs of working with the model — Continue, Expand, Rewrite (with five sub-modes), Show-Don't-Tell — plus three adjacent paths in the Bible menu. This page is the catalogue: what each mode does, when to reach for it, what triggers it, and what to watch out for.

For the basic streaming + Accept/Reject loop common to every mode, see **Your first scene + first generation** in the Getting Started half. This page is the reference.

## Where modes live

Three surfaces:

- **The generation tray** under the editor — five buttons: Continue, Expand, Rewrite, Brainstorm, Critique. (Two of those are placeholders today — see below.)
- **The Rewrite sub-mode popup** — clicking Rewrite opens a popup with Voice / Tense / Length / POV-per-character / Show-don't-tell / Generic rewrite.
- **The Bible menu** — Roll Outcome, Write Scene From Template, Draft Scene From Outline. These are generation-adjacent paths, not generation modes proper.

Loom currently has no keyboard shortcuts that fire a mode directly — modes are clicked. Shortcuts exist only for the acceptance loop (⏎ accept, ⌫ reject, ⌘⇧R keep-and-redo, Esc / ⌘. cancel).

## Tray modes

### Continue

| | |
|---|---|
| **What it does** | Picks up where your cursor sits and writes the next ~500 words of the scene in voice. |
| **Trigger** | Click **Continue** in the tray. Requires that the editor has some prose — no enable on a fully empty scene. |
| **Selection?** | No. Generates from the cursor position; any selection is ignored. |
| **Output** | Inserted at the cursor; enters the acceptance window. |

This is the workhorse — the move you'll use most often once you're rolling. The model takes its strongest steering signal from the few sentences immediately before the cursor, plus your project's bible, plus any retrieved style exemplars from your references. When you want to keep going from where you are, this is what you reach for.

If the manuscript ends mid-sentence, Loom recognises that and slips the unfinished fragment into the model's own turn rather than the user turn — the model completes the sentence from inside its own voice instead of starting a fresh response after a sentence fragment. Smaller, but it matters when you stop mid-thought.

### Expand

| | |
|---|---|
| **What it does** | Treats the selected text as a sketch / outline / beat-list and writes the prose version of it, preserving every beat. |
| **Trigger** | Select a chunk of sketchy text, then click **Expand**. |
| **Selection?** | Required. The selection is the sketch. |
| **Output** | Replaces the selection with the expanded prose; enters the acceptance window. |

Reach for Expand when you've written something like:

```
- they argue about the lighthouse
- he refuses, but breaks first
- she walks out before he can apologise
```

…and you want it turned into actual prose. The model's brief is to flesh out the sketch, not to invent new beats — it preserves what you wrote and adds sensory detail, dialogue, interiority.

**Expand is not "make this paragraph longer."** That's **Rewrite → Length → 120%/150%**. Expand presumes the input is structurally a sketch (fragments, bullets, sparse beats). If you give it fully-written prose, it'll work but the result tends to over-elaborate.

### Rewrite

Click **Rewrite** with a selection active and a popup appears with these rows:

| Row | What it does |
|---|---|
| **Voice — use instruction field** | Rewrites preserving content; you type the target voice in the tray's instruction field ("more lyrical", "Cormac McCarthy", "first-person streetwise"). |
| **Tense — past** | Switches the selection to past tense. Auto-disabled if the selection is already past. |
| **Tense — present** | Switches the selection to present tense. Auto-disabled if already present. |
| **Length — 50% / 80% / 120% / 150%** | Compress or expand to that fraction of the original length. 50% is "trim hard"; 150% is "give it room to breathe." |
| **POV — \<character\>** | One row per Bible character. Rewrites from that character's POV. Uses the knowledge ledger to constrain what the new POV character actually knows at this point — see below. |
| **Show, don't tell (~120% length)** | Dramatises a telling sentence into showing prose. Best used on a one-sentence selection. |
| **Generic rewrite** | Open-ended. Whatever you've typed in the per-call instruction field is the rewrite directive. |

All Rewrite variants are **selection-replace**: they take the selection out and put new prose in. Acceptance loop follows. Reject (⌫) puts the original back.

**POV rewrite + the knowledge ledger.** This is the only sub-mode that pulls extra data. When you pick a new POV character, Loom looks up what that character knows at this scene's point in the timeline (from the knowledge ledger — see **Knowledge ledger** in the Reference half) and folds that constraint into the prompt. The new POV won't reveal information the new POV character doesn't have. The catch: this only works if you've been letting the extractor side-task run on your scenes; if the ledger is empty, the constraint is empty too.

### Brainstorm + Critique (placeholders)

These buttons appear in the tray but are not wired today — clicking them does nothing. The design intent is documented (Brainstorm: idea generation off-prose to a sheet; Critique: editorial notes in the History inspector), but the implementation is deferred. They'll light up when the work lands; for now treat them as visible-but-inert.

Three more deferred modes — Bridge, Describe, NameSuggest — exist in the data model with prompts authored, but have no UI surface at all today.

## Bible-menu paths

The **Bible** menu carries three generation-adjacent actions that don't fit the tray flow.

### Roll Outcome…

Pick a weighted lorebook group (e.g. a group labelled "First-meet outcomes" with five entries weighted by likelihood); Loom rolls one entry's content and loads it into the tray's per-call instruction field. You then fire Continue manually. The roll never auto-generates — it primes your next call.

Why this exists: NSFW / dark-fiction projects often want stochastic beats ("does the encounter escalate, defuse, or split the difference?"). Hand-rolling a die and typing the result into the instruction field works fine; this is just plumbing for the same idea. See **Sphiratrioth pack + power-user resources** in the Reference half for the canonical weighted-group setup.

### Write Scene From Template…

Generates a new scene by re-using a Template Scene's structural skeleton (beat ordering, modality flow, pacing) with your own characters and content. Templates live in the Bible Workspace (References → Scene exemplars); you ingest a scene-shaped chunk of prose once, and from then on you can ask Loom to write a *new* scene that follows the same shape.

Different pipeline from the tray modes — uses its own coordinator (`TemplateGenerationCoordinator`) with a per-beat writing pass. See **Scene exemplars + templates** in the Reference half.

### Draft Scene From Outline

Only relevant for projects created via **File → New Planned Project…** (the guided-wizard path). Each scene in a Planned Project carries a one-paragraph outline summary; this action drafts the current scene's prose from that summary, beat by beat. For non-Planned projects the menu item exists but the scene won't have an outline to draft from.

## The per-call instruction field

Common to every mode: the single-line **Instruction** field in the tray is a one-shot steering layer for the next generation. It lands in the prompt just before the mode's own instruction, so it sits in the strongest-steering position. Use it for:

- One-off tone shifts: `more dramatic`, `keep it terse`, `purple it up`.
- Beat instructions: `end on a cliffhanger`, `she's lying`.
- Must-mentions: `mention the lighthouse`.

Cleared automatically after the call. Roll Outcome populates it programmatically; otherwise you type into it.

## Token budget + eviction (briefly)

Every generation assembles a prompt: system prompt + project memory + bible-constant entries + retrieved-keyed lorebook entries + recent prose + style exemplars + author's note + per-call instruction + mode instruction. If the assembled prompt exceeds your project's context budget, Loom evicts lower-priority layers (and tells you which in the History inspector — "this generation evicted: dynamicSheet, fewShotStyleExample, sceneSummary").

You can audit the full assembled prompt for any past generation in the **▸ History** disclosure at the bottom of the tray. Each entry expands to show the per-layer content + token counts.

For the actual layer ordering, eviction rules, and what each layer carries, see **Generation pipeline** in the Technical Reference book.

## Common acceptance + cancel loop

Identical across modes:

- Streaming starts; editor is read-only.
- **Esc** or **⌘.** cancels mid-stream — whatever already streamed in stays, the rest is discarded.
- On completion the tray switches to the acceptance row: **Accept ⏎ / Reject ⌫ / Keep & Redo ⌘⇧R**.
- Reject restores the editor's pre-generation state (re-inserts the original selection for Rewrite modes).

Editing the inserted text counts as Accept — the moment you start typing inside a pending generation, Loom locks it in.

## See also

- **Your first scene + first generation** — the walk-through for Continue.
- **Author's Note, per-call instructions, writing direction** — the steering layers in detail.
- **Story Bible** — what gets threaded in automatically.
- **References + Scene exemplars** — what's retrieved + how.
- **Generation pipeline** (Technical Reference) — the full prompt-assembly architecture.

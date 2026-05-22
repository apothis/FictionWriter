# Scene exemplars + templates

A **Scene Exemplar** is a scene-sized chunk of prose (~500–5,000 words) that does two jobs in your project at once:

1. As a **style reference**, it joins the retrieval pool — its passages get pulled when the model needs voice-matched examples at generation time. Same machinery as the previous section, **References (style ingestion)**.
2. As a **structural template**, it lets you ask Loom to write *a new scene that follows the same shape* — preserving beat ordering, modality flow (action / dialogue / description), and pacing curve, but with characters / setting / situation you describe.

The same paste is the source for both. You add it once; Loom builds two sidecar files alongside it. Whether you ever invoke the template-generation side or just let it feed retrieval is up to you.

## What "same structural shape" means

Concretely, a Template Scene's skeleton captures:

- The **beats** in order — each beat is a unit of narrative action.
- The **modality** of each beat — is it dialogue, action, description, interiority, or summary?
- The **pacing curve** — how long each beat is relative to its neighbours; where the scene compresses and where it stretches.
- A **voice descriptor** — extracted at template-ingest time, used as a steering hint at generation time.

It does **not** capture content. The lighthouse-and-letter scene that's your template gives you a "two characters meet at sunset, dialogue tightens, one walks out before the other can respond" structure — but the new scene Loom writes from it can be set in a server room, with engineers, about a leaked spec.

## Adding a Scene Exemplar

Open the **Bible Workspace** (**⌘⇧B**) and pick the **References** tab (Scene Exemplars and References share the same surface today). Add a new entry:

- **Name** — your label.
- **Body** — the scene's prose. Paste from your own work, from a published author, from your own earlier draft.
- **NSFW flag** — gates retrieval and template-generation behaviour. See *NSFW* below.

Two actions are available on each entry:

- **Ingest** runs the Phase 5 pipeline: chunk → modality-classify → Wegmann embed → write `.index` sidecar. This is the **References** half — covered fully in the previous section.
- **Extract** runs the Phase 7 Pass-A skeleton extraction: the writer model walks the prose (under a grammar constraint that guarantees well-formed output) to identify beats, modalities, pacing, and a voice descriptor. Writes the `.beats.json` sidecar. This runs against your writer server, not the extractor — so you don't need an extractor configured to use templates.

You can run them independently:

- Ingest only → the exemplar contributes to style retrieval; **Write Scene From Template** can't use it yet (no skeleton).
- Extract only → the exemplar is available as a structural template; it doesn't feed retrieval.
- Both → the exemplar is a full Scene Exemplar in the Phase 8 unified sense.

In day-to-day use, you'll usually want both. The button cluster in the workspace shows each affordance's state ("Ingest" / "Ingested 14 chunks" / "Extract" / "Extracted 9 beats" etc.).

## Writing a scene from a template

Once a template has been extracted, you can invoke it from anywhere in the editor: **Bible → Write Scene From Template…**

A dialog opens with:

- A **Template picker** — every template with an extracted skeleton, labelled with its beat count.
- A **Cast / setting / situation** multi-line text field — this is where you describe what the new scene is *about*. The template provides the shape; this provides the content.
- An **Imitate content** toggle (default off — see below).
- An **Additional instructions** field — a one-off steering hint for this generation.

About the cast/setting field: **be specific.** Phase 7 testing showed that short descriptions ("Maya and Jordan, in a server room") tend to produce vague results; the writer model invents details to fill the gap. Detailed descriptions of 200+ characters ("Maya is a freelance investigator stuck on the 12th floor of an abandoned research tower. Above her, the building's AI is preparing to vent the upper floors…") render the intended scene. A few sentences with concrete details work much better than a short label.

Click **Generate** and Loom walks the template beat by beat, asking the writer model to produce a passage of the right modality, pacing, and voice for each beat in turn — but with your cast and your situation. The full scene streams into your editor at the cursor.

This uses its own coordinator (different from the tray modes) and a per-beat prompt-assembly path; it's slower than a single Continue call because it's multiple sequential generations.

### The Imitate content toggle

By default, the template-generation prompt explicitly tells the writer **not** to reuse plot, characters, settings, or specific events from the source. The template is a voice + structure exemplar; the content is yours.

For some cases — heavy-NSFW exemplars where the cast mapping alone underspecifies the explicit register / vocabulary the user wants — that constraint is too strong. Flipping **Imitate content** to *on* relaxes the prompt to a positive-constraint phrasing: the source's content register and vocabulary may transfer; character-name leakage is still prevented.

If you're getting bland, register-flat output from an NSFW template, this is the toggle to try.

### Per-template state

The cast / setting / Imitate-content / Additional-instructions you type are remembered **per template**. If you iterate on a Write-Scene-From-Template call (regenerating until you like the result), you don't have to retype the cast each time. State is persisted at:

```
YourNovel.loom/template-gen-state/<templateId>.json
```

One file per template. Different templates remember their own state independently.

## NSFW

The NSFW flag on a Scene Exemplar applies to both halves:

- **Retrieval** — NSFW chunks are only retrieved for NSFW-coded scenes (same rule as References, previous section).
- **Template generation** — at the moment, no extra gating beyond the retrieval rule. The writer's content posture is governed by the project's writing direction and the cast description; the NSFW flag here mostly drives the retrieval filter.

## On-disk layout

For a single Scene Exemplar with both sides ingested:

```
YourNovel.loom/
├── references/
│   ├── <uuid>.md            ← Same .md as the template's, shared UUID
│   └── <uuid>.index         ← Phase 5 chunks + embeddings
└── templates/
    ├── <uuid>.md            ← Same prose (shared UUID; Phase 8 unification)
    └── <uuid>.beats.json    ← Phase 7 Pass-A skeleton
```

The `.md` body sits in *both* directories under the same UUID — the Phase 8 unification was a presentational change, not a storage one. Legacy items from before unification can be References without templates, or templates without References; they show up as "orphans" with one side dimmed. Re-ingesting fills the missing sidecar.

## When to use a Scene Exemplar vs a plain Reference

- **Plain Reference** — you want voice anchoring, nothing more. Pages of prose whose voice you want the model to drift toward. You'll never click "Write Scene From Template" against this.
- **Scene Exemplar with Extract run too** — you want voice anchoring AND want the option to ask Loom to write a structurally-similar new scene from this shape. Costs ~30s extra ingest time (the Pass-A extraction); buys you the templating affordance.

If unsure, run both. The retrieval side has the immediate, frequent payoff; the template side is there for the occasional "I want to write *this kind of scene* again" use case.

## When Write Scene From Template works well

- **Pacing-faithful drafting.** You wrote a strong scene; you want to write another in the same beat-pattern with different content. Templates excel at this.
- **Tone-anchoring an NSFW scene.** You have an exemplar in the explicit register / vocabulary you want; Imitate content on, detailed cast description, the writer produces output in the same modality flow.
- **Genre-consistent drafting.** You want every confrontation in your novel to have a similar structural shape. One template, several invocations with different casts.

When it works less well:

- **Vague cast descriptions.** As noted above: be specific.
- **Templates with very long beats.** A 5,000-word scene with three giant beats becomes three generation calls of ~1,600 words each; the writer's coherence degrades over single-call lengths that long. Templates of ~6–12 medium-length beats are the sweet spot.
- **Templates whose modality flow is very atypical.** A template that's 90% interior monologue with one dialogue line will steer every generated scene toward that shape, which may not be what you want when you're writing something else.

## See also

- **References (style ingestion)** — the previous section. Everything about the retrieval side.
- **Generation modes** — the **Bible → Write Scene From Template…** affordance is documented there too as an adjacent generation path.
- **Generation pipeline** (Technical Reference) — for the per-beat assembly path and how it differs from the tray modes' single-pass assembly.

# Entity discovery

**Entity discovery** is Loom's "I just wrote a scene; what new people / places / things did I introduce, and should they be in the bible?" pipeline. It reads the prose of a scene, finds proper-noun-named characters, places, and significant objects that aren't already in your bible, and surfaces them as proposals — you accept the ones worth tracking and reject the rest.

Without this, every named entity has to be manually added before it'll get bible-injection on later generations. Entity discovery is the lazy-build path: write first, the bible catches up.

## What it discovers

Three kinds:

| Kind | What qualifies | Where it lands when accepted |
|---|---|---|
| **Character** | A proper-noun-named person, or someone introduced as "the X" with enough definite-article weight ("the lighthouse keeper") to behave like a name. | Characters list in the Bible. |
| **Place** | A named location — "Sable Point Light", "the Roebuck Inn", "the cathedral on Vellany Hill". | Settings list. |
| **Object** | A named significant artefact — Excalibur, The Necronomicon, "Tom's father's compass." Single mentions are enough for objects (no recurrence filter), because named artefacts tend to matter from the moment they're introduced. | Objects list. |

Each proposal arrives with: a **canonical name**, suggested **aliases**, a one-line description, an **evidence quote** pulled from your prose (so you can sanity-check the extractor), and the source scene.

## What it doesn't discover (today)

- **Generic unnamed characters** ("the man", "a woman"). They don't carry a stable identity for the bible.
- **Relationships between characters** — that's a separate pipeline (relationship discovery, not yet surfaced as its own user-facing page).
- **Lorebook entries** — facts / rules / world details. You write those yourself.
- **Cross-scene merging** — the pipeline doesn't fuse a character introduced in scene 3 with the same character appearing under a different name in scene 7. The user merges by accepting the right candidate and editing aliases.

## When it runs

Two triggers:

- **Automatic.** When the **extractor server** (Ollama) is configured and a scene's word count has changed by **500 words or more** since the last discovery pass on that scene, the pipeline fires in the background. Higher threshold than the knowledge ledger (200 words) because discovery is slower (~30s vs ~20s) and rarely finds new entities after the first pass on a given scene.
- **Manual.** **Bible → Discover Entities in Current Scene**. Runs the pipeline on the active scene immediately, regardless of the threshold. Useful when you've added a small but important named entity in a brief edit.

No extractor server configured → no automatic discovery. The manual menu item still tries, and will fail loudly.

## Status indicators

While discovery is running, the Bible Workspace entity-list header shows an **amber "Discovering N scene(s)…" pulse-dot**. When results land, the indicator flips to an **emerald "N entity proposals →" badge** you click to open the review surface.

If discovery fires and finds nothing new (everyone in the scene is already in your bible), no badge appears — silent success.

## The review surface

Click the badge or open the **Bible Workspace** (**⌘⇧B**) → **Entity proposals** tab. Each row shows one proposed entity:

- A pill marking the kind (character / place / object).
- The canonical name and suggested aliases — both editable in-place before you accept.
- The one-line.
- A collapsible block of attached facts the extractor pulled alongside the entity ("Tom is the lighthouse keeper at Sable Point", "Tom doesn't talk about the army").
- The evidence quote — the sentence the extractor pulled the proposal from.
- **Accept** / **Reject** / Edit buttons.

When you accept:

- The proposal becomes a real Character / Setting / Object in the bible.
- The attached facts flow into the new entity's knowledge ledger (for characters) or onto the relevant fields (for places/objects).
- The proposal is removed from the queue.

When you reject:

- The proposal is dropped. The pipeline won't re-suggest the same one on the same scene; it remembers refusals.

## The pipeline, briefly

Behind the scenes, discovery is six stages:

1. The **candidate generator** runs the scene's prose through the Ollama extractor (with a JSON-schema-constrained prompt) and returns a list of potentially-namable entities.
2. The **promotion gate** drops candidates that fail proper-noun-shape checks, are anatomy descriptors masquerading as names ("the redhead", "the blonde"), or — for places only — appear only once in the scene with no recurrence elsewhere.
3. The **dedup pass** runs cosine-similarity against the existing bible (Wegmann embeddings via CoreML) and drops candidates that are too close to an entity you already have.
4. **Normalisation** standardises naming, strips noise.
5. A **post-normalisation dedup** catches duplicates that emerged after normalisation collapsed them.
6. The survivors land in the **proposed-entities store** on disk and surface in the Bible Workspace.

You don't need to think about any of this for normal use. It matters when you're tuning a project that's generating too many false positives ("the discovery picked up six things from one paragraph; none of them are real characters") — the spike's per-stage breakdown is in the Technical Reference's **Extraction pipelines** section.

## Where the proposals are stored

On disk under your project:

```
YourNovel.loom/proposed-entities/proposed-entities.json
```

This is a transient queue file — accept/reject mutates it; it's safe to inspect, less safe to hand-edit while Loom is running. See **Where your work lives on disk** in the Getting Started half for the rest of the project layout.

## When entity discovery is worth investing in

- **Big-cast or sprawling-setting projects.** Twenty named characters across three locales — manually adding each is its own chore. Let the pipeline do the catalogue.
- **Drafting fast.** When you're writing scenes faster than you'd want to interrupt yourself to update the bible, discovery fills it in on a delay so the next generation has the right context.
- **Fanfic / shared-world.** Names matter more, get mentioned more, and the bible quickly becomes load-bearing.

Less urgent for:

- **Small-cast intimate fiction** (three characters in one room). You'll have them in the bible after five minutes of editing; the pipeline barely earns its CPU.
- **Heavy NSFW / kink scenes** where most of the named identities are already established and the prose is dense with anatomy descriptors. False positives go up; signal-to-noise drops.

Like the knowledge ledger (the previous section), discovery is a background pass that asks you to triage. If you don't accept or reject, the queue grows. Either commit to processing it, or run only on demand via the menu item.

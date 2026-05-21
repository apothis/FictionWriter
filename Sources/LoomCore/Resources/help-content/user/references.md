# References (style ingestion)

The default writing model has its own voice. Sometimes it's close to yours; often it isn't. **References** are how you push it toward the voice you actually want: paste in chunks of prose (your own earlier work, a writer whose register you're chasing, an in-house style guide as worked examples) and Loom retrieves the relevant chunks at generation time to show the model what "good prose for this project" looks like.

This isn't style transfer — the model doesn't copy a reference's content. It's **few-shot voice anchoring**: the model sees several examples of "prose with the qualities I want" right before it writes, and its output drifts toward those qualities.

## What you can use as a reference

Anything textual. Common sources:

- **Your own previous manuscripts.** Strongest match — the model learns *your* voice, not a stranger's.
- **A scene or two from a writer whose register you're after.** A few pages of Cormac McCarthy / Toni Morrison / whoever's voice you're chasing.
- **An in-house style guide written as examples** ("here are five short passages in the voice I want"). Useful for ensemble projects, ghostwriting, or holding your own voice steady across a long manuscript.

References live per-project — they don't share across projects. Add what's relevant to *this* novel.

## Adding a reference

Open the **Bible Workspace** (**⌘⇧B**) and pick the **References** tab in the entity list. Click **+ Add reference** (or the equivalent affordance), then fill in:

- **Name** — your label. Not sent to the model; used for organisation and provenance ("which reference did this generation pull from").
- **Body** — the prose itself. Paste anything from a paragraph up to many pages.
- **NSFW** — a boolean flag. See *NSFW gating* below.

You don't *do* anything else at this point. The text is saved but not yet ingested — meaning the chunks aren't embedded, and the reference isn't yet retrievable.

## Ingesting

Click **Ingest** on a reference and the pipeline runs:

1. **Chunk** the body into ~100-word overlapping passages.
2. **Classify each chunk's modality** — is this passage primarily dialogue, action, description, interiority, or summary? Used to make retrieval modality-aware: when you're writing a dialogue beat, dialogue chunks score higher.
3. **Embed each chunk** with the Wegmann style-embedding model (runs locally via CoreML — no extra server). One 768-dim vector per chunk capturing voice-and-register signatures.
4. **Refit the project-wide function-word index** — a complementary z-score-based signature that captures rhythm and word-frequency fingerprint across all references.
5. **Write the `.index` sidecar** to disk next to the reference's `.md`.

For a one-page reference this takes a couple of seconds; multiple-page references take longer. Re-ingest is safe — it overwrites the existing index. You'll re-ingest if you edit the body, or if Loom warns you the embedding model changed underneath.

## Retrieval at generation time

When you fire **Continue** (or any tray mode that draws on style), Loom does this without asking:

1. Looks at your recent prose — the bit you're about to continue from.
2. Classifies *its* modality (dialogue / action / description / interiority / summary).
3. Embeds it.
4. Searches across every chunk in every reference for the closest matches by combined Wegmann-cosine + function-word-z-score similarity, filtered to the recent prose's modality.
5. Picks the top three chunks.

Those three chunks land in the prompt as the **`fewShotStyleExample`** layer — formatted as "Here are three short passages in the voice the author wants" and placed below-cache (strong-steering side). The model then writes your continuation.

You can audit which chunks were retrieved for any past generation in the **▸ History** disclosure of the editor tray — the layer expands to show the actual chunk text and which reference each came from.

## NSFW gating

The **NSFW** flag on a reference does one thing: it gates retrieval by scene type.

- Chunks from **non-NSFW** references can be retrieved for any scene.
- Chunks from **NSFW** references are only retrieved when the current scene is itself NSFW-coded (via the project's writing direction, scene framing, or recent-prose signal).

Why: a kitchen-sink retrieval that mixes explicit chunks into a tender breakfast scene produces tonal whiplash. The flag is a coarse instrument — it doesn't try to be smart about which-explicit-chunks-fit-which-explicit-scenes — but it solves the cross-contamination case cheaply.

## How many references is enough

A few practical answers:

- **One reference, ~500 words.** Bare minimum. Voice nudges; not consistent.
- **3–5 references, totalling ~3,000–5,000 words.** Comfortable working point for most projects. The retrieval has enough variety to match different modalities.
- **A whole novel's worth of references** (~50,000+ words). Diminishing returns past this; retrieval is fast either way but the marginal voice gain stops paying for the ingestion time.

Add a reference, generate a scene, see if the prose moved the way you wanted. Add another if it didn't. The cycle is fast.

## Where references live on disk

Each reference is two files in your project:

```
YourNovel.loom/references/
├── <uuid>.md       ← The reference's text (with frontmatter for name + nsfw)
└── <uuid>.index    ← Per-chunk embeddings (D + E vectors, modality tags)
```

The `.md` is plain readable Markdown — back it up like any other writing. The `.index` is a JSON sidecar with the embeddings; it's safe to delete (Loom will mark the reference as un-ingested and you can Ingest again) and safe to ignore (Loom rebuilds it as needed).

## When references aren't pulling their weight

A few common failure modes:

- **The reference is too short.** ~50 words can't anchor much. Aim for at least a few hundred per reference.
- **The reference's voice doesn't match the prose at the cursor.** Retrieval scores against your recent prose; if your manuscript currently sounds nothing like the reference, the reference will rank low and the model won't see it. References pull you *toward* a voice; they don't override sharp divergence.
- **You haven't run Ingest.** The reference exists but isn't embedded. The Ingest button shows the state — if it still says "Ingest", you haven't run it. After ingestion it shows the chunk count.
- **The modality filter is too narrow.** If you only have dialogue-heavy references and you're writing a long description beat, retrieval finds nothing modality-matching and falls back to a wider window. Adding a description-heavy reference fixes this.

Reference retrieval is best as a steady background drift, not a per-call lever. The per-call instruction field (covered in **Generation modes**) is the surgical tool when you want a specific one-off voice steer.

## See also

- **Scene exemplars + templates** — the next section. A Scene Exemplar is a reference *and* a structural template (beat ordering + pacing) bundled together; if you've ingested a scene that way, both the structural pass and the voice retrieval pick it up.
- **Generation pipeline** (Technical Reference) — for the layer ordering, eviction rules, and the Wegmann/function-word-z-score scoring math.

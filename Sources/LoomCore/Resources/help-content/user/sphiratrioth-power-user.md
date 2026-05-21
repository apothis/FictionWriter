# Sphiratrioth pack + power-user resources

Local models have a **positive bias** — left alone, they soften, fade to black, cut away, resolve tension early, and reach for the safe next beat. The Sphiratrioth pattern (named for the SillyTavern community author who popularised it) counters this with lorebook entries that actively instruct the model to *stay in the scene at intensity*. Loom ships a curated starter pack of these you can install with one click.

If you haven't read **Story Bible — Lorebook entries** yet, do that first — the pack is built entirely from ordinary lorebook entries, just pre-authored.

## Installing the pack

**Bible → Install Sphiratrioth Lorebook Pack.** This adds a set of lorebook entries (all prefixed `[sph]` so you can spot them) to the current project.

The installer is **additive by name** — re-running it adds only the entries that are missing, and leaves any you've deleted deleted. So you can safely run it again after a Loom update, and you can delete the entries you don't want without them coming back.

The entries are deliberately **generic-but-strong**: they steer toward sustained-intensity prose without naming a specific kink or scenario. You customise by editing their content or adding your own.

## What's in the pack

Three patterns:

### Anti-positive-bias constants

Always-on, injected at the top of the prompt. These run on every generation in the project:

- **`[sph] Continue at established intensity`** — "the scene continues at the intensity the prose has established… sensory detail compounds; the scene does not abbreviate itself."
- **`[sph] No meta-commentary or moralising`** — "do not break the narrative voice with editorial commentary, content warnings, moralising, or out-of-frame asides."
- **`[sph] Sensory detail over summary`** — "prefer concrete sensory detail to summary or skip-ahead; when a beat would naturally extend, extend it."

These are the workhorses. They counter the three most common positive-bias drifts — abbreviation, editorialising, and skip-ahead — on every call.

### Sticky scenario anchors

Keyed entries with `sticky: true` and depth-2 placement (close to the cursor). They activate when their keys appear in recent prose, and *stay* active across scene shifts once triggered:

- **`[sph] Active intimate scene (sticky)`** — keys on kiss/undressed/bedroom/body words. "Continue at established intensity. Do not introduce interruptions, scene breaks, fade-outs, or external arrivals unless the manuscript signals one."
- **`[sph] Active conflict scene (sticky)`** — keys on knife/gun/blood/fight words. "Do not introduce convenient rescues, off-page resolutions, or de-escalations the manuscript hasn't earned."

The stickiness is the point: once you're in an intimate or violent scene, the anchor keeps holding the model to it even as the prose moves past the triggering keywords.

### Weighted outcome groups

Four entries sharing the group `action_outcome`, each with a weight — the substrate for **Roll Outcome** (covered in **Generation modes**):

| Entry | Weight | Outcome |
|---|---|---|
| `[sph] Outcome — decisive success` | 25 | The action succeeds cleanly. |
| `[sph] Outcome — partial success` | 40 | The goal is reached at a cost. |
| `[sph] Outcome — failure with leverage` | 25 | Fails, but the failure reveals something usable. |
| `[sph] Outcome — reversal` | 10 | An unforeseen reversal pivots the situation. |

At a decision point, **Bible → Roll Outcome…** → pick `action_outcome`, and Loom rolls one (weighted — partial success is most likely at 40, reversal rarest at 10) into the per-call instruction field. You then fire Continue and the rolled outcome biases the generation. It's a structured way to let chance push your plot without you choosing the beat yourself.

## Using them

- **Constants** just work — install and they're in every prompt.
- **Sticky anchors** activate on their keywords automatically; nothing to do. Edit their keys if your prose uses different vocabulary.
- **Outcome groups** are invoked deliberately via Roll Outcome when you want a die thrown.

## Customising + building your own

The pack is a demonstration of the three patterns, not a fixed kit. To go further:

- **Edit the content** of any `[sph]` entry in the Bible Workspace to match your project's specific intensity or scenario.
- **Add your own outcome groups.** Make several lorebook entries sharing a new group label (e.g. `seduction_outcome`), give each a weight, and they'll appear in the Roll Outcome picker.
- **Author your own sticky anchors** for a recurring scenario specific to your work — same shape as the `[sph]` ones (keyed, sticky, depth-2).

## Power-user resources

Loom ships sane defaults but doesn't try to be the last word on model tuning. The living knowledge is in the community. Worth bookmarking:

- **r/SillyTavernAI weekly megathread** — current model + preset consensus.
- **r/LocalLLaMA** + **r/AICreativeWriting** — ongoing model + technique discussion.
- **Marinara's LLM Hub** (`spicymarinara.github.io`) — advanced presets, including the "Spaghetti Recipe" system prompt referenced in the NSFW posture section.
- **Sphiratrioth's Hugging Face** — the active-scenario lorebook recipes this pack is modelled on.
- **Sukino's SillyTavern-Settings-and-Presets** — general tuning.
- **Huihui's Hugging Face** — abliterated model variants.
- **mlabonne's abliteration article** + **the Heretic toolkit** (`p-e-w/heretic` on GitHub) — for abliterating your own models.

These are external — Loom doesn't host or bundle any of them. They're where the techniques in this help system come from, and where they keep evolving.

## See also

- **Story Bible — Lorebook entries** — the entry mechanics the pack is built from (keys, sticky, groups, weights, position).
- **Generation modes** — the Roll Outcome action.
- **NSFW / dark-fiction posture** — the framing + the Marinara preset + abliteration.
- **Author's Note, instructions, writing direction** — the other anti-positive-bias levers.

# Knowledge ledger

Stories rely on characters knowing different things at different times. The villain knows what happened in the alley; the protagonist doesn't, yet. The reader saw the letter; the recipient hasn't opened it. Long-form drafting tools that don't track this end up with characters who quietly know what they shouldn't — the model has been told everything in the bible, so the model writes a character with full omniscience.

Loom's **knowledge ledger** is the structured fix. For every character, Loom tracks the facts they've learned, scene by scene. When you write a scene from a particular POV, the model is given that POV character's KNOWS / DOES NOT KNOW state as a constraint — and prose written from that POV stays inside what the character actually knows.

This is Loom's distinctive engineering. Other long-form tools have story bibles; none ship per-character-per-scene knowledge tracking.

## What the ledger holds

Each character carries a `knownFactsBySceneId` map — for every scene, the list of facts they learned (or had revealed about them) in that scene. A fact is a short prose statement:

```
- "The lighthouse keeper's name is Tom."
- "Eleanor and Tom were married before the war."
- "The letter says Sarah is alive."
```

Each fact has:

- The **fact text** itself.
- A **certainty** marker — Asserted (confirmed), Suspected (the character believes but isn't sure), Mistaken (the character believes something false), or Unknown (slot for the contrapositive — see below).
- The **source scene** it was extracted from.
- A timestamp.

The extractor only ever emits **asserted** facts directly. Suspected / Mistaken are author-edited or rare extractor outputs. **Unknown** is never extracted — see below.

## KNOWS vs DOES NOT KNOW — how it's derived

Loom doesn't store "does not know" as facts. The model can't reliably extract negative knowledge ("X is unaware that Y") — the spike that proved this found 0/2 recall on negative-knowledge prompts. Instead, Loom **derives** what a character doesn't know by walking the manuscript chronologically and asking, for each fact extracted in scene S: was this character present in S?

- **Present in S** → the fact is in their KNOWS set as of any scene at or after S.
- **Not present in S** → the fact is in their DOES NOT KNOW set as of any scene at or after S.

That's it. The "scene-exposure" derivation gives you the contrapositive for free, without asking the model to do something it's bad at.

"Present" means the character (by canonical name or any alias) is mentioned in the scene's prose. This is loose — a character could be in the room without being named, or named in passing without really being on stage — so the ledger is best-effort, not provably-correct. Practical reality is that for nearly all scenes, named-in-prose tracks closely with on-stage, and the cases where it doesn't tend not to be the dramatic-irony-load-bearing ones anyway.

## When the extractor runs

Loom auto-runs an extractor pass on a scene when:

- An **extractor server** is configured (Settings → Servers, marked Set as Extractor — see **Configure your model servers**).
- The scene's word count has changed by **200 words or more** since the last successful extraction (additions OR deletions — a heavy trim re-runs because facts in the trimmed passage may no longer be supported).

The pass is debounced — Loom doesn't fire after every keystroke; it waits a beat after you stop editing. The first extraction on a brand-new scene fires once the scene crosses 200 words.

If no extractor server is configured, no extraction runs and no suggestions accumulate. Continue still works; the model just doesn't get knowledge-state context.

## The suggestions queue

The extractor doesn't write directly into characters' ledgers. It surfaces candidate facts in a **suggestions queue** the user reviews. Open it in the **Bible Workspace** (**⌘⇧B**) → **Suggestions** tab. A pill in the entity-list header shows the pending count.

For each suggestion:

- The proposed fact, the source scene, the certainty, and the character the extractor attributes it to.
- An evidence quote from the scene's prose, so you can confirm the extractor isn't hallucinating.
- **Accept** — the fact lands in the character's ledger.
- **Reject** — the fact is dropped; the extractor won't re-suggest the same one.
- **Edit** — fix the wording or attribution before accepting.

The queue is across characters; you don't have to flip into each character's editor to triage.

## Accepted-facts examiner

Once a fact is accepted, it sits on the character's ledger. The **accepted-facts examiner** (Bible Workspace → Character editor → KNOWS tab) shows every accepted fact grouped by source scene, with a delete affordance if you change your mind later. This closes the loop: facts the queue accepts don't disappear into invisible-data — you can always go look at them.

## What the model sees

For a generation where you've set a POV character, the prompt assembler includes a **`knowledgeLedger`** layer:

```
[KNOWLEDGE-LEDGER]
KNOWS (Tom, as of scene 12):
  - The lighthouse keeper's name is Tom.
  - Eleanor and Tom were married before the war.
  - …

DOES NOT KNOW:
  - The letter says Sarah is alive.
  - …
```

The block is computed at generation time — it walks the manuscript up to and including the current scene, applying the present-in-scene rule, and emits what Tom should know. The model is then told: continue this scene in Tom's POV, given that he knows the things above and doesn't know the things below.

No POV character set → no ledger layer injected. The layer is POV-character-specific by design.

## Setting POV

The POV is set per-scene through the editor sidebar's **Set POV** submenu (right-click a scene). For projects where you don't set a POV explicitly, the ledger layer doesn't inject and the model writes without that constraint. For POV-rotating projects, set the POV on each scene as you go and the model's worldview shifts with the scene.

## POV rewrite uses this directly

The **Rewrite → POV — \<character\>** sub-mode (see **Generation modes**) reads exactly this state: it computes the new POV character's KNOWS / DOES NOT KNOW as of the rewritten scene and feeds it into the rewrite prompt. That's why POV rewrites can re-cast a scene without leaking — the model isn't told to "pretend not to know"; it's told what the new POV knows.

The catch: this constraint is only as good as your ledger. If the extractor hasn't been running (no extractor server, scenes under 200 words, suggestions never accepted), the KNOWS set is empty, and the POV rewrite has nothing to anchor to.

## When the ledger is worth investing in

- **POV-rotating fiction.** Multiple narrators, multiple knowledge horizons. Big payoff.
- **Mystery / suspense.** Withholding information is the structural engine. The ledger keeps you honest about who knows what.
- **Dramatic irony.** The reader knows; characters don't. The ledger marks the boundary.

When it's less urgent:

- **Single-POV linear narrative** where every reveal happens to the POV character first. The KNOWS set effectively equals what's been written so far; there's nothing the model could leak that it shouldn't.
- **Light slice-of-life / vignette work.** Investment-to-payoff is low.

In all cases, the extractor running in the background is cheap (small Ollama model, side-task only). The cost is your time triaging the suggestions queue — if you don't, the queue grows and the ledger stays empty. Either commit to triaging it, or turn the extractor off in Settings → Servers → Clear Extractor.

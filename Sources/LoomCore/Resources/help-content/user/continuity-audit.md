# Continuity audit

> **Status: not yet available in the app.** The continuity-audit engine is built and works, but there is no user-facing surface to run it or review its results yet. This page is a placeholder; it will become a real how-to once the review queue ships.

## What it will do

A **continuity audit** scans your whole manuscript for contradictions across scenes — the kind that creep into long work and are hard to catch by re-reading:

- **Attribute drift** — a character's eyes are blue in chapter 2 and brown in chapter 9.
- **Knowledge-state violations** — a character acts on information they shouldn't have yet (the inverse of what the **Knowledge ledger** tracks).
- **Timeline / chronology** — events that don't line up in time.
- **Spatial / world** — someone is in two places at once, a room's geography shifts.

The design intent is a severity-ranked, evidence-cited review queue in the Bible Workspace: each finding shows the contradicting claims, the scenes they came from, and lets you judge whether it's a real error or a deliberate one (an unreliable narrator, a reveal, a lie a character tells).

## Why it's not here yet

The hard part of contradiction detection isn't finding *candidate* conflicts — it's not drowning you in false positives. Naive whole-document LLM judging runs ~54% precision (it flags far too much). Loom's engine decomposes the problem (typed-claim extraction → candidate retrieval → pairwise adjudication) to do better, and that engine is built and validated. But:

- Per-run coverage is still **stochastic** — a given run finds most contradictions, not all.
- The **review-queue UI** (where you'd actually see and triage findings) hasn't shipped.

Until both are solid, exposing it would be a feature that produces a pile of findings you can't act on — worse than not having it. So it's gated.

## What exists today

The engine runs in development + via a spike runner (`swift run ContinuityAuditSpike`), and its architecture is documented for contributors in the Technical Reference's **Extraction pipelines** section. There's nothing for you to run from the app yet.

## In the meantime

The **Knowledge ledger** (which *is* shipped) is the prevention-side counterpart: by tracking what each character knows when, and feeding that into generation, it heads off knowledge-state contradictions at the point of writing rather than catching them after. It won't catch attribute drift or timeline errors — but it's the part of the continuity story that's available today.

## See also

- **Knowledge ledger** — the shipped, prevention-side counterpart.
- **Extraction pipelines** (Technical Reference) — the audit engine's architecture, for the curious.

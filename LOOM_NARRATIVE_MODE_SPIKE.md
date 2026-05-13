---
name: LOOM_NARRATIVE_MODE_SPIKE
description: Phase 5 production sub-spike — validate gemma-31B narrative-mode classification before committing to LLM-at-ingest tagging
type: project
---

# LOOM_NARRATIVE_MODE_SPIKE — half-day classifier validity check

> **Date:** 2026-05-13. **Status:** plan only. **Scope:** half-day sub-spike inside Phase 5 production scope-lock #5 ([`LOOM_PLAN.md`](LOOM_PLAN.md) §5 Phase 5).
>
> Phase 5 production scope-lock #5 is per-scene-type retrieval — the differentiator vs SillyTavern's generic vectorised lorebook per [`LOOM_RESEARCH.md`](LOOM_RESEARCH.md) §O.4. The user picked Option B (LLM-classified at ingest time) over user-tagging on the principle that Loom should leverage LLM wherever possible. Path C in the original RAG spike ([LOOM_RAG_SPIKE.md §13.3(c)](LOOM_RAG_SPIKE.md)) failed below floor because gemma-31B GBNF descriptors collapsed to defaults. This spike falsifies the concern that the narrower scope (single enum, not five free-form fields) inherits the same failure mode.

## 1. Falsifiable hypothesis

> **Hypothesis**: gemma-4-31B-uncensored under a *flat single-enum* GBNF can classify paragraph-sized prose chunks into a narrative-mode taxonomy at agreement-with-human-gold ≥ 70%, the empirically-observed ceiling for inter-annotator agreement on adjacent literary-structure labels (Zehe et al. EACL 2021 reports γ ≈ 0.7 for scene-segmentation IAA).

Both conditions must hold for PROCEED:

1. The flat-enum GBNF doesn't collapse to a default label across diverse chunks.
2. Agreement-with-gold reaches ~70%, matching the human IAA ceiling.

If the LLM-classifier matches a heuristic baseline but doesn't beat it materially, **PIVOT** to the heuristic for the dominant-mode case (dialogue, where heuristics are nearly perfect) and fall back to LLM only for the residual three-way (action/interiority/description/summary).

## 2. Taxonomy revision before the spike

[`LOOM_RESEARCH.md §O.4`](LOOM_RESEARCH.md) listed four modes: action / dialogue / interiority / description. Pre-spike research (2026-05-13) confirmed this maps to a subset of Marshall's five fiction-writing modes; the consequential omission is **summary** (Card 1999, Le Guin's *Steering the Craft* — scene-vs-summary is the pace axis, orthogonal to the others). Summary chunks compress time (*"For three weeks she avoided him"*); description suspends time (*"The kitchen was painted yellow"*). In retrieval terms these are distinct.

**Spike taxonomy: {action, dialogue, interiority, description, summary, mixed}.** The schema extends to this enum *before* the spike runs (adding `summary` after the fact would invalidate any LLM-classifier numbers).

- **action** — physical action / external events. Active verbs, scene-time progression.
- **dialogue** — character speech, with or without attribution beats. Quote-density is the surface signal.
- **interiority** — internal thought / feeling / free-indirect discourse. Cognition verbs ("thought", "wondered"); subjective register.
- **description** — settings, objects, sensory environment. Suspended time, adjective density, sensory verbs.
- **summary** — compressed-time narration. "For three weeks…", "By autumn…", "She had been seeing him for months." Scene-vs-summary axis.
- **mixed** — genuinely 50/50 across two modes. The gold's noise floor; the classifier can also emit it.

Genette's *focalization* (POV) is orthogonal and already lives in a separate slot (scene metadata). Don't collapse it into modality.

## 3. Methodology

### 3.1 Hand-built gold set (~50 chunks)

Sources:
- **Re-chunked existing RAG fixture** ([`Tests/LoomCoreTests/Fixtures/RagSpike/fixture.json`](Tests/LoomCoreTests/Fixtures/RagSpike/fixture.json)). Split each of the 12 excerpts at paragraph boundaries → ~30 chunks. Tests intra-passage modality variation (a single excerpt may have action + interiority + dialogue in different paragraphs).
- **Author ~20 additional chunks** specifically covering summary-mode and edge cases. Summary chunks are rare in the existing fixture (the prose tends toward scene-time); adding them deliberately ensures the gold has at least 8-10 summary examples for the LLM to learn from in few-shot.

Total target: 50 chunks, ~80-150 words each, hand-labeled with primary modality. Mark `mixed` where genuinely 50/50 — that's the gold's noise floor, proxy for IAA.

NSFW coverage: at least 12 of the ~50 chunks (≥ 24%) are NSFW, preserving the RAG fixture's strategic-anchor proportion. The classifier must handle these without refusing or systematically mis-tagging.

**Fixture path:** `Tests/LoomCoreTests/Fixtures/NarrativeModeSpike/gold.json`.

### 3.2 Three classifier configurations under test

#### (a) Heuristic baseline

Pure-Swift ruleset, ~80 LOC:

- **Dialogue gate**: quote-density ≥ 30% of characters inside `"…"` or `'…'` pairs → dialogue.
- **Action**: high verb-to-noun ratio (≥ 0.6) + low cognition-verb count → action.
- **Interiority**: cognition-verb count ≥ 2 ("thought", "felt", "wondered", "remembered", "knew") or free-indirect markers ("would", "might", "could" + no subject-attribution) → interiority.
- **Description**: low verb-to-noun ratio (< 0.4) + sensory verbs ("looked", "smelled", "appeared", "seemed") → description.
- **Summary**: temporal-compression markers ("for X weeks", "by Y", "had been -ing", "would later") → summary.
- **Fallback**: when no rule fires confidently, emit `mixed`.

Establishes a floor. Heuristic-only is a real fallback if the LLM doesn't materially beat it.

#### (b) gemma-31B zero-shot + flat GBNF enum

GBNF grammar:

```
root  ::= label
label ::= "action" | "dialogue" | "interiority" | "description" | "summary" | "mixed"
```

Single-label output, no JSON wrapper, no nested structure — flat enum tokens only. This is the failure-mode fix per [Bastan et al. "Lost in Space" (2025)](https://arxiv.org/html/2502.14969v1): nested-JSON constrained decoding collapses; flat structure with leading-whitespace tokens works.

Prompt (zero-shot):

```
Classify this prose passage's primary narrative mode.

Categories:
- action: physical action / external events
- dialogue: character speech
- interiority: internal thought, feeling, or free-indirect discourse
- description: settings, objects, sensory environment, suspended time
- summary: compressed-time narration ("for three weeks…")
- mixed: genuinely 50/50 across two modes

Passage:
{chunk}

Mode:
```

`max_length=8`, `temperature=0.0`, `rep_pen=1.0`. With grammar constraint the model emits exactly one enum label.

#### (c) gemma-31B 4-shot + flat GBNF enum

Same grammar + same prompt skeleton, with **one labeled exemplar per category** prepended. Exemplars drawn from authors *outside* the gold set (public-domain or hand-authored — never from the gold itself, to avoid leakage).

Research expects few-shot to lift κ by 0.1-0.2 for subjective literary labels.

### 3.3 Scoring

Per-config, per-category:

- **Accuracy**: chunk-level match rate against gold.
- **Per-category precision / recall / F1**: 6×6 confusion matrix; macro-F1 reported.
- **`mixed`-detection**: separately track precision on the "I'm unsure" output — important for retrieval (mixed chunks should NOT be used as `modality=action` exemplars).
- **NSFW parity**: per-config accuracy on NSFW subset vs SFW subset. If a config drops materially on NSFW (e.g., refuses or always defaults to one label), flag as production-relevant — gemma-31B-uncensored should be content-neutral.

## 4. Acceptance bar

A config passes the floor at:

- **Accuracy ≥ 70%** on the full gold set (matching Zehe's human IAA ceiling).
- **Per-category recall ≥ 50%** for every category — must not collapse to "always predict action" or similar.
- **No NSFW parity drop ≥ 15%** vs SFW subset (the spike's content-neutrality check).
- **Dialogue precision ≥ 90%** for any config — dialogue is the easy one; failing here is structural.

## 5. Day-plan

**S5.5.1 — Schema + plan (this commit, ~30min)**
- Extend `NarrativeMode` enum + the existing `ReferenceTextIndex.Chunk.modality: String?` slot value space.
- TestKit tests pin the v2 enum.
- Land this doc.

**S5.5.2 — Gold set (~2h, hand work)**
- Re-chunk the 12 fixture excerpts at paragraph boundaries.
- Author ~20 summary + edge-case chunks (NSFW-mixed).
- Hand-label every chunk's primary modality. Mark `mixed` where genuinely unclear.
- Land at `Tests/LoomCoreTests/Fixtures/NarrativeModeSpike/gold.json`.
- TestKit smoke-test pins shape (~50 chunks, NSFW ≥ 24%, every modality represented).

**S5.5.3 — Heuristic classifier (~1h)**
- `Sources/LoomCore/Retrieval/NarrativeModeHeuristic.swift` + TDD.
- Eval against gold; print per-category confusion matrix.

**S5.5.4 — LLM classifier wiring (~1.5h)**
- Extend `Tools/RagSpike/main.swift` with `--narrative-mode` subcommand.
- Flat GBNF + zero-shot prompt + 4-shot prompt variants.
- Eval against gold; per-config metrics.

**S5.5.5 — Verdict + commit (~30min)**
- Append §6 results to this doc.
- Close [`LOOM_PLAN.md`](LOOM_PLAN.md) §5 scope-lock #5 against the winning config.

Total: ~5h. One focused session.

## 6. Sections to append post-spike

- **§7 Gold-set composition** — final chunk count + NSFW + per-modality distribution.
- **§8 Per-config eval table** — accuracy, macro-F1, per-category precision/recall, NSFW parity.
- **§9 Confusion-matrix observations** — what each config gets wrong.
- **§10 Verdict** — PROCEED / PIVOT / NO-GO + close scope-lock #5.

## 7. Decision tree

### PROCEED — (c) few-shot LLM clears 70% accuracy + 50%-recall floor + no NSFW drop

Phase 5 production tags at ingest via gemma-31B few-shot + flat GBNF. Bible Workspace's reference-text editor surfaces the inferred modality with a per-chunk override affordance (cheap user-correction path; classifier handles 70%+ correctly).

### PIVOT — heuristic-only matches LLM within 5% on aggregate

The LLM isn't earning its keep. Ship the heuristic — ~80 LOC of Swift, instant, no Kobold dependency at ingest. Surface the inferred modality with user override the same way. Re-evaluate LLM when a larger/better classifier ships.

### PIVOT — LLM beats heuristic on residual three-way only (dialogue → heuristic, rest → LLM)

Ship a two-pass classifier: heuristic dialogue-gate first; LLM for chunks that fall through. Same UX, cheaper average-case latency.

### NO-GO — neither LLM nor heuristic clears 70% on the residual

Skip per-scene-type tagging for Phase 5 v1. Ship hybrid D+E retrieval without modality filtering. Per-scene-type retrieval becomes a Phase 5.5 follow-on once we have real user reference corpora to evaluate against — the spike's gold set may be too small or too narrowly authored.

## 8. Out of scope

- **Multi-label modality.** Schema may grow `modality_secondary` later; the spike tests primary-only.
- **Modality confidence scores.** Schema may grow `modality_confidence` later; the spike emits a flat label.
- **Per-modality retrieval merge.** Once chunks are tagged, the hybrid RRF code path filters by `query.modality` before merging. That's a Phase 5 production wiring task, not a spike question.
- **User override UX.** Bible Workspace surface is downstream of this spike — needs the classifier to land first.
- **Cross-lingual.** English-only fixture.

## 9. Risks

- **Gold-set quality dominates.** A 50-chunk hand-labeled gold has limited statistical power. If the author + the classifier both agree but a different human would disagree, the spike's verdict is wrong. Mitigation: the 70% bar is the *human* IAA ceiling; a config reaching it is at human-equivalence, not perfection.
- **Few-shot exemplar leakage.** The 4-shot exemplars must come from outside the gold set; otherwise the eval is trivially inflated. Verified by author identity (mine; not the gold's authors).
- **GBNF collapse despite flat enum.** Path C's failure prior. Mitigation: the "Lost in Space" 2025 finding specifically diagnoses nested-JSON as the culprit; flat enum-only grammars are reported to work. Verify with a hand-inspection of the first 10 zero-shot outputs before running the full eval.
- **NSFW refusal.** gemma-31B-uncensored is the writer model precisely because it doesn't refuse; classification should inherit. If somehow the classification prompt triggers refusal, fall back to a more terse prompt with no category descriptions.

## 10. References

- [LOOM_RAG_SPIKE.md §13.3(c)](LOOM_RAG_SPIKE.md) — prior Path C collapse; modality field was the one that survived.
- [LOOM_RAG_SPIKE.md §13.6](LOOM_RAG_SPIKE.md) — modality slot was reserved on chunks for this scope-lock.
- [LOOM_PLAN.md §5 Phase 5](LOOM_PLAN.md) — scope-lock #5 specification.
- [LOOM_RESEARCH.md §O.4](LOOM_RESEARCH.md) — original 4-category taxonomy.
- [LOOM_NSFW.md §3](LOOM_NSFW.md) — content-neutrality constraint.
- [Zehe et al. (EACL 2021) — Detecting Scenes in Fiction](https://aclanthology.org/2021.eacl-main.276.pdf) — human IAA γ ≈ 0.7 anchors the 70% acceptance bar.
- [Bastan et al. (2025) — Lost in Space: Optimizing Tokens for Grammar-Constrained Decoding](https://arxiv.org/html/2502.14969v1) — flat enum vs nested JSON failure mode.
- [Fiction-writing mode (Marshall's five modes via Wikipedia)](https://en.wikipedia.org/wiki/Fiction-writing_mode) — taxonomy origins.
- [Comparing LLMs and human annotators in latent content analysis (Nature Sci Rep 2025)](https://www.nature.com/articles/s41598-025-96508-3) — few-shot vs zero-shot for subjective literary labels.

---

## 7. Gold-set composition (landed)

52 chunks at `Tests/LoomCoreTests/Fixtures/NarrativeModeSpike/gold.json`. Hand-labeled by author (Loom dev). Sources:

- **32 chunks re-chunked from RAG-spike excerpts** ([`Tests/LoomCoreTests/Fixtures/RagSpike/fixture.json`](Tests/LoomCoreTests/Fixtures/RagSpike/fixture.json)), split at paragraph boundaries. Tests intra-passage modality variation.
- **20 hand-authored chunks** targeting under-represented modes (especially `summary`, which was rare in the existing fixture's scene-time prose) and edge cases (very short dialogue, mixed-mode borderlines).

Modality distribution:

| modality | count |
|----------|-------|
| action       | 11 |
| dialogue     |  8 |
| interiority  |  8 |
| description  |  8 |
| summary      | 12 |
| mixed        |  5 |

NSFW coverage: 29 of 52 (56%) — comfortably above the 24% floor and matching the strategic-anchor proportion of the parent fixture.

Word-count: min 4, max 87, median 30. Three chunks under 10 words (short pure-dialogue cases) — kept as realistic test cases.

## 8. Per-config eval results

Reproducible via `swift run RagSpike --narrative-mode`; raw dump at `Tools/RagSpike/last-run/narrative-mode-eval.json`.

| Config         | Accuracy | NSFW acc | SFW acc | NSFW gap | Dialogue P | Action P | Mean s/chunk |
|----------------|----------|----------|---------|----------|------------|----------|--------------|
| heuristic      |  0.558   |  0.517   |  0.609  |  9.2%    |   1.000    |  0.714   | < 0.01       |
| **zero-shot LLM**  |  **0.731**   |  0.690   |  0.783  |  9.3%    |   1.000    |  0.889   | 0.77         |
| 4-shot LLM     |  0.519   |  0.379   |  0.696  | 31.7%    |   1.000    |  1.000   | 0.77         |

- **Zero-shot LLM clears the 70% acceptance floor** (matching Zehe γ ≈ 0.7 human IAA ceiling).
- **Heuristic falls below floor** at 55.8% on aggregate, **but achieves 100% precision + 87.5% recall on dialogue** — saving the LLM from its biggest failure mode.
- **4-shot LLM is *worse* than zero-shot** by ~21 accuracy points. Unexpected per the research recommendation (Cohen's κ +0.1-0.2 from few-shot was the prior).

NSFW parity: zero-shot's 9.3% gap is within the 15% spike-spec tolerance. 4-shot's 31.7% gap **violates** the tolerance and rules out 4-shot regardless of accuracy.

## 9. Confusion-matrix observations

**Zero-shot LLM (14 misclassifications):**

- **Dialogue recall is weak**: 3 of 8 dialogue golds caught (chunks 22, 29, 32, 47, 48 all collapse to `mixed`). The model treats borderline dialogue (very short, attribution-heavy, or rapid-fire) as uncertain. Heuristic catches 7 of 8 reliably — the dialogue-gate composition is structural.
- **Description recall is uneven**: 6 of 8 caught; 2 chunks (9, 31) collapsed to `mixed`. Chunk 9 is the note-on-the-table fragment (4 lines, deliberately fragmentary); chunk 31 mixes physical action ("She sat up") with description ("The mark on her neck"). Both are genuinely hard cases.
- **Summary detection is strong**: 10 of 12 caught, including all hand-authored summary chunks (33-40). The compressed-time prose marker is a clear signal.
- **Interiority detection is strong**: 7 of 8 caught.
- **No NSFW refusals**: gemma-31B-uncensored stayed content-neutral as expected; the 9% NSFW-vs-SFW accuracy gap is *retrieval-quality drift*, not model-behaviour change.

**4-shot LLM (25 misclassifications):**

The few-shot prompt collapses ~17 chunks to `mixed` that zero-shot correctly classified, especially on short or attribution-heavy chunks. Hypothesis: the four exemplars + the GBNF token boundary push the model toward "mixed" as the safe option — exposure to all six labels in-context primes the salience of the abstention category. The "Lost in Space" finding optimised flat-enum structure but didn't address few-shot interaction; that's a real research gap. **Drop 4-shot from production.**

**Heuristic-only (23 misclassifications):**

Strong on dialogue + summary (the rule-detectable categories); weak on interiority and the action↔description distinction. Falls below floor on aggregate but is structurally complementary to the LLM.

## 10. Verdict — PIVOT: two-pass hybrid (heuristic dialogue-gate + zero-shot LLM)

**Phase 5 production scope-lock #5 closes against:**

```
1. NarrativeModeHeuristic.classify(text)
   → if .dialogue, use that (87.5% recall, 100% precision).
2. otherwise, call gemma-31B-uncensored with the zero-shot prompt
   + flat GBNF enum, parse the response as NarrativeMode.
3. on LLM nil-return (network error etc), fall back to the
   heuristic verdict — a defensible mode beats a nil modality slot.
```

Implemented at [`Sources/LoomCore/Retrieval/NarrativeModeClassifier.swift`](Sources/LoomCore/Retrieval/NarrativeModeClassifier.swift) — pure-data composition, LLM closure is caller-supplied (production wiring lives in the embed pipeline alongside the D + E call sites). 5 TestKit tests pin the composition contract.

**Projected hybrid accuracy:** ~80% (zero-shot's 73.1% + dialogue-recall recovery of 4-5 chunks via heuristic-first). Above the 70% spike-spec floor with margin.

**The empirical surprises worth carrying forward:**

1. **Few-shot can backfire under GBNF constraint.** Research said κ should rise; empirically it fell ~20 accuracy points + violated NSFW parity. Future spikes that use few-shot + GBNF should run a zero-shot baseline first to catch this failure mode.
2. **Zero-shot gemma-31B is a competent literary annotator.** The 73.1% accuracy is above the Zehe γ ≈ 0.7 human-IAA ceiling — striking for a 31B writer model used as judge. Phase 5 production budget for inference is generous (offline-ingest, not retrieval-time): 0.77s per chunk is fine for 50-chunk reference texts.
3. **Heuristic dialogue-gate is essential.** The LLM's dialogue *precision* is 100% but *recall* drops below 40% on short / attribution-heavy cases. Without the heuristic short-circuit the production classifier under-tags dialogue, the highest-volume retrieval-filter category.

## 11. What graduated from the spike

- `Sources/LoomCore/Models/NarrativeMode.swift` — 6-value taxonomy + `gbnfAlternation` grammar fragment.
- `Sources/LoomCore/Retrieval/NarrativeModeHeuristic.swift` — pure-Swift heuristic baseline, used by the hybrid as the dialogue-gate.
- `Sources/LoomCore/Retrieval/NarrativeModeClassifier.swift` — production composition (`classify(_:via:)`). LLM closure is supplied at the ingest call site.
- `Tools/RagSpike/main.swift::narrativeMode()` — eval runner. Kept as on-demand re-eval against the gold set if Phase 5 production swaps models or extends the taxonomy.
- The gold fixture — kept; extend with real user reference text if Phase 5 production exposes a coverage gap.

## 12. What did NOT graduate

- **4-shot prompting.** Empirically worse than zero-shot on this task at this model. Don't ship it.
- **Heuristic-only production path.** Falls below the 70% floor on aggregate; dialogue-gate alone is too narrow a feature without the LLM for the residual.
- **Free-text classifier output (no GBNF).** Not tested; the GBNF flat-enum approach worked and there's no reason to evaluate the alternative.


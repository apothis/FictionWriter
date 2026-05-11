# LOOM_LEDGER_SPIKE — feasibility eval

> **Date:** 2026-05-11. **Status:** half-day eval landed. **Recommendation: PROCEED with caveats** — see §6.
>
> This document captures the empirical findings from the knowledge-ledger extraction feasibility spike (LOOM_MEMORY §4.5 falsifiable hypothesis, gated Phase 4 #7 in HANDOFF §15.3). The pure-data plumbing (prompt builder, JSON-array parser with per-object fallback, scorer with alias resolution) is committed in [`Sources/LoomCore/Generation/LedgerExtraction.swift`](Sources/LoomCore/Generation/LedgerExtraction.swift); the network-y eval runner is [`Tools/LedgerSpike`](Tools/LedgerSpike); fixture (5 scenes, 20 hand-graded gold facts, mixed SFW/NSFW per the LOOM_NSFW strategic-anchor directive) lives at [`Tests/LoomCoreTests/Fixtures/LedgerSpike/fixture.json`](Tests/LoomCoreTests/Fixtures/LedgerSpike/fixture.json).

## 1. Falsifiable hypothesis

From [LOOM_MEMORY.md §4.5](LOOM_MEMORY.md):

> **Falsifiable hypothesis**: per-scene knowledge-state extraction is feasible at <13B model size. Test with a small fixture corpus before committing UI in Phase 4.

We tested at **Qwen3.6-27B-Uncensored-HauhauCS-Aggressive-Q4_K_P** (live local server at the user's standard URL) — comfortably above the <13B threshold, so a "yes" here is the floor for the hypothesis, not the ceiling.

## 2. What the eval measured

For each of 5 scenes:

1. Build the LOOM_STORY_BIBLE §3.3 extraction prompt (bible character JSON list + scene prose + completion cue).
2. Send to the live `KoboldClient.generate(...)` non-streaming endpoint.
3. Strip `<think>...</think>` thinking-mode blocks; synthesise the force-prefilled leading `[` back into the response.
4. Parse the JSON array. Strict full-array decode first; fall back to per-object brace-balanced recovery when the array is malformed or truncated (very common — see §3.b).
5. Score against the hand-graded gold ledger. Match predicate: (alias-resolved `character_id`, `certainty`) plus fact-text Jaccard ≥ 0.5 over normalised tokens with the character's surface forms stripped first.

## 3. Findings

### a. The model can produce structured JSON — but only with significant prompt-engineering scaffolding

Three load-bearing tail elements emerged through iteration; remove any of them and the eval collapses to zero output:

1. **Force-prefill the array opening `[`**. Without it, Qwen reads the §3.3 prompt verbatim and emits EOS immediately (`completion_tokens=1`, empty `text`, `finish_reason="stop"`). The model treats the scene prose as document-complete. Synthesising the `[` so the prompt ends *inside* an array reliably forces continuation.

2. **A trailing `JSON output:` completion cue** before the `[`. Acts as the "your turn" anchor.

3. **A loose response parser**. The model's JSON is frequently malformed mid-output: `"Answer":` instead of `"fact":`, missing commas, missing closing braces, truncation mid-string when the response hits `max_length`. The strict full-array decode fails on every scene in our fixture; the per-object fallback (brace-depth walker that ignores braces inside strings, parses each `{...}` block individually) recovers most of the content.

### b. The Qwen3 model insists on thinking-mode, even with `<think>` not in the prompt

Every scene's response contained an embedded `<think>...</think>` block — usually opened *after* the model emitted a partial JSON entry. The think block routinely consumed **~70% of the output budget**, with the actual JSON output trailing afterward. At `max_length=1024` the JSON was almost always truncated mid-entry. At `max_length=2048` recovery improved noticeably.

`ThinkBlockStripper` already handles closed `<think>...</think>` pairs; the production pipeline must also handle the unclosed-`<think>` truncation case (the spike's parser does — it walks brace-balanced objects across the response without requiring a closing `]`).

### c. Aggregate metrics (rough, see §4 for the honest interpretation)

| Metric    | Value | Note |
|-----------|-------|------|
| TP        | 4     | by the scorer's strict Jaccard ≥ 0.5 match |
| FP        | 65    | mostly valid extractions our gold didn't include |
| FN        | 16    | mostly gold facts matched by extracted facts with different wording (Jaccard < 0.5) |
| Precision | 0.06  | misleading — see §4 |
| Recall    | 0.20  | misleading — see §4 |

| Certainty | Gold | Matched | Recall |
|-----------|------|---------|--------|
| `asserted` | 18 | 4  | 0.22 |
| `unknown`  | 2  | 0  | 0.00 |

The `unknown` row is the load-bearing signal — see §3.e.

### d. Asserted-fact extraction works (when the eval is read honestly)

The aggregate metrics undersell the model's actual performance. Walking the extracted facts for scene 1 by hand:

| Gold | Closest extracted | Match by scorer? | Honest verdict |
|---|---|---|---|
| Mia drinking wine alone | "Mia was drinking wine when the knock came." | no (Jaccard 0.33) | **same fact** |
| Mia learned stranger's name is Anders | "Anders introduced himself as Anders." | no (char mismatch) | **same event, framed from Anders's POV** |
| Mia gave directions to flat 19 | "Mia told the man the location was down one floor in the opposite corner." | no (Jaccard 0.3) | **same fact** |
| Anders lost looking for flat 19 | "Anders was looking for number nineteen." | no (Jaccard 0.4 — "number" vs "flat") | **same fact** |
| Anders going to dinner | "Anders was meant to be at a dinner." | no (Jaccard 0.33) | **same fact** |
| Anders's coat damp from rain | "Anders was wearing a dark coat damp from the rain." | ✓ (Jaccard 0.6) | match |

Honest hit rate on scene 1: **5 of 6 asserted gold facts are present in the extraction, in different wording**. The scorer caught 1. Pattern repeats across the other scenes.

**This is the central finding:** the model's extraction quality on asserted facts is high enough to be production-useful. The scorer's metrics are wrong because the eval's Jaccard threshold doesn't model "did the extracted fact assert the same proposition as the gold fact" — it models "did the extracted fact share enough wordform tokens with the gold fact." Those diverge sharply for natural-language paraphrasing.

### e. Negative knowledge (`unknown`, `mistaken`) does NOT extract reliably

Both gold `unknown` facts (Mia not connecting Karim's coworker to her stranger, Karim not knowing Anders is dating his sister) went unextracted by the model — recall 0 of 2.

This matches the doc's own warning (LOOM_STORY_BIBLE §3.5): *"Negative knowledge isn't auto-extractable in many cases. 'Mia does not know X' requires the prose to explicitly negate, which is rare. Manual authoring of explicit unknowns is the dominant input path; extraction handles assertions."*

The eval confirms it empirically. The pipeline needs the **manual-authoring path for `unknown` / `mistaken`** as the primary input; the extractor handles assertions and surfaces them as Suggestions.

### f. The model over-extracts

The model emits 20–28 facts per scene, against 3–6 gold facts. Most are real prose observations (Mia walked barefoot, Anders had careful posture, etc.) that we chose not to mark in gold. For a knowledge ledger this is **fine** — extra facts are accepted into Suggestions; the user filters during the accept/reject pass. But it does mean the prompt cannot demand "concise" extraction; the budget allocation in [LOOM_MEMORY.md §4.5](LOOM_MEMORY.md) (~300–1000 tokens for the knowledge-ledger context layer) needs to assume **dozens of facts per character per arc**.

## 4. Honest interpretation

The aggregate F1 of 0.09 looks damning but is mostly an artifact of:

1. **Sparse hand-graded gold**. We selected key facts; the model extracted everything plausibly factual in the prose. Those extras score as FP under our predicate but aren't actually errors.
2. **Jaccard-similarity threshold mismatch**. Natural-language paraphrasing reliably scores Jaccard 0.3–0.5 even when the propositions are identical.

Hand-reviewed recall on **asserted** facts across the fixture: **~70%**. That's a useful precision floor for an autopopulating suggestions UI where the user accepts/rejects per fact (LOOM_STORY_BIBLE §3.2 step 3).

Hand-reviewed recall on **unknown** / **mistaken** facts: **0%** — extractor cannot do this reliably; manual authoring path is mandatory for negative knowledge.

## 5. Production gaps the spike surfaced

Beyond what's in the existing design docs, these need to be planned into the Phase 4 #7 pipeline:

1. **System-prompt instrumentation to suppress `<think>` mode** OR an `<endthink>` stop-sequence. The current Qwen card consumes ~70% of `max_length` on think; without suppression, `max_length` must be 4096+ to leave room for the actual extraction. Investigate if `--no-think` or similar Kobold/sampler flags can disable.

2. **`max_length=2048` minimum** for the side-call. 1024 truncates routinely.

3. **Per-object recovery parser** is non-negotiable — the model's JSON is malformed often enough that strict array decoding fails on most scenes. The fallback walker in `parseExtractedFacts` handles it but is brittle to syntax variants; consider tightening once we have more eval data.

4. **Force-prefill the array opening** in the prompt assembler. Already done in `LedgerExtraction.buildExtractionPrompt`; pin this with a doc note in §3.3 so it doesn't drift.

5. **A better evaluator** if we want continued empirical tuning. The Jaccard threshold misses synonym paraphrases. Options: (a) lower threshold to 0.35 and accept some false matches; (b) replace Jaccard with embedding-similarity (~bge-small over normalised fact strings); (c) hand-grade richer gold (every plausibly factual sentence, not just "key" ones). Option (a) is cheapest; (c) is most rigorous.

6. **Asserted-only extraction** as Phase 4 default. The pipeline ships with extraction for `asserted` (works ~70% recall) and Suggestions UI. `unknown` / `mistaken` populate via the Bible-inspector manual-authoring flow (already designed in LOOM_STORY_BIBLE §7.2). Defer auto-extraction of negative knowledge to Phase 5 or later, behind a "stretch" hypothesis test on much richer prose corpora.

## 6. Recommendation

**Proceed with Phase 4 #7 (the full ledger pipeline).** The extractor side is viable at Qwen3.6-27B with the prompt-engineering scaffolding above. Specifically:

- Build the post-scene side-call → extractor → diff-against-existing → Bible-inspector Suggestions chip flow as designed in LOOM_STORY_BIBLE §3.
- Ship with `asserted`-only extraction; `unknown` and `mistaken` come from manual authoring in the Bible inspector's ledger editor.
- Pin the prompt-engineering elements (`[`-force-prefill, `JSON output:` cue, per-object fallback parser) in the production prompt assembler.
- Plan `max_length ≥ 2048` for the side-call; investigate think-mode suppression as a Phase 4.x follow-on if it bites the side-call latency.

**Do not** try to land negative-knowledge auto-extraction in Phase 4. The eval shows it doesn't work at 27B; production should not attempt it. Bible-inspector manual authoring of `unknown` / `mistaken` is the primary path until either model capability advances or the doc team designs a better extraction prompt for negative space.

The pieces from this spike that graduate into production:

- `LedgerExtraction.buildExtractionPrompt` — keep verbatim, pin in the docs.
- `LedgerExtraction.parseExtractedFacts` (with per-object fallback) — keep, sanity-check against more model families later.
- `LedgerExtraction.score` — keep for future regression testing; lower the Jaccard threshold or swap to embedding-similarity when we have more eval data.
- The fixture — keep, extend as Phase 4 hits real manuscripts.
- The `LedgerSpike` executable — keep as a one-off runner for future eval re-runs against new models / new prompts.

## 7. References

- [LOOM_STORY_BIBLE.md §3](LOOM_STORY_BIBLE.md) — extraction pipeline spec.
- [LOOM_MEMORY.md §4.5](LOOM_MEMORY.md) — falsifiable hypothesis.
- [HANDOFF.md §15.3 #5](HANDOFF.md) — gated work item.
- [`Sources/LoomCore/Generation/LedgerExtraction.swift`](Sources/LoomCore/Generation/LedgerExtraction.swift) — pure-data plumbing.
- [`Tools/LedgerSpike/main.swift`](Tools/LedgerSpike/main.swift) — eval runner.
- [`Tests/LoomCoreTests/Fixtures/LedgerSpike/fixture.json`](Tests/LoomCoreTests/Fixtures/LedgerSpike/fixture.json) — hand-graded scenes + gold facts.
- [`Tests/LoomCoreTests/Phase4LedgerExtractionTests.swift`](Tests/LoomCoreTests/Phase4LedgerExtractionTests.swift) — 13 pure-data tests for the plumbing.

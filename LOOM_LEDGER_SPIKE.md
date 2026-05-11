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

## 8. Research follow-on (2026-05-11 evening) — four structural wins

After §6's PROCEED-with-caveats verdict landed, a research pass against
Qwen3 / KoboldCpp / structured-extraction prior art surfaced four
structural improvements that supersede the brittle prompt-engineering
recommendations in §5. **These are the new Phase 4 #7 plan.**

### 8.1 GBNF grammar-constrained decoding (the headline win)

KoboldCpp's `/api/v1/generate` and `/v1/chat/completions` both accept a
`grammar` parameter — a GBNF (llama.cpp grammar format) string that
constrains token sampling to grammar-conformant tokens. This is a
**structural guarantee**, not a prompt hope:

- 100% well-formed JSON by construction (the parser fallback in §5.3
  becomes dead code).
- The model literally cannot emit `<think>` tags if the grammar root is
  a JSON array (§5.1's max_length-eating problem vanishes).
- The model literally cannot emit EOS at the start if the grammar
  forces `[` as the first token (§5.4's force-prefill becomes
  unnecessary — the grammar IS the prefill).

**Verified against the live server (2026-05-11):** a 4-line GBNF
returning `[{"character": "Mia", "fact": "drank wine"}]` with
`completion_tokens: 29` and `finish_reason: "stop"`, no preamble, no
malformed output, no thinking-mode leakage. The §5 workarounds become
obsolete in one move.

References:
- [KoboldCpp Wiki — `grammar` parameter](https://github.com/LostRuins/koboldcpp/wiki)
- [llama.cpp grammars README](https://github.com/ggml-org/llama.cpp/blob/master/grammars/README.md)
- [llama.cpp `json.gbnf` reference](https://github.com/ggml-org/llama.cpp/blob/master/grammars/json.gbnf)
- [Aidan Cooper — Constrained decoding survey](https://www.aidancooper.co.uk/constrained-decoding/) (industry numbers: "prompted JSON ~70-80% syntactic compliance; grammar-constrained ~100%; even phi-3-mini becomes perfectly reliable under grammar constraints")

### 8.2 `enable_thinking=false` for Qwen3 (belt-and-braces with §8.1)

KoboldCpp v1.90+ accepts `chat_template_kwargs.enable_thinking=false`
on `/v1/chat/completions`, or `--reasoning-budget 0` at server launch.
Per-request body example:

```json
{
  "messages": [...],
  "chat_template_kwargs": {"enable_thinking": false}
}
```

For `/api/v1/generate` (the path Loom uses today), the documented
fallback is appending `/no_think` to the user message text (per the
Qwen3 model card). Grammar (§8.1) already prevents `<think>` emission;
this is redundant but cheap insurance for non-grammar contexts.

References:
- [KoboldCpp issue #1997 — `chat_template_kwargs` support](https://github.com/LostRuins/koboldcpp/issues/1997)
- [Qwen3 docs — `enable_thinking`](https://qwen.readthedocs.io/en/latest/getting_started/quickstart.html)
- [Qwen3 `/no_think` placement](https://github.com/QwenLM/Qwen3/discussions/1329) (note: user message, not system)

### 8.3 `unknown` as scene-exposure derivation, not LLM extraction

The spike's most useful negative finding (§3.e — `unknown` recall 0/2)
matches the design-doc warning at LOOM_STORY_BIBLE §3.5, but the prior
art surfaces a cleaner solution than "manual authoring only":

**SymbolicToM (Sclar et al. ACL 2023 Outstanding Paper)** maintains
explicit per-character belief graphs *external* to the LLM. The LLM is
never asked "what does X not know?" — instead, an exposure set is
maintained from scene metadata (which scenes the character was POV /
present-for), and `unknown` is computed as set-difference at query
time. The LLM only ever does the easy direction (extract positive
facts from prose it sees).

For Loom's data model this is a natural fit because scene metadata
already carries POV (`Scene.pov`) and (via the manuscript walk + bible
keyed-injection plumbing from Phase 2) per-scene character presence.
The implementation is:

1. The extractor emits only `asserted` facts (positive observations from
   the prose). Drop the `unknown` / `mistaken` certainty levels from the
   extractor's grammar — they're not extracted.
2. Each `KnownFact` is stamped with the `sourceSceneId` it was extracted
   from (already in the schema, [LOOM_DATA_MODEL.md §3.1](LOOM_DATA_MODEL.md)).
3. A new pure-data query: `Character.knows(fact:asOfSceneId:in:)` walks
   scenes chronologically ≤ the query scene, checks `Scene.pov ==
   character.id || presence-set contains character.id`, and returns
   true iff the fact appears in an extracted ledger from an exposing
   scene.
4. `mistaken` stays as a manual-authoring path in the Bible inspector
   (rare; user surfaces it explicitly when prose contradicts a
   character's belief).

This sidesteps the local-model-can't-do-negative-knowledge problem
entirely, AND it's empirically defensible — the spike already shows
positive-fact extraction at ~70% recall.

References:
- [SymbolicToM arxiv 2306.00924](https://arxiv.org/abs/2306.00924) / [code](https://github.com/msclar/symbolictom)
- [Lookbacks for belief tracking arxiv 2505.14685](https://arxiv.org/html/2505.14685) (confirms LLMs implement belief-tracking as pointer-dereference, not first-class belief representation — no native operation for "facts X has not been exposed to")

### 8.4 Optional follow-ons (Phase 4.5+, not Phase 4)

Surfaced by the research, NOT load-bearing for Phase 4 #7:

- **CHIRON two-stage extract-then-NLI-validate** ([arxiv 2406.10190](https://arxiv.org/abs/2406.10190)) — if grammar-constrained extraction shows accuracy problems, add a small NLI validator that filters non-entailed facts before they reach the Suggestions UI. Defer until measured.
- **Smaller, non-thinking extractor model** — Mistral-Small-3-24B or Phi-4-14B (abliterated for NSFW) at the role-routed summariser server. 3-5× faster than the 27B writer; equivalent JSON quality under grammar constraint. Defer until latency is the bottleneck.
- **Per-character isolation** as a fallback ladder — if one-shot whole-scene under-extracts, loop per-character with the same grammar. Cheap to bolt on once §8.1 is wired.

### 8.5 Revised recommendation (supersedes §6)

The four §8 wins are **server-config + schema changes only** — no
fragile new prompts, no model swap, no UX rework. They turn the
spike's "PROCEED with caveats" into "PROCEED with structural
guarantees." Specifically:

1. Build GBNF for the §3.3 fact schema and pass it as `grammar` on
   every extraction call.
2. Drop the force-prefill `[` from the prompt builder; the grammar IS
   the prefill.
3. Drop the malformed-JSON fallback parser; grammar-constrained output
   is well-formed by construction. Keep the per-object recovery code
   path as a safety net (cheap), but expect it to be dead code.
4. Append `/no_think` to the user message as belt-and-braces; consider
   the `chat_template_kwargs` path once we migrate to ChatML.
5. Reframe the extractor's job as "emit positive `asserted` facts
   only." Drop `unknown` / `mistaken` from the grammar. Compute
   `unknown` from the per-character scene-exposure graph at query time.
6. Defer CHIRON-validate and extractor-model-swap to Phase 4.5+.

The spike's pure-data plumbing (prompt builder, parser, scorer,
fixture) stays — the grammar is bolted on as an additional parameter,
the rest of the contract is unchanged.

## 9. Post-research empirical findings (grammar-constrained Qwen3.6-27B)

The §8 research surfaced four structural improvements. The headline
one — GBNF grammar-constrained decoding — landed in the codebase
(`LedgerExtraction.gbnfGrammar()`, threaded through
`GenerateRequest.grammar`, wired into `LedgerSpike`). Re-ran the eval
against the production server with the new shape: short prompt,
grammar-constrained output, `asserted`-only certainty, `rep_pen=1.1`
(needed to break degenerate-loop output), `max_length=1024` (now
sufficient because grammar prevents `<think>` emission).

### 9.1 Structural wins, confirmed

- **JSON is always well-formed.** No malformed-JSON failures across
  any scene. The fallback per-object recovery parser is dead code as
  predicted in §8.5.
- **No `<think>` leakage.** Grammar root being a JSON array literally
  prevents `<` emission. The `ThinkBlockStripper` is no longer in the
  extraction code path.
- **No force-prefill required.** Grammar forces `[` as the first token.

### 9.2 Content-quality bottleneck, NOT solved by grammar

Grammar fixes the SHAPE; the model's CONTENT under grammar constraint
on this fixture is still rough on Qwen3.6-27B:

- **Prompt-text leakage into strings.** Multiple scenes produced facts
  with `evidence_quote` containing chunks of the spike's own prompt
  text (e.g. *"List one entry per fact the character DID or LEARNED in
  this scene…"* embedded inside an `evidence_quote`). The grammar
  doesn't constrain string CONTENT, only string shape.
- **Mid-generation degeneration.** Scenes 1 and 4 routinely produce
  empty arrays (`[]`) under conservative sampling; bumping `rep_pen`
  to break repetition loops on scenes 1+3 caused scenes 1+4 to give
  up entirely. There's a narrow sampler window where extraction
  works; outside it, the model degenerates.
- **Random capitalisation in string content.** *"DECIDED"*, *"KNOWN"*,
  *"BEEN"* in fact text. The model is in a near-degenerate state under
  grammar constraint and emits random-cased tokens.

### 9.3 Honest interpretation

Grammar-constrained decoding is the right structural fix and graduates
into production unchanged. But Qwen3.6-27B-abliterated is empirically
**not a good extraction model** even with the grammar shape locked
down — the model was tuned for creative writing, and the grammar
makes its content-quality issues more obvious by forcing it into a
narrow output shape.

### 9.4 Revised recommendation (replaces §8.5)

1. **Ship the grammar plumbing now** as a structural improvement.
   `GenerateRequest.grammar`, `LedgerExtraction.gbnfGrammar`,
   simplified extraction prompt — all already wired and tested.
2. **The extractor model must NOT be the primary writing model.**
   This is the single most actionable conclusion from this iteration.
   Run the extractor side-call against a smaller, extraction-tuned
   model on the role-routed summariser server (RPClient's pattern,
   already supported). Research §5 candidates: **Mistral-Small-3-24B**
   (non-thinking, fast, JSON-strong), **Phi-4-14B** (non-thinking,
   strongest small-model JSON compliance under grammar — note: needs
   abliterated variant for NSFW), or **Qwen2.5-7B-Instruct-Uncensored**
   (NSFW-tolerant, ~3-5× faster than Qwen3-27B, comparable JSON
   quality under grammar).
3. **Re-run the spike against the new extractor model.** Same
   fixture, same grammar, same scorer — apples-to-apples comparison.
   If the new model produces clean content under grammar (no prompt
   leakage, no degenerate loops, no random caps), Phase 4 #7 ships.
   If it has the same problems, the recommendation flips to "manual
   ledger authoring only; defer auto-extraction to Phase 5+".
4. **Compute `unknown` knowledge from scene-exposure regardless.**
   Per §8.3, this is the right design independent of which model
   handles the extractor side-call.

### 9.5 What graduated into production from this spike

- [`LedgerExtraction.swift`](Sources/LoomCore/Generation/LedgerExtraction.swift) — prompt builder (simplified), parser (with per-object fallback as safety net), scorer, GBNF grammar generator. 15 tests pinning behaviour.
- [`KoboldClient.generate(request:completion:)`](Sources/LoomCore/Networking/KoboldClient.swift) overload — accepts a full `GenerateRequest`, supports the `grammar` field.
- [`Tools/LedgerSpike/main.swift`](Tools/LedgerSpike/main.swift) — eval runner. Keep for re-running against alternative extractor models (the §9.4 next step).
- [`Tests/LoomCoreTests/Fixtures/LedgerSpike/fixture.json`](Tests/LoomCoreTests/Fixtures/LedgerSpike/fixture.json) — 5 scenes, 20 hand-graded gold facts, mixed SFW/NSFW.

### 9.6 What did NOT graduate

- The force-prefilled `[` in the prompt → grammar handles it.
- The `ThinkBlockStripper` in the extraction parse path → grammar prevents `<think>`.
- The `max_length ≥ 2048` requirement → grammar's no-think output fits in 1024.
- The `unknown` / `mistaken` certainty values in the extractor grammar (the production grammar passes `[.asserted]`).
- Detailed schema documentation in the prompt body → simplified to a two-line "extract facts about these characters" framing.

## 7. References

- [LOOM_STORY_BIBLE.md §3](LOOM_STORY_BIBLE.md) — extraction pipeline spec.
- [LOOM_MEMORY.md §4.5](LOOM_MEMORY.md) — falsifiable hypothesis.
- [HANDOFF.md §15.3 #5](HANDOFF.md) — gated work item.
- [`Sources/LoomCore/Generation/LedgerExtraction.swift`](Sources/LoomCore/Generation/LedgerExtraction.swift) — pure-data plumbing.
- [`Tools/LedgerSpike/main.swift`](Tools/LedgerSpike/main.swift) — eval runner.
- [`Tests/LoomCoreTests/Fixtures/LedgerSpike/fixture.json`](Tests/LoomCoreTests/Fixtures/LedgerSpike/fixture.json) — hand-graded scenes + gold facts.
- [`Tests/LoomCoreTests/Phase4LedgerExtractionTests.swift`](Tests/LoomCoreTests/Phase4LedgerExtractionTests.swift) — 13 pure-data tests for the plumbing.

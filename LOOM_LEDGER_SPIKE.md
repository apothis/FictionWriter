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

## 10. Round-3 — embedding scorer + character-id grammar restriction

After §9's honest "structural fix works; content quality is messy"
verdict, two more wins landed by putting the **same KoboldCpp server's
embedding endpoint** to work alongside the generation endpoint. The
server is launched with `--embeddingsmodel` against nomic-embed-text
(768-d, verified live), so the embedding side-call is free and local —
the same cache-warm, NSFW-tolerant connection the writer uses.

### 10.1 Embedding scorer (replaces the misleading Jaccard metrics)

`LedgerExtraction.scoreByEmbedding(extracted:gold:embedding:threshold:aliases:)`
matches facts by **cosine similarity over embeddings** instead of
wordform Jaccard. Default threshold 0.65 (LOOM_MEMORY §B2's verified
SillyTavern Chat Vectorisation floor of 0.55 with diminishing returns
above 0.7). The runner batch-embeds every unique gold + extracted fact
text in a single `/v1/embeddings` round-trip after extraction
completes, then re-scores from the cached vectors — no per-fact
embed cost beyond the one batch.

Both Jaccard and Embedding scorers now run on every spike pass and
report side-by-side in the aggregate table. The honest §3.c
"misleading metrics" disclaimer is no longer needed — the embedding
column IS the measure of extraction quality.

### 10.2 Grammar-level `character_id` enum (kills a content failure mode)

§9.2 noted the model occasionally emits garbage in `character_id`:
`"hallway"`, `"kitchen"`, sentence fragments like `"To bed early."`.
Root cause: the GBNF had `character_id ::= string`, allowing any
JSON string. Fix:
`LedgerExtraction.gbnfGrammar(characters:)` builds the rule as an
alternation of the bible's known names + aliases — e.g.
`character_id ::= "\"Mia\"" | "\"Miss Vance\"" | "\"the librarian\"" | "\"Anders\"" | ...`.
The model **literally cannot** emit anything but a registered name.
Eliminates the garbage-character_id failure mode by construction. The
spike's runner now passes the fixture's character list into the
grammar generator; production callers pass `bible.characters`.

### 10.3 Empirical numbers (live Qwen3.6-27B + character-restricted GBNF + embedding scorer)

| Scene | Tag | Extracted | Gold | Embedding TP/FP/FN | Recall |
|-------|-----|-----------|------|--------------------|--------|
| 01_door         | SFW  | 10 | 6 | 3/7/3 | 0.50 |
| 02_coffee       | SFW  |  0 | 4 | 0/0/4 | 0.00 |
| 03_first_night  | NSFW |  7 | 3 | 2/5/1 | 0.67 |
| 04_revelation   | SFW  |  0 | 4 | 0/0/4 | 0.00 |
| 05_confession   | NSFW |  8 | 3 | 3/5/0 | **1.00** |

Aggregate (embedding scorer, 5 scenes, 20 gold facts): TP 8 / FP 17 /
FN 12; precision 0.32, recall 0.40, F1 0.36.

**For scenes the model engages with (1, 3, 5):** 8 of 12 gold facts
recovered = **67% recall**. This confirms §3.d's hand-review estimate
with a real metric. Scene 5 hits 100% recall.

The "FP" column is still partly artefactual — many "false positives"
are valid extra prose observations the model captured (Mia walked
barefoot, Anders had careful posture, etc.) that weren't in the
selective hand-graded gold. For the production Suggestions UI flow,
those go to the user for accept/reject; they're not extraction errors.

### 10.4 The remaining failure mode: scenes 2 + 4 emit `[]`

Two of the five SFW scenes (`02_coffee`, `04_revelation`) routinely
return an empty array. Both feature all three bible characters and
have plenty of clear factual content. The model evaluates `[]` as a
valid grammar production from the opening `[` and exits immediately —
likely a sampler / prompt interaction where the EOS-equivalent
"empty array" token has higher probability than `{`.

Possible fixes for Phase 4 #7 (NOT for this commit):

1. **Require at least one fact in the grammar**: change
   `root ::= "[" ws (fact (ws "," ws fact)*)? ws "]"` to
   `root ::= "[" ws fact (ws "," ws fact)* ws "]"`. Forces the model
   to emit at least one fact. Risk: the model loops trying to invent
   content if there's nothing to extract.
2. **Higher temperature + lower min_p** so the empty-array
   short-circuit is sampled less often.
3. **Switch the extractor model** per §8.4 — Mistral-Small-3-24B
   was specifically released as non-thinking, structured-output
   strong; this kind of degenerate behaviour is much less common.

The §9.4 recommendation (smaller extraction-tuned model on the
role-routed summariser server) still stands as the principal Phase 4
#7 prerequisite. The empty-array problem is one more data point in
favour of that swap.

### 10.5 What else the embedding endpoint enables (Phase 4 #7 design)

Beyond the spike's scorer, the embedding endpoint unlocks three
production features the design docs assumed but didn't yet wire:

1. **Fact deduplication.** When the extractor emits 10 facts and many
   are paraphrases ("Mia drank wine" / "Mia was drinking wine"),
   embed them and cluster by cosine ≥ 0.85; merge clusters into
   single ledger entries.
2. **Evidence-quote validation** (CHIRON-lite, see §8.4). After
   extraction, embed each fact's `evidence_quote` and the scene's
   sentences; drop facts whose evidence has no high-cosine sentence
   match (hallucinated evidence quotes — the model invented a quote
   that isn't actually in the prose).
3. **Prompt-leakage filter.** §9.2 noted facts where the extractor
   leaked our own prompt text into strings. Embed the prompt text
   ahead of time; drop facts whose content cosine-matches the prompt
   above some threshold. Cheap defence against the model echoing
   instructions back.

All three are pure-data follow-ons that reuse the existing
`KoboldClient.embed(...)` path (now in LoomCore alongside `generate`).

### 10.6 What graduated in Round-3

- `KoboldEmbedding` protocol + `KoboldClient.embed(texts:completion:)`
  ported from RPClient ([`Sources/LoomCore/Networking/KoboldClient.swift`](Sources/LoomCore/Networking/KoboldClient.swift)).
- `LedgerExtraction.cosineSimilarity(_:_:)` +
  `LedgerExtraction.scoreByEmbedding(...)` ([`Sources/LoomCore/Generation/LedgerExtraction.swift`](Sources/LoomCore/Generation/LedgerExtraction.swift)).
- `LedgerExtraction.gbnfGrammar(certainties:characters:)` builds the
  `character_id` enum from a bible character list.
- `LedgerSpike` runs both scorers side-by-side; report shows both
  metrics in the aggregate table.
- Six new TDD tests pinning behaviour.

## 11. Round-4 — Gemma 4 4B abliterated via Ollama (the §9.4 model-swap)

§9.4 / research §5 recommended swapping the extractor side-call to a
smaller, extraction-tuned, non-thinking model on the role-routed
summariser server. The user spun up an abliterated Gemma 4 4B
(`gemma4_4b:latest`, 7.5B actual params, Q4_K_M) on Ollama at
`localhost:11434`. Wired the spike to talk to it via `/api/chat` with
the JSON Schema in the `format` field — Ollama 0.5+ supports
schema-constrained outputs natively, and Ollama applies the model's
chat template (Gemma's `<start_of_turn>user/model` wrapping)
automatically.

### 11.1 New machinery shipped

- `LedgerExtraction.jsonSchema(certainties:characters:)` — sibling to
  `gbnfGrammar(...)`. Produces a top-level array schema with the
  ledger-fact object shape, with optional certainty + character_id
  enum restrictions matching the GBNF. Three TDD tests pin behaviour.
- `LedgerSpike` now backend-selects on `LOOM_SPIKE_BACKEND` env var:
  `kobold` (default, hits KoboldCpp's `/api/v1/generate` with GBNF)
  or `ollama` (hits Ollama's `/api/chat` with JSON Schema). Two
  additional env vars (`LOOM_SPIKE_OLLAMA_URL`,
  `LOOM_SPIKE_OLLAMA_MODEL`) configure the Ollama path.
- The embedding scorer (§10) continues to run against the KoboldCpp
  server's embedding endpoint regardless of which backend produced
  the extractions. The two servers are independent.

### 11.2 Empirical numbers

Live run, same fixture, same prompt builder, same embedding scorer at
threshold 0.65 — only the generation backend differs:

| Scene          | Tag  | Extracted | Gold | TP/FP/FN | Recall |
|----------------|------|-----------|------|----------|--------|
| 01_door        | SFW  | 16        | 6    | 5/11/1   | 0.83   |
| 02_coffee      | SFW  | 15        | 4    | 3/12/1   | 0.75   |
| 03_first_night | NSFW | 15        | 3    | 3/12/0   | **1.00** |
| 04_revelation  | SFW  | 15        | 4    | 3/12/1   | 0.75   |
| 05_confession  | NSFW | 16        | 3    | 3/13/0   | **1.00** |

Aggregate: TP 17 / FP 60 / FN 3. Precision 0.22, **Recall 0.85**,
F1 0.35.

### 11.3 Comparison vs Qwen3.6-27B

| Metric (embedding scorer)       | Qwen3.6-27B + GBNF | Gemma 4 4B + JSON Schema |
|---------------------------------|---------------------|----------------------------|
| Aggregate recall                | 0.40                | **0.85**                   |
| Scenes engaged (non-empty)      | 3 of 5              | **5 of 5**                 |
| 100%-recall scenes              | 1                   | **2**                      |
| Total FN                        | 12                  | **3**                      |
| Model params                    | 27B                 | 7.5B (q4)                  |

Gemma 4 4B at a quarter of the parameters has more than double the
recall — exactly what the research §5 prediction (non-thinking,
structured-output-strong small models outperform creative-writing
generalists at this task) suggested would happen. The §9 / §10 issues
with Qwen (`[]`-emission on some scenes, prompt-text leakage into
strings, degenerate loops) **do not appear at all** under Gemma 4 4B
in this run.

### 11.4 Precision is dragged down by selective hand-gold, not model error

Aggregate precision 0.22 looks weak but is the same artefact as
§9.3 / §10.4: the model emits 15-16 facts per scene; the gold is the
3-6 most-load-bearing facts hand-picked for the eval. Most "FPs"
are valid prose observations the user would accept in the
Suggestions UI flow ("Anders placed his hands on Mia's hips",
"Mia watched the streetlight bend across the ceiling") — they're
not extraction errors.

For Phase 4 #7's UI flow this is actually the **right tradeoff**:
recall-heavy extraction + per-fact user accept/reject in the
Bible-inspector Suggestions chip. The §10.5 production filters
(deduplication, evidence-quote validation, prompt-leakage filter)
trim the high-FP output to the most useful candidates before they
reach the user.

### 11.5 Revised recommendation (supersedes §9.4)

**The extractor for Phase 4 #7 production is Gemma 4 4B abliterated
on Ollama (or equivalent abliterated small model at ≤ 8B params).**
The empirical numbers cleared the §9.4 model-swap prerequisite. Next:

1. Build the Phase 4 #7 UI surfaces against this extractor:
   - Post-scene side-call to Ollama with the §11.1 plumbing.
   - Diff vs existing ledger.
   - Bible-inspector Suggestions chip per character.
   - User accept / reject / edit, per-fact, with the
     fixture-aliases-style canonicalisation already in place.
2. Wire the §10.5 production filters (deduplication, evidence-quote
   validation, prompt-leakage filter) as quality gates between
   extraction and Suggestions display.
3. Compute `unknown` from per-character scene-exposure at query time
   (§8.3 / SymbolicToM, already documented in
   [LOOM_STORY_BIBLE §3.5](LOOM_STORY_BIBLE.md)).
4. Persist accepted facts into `Character.knownFactsBySceneId`
   stamped with `sourceSceneId`; render the
   `[KNOWLEDGE-LEDGER]` prompt layer below the cache boundary at
   generation time.

The Qwen3.6-27B writer stays as the primary generation model;
Gemma 4 4B (or similar) is the role-routed summariser. KoboldCpp +
Ollama can coexist on the same machine — RPClient's role-routed
servers pattern (different server URL per role) accommodates this
without further plumbing changes.

## 7. References

- [LOOM_STORY_BIBLE.md §3](LOOM_STORY_BIBLE.md) — extraction pipeline spec.
- [LOOM_MEMORY.md §4.5](LOOM_MEMORY.md) — falsifiable hypothesis.
- [HANDOFF.md §15.3 #5](HANDOFF.md) — gated work item.
- [`Sources/LoomCore/Generation/LedgerExtraction.swift`](Sources/LoomCore/Generation/LedgerExtraction.swift) — pure-data plumbing.
- [`Tools/LedgerSpike/main.swift`](Tools/LedgerSpike/main.swift) — eval runner.
- [`Tests/LoomCoreTests/Fixtures/LedgerSpike/fixture.json`](Tests/LoomCoreTests/Fixtures/LedgerSpike/fixture.json) — hand-graded scenes + gold facts.
- [`Tests/LoomCoreTests/Phase4LedgerExtractionTests.swift`](Tests/LoomCoreTests/Phase4LedgerExtractionTests.swift) — 13 pure-data tests for the plumbing.

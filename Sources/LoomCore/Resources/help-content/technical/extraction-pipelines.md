# Extraction pipelines

Loom has five "extract structured data from prose" passes: knowledge ledger, entity discovery, relationship discovery, continuity audit, and scene-template beat extraction. They were built across Phases 4, 7, 9, and 10, but they converged on a shared set of patterns. This page is the synthesis — **read it before building any new extraction pass.** The per-pipeline detail lives in the spike docs cited at the end.

## The transport split — GBNF vs. unconstrained

The single most important decision is how you constrain the model's output, and it differs by backend:

| Backend | Constraint | Why |
|---|---|---|
| **KoboldCpp** (writer model) | **GBNF grammar** | llama.cpp's grammar sampler is a reliable structural constraint. `LedgerExtraction.gbnfGrammar(certainties:characters:)` builds one. Use this when the writer model does the extraction. |
| **Ollama** (small gemma extractor) | **Unconstrained — do NOT use the `format` JSON-schema** | The Ollama `format` schema flakes ~50% on `gemma4_2b` (degenerate buffer → empty `message.content`; HANDOFF §15.19). Run unconstrained, pin the field names in the prompt, prefer JSONL or delimited lines, tolerant-parse, re-roll on degenerate output. |

Most of Loom's extraction runs Ollama-side (the extractor role), so **the unconstrained + tolerant-parse pattern is the default.** The `format`-schema trap is the single biggest footgun — it looks like it should work, passes a smoke test, then silently empties out half the time under load.

## The shared pattern (Ollama-side)

Every Ollama extractor follows the same shape:

1. **Prompt with pinned field names.** Don't rely on a schema; tell the model the exact keys in the prompt body. Prefer **JSONL** (one flat JSON object per line, no enclosing array, no commentary) — it's more robust than a single big array because a single malformed line doesn't poison the whole parse.
2. **Scene-aware token budget.** `OllamaLedgerExtractor.budgetForSceneWords(_:)` = `min(8192, max(2048, sceneWords * 8))`. The model emits ~1 fact per ~14 scene-words, each fact ~70 tokens of JSON, so ~8× scene-words of headroom closes the output. Floor 2048 (live-verified safe minimum), cap 8192 (keeps a runaway scene from monopolising the extractor).
3. **Retry-on-empty with doubled budget.** `callWithRetry` — on an empty `message.content`, retry once with `num_predict` doubled (capped 8192). Empty responses come from two causes: a transient degenerate roll (any retry fixes it) OR `num_predict` cut the output before the first token survived EOS (only a budget bump fixes it). The doubled-budget retry covers both.
4. **Tolerant parse.** `LedgerExtraction.parseExtractedFacts` / `ContinuityAudit.parseClaims` — locate the structured payload inside chatty preamble/postamble, accept JSONL or a JSON array interchangeably, recover per-object so one bad row doesn't drop the rest. Throws `noJSONObjectFound` / `noJSONArrayFound` only when there's genuinely nothing parseable.
5. **Retry on parse-fail.** Stage A2 (entity discovery) retries on `noJSONObjectFound` / `noJSONArrayFound`; the beat extractors retry on **any** `BeatExtraction.ParseError` (both `noJSONObjectFound` *and* `decodingFailed` — braces found but malformed). NSFW prose has a ~30% transient parse-fail rate; a re-roll usually clears it. (The `decodingFailed` case was a silent-fail gap fixed 2026-05-22 — a malformed roll used to give up after one attempt.)
6. **Post-extraction filters, fail-soft.** Raw extractor output is noisy (paraphrase dupes, hallucinated evidence quotes, prompt-leakage). `LedgerFilters` runs cosine dedup + evidence-quote validation + prompt-leakage detection; `LedgerFilterPipeline` runs them async and fail-soft (a filter erroring degrades to pass-through, never drops the whole batch).

## Per-pipeline map

| Pipeline | Phase | Extractor | Trigger | Output store |
|---|---|---|---|---|
| **Knowledge ledger** | 4 | `OllamaLedgerExtractor` | post-scene, 200-word delta (`LedgerExtractionTrigger`) | `LedgerSuggestionsQueue` → `Character.knownFactsBySceneId` on accept |
| **Entity discovery** | 9 | `GLiNERCandidateDetector` + `OllamaEntityDiscoveryExtractor` | post-scene, 500-word delta (`EntityDiscoveryTrigger`), piggybacks on ledger | `ProposedEntitiesStore` |
| **Relationship discovery** | 10 | `OllamaRelationshipDiscoveryExtractor` (vote-aggregated) | post-scene | `ProposedRelationshipsStore` |
| **Continuity audit** | 10 | `OllamaContinuityExtractor` (two-stage) | on-demand | `ContinuityAuditStore` |
| **Scene-template beats** | 7 | Pass-A — **prefers** `OllamaBeatExtractor` (gemma4_2b, unconstrained); falls back to `KoboldBeatExtractor` (writer, unconstrained) | on Extract (manual) | `templates/<id>.beats.json` |

### Knowledge ledger

`OllamaLedgerExtractor.extract` → tolerant parse → `LedgerFilterPipeline` → `LedgerDiff` (vs existing bible) → `LedgerSuggestionsQueue`. The extractor emits **`asserted` facts only** — negative knowledge (DOES NOT KNOW) is never extracted (the spike found 0/2 recall on it); it's set-differenced at query time by `LedgerKnowledge.compute` using scene presence. See **Knowledge ledger** in User Help + `LOOM_LEDGER_SPIKE.md`.

### Entity discovery

Six stages: candidate generation (GLiNER deterministic NER + Ollama gemma A2 pass) → promotion gate (`EntityPromotionGate`: proper-noun shape, anatomy-descriptor block-list, place-recurrence) → cosine dedup against the existing bible (`EntityDedupEngine`, Wegmann embeddings) → normalisation → post-norm dedup → `ProposedEntitiesStore`. See **Entity discovery** in User Help + `LOOM_ENTITY_DISCOVERY_SPIKE.md`.

GLiNER (DeBERTa-v3 via ONNX) is the deterministic, NSFW-robust candidate detector — it never refuses on explicit prose, where a generative model might.

### Relationship discovery

`OllamaRelationshipDiscoveryExtractor` runs multiple samples and vote-aggregates — voting drops gemma's run-to-run *unstable* edge invention (a real edge recurs across votes; a hallucinated one doesn't). Surfaces `ProposedRelationship`s with a conflict-detection pass (`RelationshipConflict`) against existing `Character.relationships`.

### Continuity audit

The most elaborate. Per-scene typed-claim extraction (`OllamaContinuityExtractor`, two-stage) → deterministic typed fact-base + attribute diffing → candidate-conflict retrieval (entity index + Wegmann embeddings, `ContinuityConflictRetrieval`) → pairwise NLI adjudication (one claim pair at a time, on the writer model — `gemma4_2b`/`4b` fail the adjudication gate) → severity-ranked `ContinuityFinding`s. Knowledge-state checks reuse `LedgerKnowledge.compute`; the whole thing runs on Goetia/KoboldCpp + a text embedder. Per-run coverage is **stochastic** (extraction recall ~83%); it's a usable review aid, not a guarantee. See `LOOM_CONTINUITY_AUDIT.md` §19–20.

### Scene-template beat extraction

`KoboldBeatExtractor` (Pass-A) walks a template scene's prose and emits an `ExtractedSceneSkeleton` — ordered beats with modality tags + pacing + a `VoiceDescriptor`. Persisted as `templates/<id>.beats.json`, consumed at generation time by `TemplateGenerationCoordinator` (Pass-B). See **Scene exemplars + templates** in User Help + `LOOM_SCENE_TEMPLATE_SPIKE.md`.

This pass's transport history is the cautionary tale of the whole page (all dated 2026-05-22, on a 31B Thinking writer at 16384 context):

1. **Ollama `format`-schema** → ~97KB off-schema body, parse failure (the documented format-schema flake).
2. **Writer + GBNF** → fixed the *parse* (always valid JSON) but exposed a deeper failure: GBNF guarantees structure, not *meaningful values*. On a Thinking writer, forcing JSON from token 0 suppresses reasoning → valid-but-degenerate skeletons (26 beats all `arrival`, `targetWords` 0).
3. **Writer, unconstrained (think-first)** → the model can reason, but on a verbose reasoner the reasoning ate the output budget and the JSON truncated mid-structure → parse failure. (The output-token cap, not the context, was the limiter — fixed by sizing `num_predict` to the *remaining* context.)
4. **gemma4_2b unconstrained, single nested object** → free-formed a wrong `title`/`characters`/`plot` shape (couldn't produce the deep nesting).
5. **gemma4_2b unconstrained, JSONL** → prompt-recency fix got it emitting JSON, but it invented wrong keys (`speaker`/`utterance`) — unconstrained, it won't follow a specific multi-shape schema.
6. **Settled — flat schema + `format` constraint.** `BeatExtraction.flatJSONSchema` / `buildFlatPrompt` / `parseFlatSkeleton`: a **flat structure-of-arrays** object — voice fields at top level + parallel `beatFunctions` / `beatModalities` / `beatSummaries` / `beatTargetWords` arrays, no nested objects. The `format` schema constrains the keys (fixing the wrong-shape problem) and the shape is shallow enough that the format decoder *doesn't* flake (the original flake was the deep array-of-objects nesting). Prompt is scene-first / directive-last (recency). Tolerant parse: zip the parallel arrays, unknown enums fall back, `targetWords ≤ 0 → 100`, zero beats → retry. Pass-A **prefers `OllamaBeatExtractor` (gemma4_2b) with the flat `format` schema**; falls back to `KoboldBeatExtractor` (writer, unconstrained flat prompt; `useGrammar: true` re-enables the nested + GBNF path for a non-thinking writer).

The lessons, in order: **the *nested* `format` schema flakes; GBNF buys well-formed JSON but not well-chosen values; a reasoner's reasoning competes with its output budget; a small model can't free-form a complex shape unconstrained (nested → wrong shape, JSONL → wrong keys); the durable answer is a *flat* schema held by the `format` constraint.**

## Why the tolerant parser, concretely

Local small models do not emit clean JSON reliably. Real failure modes the parser absorbs:

- **Chatty preamble:** `"Here are the facts I extracted:\n[...]"`. The parser locates the outermost `[` (array) or first `{` per line (JSONL) and ignores the prose around it.
- **Postamble:** `"[...]\n\nLet me know if you need more!"`.
- **Mixed format:** asked for JSONL, the model returns a JSON array (or vice versa). The parser accepts either.
- **One malformed object among good ones:** per-object recovery keeps the parseable rows, drops only the broken one.
- **Degenerate / empty:** caught by the retry-on-empty before the parser sees it.

The combination — unconstrained generation + JSONL framing + tolerant parse + retry — proved more reliable on `gemma4_2b` than the nominally-stricter `format` schema, because the schema's failure mode (silent empty content) is invisible and unrecoverable within a single call.

## Concurrency + fail-soft

Extraction runs off-main on the pipeline's own queue, debounced from the post-scene-save event (ledger + discovery) or fired on demand (continuity, beats). Results bounce to main for store-write + UI update. Every pipeline is **fail-soft**: a transport error, a parse failure, a filter exception — none of them crash or block the editor; they log to the relevant `[ledger]` / `[proposals]` / `[continuity]` / `[scene-exemplar]` subsystem and the user keeps writing. Extraction is an enhancement, never a gate.

## See also

- **Embeddings** — the next section: the dedup + evidence-validation embedders these pipelines lean on.
- **Knowledge ledger** / **Entity discovery** (User Help) — the user-facing surfaces.
- [`LOOM_TECH_STACK.md`](LOOM_TECH_STACK.md) "Structured extraction from prose" — the solved-problem registry rows. **Check there before building a new pass.**
- [`LOOM_LEDGER_SPIKE.md`](LOOM_LEDGER_SPIKE.md), [`LOOM_ENTITY_DISCOVERY_SPIKE.md`](LOOM_ENTITY_DISCOVERY_SPIKE.md), [`LOOM_CONTINUITY_AUDIT.md`](LOOM_CONTINUITY_AUDIT.md), [`LOOM_SCENE_TEMPLATE_SPIKE.md`](LOOM_SCENE_TEMPLATE_SPIKE.md) — per-pipeline depth.

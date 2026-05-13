---
name: LOOM_RAG_SPIKE
description: Phase 5 RAG-for-style feasibility spike plan
type: project
---

# LOOM_RAG_SPIKE — feasibility eval plan

> **Date:** 2026-05-13. **Status:** plan only. No code lands from this document.
>
> Phase 5 ([LOOM_PLAN.md §5](LOOM_PLAN.md)) is Loom's largest single phase
> and sits on genuinely under-explored R&D territory ([LOOM_RESEARCH.md §O.4](LOOM_RESEARCH.md):
> *"no widely-adopted stylistic embedding model exists in 2026"*). Before
> committing a multi-session production arc to chunking, embedding,
> per-scene-type retrieval, and reference-text storage, this spike answers
> one question empirically: **can the local model fleet retrieve
> stylistically similar prose, or is it confined to retrieving topically
> similar prose?**
>
> Mirrors the shape of [LOOM_LEDGER_SPIKE.md](LOOM_LEDGER_SPIKE.md) §1–7
> (the plan portion; the post-eval rounds get appended once results land).

## 1. Falsifiable hypothesis

From [LOOM_PLAN.md §5 Phase 5](LOOM_PLAN.md) + [LOOM_RESEARCH.md §O.4](LOOM_RESEARCH.md):

> **Falsifiable hypothesis:** with the local model fleet available to
> Loom today, retrieval over a corpus of reference-text chunks can rank
> *stylistically* similar passages above merely *topically* similar
> ones, well enough to be production-useful as few-shot style exemplars
> in the writer prompt.

"Well enough" is operationalised in §5 below as **NDCG@3 ≥ 0.7 against
gold rankings where the right answer is style-matched, not
topic-matched**.

If the hypothesis is false at the floor of available models, Phase 5
production scope must shrink — likely to a lorebook-style RAG (topical
retrieval over user-curated reference snippets, with style addressed
purely via the style-sheet entity and few-shot prompt-side exemplars
the user manually pins). The spike's job is to surface this before
production commits.

## 2. What the eval measures

For each candidate **embedding path** (§3) and each **query scene** (§4):

1. Chunk the reference corpus at the configured chunk size.
2. Embed every chunk via the path under test.
3. Embed the query scene via the same path.
4. Rank chunks by cosine similarity to the query.
5. Score the ranking against gold (§5).

Cross-cuts measured:

- **Style-vs-topic preference** — does the path's top-3 prefer
  same-style or same-topic chunks? This is the load-bearing signal.
- **Chunk size sensitivity** — 50 / 150 / 400 words.
- **Latency / corpus-time cost** — wall-clock per chunk to embed; one
  full corpus pass.
- **Dimensionality + persistence cost** — sidecar size projection per
  [LOOM_PLAN.md §7](LOOM_PLAN.md) `references/<id>.index`.

## 3. Candidate embedding paths

The user proposed three models: gemma-4-31B writer (Kobold),
nomic-embed (Kobold), gemma4_2b (Ollama). Probe at planning time
revealed a hard constraint:

- **Kobold `/v1/embeddings`** — works, returns 768-dim vectors. The
  underlying model is nomic-embed-text (Kobold's `embeddings: true`
  capability flag confirmed via `/api/extra/version`).
- **Ollama `/api/embed` for `gemma4_2b`** — returns `{"error": "this
  model does not support embeddings"}`. Not a config issue — the
  Gemma 4 generative checkpoint isn't exposed as an embedder. This
  candidate, as proposed, is non-viable.

This shifts the candidate list to three meaningfully different
**paths** rather than three models:

### Path A — nomic-embed direct (the baseline)

- **Endpoint:** Kobold `POST /v1/embeddings`
- **Input:** raw chunk text.
- **Output:** 768-dim vector.
- **Hypothesis:** retrieves by topic. Will rank same-topic chunks high
  regardless of style. This is the *control* — the result the
  literature predicts ([LOOM_RESEARCH.md §M.5](LOOM_RESEARCH.md):
  *"generic semantic embeddings work partially for style"*).

### Path B — dedicated embedder on Ollama (cross-check)

- **Endpoint:** Ollama `POST /api/embed`
- **Models:** **both** `mxbai-embed-large` (1024-dim, strong on MTEB
  style/clustering tasks) **and** `bge-large-en-v1.5` (1024-dim, classic
  strong open embedder). ~670 MB each; pulled at spike start; verified
  via `/api/embed` probe before fixture run. Running both costs two
  extra result columns; if they agree closely, the bottleneck is the
  embedder *class* — a meaningful negative result. If they diverge,
  Phase 5 has real signal on which dedicated embedder to ship.
- **Input:** raw chunk text.
- **Output:** 1024-dim vector.
- **Hypothesis:** if A and B agree on rankings, the bottleneck is the
  *class* of model (semantic embedder), not the specific model — a
  meaningful negative result. If B materially beats A, the embedder
  choice matters and Phase 5 should benchmark several before committing.

### Path C — writer-distilled style descriptors (the speculative win)

The original third slot in the user's proposal was gemma4_2b on Ollama.
Since gemma4_2b can't embed directly, we redirect the *idea* behind the
proposal — use the local generative model for style retrieval — into a
two-stage pipeline:

1. **Style descriptor generation.** For each chunk, prompt gemma-4-31B
   on Kobold to emit a short structured descriptor of prose voice:
   sentence-length profile, modality (action / dialogue / interiority /
   description), tense, POV, register (literary / pulpy / clinical /
   journalistic), lexicon notes. ~80–120 tokens out, constrained via
   GBNF grammar (technique already validated in [LOOM_LEDGER_SPIKE.md §8.1](LOOM_LEDGER_SPIKE.md)).
2. **Descriptor embedding.** Embed the descriptor (not the raw chunk)
   via Path A (nomic) or B (mxbai). Cosine over descriptor space.

The intuition: a semantic embedder over a *style-only feature
description* is closer to a stylistic embedder than a semantic embedder
over raw prose. The distillation step strips the topical signal
(characters, setting, plot beats) and keeps the voice signal.

- **Hypothesis:** C ranks by style materially better than A or B alone.
  If true, Phase 5 production indexes chunks via descriptor-embedding
  (descriptors generated offline at reference-ingest time, not per
  query — same one-shot cost model as raw embedding).

### Oracle path — gemma-4-31B as judge (ground truth, not a candidate)

Not a production path — used to *grade* A/B/C when hand-grading the
full ranking is infeasible.

- For each (query, candidate-pair) tuple, ask gemma-4-31B which of two
  chunks is more stylistically similar to the query. Tournament
  pairwise comparisons across the corpus yield a gold ordering.
- Validate the oracle on a 20-comparison subset against the author's
  hand-judgement. If oracle / hand agreement ≥ 0.85, the oracle is
  trusted for the full sweep. If lower, fall back to full hand-grading
  (limits fixture size; see §4).

## 4. Fixture design

The fixture must let topic and style **vary independently** so the
eval can distinguish them. Hand-authored to avoid copyright
contamination of the reference corpus.

**Crossing:** 4 styles × 3 topics = **12 reference excerpts**, each
~300–400 words.

Styles (chosen for sharp differentiation, deliberately exaggerated):

1. **S1 — Clipped minimalist.** Short sentences, concrete nouns,
   absent modality, Hemingway-adjacent.
2. **S2 — Lush gothic.** Long compound sentences, archaic vocabulary,
   sensory excess, McCarthy/du Maurier-adjacent.
3. **S3 — Free-indirect interior.** Tight third-person, present
   subjective register, fragmentary thought-rhythm, Rooney-adjacent.
4. **S4 — Procedural thriller.** Mid-length declarative sentences,
   technical/operational vocabulary, suppressed affect, Clancy/Forsyth-adjacent.

Topics (chosen so each works in every style):

- **T1 — A car chase / pursuit.**
- **T2 — A kitchen breakfast scene.**
- **T3 — A confrontation between two characters.**

**Query scenes** (the "user wants to write X in Y style" inputs): 4
queries, one per style, at varied topics:

- **Q1:** S1 (clipped) at T2 (breakfast).
- **Q2:** S2 (gothic) at T1 (pursuit).
- **Q3:** S3 (interior) at T3 (confrontation).
- **Q4:** S4 (procedural) at T2 (breakfast).

**Gold rankings:** for each query, the 3 same-style chunks rank
positions 1/2/3 (any order among themselves); the 3 same-topic
different-style chunks should *not* rank in the top 3 — they're the
adversarial decoys. Remaining 6 chunks are uninvolved.

**NSFW coverage:** per [LOOM_NSFW.md §3](LOOM_NSFW.md) content-neutrality
directive, at least 2 of the 12 excerpts are NSFW (one in S2 lush, one
in S3 interior). Mirrors LedgerSpike fixture practice.

**Fixture path:** `Tests/LoomCoreTests/Fixtures/RagSpike/fixture.json`.

## 5. Scoring methodology

Two metrics, both reported per path:

### 5.1 NDCG@3 with binary relevance (style-match)

Standard normalised DCG, with `rel(c) = 1` if chunk `c` is same-style
as the query, `0` otherwise. NDCG@3 = 1.0 iff all three top-3 results
are same-style.

**Headline metric.** A path passes the floor at NDCG@3 ≥ 0.7
(operationalises "well enough" in §1).

### 5.2 Style-vs-topic preference index

For each query, count among top-3 results:

- `s` = same-style chunks
- `t` = same-topic chunks (different style)
- preference = `(s − t) / 3`

`+1.0` = perfect style-preferred ranking. `−1.0` = perfect
topic-preferred ranking. `0` = indifferent.

Averaged across the 4 queries. A path that hits NDCG@3 ≥ 0.7 but with
preference ≤ 0 isn't actually retrieving style — it's getting lucky on
small fixture overlap. Both metrics must agree.

### 5.3 Oracle agreement

For the trusted oracle (gemma-4-31B-as-judge, §3 oracle), compute
Kendall's τ between oracle ranking and each path's ranking. Useful as
a secondary signal — a path may miss NDCG@3 on the binary metric but
agree with the oracle on fine-grained ordering, suggesting the metric
not the retrieval is the limiter.

## 6. Day-plan (commit-by-commit)

Mirrors LedgerSpike's red→green→commit cadence; pure-data Swift first,
network layer last. TDD per memory `feedback_tdd_always`.

**S1 — Scaffolding (pure-data, ~2h)**
- `Sources/LoomCore/Retrieval/Embeddings.swift`: `EmbeddingVector`
  (Float array + dim), `cosine(_:_:)`, `Chunk` struct, `chunkText(_:size:overlap:)`.
- `Sources/LoomCore/Retrieval/RankingMetrics.swift`: `ndcgAt(_:gold:ranking:)`,
  `styleTopicPreference(...)`, `kendallTau(...)`.
- TestKit tests against hand-computed values. Commit.

**S2 — Fixture authorship (~3h, no code)**
- Write 12 reference excerpts + 4 query scenes. Hand-author; do not
  paste copyrighted text. Land at
  `Tests/LoomCoreTests/Fixtures/RagSpike/fixture.json`.
- The fixture is the load-bearing artifact — most of the spike's value
  is in how cleanly styles separate. Aim for excerpts that any
  literate reader would assign to the right style with > 90% accuracy.
- Commit.

**S3 — Embedding clients (~2h)**
- `Tools/RagSpike/`: standalone Swift executable mirroring
  `Tools/LedgerSpike`. Calls Kobold `/v1/embeddings`, Ollama `/api/embed`.
- No production code path yet — the spike runner exists solely to
  produce the eval table.
- Commit.

**S4 — Path A + B sweep (~2h)**
- Embed corpus + queries via A (nomic) and B (mxbai).
- Score under §5 at chunk sizes {50, 150, 400} words.
- Land results as a markdown table in §7 of this doc.
- Commit (doc + tooling).

**S5 — Path C: descriptor distillation (~3h)**
- GBNF for style descriptor (sentence-length / modality / tense / POV /
  register / lexicon).
- Generate descriptors for all 12 chunks via gemma-4-31B on Kobold.
- Embed descriptors via A (or whichever of A/B scored higher in S4).
- Score.
- Commit.

**S6 — Oracle pass (~2h, optional if A/B/C already give a clean verdict)**
- Pairwise gemma-judge over the corpus per §3 oracle.
- 20-comparison hand-validation sanity check.
- Kendall τ for each path. Land in §7.
- Commit.

**S7 — Findings + recommendation (no code, ~1h)**
- Append sections to this doc (like LedgerSpike §8–12 evolved
  post-results) and update [LOOM_PLAN.md §5](LOOM_PLAN.md) with the
  PROCEED / PIVOT / NO-GO verdict.
- HANDOFF.md write-up.

Total estimate: ~13–15h. One full session if focused; two sessions
realistic.

## 7. Decision tree (PROCEED / PIVOT / NO-GO)

After all paths score, exactly one branch fires:

### PROCEED — any path clears NDCG@3 ≥ 0.7 AND preference ≥ +0.3

Phase 5 production proceeds with the winning path:

- A or B → raw-chunk embedding pipeline; the per-scene-type pillar
  ([LOOM_RESEARCH.md §O.4](LOOM_RESEARCH.md)) is supplied by
  *tagging* chunks at ingest time and filtering candidates by tag
  before similarity ranking.
- C → descriptor distillation; ingest pipeline becomes two-stage
  (chunk → descriptor → embed), index sidecar stores descriptor
  embeddings, per-scene-type pillar is supplied by the descriptor's
  `modality` field as a filter.

### PIVOT — A/B at floor but C wins materially

Phase 5 ships **descriptor-distillation** as the indexing strategy.
This is a non-trivial production complication (writer model runs on
every reference-text ingest, not just on user-facing scene
generation) — the spike justifies the cost.

### PIVOT — no path clears floor, but oracle agreement is high (Kendall τ ≥ 0.6) for one path

The retrieval is *better than the binary metric shows*; the metric is
too coarse. Phase 5 proceeds with that path but the production UX
surfaces top-K with K ≥ 5 (more candidates, looser filter) rather
than top-3, and pins few-shot inclusion behind a user confirm step.

### NO-GO — no path clears floor and oracle agreement is low across all

Style-RAG isn't feasible at the current model fleet. Phase 5
production scope shrinks to:

- **Lorebook-style topical RAG** (general semantic retrieval over
  user-curated reference snippets — useful for setting/worldbuilding
  retrieval, not voice).
- **Style addressed via the style-sheet entity** (always-on prompt
  injection of user-authored tone descriptors) + **few-shot exemplars
  manually pinned** by the user via the Bible Workspace.

This is roughly SillyTavern's status quo ([LOOM_RESEARCH.md §C.3 + §M.5](LOOM_RESEARCH.md))
and matches the deprecation pattern of NovelAI's AI Modules. Not a
failure mode for Loom — just a smaller Phase 5.

## 8. Out of scope

Explicitly NOT in this spike:

- The `references/<id>.md` + `<id>.index` storage format ([LOOM_PLAN.md §7](LOOM_PLAN.md)).
  Spike works in-memory.
- The Bible Workspace reference-text entity type. New selection kind /
  view / intent cases land in Phase 5 production, not the spike.
- Real reference-corpus indexing. The spike's 12-excerpt fixture
  exists to differentiate style from topic; it does not exercise
  scale (1000s of chunks).
- Writer-prompt integration. The spike measures retrieval ranking; it
  does not feed retrieved chunks into the writer prompt or measure
  generation quality.
- Per-scene-type classification *as a classifier*. The spike's
  descriptor path emits modality as one of several fields; production
  may need a separate classification step. Out of scope here.
- Streaming embedding (incremental ingest). Production batch.
- Cache invalidation when reference text edits.
- Chunk-overlap optimisation.
- Cross-language retrieval. English-only fixture.

## 9. Production gaps the spike will likely surface

Anticipated, to be confirmed empirically:

1. **Descriptor schema design.** Path C's descriptor template is the
   load-bearing detail — too generic and topic leaks back in; too
   specific and the writer model under-distills. Expect 2–3 iterations
   on the GBNF schema.
2. **Chunk-boundary sensitivity for style.** Voice emerges over
   paragraph-scale spans; 50-word chunks may strip too much rhythm,
   400-word chunks may dilute against intra-passage style shifts.
3. **NSFW retrieval parity.** Generic semantic embedders may
   under-weight NSFW vocabulary (training-corpus filtering effects).
   The fixture's 2 NSFW excerpts will reveal this — if path A
   systematically deranks NSFW chunks vs SFW ones at equivalent
   style match, that's a production constraint.
4. **Index sidecar format.** 768-dim float32 × ~10k chunks ≈ 30MB per
   reference text. 1024-dim doubles that. The spike confirms which
   path's dimensionality we're paying for. Float16 packing is a
   probable Phase 5 production optimisation.

## 10. Risks

- **Fixture quality dominates.** If the hand-authored excerpts don't
  cleanly separate by style (e.g. all four "styles" share too much
  base register), the eval is unfalsifiable. Mitigation: author the
  fixture deliberately exaggerated; do a literate-reader sanity
  check (the author plus one other reader independently classify all
  12 excerpts; mismatch on more than 1 means rewriting before eval).
- **Oracle is unreliable for style.** gemma-4-31B is the writer
  model, trained for generation not stylistic judgement. The 20-pair
  hand-validation gate (§3 oracle) catches this; if oracle fails
  validation, fall back to full hand-grading at the cost of fixture
  size (likely shrink to 8 chunks × 2 styles).
- **Path C grammar drift.** The GBNF for descriptors may interact
  with gemma-4-31B's generation patterns in unexpected ways
  ([LOOM_LEDGER_SPIKE.md §9.2](LOOM_LEDGER_SPIKE.md): grammar fixes
  structure but not content). Mitigation: spike-day inspect 3
  descriptors by hand before running the full corpus through.
- **Latency makes Path C non-viable in production even if it wins.**
  If descriptor generation per chunk takes 5s+, indexing a
  100-chunk reference text takes 8 minutes — acceptable for offline
  ingest, but flag explicitly in §7 PROCEED/PIVOT.

## 11. Memory + design-doc updates produced

Doc-only, post-results:

- This doc, §12+ appended with empirical findings.
- [LOOM_PLAN.md §5 Phase 5](LOOM_PLAN.md): scope locked from PROCEED /
  PIVOT / NO-GO verdict.
- [LOOM_RESEARCH.md §O.4](LOOM_RESEARCH.md): "no widely-adopted
  stylistic embedding model exists" updated with Loom's empirical
  data point.
- HANDOFF.md: new section recording the spike's verdict + Phase 5
  scope lock.

## 12. References

- [LOOM_PLAN.md §5 Phase 5](LOOM_PLAN.md) — Phase 5 scope.
- [LOOM_PLAN.md §7](LOOM_PLAN.md) — `references/` directory + index
  sidecar.
- [LOOM_RESEARCH.md §O.4](LOOM_RESEARCH.md) — R&D risk: no widely-adopted
  stylistic embedding model.
- [LOOM_RESEARCH.md §M.5](LOOM_RESEARCH.md) — style ingestion open
  territory.
- [LOOM_RESEARCH.md §L.5](LOOM_RESEARCH.md) — RAG fundamentals
  (chunking + embedding).
- [LOOM_RESEARCH.md §C.3](LOOM_RESEARCH.md) — NovelAI AI Modules
  deprecation history.
- [LOOM_LEDGER_SPIKE.md](LOOM_LEDGER_SPIKE.md) — structural template
  for this doc; GBNF technique transferable to Path C.
- [LOOM_NSFW.md §3](LOOM_NSFW.md) — content-neutrality directive.
- [nomic-embed-text](https://blog.nomic.ai/posts/nomic-embed-text-v1) —
  Path A embedder.
- [mxbai-embed-large](https://www.mixedbread.ai/blog/mxbai-embed-large-v1) —
  Path B candidate embedder.
- [BGE-large-en-v1.5](https://huggingface.co/BAAI/bge-large-en-v1.5) —
  Path B alternative embedder.
- [llama.cpp GBNF README](https://github.com/ggml-org/llama.cpp/blob/master/grammars/README.md) —
  Path C descriptor schema.

# Loom — Continuity Audit (design + plan)

> **Status: Phase B built + tuned against an eval harness; tuning ongoing
> (2026-05-19).** Phase A cleared the feasibility gate (§13); Phase B built
> the pipeline (§14–18). §19–20 gave the honest stochastic picture and the
> open problems; §21 is the research pass + plan; §22 is the eval harness
> and the retrieval/filter tuning. Definitive k=10 engine eval: end-to-end
> finding recall **35% ±4**, precision **75% ±7**, pass@k 26/40 — per-run
> recall roughly doubled from the ~17% baseline. It is a usable review aid
> that improves on re-run, not yet polished. Remaining: multi-sample
> aggregation, the `knowledge_violation` collapse, precision recovery, then
> Phase C (Bible Workspace surface). This document is the authoritative
> plan. Inventory pointer: **L10** in [`LOOM_PLAN.md`](LOOM_PLAN.md).

## 0. What this is

An automated audit that scans a finished (or in-progress) manuscript and
reports **contradictions across scenes** — surfaced as a ranked, evidence-cited
review queue the writer accepts or dismisses. It never auto-corrects.

Four contradiction classes are in scope (user-confirmed 2026-05-17):

1. **Factual attribute drift** — a character's eye colour, scar, job, or
   possession changing inconsistently between scenes.
2. **Knowledge-state violations** — a character knowing or referencing
   something before the scene that reveals it to them. *This is the
   differentiator* — Loom already tracks knowledge-state-per-character.
3. **Timeline & chronology** — event-ordering conflicts, ages, durations,
   season / time-of-day inconsistencies.
4. **Spatial / world consistency** — geography, location layout, object
   placement. Broadest and fuzziest; lowest detection precision (see §10
   phasing — this class lands last).

Trigger model (user-confirmed): **on-demand first, incremental later.**

## 1. Why this is worth building — verified prior art

A focused prior-art pass (2026-05-17) confirms this is a **genuine market gap**,
not a solved problem:

- **No mainstream fiction tool ships an automated cross-scene contradiction
  auditor.** Sudowrite's "Chapter Continuity" and NovelCrafter's Codex are
  *prevention-at-generation* — they inject prior context into the writing
  prompt; they do not scan a finished manuscript and report conflicts.
  Sudowrite's own docs say "a final human read-through catches nuances no tool
  can." AutoCrit checks only tense / POV slips (pattern-matching, not facts).
  Marlowe and Fictionary do developmental feedback (plot beats, pacing) — a
  Marlowe review notes it "misses … the continuity of the chapters." Campfire
  and Plottr only make errors *visible* to a human.
- Marketing blogs claiming "AI continuity checkers exist" were checked
  skeptically and resolve to the prevention / linter features above.

So an automated factual + knowledge-state + timeline auditor would be
genuinely differentiated.

## 2. Why the naive approach fails

**CONTRADOC (Hsu et al., NAACL 2024)** — the first human-annotated
document-contradiction dataset — found that asking an LLM "does this document
contradict itself?" performs badly: **GPT-4 reached only ~54% precision** at
97% recall; GPT-3.5 ~50%; smaller models near-random. Models default to "no
contradiction." Our extractor model is far smaller than GPT-4.

Conclusion: **a whole-document (or even whole-chapter) LLM judge is not
viable.** The audit must decompose the problem so the LLM only ever judges
*small, localized, same-subject claim pairs* — a much easier task than
holistic document reasoning.

## 3. Architecture — a pipeline, not a pass

The principle (from long-form-factuality work — FActScore, VeriScore, and the
ConStory-Checker blueprint): **the LLM does extraction and final pairwise
adjudication; deterministic code does the diffing and ordering.** This bounds
LLM calls and keeps precision controllable.

```
per-scene claim extraction   →   typed fact-base   →   candidate-conflict
   (LLM, schema-constrained)      (deterministic)       retrieval (index +
                                                         embeddings)
                                                              ↓
   findings store  ←  finding assembly  ←  pairwise NLI adjudication
   (sidecar JSON)     (severity, evidence)    (LLM, one claim pair at a time)
```

### 3.1 Per-scene claim extraction

Each scene is processed **independently** (one scene fits in context). The LLM
emits *atomic, decontextualized, typed* claims. Decontextualization is
essential (FActScore lesson) so a claim is comparable across scenes without its
original sentence.

A `Claim`:

| field | meaning |
|---|---|
| `id` | UUID |
| `type` | `attribute` / `event` / `knowledgeState` / `temporal` / `spatial` |
| `subjectEntityId` | resolved Character / Setting / BibleObject, if known |
| `subjectName` | raw name/alias as written (for unresolved subjects) |
| `attributeKey` | for `attribute`: normalised key, e.g. `eye colour`, `occupation` |
| `value` | the asserted value / proposition |
| `sourceSceneId` | scene the claim came from |
| `sourceKind` | `narration` / `dialogue` / `thought` — **attribution** |
| `speakerEntityId` | for dialogue/thought: whose assertion/belief this is |
| `evidenceQuote` | verbatim span — every claim must be grounded |
| `certainty` | `asserted` / `suspected` / `mistaken` (reuse `Certainty`) |

**Constrained-decoding posture — apply the accumulated gemma lesson.**
Extraction does **not** use Ollama's `format` schema. The project learned
(HANDOFF §15.19, commits `b6c7a97` / `d4df07e`) that Ollama's
schema-constrained sampling flakes ~50% on gemma4_2b — a degenerate
non-terminating buffer that hits `num_predict` and returns empty content.
The newer discovery extractors abandoned the schema; continuity extraction
follows that path: **unconstrained generation, field names pinned in the
prompt, JSONL output** (a small model emits one flat object per line far
more reliably than a nested array), a **tolerant parser**, and a **re-roll**
on any degenerate result (empty / unparseable / zero claims). It keeps the
scene-word-aware `num_predict` budget (`OllamaLedgerExtractor.budgetForSceneWords`).
The claim extractor is `OllamaContinuityExtractor`.

**Two-stage extraction — typing is its own focused pass.** A
model A/B (§15) and prior-art research (Claimify) both found that asking
one call to do recall + typing + JSON + quoting at once overloads the
*type* classification — a bigger model finds more facts but types them no
better. So extraction runs in two stages: stage 1 extracts claims; stage 2
re-classifies each claim's `type` in a call that does nothing else (scene +
the claim list → one type per claim). Stage 2 fails open — a typing error
keeps the stage-1 best-effort types. **Both stages run on Goetia (24B,
KoboldCpp)** — see §15; the small Ollama model is not capable enough even
for the focused typing pass, so the continuity audit is entirely a
KoboldCpp/Goetia feature with no Ollama dependency.

**Reuse vs. fresh extraction.** Loom already extracts character facts into
`Character.knownFactsBySceneId` ([`Character.swift:23`](Sources/LoomCore/Models/Character.swift)).
The audit *consumes* those accepted facts as `attribute` / `knowledgeState`
claims for free — but it cannot rely on them alone (they are character-only and
suggestion-gated; the user may not have accepted everything). The audit runs
its own complete extraction pass covering settings, objects, temporal and
spatial claims, and treats accepted ledger facts as a high-confidence subset.

**Claim-filter pass — reuse the proven `LedgerFilters` infrastructure.**
Raw extraction is noisy (the spike saw 11–24 claims/scene, many redundant).
Before claims enter the fact-base, run a filter pass mirroring
[`LedgerFilters`](Sources/LoomCore/Generation/LedgerFilters.swift) /
[`LedgerFilterPipeline`](Sources/LoomCore/Generation/LedgerFilterPipeline.swift) —
already built, tested, and live for the knowledge ledger:

- **Dedup** — cosine paraphrase-cluster collapse (`KoboldEmbedding` +
  `LedgerExtraction.cosineSimilarity`), so the same fact stated twice in a
  scene yields one claim.
- **Evidence-quote validation** — drop a claim whose `evidenceQuote` has no
  scene sentence within cosine threshold. This *is* §4 defense #4
  (evidence-grounding) and kills claims with hallucinated/editorialised
  quotes — a precision lever for free.

`LedgerFilters` is typed to `LedgerSuggestion`, so the audit gets a sibling
`ContinuityClaimFilter` over `Claim` (the same per-pipeline pattern entity
discovery already follows), reusing the cosine helper and embedder rather than
the literal functions.

**Subject grounding — reuse GLiNER + the bible/alias index.** A claim's
`subject` is free text as the LLM wrote it ("Mara", "she", "the investigator",
"the Lighthouse"). Conflict retrieval (§3.3) groups claims by subject, so
ungrounded subject strings fragment a single entity across several groups and
silently lose real conflicts. The audit resolves each claim's `subject` to a
stable entity id *before* retrieval, reusing infrastructure already in the
project:

- The **bible entity + alias index** — `Character` / `Setting` / `BibleObject`
  names and `aliases` — resolves the common case.
- [`GLiNERDetector`](Sources/LoomCore/Generation/GLiNERDetector.swift) — the
  project's native bidirectional NER encoder (ONNX / DeBERTa-v3), already the
  production entity detector for Phase 9 discovery
  ([`GLiNERCandidateDetector`](Sources/LoomCore/Generation/GLiNERCandidateDetector.swift)).
  It is **deterministic and, unlike a generative pass, cannot refuse or derail
  on explicit prose** — load-bearing for a heavy-NSFW app. GLiNER gives the
  audit a reliable per-scene list of the entities actually present, which
  subject-resolution anchors to (and which surfaces entities the bible has not
  yet captured).

Resolution writes a canonical subject onto each claim; `ContinuityConflictRetrieval`
then groups by that. Claims whose subject cannot be resolved fall back to the
normalised surface string.

### 3.2 Typed fact-base (deterministic)

Claims accumulate into a store keyed by `(subjectEntityId, type, attributeKey)`.
For `attribute` claims this makes drift a **cheap deterministic diff** — two
claims with the same key and incompatible values, no LLM needed for the
*candidate* step. High-precision for typed attributes; LLM is reserved for
deciding whether the two values are genuinely incompatible (§3.4).

### 3.3 Candidate-conflict retrieval

Never compare all O(n²) scene pairs. For each claim, retrieve only **prior
claims about the same subject and same dimension** as conflict candidates. The
subject is the **grounded entity** from the §3.1 subject-resolution step
(bible/alias index + GLiNER), so "Mara" / "she" / "the investigator" collapse
to one entity instead of fragmenting into three groups; the CoreML Wegmann
embedder handles fuzzy attribute-key matching. This bounds the number of LLM
adjudication calls to roughly the number of genuinely-overlapping claim pairs.

### 3.4 Pairwise NLI adjudication

The LLM judges **one candidate pair at a time**: premise = earlier claim,
hypothesis = later claim → `contradiction` / `consistent` / `evolution`
(legitimate change over time). Localized same-subject pairs are far easier for
a small model than whole-document judgment. **Open question (§11): which model
adjudicates** — the tiny extractor model, or the 24B writer (Goetia). The spike
A/Bs this.

### 3.5 Knowledge-state & timeline checks (mostly deterministic)

- **Knowledge-state** leans directly on existing machinery:
  [`LedgerKnowledge.compute(characterId:asOfSceneId:in:scenes:)`](Sources/LoomCore/Generation/LedgerKnowledge.swift:40)
  already buckets each character's facts into KNOWS / UNKNOWNS at any scene by
  walking `manuscript.flatSceneIds`. A `knowledgeState` claim that a character
  *references* fact F in scene S is a violation if F's first `asserted`
  exposure for that character is a scene *after* S. Deterministic given the
  reveal ordering; the LLM only extracts the "character references F" claim.
- **Timeline & chronology** — v1 **folds timeline conflicts into the
  retrieval + adjudication path** rather than building a separate
  deterministic chronology engine. The reason (a Phase-B scope finding): the
  conflict cases are already covered there — a `temporal` claim is a
  `pairableType`, so two temporal claims about the same subject (e.g. a storm
  dated "last week" vs. "a month ago") form a candidate pair and are
  adjudicated; an age conflict is an `attribute` claim (`attributeKey: "age"`)
  and rides the attribute path; event-ordering conflicts need the LLM anyway.
  The *additional* value of a standalone deterministic engine — absolute
  ordering, interval/duration arithmetic — needs real temporal-expression
  normalisation, which is disproportionate for v1 and entangled with the
  unresolved flashback question (§11.2). The spike confirmed Goetia
  adjudicates the storm-date conflict correctly (pair p5). A dedicated
  chronology engine is deferred to a later phase.

## 4. False-positive defenses — the real battle

CONTRADOC's ~54% precision is the headline risk. The hardest case is
**intentional** inconsistency — a lie, a reveal, an unreliable narrator,
character growth, or mere paraphrase — all of which look like contradictions to
a naive judge. Defenses, all designed in from v1:

1. **Source-attribution.** A claim inside dialogue/thought is the *character's*
   assertion, not a world-fact (`sourceKind`, `speakerEntityId`). "Character X
   *says* the vault is empty" conflicting with narration is X lying — not a
   continuity error. Only `narration`-sourced claims conflict as world-facts;
   dialogue claims conflict only with the *same speaker's* other claims.
2. **Time-indexed facts.** Every claim is scene-anchored. Legitimate evolution
   (a haircut, a promotion, character growth) registers as `evolution`, not
   `contradiction` — the adjudicator has an explicit `evolution` verdict, and
   attribute drift is only flagged when two claims assert the *same* state with
   no plausible change between them.
3. **Defeasible reveals.** A later reveal scene is a *defeater*, not a
   contradiction (defeasible-NLI framing). The `mistaken` certainty value
   already encodes "wrong belief, later corrected" — a `mistaken` fact never
   raises a finding.
4. **Evidence-grounding.** Every finding cites *both* verbatim quotes. Findings
   whose quotes cannot be located in the source scenes are dropped — this alone
   removes hallucinated flags.
5. **Ranked review queue, human decides.** Output is severity-ranked, top
   candidates surfaced first; never auto-correction. A false positive is then
   cheap — one dismiss click.
6. **Conservative thresholds.** NLI models over-predict contradiction; the
   adjudication confidence threshold is tuned high. Recall in *extraction*,
   precision in *adjudication*.

## 5. Data-model additions

All additive, lazy-versioned (the repo's §9.4 forward-load contract — every
schema test includes the old-JSON-decodes case):

- `Claim` (§3.1) and `ContinuityFinding` — pure-data structs in `LoomCore`.
- `ContinuityFinding`: `id`, `class`, `severity` (`high`/`medium`/`low`),
  `claimA`, `claimB`, `explanation`, `confidence`, `status`
  (`open`/`dismissed`/`resolved`).
- **`ContinuityAuditStore`** — sidecar JSON at
  `<project>/continuity-audit/audit.json`, exactly parallel to
  [`ProposedEntitiesStore`](Sources/LoomCore/Storage/ProposedEntitiesStore.swift)
  (`load` / `save` / `replaceFindings(forSceneId:)` / `remove`). Claims and
  findings persist here, not in `project.json`.

## 6. Bible Workspace surface

The audit findings surface in the existing WKWebView Bible Workspace, mirroring
the entity-proposal review queue:

- New `auditFindings: [SnapshotAuditFinding]` on
  [`BibleWorkspaceSnapshot`](Sources/LoomCore/Models/BibleWorkspaceSnapshot.swift) —
  each pre-resolves scene titles and both evidence quotes for the webview.
- New intents on [`BibleWorkspaceIntent`](Sources/LoomCore/UI/BibleWorkspaceBridge.swift:125):
  `runContinuityAudit(scope:)`, `dismissAuditFinding(id:)`,
  `resolveAuditFinding(id:)`, and a "jump to scene" navigation intent.
- An `auditingSceneIds` / progress indicator, mirroring the entity-discovery
  amber pulse-dot.
- A finding card: class badge, severity pill, both scene titles + quotes, the
  explanation, and dismiss / resolve / jump affordances.

## 7. Model routing

Extraction and adjudication are *structured* tasks → the Ollama
schema-constrained path ([`OllamaCallProvider`](Sources/LoomCore/Generation/OllamaLedgerExtractor.swift:10)),
not the KoboldCpp writer path. The writer model (Goetia) is a candidate
*adjudicator* only — the spike decides (§11).

## 8. Cost & UX shape

A whole-manuscript audit is N extraction calls (one per scene) + M adjudication
calls (one per retrieved candidate pair). For a 30-scene novella that is ~30 +
(tens of) calls — minutes, not seconds. So: background generation with a
progress indicator (the entity-discovery pattern), on-demand only for v1. The
incremental trigger (Phase D) re-extracts only the changed scene and
re-adjudicates only its affected entities.

## 9. Testing posture

TDD throughout (repo norm — red → green → commit, TestKit). Pure-data layers
(`Claim`, fact-base diffing, `ContinuityFinding`, knowledge-state/timeline
ordering, the store's forward-load) are fully unit-tested. The extraction and
adjudication prompts are tuned on a hand-graded fixture set and probe-validated
against the live model — mirroring `EntityDiscoverySpike`'s empirical
precision/recall/F1 method.

## 10. Phased plan

**Phase A — Spike (de-risk first).** *Before any production commitment.* Build
a CLI probe (à la `EntityDiscoverySpike`). Hand-grade a fixture set of scenes
with deliberately injected contradictions across the four classes. Measure:
(a) per-scene typed-claim extraction quality; (b) pairwise NLI adjudication
precision/recall — the make-or-break number, given CONTRADOC; (c) the
extractor-model vs. Goetia adjudicator A/B. **Gate: if pairwise adjudication
precision cannot clear a usable bar, the feature is rethought or shelved.**

**Phase B — Production engine.** Claim extraction (+ filter pass), subject
resolution, candidate retrieval, adjudication, the deterministic
knowledge-state check, finding assembly, `ContinuityAuditStore`, the engine
orchestrator. Timeline conflicts are folded into retrieval + adjudication
(§3.5); a standalone chronology engine is deferred.

**Phase C — Bible Workspace surface + on-demand trigger.** Snapshot fields,
intents, the finding-card review UI, progress indicator. End-to-end on-demand
audit, in-app.

**Phase B.2 — Spatial / world class.** Added as a fourth claim type once 1–3
are solid; lands last because it is the lowest-precision class and benefits
from the precision lessons of B/C.

**Phase D — Incremental trigger.** Piggyback on
[`LedgerExtractionCoordinator.onExtractionComplete`](Sources/LoomCore/Generation/LedgerExtractionCoordinator.swift:67) —
re-extract the changed scene, re-adjudicate only affected entities.

## 11. Open questions

1. **Adjudicator model** — tiny extractor model vs. Goetia (24B). Resolved by
   the Phase A A/B. A 24B writer may be a much better NLI judge than a 2B
   extractor; cost is the tradeoff.
2. **Flashbacks / non-linear order.** The timeline check assumes `flatSceneIds`
   is chronological. Loom does not model flashbacks
   ([`LedgerKnowledge.swift:33`](Sources/LoomCore/Generation/LedgerKnowledge.swift)
   defers this). v1 either assumes linear order or adds a per-scene
   "story-time" hint. Decide before Phase B timeline work.
3. **Attribute-key normalisation.** "eyes", "eye colour", "her gaze" must
   collapse to one key for the deterministic diff. Controlled vocabulary vs.
   embedding-clustered keys — tune in the spike.
4. **Dialogue-claim scope.** Do we audit consistency *within* a single
   character's dialogue claims (a character contradicting themselves)? Probably
   yes, but lower severity. Confirm in Phase A.
5. **Scope granularity** for on-demand runs — whole manuscript, a Part, a
   chapter range. Whole-manuscript v1; range selection in Phase C if cheap.

## 12. References

- [ConStory-Bench / "Lost in Stories" (arXiv 2603.05890)](https://arxiv.org/abs/2603.05890) —
  the closest blueprint: a 5-category / 19-subtype taxonomy + an automated
  evidence-grounded checker. Errors cluster mid-story and in factual/temporal
  dimensions.
- [ContraDoc (Hsu et al., NAACL 2024)](https://aclanthology.org/2024.naacl-long.362.pdf) —
  GPT-4 ~54% precision on whole-document contradiction judgment; the reason the
  audit must decompose.
- [Re3 (Yang et al., EMNLP 2022)](https://aclanthology.org/2022.emnlp-main.296/) /
  [DOC (ACL 2023)](https://aclanthology.org/2023.acl-long.190.pdf) — entailment-
  based consistency, but generation-time, not post-hoc auditing.
- [FActScore](https://www.emergentmind.com/topics/factscore) /
  [VeriScore](https://arxiv.org/html/2406.19276v1) — decompose → retrieve →
  verify; the atomic-decontextualised-claim recipe.
- [Defeasible NLI (Rudinger et al.)](https://github.com/rudinger/defeasible-nli) —
  reveals as defeaters, not contradictions.
- [SCORE (arXiv 2503.23512)](https://arxiv.org/html/2503.23512v1) — incremental
  story knowledge-graph for persistent memory.
- Commercial scan: [Sudowrite Chapter Continuity](https://docs.sudowrite.com/using-sudowrite/1ow1qkGqof9rtcyGnrWUBS/chapter-continuity/4KL8gFeLZQ6GSBjDWtSbV6),
  [NovelCrafter Codex](https://docs.novelcrafter.com/en/articles/8675743-the-codex),
  [AutoCrit](https://www.autocrit.com/editing/support/tense-consistency/),
  [Marlowe](https://authors.ai/marlowe/).

## 13. Phase A spike results (2026-05-17) — GO

The Phase A spike ran a 6-scene fixture ("The Lighthouse at Greystone",
`Tests/LoomCoreTests/Fixtures/ContinuityAuditSpike/fixture.json`) with planted
errors across all four classes plus precision controls (a lie in dialogue, a
beard→clean-shaven evolution, two paraphrases). 18 gold claims scored
extraction recall; 10 hand-authored gold claim pairs (4 contradiction / 5
consistent / 1 evolution) scored pairwise adjudication. Runner:
`Tools/ContinuityAuditSpike`.

**Adjudication — the make-or-break gate** (contradiction precision / recall /
F1; overall 3-way verdict accuracy):

| adjudicator | precision | recall | F1 | accuracy | false positives |
|---|---|---|---|---|---|
| gemma4_2b | 66% | 50% | 0.57 | 60% | 1 (the dialogue lie) |
| gemma4_4b | 100% | 25% | 0.40 | 70% | 0 |
| **Goetia (24B writer)** | **80%** | **100%** | **0.89** | **90%** | 1 (the dialogue lie) |

Goetia clears the bar decisively — F1 0.89 vs. the ~54%-precision ContraDoc
whole-document baseline, and it caught *every* planted contradiction including
the subtle knowledge-before-reveal pair and the storm-date conflict that both
gemma models missed. The small models fail in opposite ways: gemma4_2b
under-precise, gemma4_4b badly under-recalls (it labels real attribute drift as
"evolution"). **Decision: Goetia is the adjudicator.** Open question §11.1
resolved.

**Extraction** (recall of planted gold claims, schema-constrained Ollama):
gemma4_2b 61%, gemma4_4b 66%. Untuned and mediocre but not a feasibility
blocker — extraction mirrors the proven ledger-extractor pattern (which reached
~92% after tuning). gemma4_4b returned **zero claims for scene 2** — the
known JSON-Schema empty-content failure (`OllamaClient` num_predict note);
needs the retry-on-empty guard.

**The one false positive — and why it is already designed for.** Both
gemma4_2b and Goetia flagged pair p8 — Cole lying in dialogue ("never set foot
in that church") against narration showing he was there. The prompt's
source-attribution rule did not stop it. This is *exactly* the predicted
intended-vs-unintended failure (§4) — and §4 defense #1 already handles it
structurally: in the production pipeline a `dialogue`-sourced claim is not
routed into the world-fact adjudicator at all (it conflicts only with the same
speaker's other claims). The spike adjudicates every pair regardless of source,
so p8 reaching the adjudicator is a spike artefact. Per the
`feedback_prompt_blacklist_evasion` lesson, the fix is structural routing, not
heavier prompt language.

**Phase B follow-ups carried from the spike:**
1. Source-routing must be deterministic and upstream of adjudication — a
   `dialogue`/`thought` claim never adjudicated as a world-fact (kills the p8
   class of false positive).
2. Production extraction must mirror `OllamaLedgerExtractor` — `callWithRetry`
   (retry-on-empty with doubled `num_predict`) + `budgetForSceneWords`. The
   spike runner skipped both, which is why gemma4_4b returned zero claims for
   one scene and extraction recall read low; the proven guards recover that
   case. Then add a `ContinuityClaimFilter` pass — dedup + evidence-quote
   validation — reusing the `LedgerFilters` / `LedgerFilterPipeline` pattern
   (§3.1).
3. Subject grounding (§3.1) — resolve each claim's `subject` to a stable
   entity before retrieval, reusing the bible/alias index and `GLiNERDetector`
   (the NSFW-robust deterministic NER tagger already used for Phase 9
   discovery). Without it, retrieval groups by raw surface string and loses
   conflicts across "Mara" / "she" / "the investigator".
4. Goetia adjudication is ~one call per candidate pair — fold into the §8 cost
   model (background, progress indicator).

## 14. Phase B — production engine (2026-05-18)

Phase B built the whole pipeline, TDD throughout (1755 → 1834 tests). Nine
pure-data / orchestration modules in `Sources/LoomCore/`:

| Module | Role |
|---|---|
| `ContinuityAudit` | claim/verdict types, extraction + adjudication prompts/schemas/parsers (Phase A) |
| `OllamaContinuityExtractor` | production extractor — retry-on-empty + scene-aware budget, mirrors `OllamaLedgerExtractor` |
| `ContinuityClaimFilter` | dedup + evidence-quote validation, mirrors `LedgerFilters` |
| `ContinuitySubjectResolver` | grounds claim subjects to canonical entity names |
| `ContinuityConflictRetrieval` | candidate-pair retrieval; source-routing + type-routing |
| `ContinuityKnowledgeCheck` | deterministic knowledge-before-reveal detection |
| `ContinuityFinding` (+ assembly) | the finding type; verdict/violation → finding |
| `ContinuityAuditEngine` | the orchestrator — extract → ground → retrieve → adjudicate → knowledge-check → store |
| `ContinuityAuditStore` | sidecar persistence; re-audit carries triage status forward |

**Scope decisions taken during the build:**
- **Timeline** folded into retrieval + adjudication (§3.5) — no standalone
  chronology engine in v1.
- **`ContinuityClaimFilter` is built and unit-tested but not yet wired into
  the engine** — it needs a live embedder; the async embed orchestration is
  the remaining Phase-B-tail wire-up (mirror `LedgerFilterPipeline`).

**Not yet done:** a live end-to-end run of `ContinuityAuditEngine` against the
real models (extraction on Ollama, adjudication on Goetia) — the engine is
stub-smoke-tested only. That live pass + the filter wire-up close Phase B
before Phase C (the Bible Workspace surface).

## 15. Extraction tuning — research + model A/B (2026-05-18)

After the Phase B engine landed, an extraction-quality pass: prior-art
research on alternatives to a generative LLM, plus a model A/B for the
claim extractor.

**Prior-art research — alternatives to generative extraction.** Verdict:
do **not** bolt on classic IE.

- OpenIE, Semantic Role Labeling, REBEL-style relation extraction, AMR,
  spaCy SVO triples — all trained/benchmarked on news/encyclopedic text,
  all collapse on dialogue and interiority, none emits a *typed* claim with
  source attribution. They would lower recall on fiction. NER-family
  approaches are genuinely the wrong shape (confirms the GLiNER-for-claims
  rejection).
- The real match is **claim decomposition** from the fact-verification
  literature — Microsoft's **Claimify** (select claim-bearing sentences →
  decompose into atomic claims → abstain on ambiguous ones), VeriScore
  (benchmarked on fiction). But every published system still does *type*
  classification as a separate LLM judgment — typing is not free.
- Reliable constrained decoding (GBNF, XGrammar, llguidance) lives in
  llama.cpp / KoboldCpp, **not** Ollama, whose `format` schema is leaky by
  design. Available as a future hardening; the unconstrained + re-roll path
  already removed the structural flake empirically.

**Model A/B — claim extraction** (6-scene fixture, recall of planted gold
claims; "content" = type-agnostic, "typed" = type must also match):

| extractor | content recall | typed recall |
|---|---|---|
| gemma4_2b, single-stage | 77% | 61% |
| gemma4_2b, two-stage typing | 72% | 61% |
| Goetia 24B, single-stage | 83% | 55% |
| **Goetia 24B, two-stage typing** | **83%** | **72%** |

The two-stage typing pass lifts typed recall **+17 points on Goetia**
(55→72%) and is flat on gemma4_2b — a 2B model is too weak even for the
focused typing call. **Decision: claim extraction runs on Goetia 24B,
two-stage.** n=1 per cell (generation is stochastic); a few more runs
would firm the numbers, but the direction is consistent with the research.

## 16. Engine end-to-end validation (2026-05-18)

`ContinuityAuditSpike` gained an `engine` phase that drives the full
`ContinuityAuditEngine` (extraction + adjudication on Goetia) over the
6-scene fixture. First live run:

- **6 scenes audited in 183s; 3 findings; zero false positives.**
- Caught the planted **attribute drift** (Mara's eyes green s1/s2 → brown
  s3 — two findings, conf 0.95) and the **spatial conflict** (lighthouse
  north s1 vs south s6 — conf 1.00).
- The precision controls held — the dialogue lie, the beard→clean-shaven
  evolution, and the paraphrases produced **no spurious findings**.

This validates the pipeline end to end — the architecture and plumbing
are sound, not just stub-tested.

**Two planted contradictions were missed**, both explained and both
mapping to known tuning items:
- **Temporal** (the storm dated two ways) — extraction did not surface
  both temporal claims about the storm, or did not type them `temporal`;
  a retrieval pair never formed. → extraction-recall tuning.
- **Knowledge-state** (Mara references the missing money before its
  reveal) — the engine's knowledge check ran on the crude `tokenJaccard`
  fallback similarity, which fell just short of the match threshold. →
  the `ContinuityClaimFilter` embedder wire-up gives the knowledge check
  an embedding-backed similarity, which should close this.

So Phase B is live-validated. The remaining Phase-B-tail items — the
embedder wire-up and extraction-recall tuning — are exactly what would
lift the 2/4 class coverage; neither is a correctness defect.

## 17. Embedder wire-up — validation surfaced a knowledge-check precision gap (2026-05-18)

`ContinuityClaimFilterPipeline` (dedup + per-scene evidence validation,
batched embed, fail-soft) was built and wired into `ContinuityAuditEngine`
as an optional embedder; the engine also derives an embedding-backed
cosine similarity for the knowledge check from the same vectors.

End-to-end re-run (Goetia extraction/adjudication + bge-large embedder):
**5 findings** — the 2 genuine attribute-drift findings, the genuine
knowledge violation (p3, money-before-reveal — now caught, the prior miss
closed), **but 2 false-positive knowledge violations**.

The false positives expose a real design gap: the knowledge check is
**deterministic** — a similarity match directly emits a finding, with no
adjudicator in the loop. Raw sentence-embedding cosine is too loose for
proposition matching:

- "Cole knew Mara was sent by someone" (s2) was matched to "Mara crossed
  to Cole" (s4) — unrelated propositions that merely share the same two
  characters.
- "Mara knew the keeper lost a brother" (s2) was flagged against Innes
  restating it in s3 — but Mara *learns* it from Cole in s2; the genuine
  s2 reveal was not matched as the earliest reveal.

**Conclusion:** the deterministic knowledge check needs hardening. The
options: (a) a much tighter similarity threshold (cheap, but won't fix
the same-topic FP2); (b) route knowledge-violation *candidates* through
the existing adjudicator — the LLM judges "does claim B genuinely reveal
what A references, before A references it" — which fits the §3 "LLM
adjudicates, deterministic narrows" architecture and would reject both
FPs. (b) is the robust fix and is the recommended next step. Attribute
drift and adjudicated classes are unaffected — they already route
through the adjudicator and stayed clean.

## 18. Knowledge-adjudication routing — resolved (2026-05-18)

The §17 false positives were fixed by routing knowledge-violation
candidates through the adjudicator (the §3 "LLM adjudicates,
deterministic narrows" architecture): the knowledge check now emits
*candidates*, each judged by an LLM call before becoming a finding.

The adjudication question matters. A first prompt asked "is this a
genuine continuity error" with a "could plausibly already know it"
escape hatch — too conservative: the end-to-end run rejected all three
candidates including the genuine one (0 knowledge findings). Reframed
to the narrow question the claim pair can actually answer — *does the
LATER claim reveal the same fact the EARLIER claim refers to?* The
ordering is already deterministic; an earlier reveal, if one exists,
is extraction's job to surface.

End-to-end re-run (Goetia + bge-large, reframed prompt) — **4 findings,
zero false positives:**

- attribute drift ×2 (eye colour green→brown) ✓
- spatial conflict (lighthouse north vs south) ✓
- knowledge violation (Mara knows the missing money before its reveal) ✓
- both §17 false positives gone.

**3 of the 4 planted contradiction classes now detected cleanly, no
false positives.** The one remaining miss is the temporal class (the
storm dated two ways) — extraction did not surface both temporal
storm claims, so no candidate pair formed. That is the documented
extraction-recall tuning item (§16), not a pipeline defect.

Phase B is complete and validated. Remaining before Phase C:
extraction-recall tuning (would close the temporal miss).

## 19. End-to-end behaviour is stochastic — honest assessment (2026-05-18)

Repeated end-to-end runs after §18 give a more honest picture than the
single clean "§18: 4 findings, 0 FP" run, which was a good roll, not the
stable state. Across four engine runs on the 6-scene fixture:

- **Eye-colour drift** — caught every run (the prototypical attribute case).
- **Spatial / temporal conflicts** — caught in *some* runs, missed in
  others. The cause is extraction recall: a contradiction is only found
  when **both** of its claims are extracted *in the same run*, and per-run
  extraction recall is ~83% and varies. The temporal extraction fix (§16
  follow-up — decompose time-anchored sentences; commit `4f3b732`) is
  correct and dump-verified (extraction now emits `temporal` storm claims),
  but a given run can still miss it if a claim does not surface.
- **False positives** — two seen and addressed/diagnosed:
  - *Conjunction* — "wind smelled of salt" vs "woodsmoke" from one scene's
    "a wind that smelled of salt and woodsmoke". **Fixed** (`8bf3d26`):
    retrieval now pairs cross-scene only — the audit is about drift across
    scenes; a same-scene pair is far more often a conjunction.
  - *Knowledge FP2* — "Mara filed away that the keeper lost a brother" (s2,
    where Cole tells her) flagged against Innes restating it (s3). Root
    cause: extraction did not surface the s2 reveal event, so the earliest
    matched reveal was s3. An extraction-completeness gap, not a pipeline
    defect.

**Assessment.** The pipeline is architecturally sound and every component
is unit-tested (1855 tests green); end to end it genuinely surfaces real
contradictions. But it is **not yet polished** — per-run coverage is
stochastic and precision is imperfect. Reaching production quality needs
sustained tuning of extraction recall + consistency (the dominant lever)
and a few precision refinements. This is honest ongoing work, not a quick
fix. The feature is a usable review aid in its current state — re-running
an audit improves coverage — but should be presented as such, not as
exhaustive.

## 20. Open problems — research targets for the next session

The pipeline is built and sound; the gap to production quality is recall +
consistency, not architecture. Concrete open problems, in priority order —
**the next session should research each widely (prior art, papers, other
tools, fine-tuning options) before tuning blindly:**

1. **Per-scene extraction recall (~83%) and its run-to-run variance — the
   dominant problem.** A contradiction is found only when *both* its claims
   are extracted in the same run; at ~83% per-claim recall that is ~69% per
   contradiction, and it varies. Research: claim/proposition-extraction
   recall techniques; multi-sample / self-consistency / ensemble extraction
   (run extraction k times, union the claims); whether a small purpose-built
   or fine-tuned extraction model beats prompting a 24B; the Claimify
   pipeline applied more fully (select → decompose → classify); reliable
   constrained decoding (GBNF / XGrammar on KoboldCpp) for structural
   guarantees without the Ollama flake.
2. **Type-classification accuracy.** Two-stage typing helped (typed recall
   55→72% on Goetia) but a gap remains, and `type` drives retrieval
   routing. Research: whether the 5-type taxonomy itself is too brittle
   (attribute vs event is genuinely ambiguous); a tighter taxonomy; or
   constrained-enum classification.
3. **Knowledge-check reveal-completeness (FP2).** A knowledge violation is
   mis-flagged when extraction fails to surface the *earliest* reveal event
   (the character is shown learning the fact, but that event claim is
   missed). Tied to problem 1, but also: should the knowledge check be more
   conservative, or use scene-text context in adjudication?
4. **Making a single on-demand audit trustworthy despite stochastic
   extraction.** Research: is the answer multi-run aggregation, a confidence
   floor, or surfacing "low-confidence / re-run for coverage" to the user?

A proper **eval harness** (a larger hand-graded fixture than the current
6-scene one, multi-run averaging, precision/recall tracked over runs) is a
prerequisite for tuning any of this without dice-rolling — building it is
likely the first concrete step after the research.

## 21. §20 research findings + chosen approach (2026-05-18)

A wide prior-art pass on the §20 open problems (four parallel research
agents — claim-extraction recall, multi-sample ensembling, constrained
decoding / fine-tuning, comparable systems + eval design). Findings:

**Loom's numbers are field-normal.** ConStory-Checker (*Lost in Stories*,
ACL 2026, [arXiv 2603.05890](https://arxiv.org/abs/2603.05890)) is
architecturally identical to Loom's pipeline and reports precision 0.88 /
**recall 0.55** / F1 0.68. Loom's ~83% extraction recall is *ahead* of the
published norm — recall is the hard part for everyone. No published claim-
extraction method even reports a true decomposition-recall figure against a
human gold set, so the measured 83% is more honest than most of the
literature.

**Problem 1 (recall + run-to-run variance) — multi-sample union extraction.**
Run extraction k times, union the claims. Reliably lifts recall; the
recall-vs-k curve saturates log-linearly — predictable diminishing returns
(*Large Language Monkeys* 2024; L3X "Recall Them All" 2024). Attacks the
17% miss rate *and* its variance in one move. Cost: the unioned claim set's
precision collapses (L3X saw ~10%), so union must be paired with a
verification stage — Loom already has one (retrieval + pairwise
adjudication filters junk claims downstream). Supporting single-pass lever:
per-sentence windowed extraction (Claimify/VeriScore — walk the scene
sentence-by-sentence with a ±context window). Do **not** chase finer/atomic
claims — *Decomposition Dilemmas* (NAACL 2025) shows granular decomposition
shifts from helpful to harmful; it fragments and lowers effective recall.

**Problem 4 (single-audit trust) — capture-recapture / Chao1.** The Chao1
estimator computes undetected items from the k runs themselves, no ground
truth: `missing ≈ f₁²/(2·f₂)` (f₁ = claims seen in exactly one run, f₂ =
in exactly two). Validated as a search-stopping rule by Kastner et al.
(2009). Gives Loom a user-facing completeness estimate ("~92% complete;
re-run for coverage") and a principled adaptive-stopping rule (k≈3–5
typically saturates per scene). Requires good claim canonicalization —
the same proposition phrased differently inflates f₁; Loom's embedder /
cosine-dedup infrastructure covers this.

**Problem 2 (type classification) — GBNF constrained decoding on KoboldCpp.**
Constrain JSON *structure* + the 5-value `type` enum only, leave proposition
values as free strings, with an optional free-text reasoning field *first*
per record (the CRANE pattern — avoids the reasoning-degradation hit shown
by *Let Me Speak Freely?*). Constrained classification genuinely improves
accuracy (5–13 F1 points in IE studies) on the format-noise slice. Low-risk,
independent change.

**Deferred (researched, not now):** fine-tuning a small extraction model
(feasible — cloud QLoRA, Xcode not needed — but a rabbit hole before a
clean gold set exists; the off-the-shelf Propositionizer is wrong domain);
a SCORE-style incremental world-state ledger as a deterministic second
detector (promising, larger architectural change — revisit after step 2).

**Chosen approach (user-confirmed 2026-05-18) — three-step sequence:**

1. **Eval harness + medium fixture.** Extend the Lighthouse fixture to
   ~3–4 manuscripts / ~40–60 contradiction instances (single grader).
   Multi-run audits (k≥10), report mean±CI and **pass@k vs pass^k** (the
   gap is the stochasticity tax). Stage-conditioned metrics — per-claim
   extraction recall → retrieval recall@candidate → adjudication P/R →
   end-to-end finding P/R — so a regression localizes to a stage.
2. **Multi-sample union extraction + Chao1.** Extract k times, canonicalize
   /dedup (existing embedder), union, Chao1 adaptive stopping + a
   user-facing completeness estimate.
3. **GBNF constrained decoding** for structure + type enum (CRANE pattern).

Re-measure after each step; revisit fine-tuning / the state-ledger only if
still short. Step 1 (the eval harness) is the prerequisite for tuning
steps 2–3 without dice-rolling.

**Key sources:** [Claimify, ACL 2025](https://aclanthology.org/2025.acl-long.348.pdf) ·
[VeriScore, EMNLP 2024](https://arxiv.org/html/2406.19276v1) ·
[Decomposition Dilemmas, NAACL 2025](https://arxiv.org/abs/2411.02400) ·
[Large Language Monkeys, 2024](https://arxiv.org/abs/2407.21787) ·
[L3X "Recall Them All", 2024](https://arxiv.org/html/2405.02732v1) ·
[Chao1 / capture-recapture stopping rule, Kastner et al. 2009](https://www.sciencedirect.com/science/article/abs/pii/S0895435608001509) ·
[Let Me Speak Freely?, EMNLP 2024](https://arxiv.org/html/2408.02442v1) ·
[CRANE, 2025](https://arxiv.org/html/2502.09061v3) ·
[Lost in Stories / ConStory-Bench, ACL 2026](https://arxiv.org/abs/2603.05890) ·
[SCORE, 2025](https://arxiv.org/abs/2503.23512) ·
[Stochasticity in Agentic Evaluations, 2025](https://arxiv.org/html/2512.06710v1).

## 22. Eval harness + retrieval/filter tuning — results (2026-05-19)

§21's step 1 (the eval harness) was built and then used to diagnose and
tune the engine. Summary of the work and the definitive numbers.

**The eval harness.** `ContinuityEvalMetrics` (LoomCore, pure-data, 26
tests) — stage-conditioned scoring: extraction recall, adjudication
P/R/F1, end-to-end finding P/R, multi-run aggregation (mean ± CI,
pass@k / pass^k), Chao1 coverage. A medium fixture set —
`Tests/LoomCoreTests/Fixtures/ContinuityAuditEval/`, four manuscripts
(Lighthouse + three new: sci-fi, fantasy, thriller), **40 planted
contradictions**, 111 gold claims, 58 gold pairs, each contradiction
tagged `kind` + `scene_distance`. An `eval` phase on
`ContinuityAuditSpike` drives the set k times (extraction mode or full
engine mode) and scores it.

**Baseline + diagnosis.** The first engine baseline measured end-to-end
finding recall at **17%** against ~84% per-scene extraction recall — a
~67-point collapse. `DebugLog` stage counts localised it: (a) the
claim-filter's evidence validation dropped ~80 of ~200 claims/audit —
short verbatim quotes embed far from the long sentences containing
them, so a cosine-only check false-dropped them; (b) retrieval formed
only 2–7 candidate pairs/audit — exact `(type, subject)` keying never
matched when the model drifted a claim's subject or type.

**Fixes (all TDD, committed).**
1. Eval matcher — stem before word-Jaccard (inflectional variants were
   scored as extraction misses).
2. `ContinuityConflictRetrieval` — cluster by **value similarity**
   (injected closure) instead of an exact `(type, subject)` key;
   type-tolerant, drift-tolerant; `event` claims now pairable.
3. `ContinuityClaimFilter.validateEvidence` — verbatim-substring check
   first; the cosine fallback applies only to non-verbatim quotes.
   Evidence drops fell from ~80 to ~4 per audit.
4. Engine wires the embedding-backed similarity into retrieval
   (cosine threshold 0.7); candidate pairs rose from 2–7 to ~100.
5. Speaker-aware dialogue routing — claims carry a `speaker`; two
   dialogue claims pair when they share a speaker (a character
   contradicting themselves), never with narration.

**Definitive k=10 engine eval (2026-05-19):**

| metric | value |
|---|---|
| finding recall | **35% ±4** |
| finding precision | **75% ±7** |
| F1 | 0.46 |
| pass@k — caught in ≥1 of 10 runs | **26/40 (65%)** |
| pass^k — caught in every run | 3/40 |

Per-run finding recall roughly **doubled** (≈17% → 35%) — the durable
gain is the evidence-filter and retrieval-embedding fixes, both
stage-count-verified. The k=3 runs along the way (19% / 45% / 35%) had
CIs too wide to trust individually; k=10 (±4) is the real figure.

**Honest state + open problems.**
- **pass@k 26/40 (65%)** vs 35% per run — re-running an audit ~doubles
  coverage. This empirically supports the §21 multi-sample-aggregation
  direction (run k times, union findings, Chao1 completeness).
- **`knowledge_violation` ≈ 8%** — nearly non-functional; needs its own
  diagnosis.
- **~14 of 40 contradictions never caught in 10 runs** — a hard floor
  from extraction (both claims must surface together) and from
  divergent claim phrasing that even embedding clustering misses.
- **Dialogue routing showed no measurable gain** — the code is correct
  and tested, but the extractor does not label `speaker` reliably or
  consistently enough for same-speaker pairs to form. Revisit only with
  a more reliable speaker signal.
- Precision 75%; `tuesday_account` (44%) is the outlier — more
  candidate pairs since the retrieval rewrite means more false
  findings reach the adjudicator.

Next levers, unprioritised: multi-sample union extraction + Chao1
(§21 step 2 — now empirically motivated by pass@k); the
`knowledge_violation` collapse; precision recovery (retrieval cosine
threshold / adjudication); GBNF constrained decoding (§21 step 3).

## 23. `knowledge_violation` diagnosis (2026-05-19)

The k=10 eval put `knowledge_violation` detection at **8%** — effectively
non-functional, and it is the audit's differentiator class (§0). A
code-level diagnosis (no fix applied yet):

**Cause A — type-gating (confirmed, structural).**
`ContinuityKnowledgeCheck.violations` filters
`reveals = claims.filter { $0.type == .event }` and only considers
claims typed `knowledge_state` as references. Type classification is
~62% reliable (§15). So whenever the model types the *reveal* as
`attribute` / `temporal` instead of `event`, or types the *reference*
as anything but `knowledge_state`, the claim is invisible to the check
— a candidate never forms. This is the *same* exact-type brittleness
the §22 retrieval rewrite removed from the world-fact path, still
present on the knowledge path. (A mistyped knowledge reference is also
lost twice: the knowledge check needs `knowledge_state`, and the
value-clustering retrieval explicitly *excludes* `knowledge_state`.)

**Cause B — similarity threshold / framing (hypothesis).** The check
matches a reference to a reveal at cosine `>= 0.7`. A knowledge claim
("X knows / references P", often verbose) and its reveal ("P", terse,
plainly asserted) are deliberately *differently framed*, so their
embedding cosine can sit below 0.7 even when they concern the same
fact. Needs verification when this is tuned.

The check is a long conjunction — reference extracted + typed
`knowledge_state` + reveal extracted + typed `event` + cosine ≥ 0.7 +
reveal-after-reference ordering + adjudicator returns `contradiction` —
seven conditions, several probabilistic; their product lands near the
observed 8%.

**Recommended fix.** Apply the §22 philosophy to the knowledge path:
do not gate on the unreliable `type` label. Treat *any* non-reference
claim as a candidate reveal (matched by proposition similarity, not by
`type == .event`); retune or lower the threshold, or match on a
normalised proposition; let the adjudicator be the precision gate. The
ordering rule (reveal scene after reference scene) and the
adjudication step stay. TDD against the four `knowledge_violation`
contradictions in the eval fixture set.

## 24. `knowledge_violation` fix campaign + model A/B (2026-05-19)

§23's diagnosis was acted on. The knowledge path was rebuilt with seven
TDD fixes, the writer model was A/B'd against alternatives, and two
load-bearing assumptions were *measured* rather than guessed. Net
result: `knowledge_violation` went from **0/4 → 3/4** on the eval
fixtures. This section records the campaign and the honest ceiling it
reached.

**Seven pipeline fixes (all TDD, committed `07f07e8`…`7bda335`).**
1. **Type-tolerant reveal matching** — the reveal side no longer gates
   on `type == .event`; any non-`knowledge_state` claim is a candidate
   reveal. (§23 cause A.)
2. **No fuzzy-early-match veto** — the check picked the *globally*
   earliest matching reveal then required it to be after the reference;
   a topically-related claim in an early scene became the "earliest
   reveal" and silently cleared the violation. Now only reveals strictly
   *after* the reference scene are considered.
3. **Match threshold 0.55 → 0.70** — §23 hypothesised real
   reference→reveal cosines sit below 0.7; direct measurement disproved
   it (real reveals 0.73–0.94, unrelated junk below 0.70). 0.55 flooded
   the adjudicator with noise.
4. **Task-fit verdict vocabulary** — a knowledge-before-reveal error has
   the two claims *agreeing* about the fact, so it is not a logical
   "contradiction"; reusing the `{contradiction, consistent}` enum made
   the model map two agreeing claims to "consistent". A direct probe
   showed the model recognised the same fact yet returned `consistent`
   5/6 and 6/6 on real violations. A `KnowledgeVerdict {violation,
   not_a_violation}` vocabulary (own schema, parser, prompt) flipped the
   probe to 6/6, 3/6, 6/6.
5. **Knowledge-specific schema + parser** — `knowledgeAdjudication`
   path, separate from the world-fact `Adjudication`.
6. **Scene-prose adjudication context** — the adjudicator now sees a
   window of each claim's real scene prose, not two stripped one-line
   claims (see the decisive measurement below).
7. **Trivial-reference filter** — drops negated references ("X does not
   know P") and bare topic-awareness ("X knows about the lighthouse" —
   a topic, not a proposition) before candidate formation.

Plus two infra fixes: the `ContinuityAuditSpike` eval harness now
detects the instruct template from the loaded model name (so a
model-vs-model A/B is fair), and `InstructTemplates.detect` now maps
stock Mistral-Small-3.x (2501/2503/2506) to V7 Tekken.

**Model A/B (k=1 screens, eval harness).** The writer model is Goetia
(Mistral-Small-3 24B). Alternatives were tested for the audit task:

| model | recall | precision | knowledge | attribute |
|---|---|---|---|---|
| Goetia 24B (writer) | 33% | 59% | 0/4 | 38% |
| Qwen3.6-27B *(RP finetune)* | 23% | 63% | 0/4 | 25% |
| Mistral-Small-24B abliterated | 44% | 57% | 1/4 | 31% |
| **Gemma-4-31B abliterated** | **46%** | 43% | **3/4** | **56%** |

A roleplay/uncensored finetune (Qwen3.6 "HauhauCS") was *worst* — RP
tuning sacrifices instruction-following. Abliterated *instruct* models
(refusals removed, reasoning intact) are the right class; Gemma-4-31B
abliterated clearly won on `knowledge_violation` and `attribute_drift`.
Uncensored matters because the manuscripts contain explicit/dark
fiction — a refusing model degrades extraction.

**Two decisive measurements (proven, not guessed).**
- **Embedding cosine cannot separate a real knowledge violation from a
  topical look-alike.** The two real pairs measured at 0.73 and 0.78;
  five junk pairs scored *higher*, up to 0.83 (a junk pair sharing a
  noun phrase out-scores a real violation). So the candidate set is
  irreducibly topically-noisy — no similarity threshold cleans it, and
  discrimination *must* be the adjudicator's job. This motivated fix 6.
- **The adjudicator returns no usable confidence signal.** Abliterated
  Gemma-4-31B reported `confidence: 1.0` on every probe call — real and
  junk alike. A confidence floor is not possible.

**Result (k=1, all four manuscripts).** Gemma-4-31B + the seven fixes:
finding recall **46%**, precision **43%**, `knowledge_violation`
**3/4** (lighthouse c2, ash_court c11, tuesday c11 caught; long_watch
c7 missed), `attribute_drift` **56%**. Versus §22's k=10 baseline
(recall 35%, knowledge ~8%) this is a real gain on the differentiator
class — but every number here is **k=1 and noisy** (recall CI ±~24); a
k=3+ definitive run has not been done.

**Honest ceiling.** The knowledge path is no longer structurally broken
(candidates form; the adjudicator is willing and correctly framed; it
catches 3/4). The remaining cost is precision: of ~12 junk knowledge
candidates per run the adjudicator wrongly stamps ~6 `violation`, of
which ~2–3 are actually genuine same-fact pairs the eval fixture did
not plant (fixture-completeness, cf. §19 FP2) and ~3–4 are real topical
errors. There is **no remaining clean lever**: candidate quality can't
be filtered by similarity (proven), the references are bare facts
indistinguishable from real ones by surface form or type, and there is
no confidence signal. This is roughly the floor for a local model on
genuine topical disambiguation. Further gains need either a better
adjudication architecture or a stronger model — a broad research sweep
is the chosen next step.

## 25. Research sweep + chosen rearchitecture (2026-05-19)

A three-agent prior-art sweep, briefed with §24's measured findings,
was run on: (a) proposition matching beyond embedding cosine, (b)
world-state tracking for the knowledge class, (c) LLM adjudication
quality. All three independently pointed *away* from further tuning of
the embedding-retrieval + pairwise-adjudication pipeline.

**Key findings.**
- **Embedding cosine is a bi-encoder — it scores topic, not
  proposition.** A *cross-encoder* scores a pair jointly. NLI
  cross-encoders additionally emit a `neutral` class that is exactly
  "same topic, different proposition" — the §24 junk. Small DeBERTa-v3
  NLI models (~400M) are the state of the art and run locally.
- **`knowledge_violation` is a state-membership question** ("had fact P
  entered character C's knowledge by scene N?"), not a similarity
  question — which is *why* embedding retrieval fails on it. Prior art
  (SCORE, EvolvTrip, EnigmaToM) tracks an incremental world-state.
  Loom already built the machinery — `LedgerKnowledge` derives
  per-character known facts by scene.
- The verbalised-confidence dead end (§24) has a known fix — a linear
  probe on adjudicator hidden states — but it is more involved;
  deferred.

**Chosen approach (user-confirmed 2026-05-19) — two parts, A before B.**

*Part A — NLI cross-encoder proposition gate.* Export a DeBERTa-v3 NLI
model to ONNX (Loom already links ONNX Runtime for GLiNER, and GLiNER
already ships the DeBERTa-v3 tokenizer — the runtime precedent is
near-identical). A new `NLIRuntime` / `NLICrossEncoder` scores each
candidate claim pair; `ContinuityConflictRetrieval` and
`ContinuityKnowledgeCheck` keep embedding retrieval for recall, then
drop any pair the NLI scores `neutral`. Step A0 is a de-risk probe —
run the model on §24's measured junk/real pairs and confirm `neutral`
separates them before integrating.

*Part B — world-state fact ledger for `knowledge_violation`.* Replace
pairwise reference↔reveal matching with canonical fact nodes: walk
non-knowledge claims in scene order, cluster those asserting the same
proposition (using Part A's NLI scorer for proposition identity, not
cosine) into fact nodes with a `firstAppearanceScene`; a
`knowledge_state` reference at scene N is a violation when its fact
node first appears after N. The LLM adjudicator becomes a confirmation
backstop. Phase 2 (B3, deferred): per-character knowledge via
`ScenePresence` + an off-page knowledge-transfer extraction pass —
larger, couples the audit to the Bible model.

Sequencing: A0 → A1–A4 → re-eval → B1–B2 → re-eval → decide on B3.

**Key sources:** [Atomic-SNLI 2026](https://arxiv.org/html/2601.06528v1) ·
[MoritzLaurer DeBERTa-v3 zeroshot-v2.0](https://huggingface.co/MoritzLaurer/deberta-v3-large-zeroshot-v2.0) ·
[SCORE 2025](https://arxiv.org/html/2503.23512v1) ·
[EvolvTrip 2025](https://arxiv.org/abs/2506.13641) ·
[EnigmaToM 2025](https://arxiv.org/pdf/2503.03340) ·
[Calibrating LLM Judges — linear probes](https://arxiv.org/html/2512.22245v1) ·
[Auto-Prompt Ensemble for LLM Judge](https://arxiv.org/abs/2510.06538).

## 26. Part A built and ripped out — NLI gate is a negative result (2026-05-20)

§25's Part A (the DeBERTa-v3 NLI cross-encoder proposition gate) was
built end-to-end, integrated, TDD'd, and measured. It does **not** lift
the audit's numbers. The infrastructure has been removed; this section
records the chain of evidence so the lesson is preserved.

**Build (committed then reverted).** A0 export tooling (`Tools/NLIProbe/`),
A1 ONNX bundle (FP32 — INT8 quantization flipped DeBERTa-v3 verdicts,
verified), A2 `NLIRuntime` (ONNX session, mirroring `GLiNERRuntime`),
A3 `NLICrossEncoder` (pair tokenisation byte-for-byte matched to Python
via fixture; softmax decode reading `id2label` from `config.json`),
A4 `ContinuityAuditEngine.worldFactPairFilter` + spike wiring. All
phases passed their unit tests cleanly.

**A0 probe — green on gold strings.** The de-risk probe scored
NLI(`value_a`, `value_b`) on the eval fixture's 36 non-knowledge gold
contradictions: **34/36 flagged `contradiction`**, every clearly-unrelated
pair flagged `neutral`. That looked like a clean go.

**End-to-end measurement — not a win.**

| metric | Gemma-4-31B no gate (k=1) | label-based gate (k=1) | prob-based gate (k=3) |
|---|---|---|---|
| recall | 46% | 44% | **40% ±12** |
| precision | 43% | 40% | **38% ±7** |
| F1 | 0.42 | 0.40 | 0.37 |
| attribute_drift | 56% | 44% | 50% |
| timeline_conflict | 20% | 10% | 17% |
| spatial_conflict | 20% | 40% | 20% |

Tightening the threshold (label → probability-based, `neutralMax = 0.7`)
helped `attribute_drift` (44% → 50%) but the overall picture stayed
flat or worse than no gate. k=3 narrows CIs enough (±7 precision)
to trust the negative read.

**Why the A0 green didn't translate.** A0 scored *gold canonical*
strings — `"the vault is on the fourteenth floor"` vs `"the vault is on
the ninth floor"`. The audit feeds NLI the *extracted* claims, which
are paraphrases the LLM produced from prose. NLI's strict logical-
entailment frame is narrower than "same proposition / contradicts": a
genuine attribute contradiction phrased as paraphrase often comes back
`neutral` because neither side strictly entails the other under
classical NLI semantics. A0 measured the model's *capability* on clean
inputs; it did not measure its *behaviour* on noisy extraction output —
that distinction was not visible from the probe.

**Disposition (user-confirmed 2026-05-20).** Ripped out the gate — the
engine `worldFactPairFilter`, the `NLICrossEncoder` / `NLIRuntime`
sources and tests, the tokenizer fixture, `Tools/NLIProbe/`, the
`Resources/NLI` bundle entry, and the spike wiring. The methodology —
probe-then-measure with the model's actual behaviour on actual inputs —
stays. Part B (world-state fact ledger for `knowledge_violation`) is
the remaining direction from §25.

**Open lesson.** A *capability* probe is necessary but not sufficient.
Whenever a research-driven component sits downstream of a noisy
production stage, the de-risk has to use the noisy stage's actual
output, not the clean reference data — otherwise the probe answers a
question the production pipeline never asks.

## 27. Same-fact judgment probe — GO for Part B (2026-05-20)

§25 Part B needs a proposition-identity primitive to cluster extracted
claims into canonical fact nodes. Embedding cosine fails on this (§24)
and NLI fails on this (§26), so the remaining direction is to ask the
LLM directly: *"do these two claims assert the same specific
proposition?"* §24's `KnowledgeVerdict` work already gave us a
template — task-fit vocabulary, JSON schema, tolerant parser — and a
weak prior that the model handles same-fact judgment on extracted
claims (the knowledge adjudicator caught 3/4 on the eval).

This time the probe was designed under §26's open lesson: feed the
*production stage's actual noisy output*, not gold reference strings.

**Build (TDD, committed).** A `SameFactVerdict {same_fact,
different_fact}` enum, `buildSameFactPrompt(claimA, claimB)`,
`sameFactJSONSchema`, `parseSameFact`. 10 unit tests added (2032/2032
passing). A spike `phase=probe` runs k=3 extraction on one eval
manuscript through the production extractor, labels pairs mechanically
against the gold contradictions (within-cluster = `same_fact`,
cross-cluster at the same gold site = `different_fact` — same Jaccard
≥ 0.34 the eval matcher uses), runs the same-fact prompt on each pair,
and reports a 2×2 confusion.

**Probe — lighthouse, Gemma-4-31B abliterated, 58 pairs.**

| label \ pred | same_fact | different_fact |
|---|---|---|
| same_fact (n=25) | 19 | 6 |
| different_fact (n=33) | **0** | **33** |

- **0/33 false same-fact clusterings on the topical-noise pairs.**
  This is the §24 failure case (junk pairs scoring 0.83 above real
  pairs at 0.73) and the §26 failure case (NLI returning `neutral` on
  paraphrases). The same-fact prompt is the first method in the entire
  campaign to clear it.
- **19/25 same-fact agreement at first glance, but the 6 "misses" are
  the model fixing the labels.** Every miss is `"Mara's eyes were
  brown"` vs `"Mara's eyes were steady"` — same subject, same surface
  form, *different propositions* (eye colour vs. eye demeanor). The
  mechanical labeller's word-Jaccard sees the shared "Mara"/"eyes"
  and clusters them; the model correctly returns `different_fact` at
  confidence 1.0 with explanations like *"color vs. quality/manner."*
  Real same-fact agreement is 19/19 = 100% on genuine paraphrases.

**Disposition — GO.** This is the cleanest signal across the
§24–§26 campaign on the proposition-identity problem. Build Part B
with `SameFactVerdict` as the canonicalisation primitive: walk
non-knowledge claims in scene order, single-pass online clustering
("does this claim assert the same proposition as any existing fact
node's representative?"), create a new fact node on no match, attach
`firstAppearanceScene` to each node. A `knowledge_state` reference
at scene N becomes a violation when its fact node's
`firstAppearanceScene` is later than N. The LLM adjudicator becomes a
confirmation backstop (not the load-bearing precision gate it has been
since §24).

**Caveats.** k=1, lighthouse only — 25+33 pairs is small. The
uniformity of the negative result (0/33 false merges) is the strongest
signal; same-fact recall has wider CIs and warrants confirmation on
another manuscript once Part B is built. The 6 mechanical-label errors
also mean the eval matcher's Jaccard threshold isn't itself a
proposition-identity test — Part B's clustering will need to use the
LLM's verdict, not Jaccard, for the actual fact-ledger construction.

**Probe outputs.** `Tools/ContinuityAuditSpike/probe/{claims.json,
pairs.json, results.json, report.md}`.

**Model comparison — Goetia 24B (2026-05-20).** The same probe was
re-run against Goetia (Mistral-Small-3 24B, the writer model already
loaded for prose generation), to test whether canonicalisation can use
the writer's model and avoid a Gemma/Goetia swap during an audit.

| model | same_fact | different_fact | real same-fact accuracy |
|---|---|---|---|
| Gemma-4-31B abliterated | 19/25 (76%) | 33/33 (100%) | 19/19 (100%) |
| Goetia 24B v1.3 | 20/25 (80%) | 33/33 (100%) | 20/20 (100%) |

Goetia's 5 same-fact "misses" are again all model-fixes-the-labels:
e.g. `"Mara moved her green eyes over the boats"` (an action that
mentions eye colour) vs `"Mara's eyes are green"` (the colour attribute
itself) — Goetia returns `different_fact` at confidence 0.90–0.95 with
explanations like *"action vs. attribute."* Both models are 100% on
genuine paraphrases and 100% on topical-noise pairs.

**Operational implication.** Part B can canonicalise on Goetia. The
audit and the writer share a model — no Kobold model swap during a
real audit. Outputs at `Tools/ContinuityAuditSpike/probe-goetia/`.

## 28. Part B built and ripped out — a negative result on Goetia (2026-05-20)

§25 Part B was built end-to-end in two forms, measured against the
legacy similarity-threshold path on the same eval set, and reverted.
The §27 probe over-promised: a green probe didn't translate to a
working production component. This section records the chain of
evidence so the lesson is preserved.

### Build (two shapes, both committed then reverted)

**v1 — global FactLedger.** Single-pass online clustering of all
non-knowledge claims via the same-fact judge, with a token-Jaccard
≥ 0.1 prefilter to bound cost. For each `knowledge_state` claim k,
look up fact nodes whose `firstAppearanceScene` falls after k's
scene. TDD'd (19 tests across 4 files). The initial implementation
used completion-passing recursion across both `step` (claims walk)
and `matchAgainst` (ledger walk), which crashed on the first k=1
eval with `EXC_BAD_ACCESS — Thread stack size exceeded` at depth
~9300 on URLSession's 544K-stack delegate queue. Rewritten as an
explicit `advance()` state machine with two nested `while` loops —
stack depth bounded to one frame per outstanding judge call.

**v2 — per-knowledge-claim cosine top-K.** v1 was both slow
(O(N²): ~30–60 min ledger build per manuscript, projected ~36 hr per
audit on an 80k-word novel) *and* the global clustering allowed
false-positive same-fact merges to silently suppress real violations
by setting `firstAppearanceScene` before the reference. v2 dropped
the global ledger: per knowledge claim k, cosine-rank all
non-knowledge claims (embeddings already exist from
`ContinuityClaimFilterPipeline`), take top-K=10, sort by scene order,
walk via the same-fact judge. First match's scene determines outcome.
Cost: O(knowledge_claims × K) judge calls — minutes per manuscript
on lighthouse-sized inputs.

### Measurement (k=1, all four manuscripts, Goetia 24B)

| metric | §24 Gemma-4-31B legacy | Goetia legacy | Goetia Part B v1 | Goetia Part B v2 |
|---|---|---|---|---|
| recall | 46% | **44%** | 38% | 35% |
| precision | 43% | 53% | 65% | **67%** |
| F1 | 0.46 | **0.47** | 0.46 | 0.46 |
| **knowledge_violation** | **3/4** | **1/4** | 0/4 | 0/4 |
| attribute_drift | 56% | 50% | 44% | 38% |
| timeline_conflict | 20% | 20% | 30% | 30% |
| spatial_conflict | 20% | 60% | 40% | 60% |

Two findings:

1. **Goetia legacy < Gemma-4-31B legacy on knowledge_violation
   (1/4 vs 3/4).** §24's 3/4 result was substantially Gemma-specific.
   The writer-model A/B in §24 chose Goetia for *prose generation*;
   for *knowledge_violation specifically*, Gemma-4-31B abliterated
   was the better audit model.
2. **Goetia Part B < Goetia legacy across the board.** Recall down
   8–9 points, attribute_drift down 6–12 points, knowledge_violation
   down to 0/4. The extra precursor LLM gate (same-fact judge between
   cosine retrieval and the final adjudicator) over-rejects real
   reference/reveal pairs in production. The legacy single-gate path
   (`cosine ≥ 0.7 → knowledge adjudicator`) gives the adjudicator more
   to work with — it sees scene-prose context, applies the §24 task-fit
   verdict vocabulary, and decides per pair; whereas Part B vetoes
   candidates upstream before the adjudicator can correct.

### Why §27's probe didn't predict §28

The probe scored same-fact on pairs the eval matcher's word-Jaccard
clustered (≥ 0.34 to gold). Those are *easy* pairs — they share
substantial surface. In production, a knowledge_state reference
("X knows P") and a narration reveal ("P happened") often share
*no surface*: their cosine sits in the 0.73–0.94 band (§24) but their
Jaccard is below the §27 prefilter floor and very far from 1.0.

§26's open lesson reasserts: a *capability* probe on filtered/clean
inputs is necessary but not sufficient. The §27 sample was
representative-of-the-cluster but not representative-of-the-task. The
discriminating cases for production are exactly the
ref/reveal-cross-form pairs the §27 sampling never touched.

### Disposition (user-confirmed 2026-05-20) — REVERTED

All Part B code removed: `SameFactVerdict` / `SameFactJudgment` /
`buildSameFactPrompt` / `sameFactJSONSchema` / `parseSameFact` in
`ContinuityAudit.swift`; `SameFactJudging` protocol +
`SameFactLLMJudge` impl; the global-ledger `FactNode` /
`FactLedger.build`; the per-k cosine `violations()` overload; the
engine wiring for both; the spike's `phase=probe` block and judge
plumbing; all related tests. Files restored to commit `05a9e2c`.
`2022/2022` tests passing, matching the pre-Part-B count exactly.

Probe artifacts under `Tools/ContinuityAuditSpike/probe/`,
`probe-goetia/`, `eval-partB-*`, `eval-legacy-*` preserved as
evidence.

### Where this leaves L10 (knowledge_violation specifically)

- **Current best:** legacy path on Gemma-4-31B abliterated (§24's
  3/4 at k=1). Goetia is the default writer model; for the audit on
  Goetia the headline is 1/4.
- **Open option:** per-audit model routing. Goetia for the world-fact
  retrieval/adjudication path (where it matches Gemma per §24's
  A/B), Gemma-4-31B abliterated for the knowledge-adjudication
  prompt. Not implemented; would need to extend
  `ContinuityAuditEngine`'s init to take two providers and route by
  prompt type. Manual model swap on KoboldCpp is the bottleneck —
  L10's `LOOM_TECH_STACK` notes the Ollama-vs-KoboldCpp
  model-server flexibility direction as a separate deferred idea.
- **Not worth re-spiking:** any "extra precursor LLM gate" between
  candidate retrieval and the final adjudicator. The §28
  measurement shows that direction systematically hurts recall on
  Goetia; the legacy single-adjudicator-as-precision-gate shape is
  the right one.

### Open lesson

A probe that scores well on filtered/clean inputs predicts capability,
not behaviour. Before committing to build *anything* downstream of an
LLM-extracted-claim pipeline, the de-risk probe must sample the
production stage's *worst-case* outputs (low-Jaccard ref/reveal pairs,
mismatched extraction styles), not just its *typical* outputs (high-
Jaccard clustered pairs). §28 cost ~2 days of build + ~10 hr of
compute. The probe should have looked harder.

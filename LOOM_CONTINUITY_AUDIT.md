# Loom — Continuity Audit (design + plan)

> **Status: Phase A spike complete — GO (2026-05-17).** Research-grounded;
> the pairwise-adjudication feasibility gate is cleared (§13). This document
> is the authoritative plan for the whole-manuscript continuity audit feature;
> it follows the `LOOM_*_SPIKE` / `LOOM_PLANNED_PROJECT` pattern. Inventory
> pointer: **L10** in [`LOOM_PLAN.md`](LOOM_PLAN.md).

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

Reuses the `OllamaLedgerExtractor` / `LedgerExtraction` JSON-Schema + GBNF +
tolerant-parser pattern ([`OllamaLedgerExtractor.swift:57`](Sources/LoomCore/Generation/OllamaLedgerExtractor.swift),
[`LedgerExtraction.swift:31`](Sources/LoomCore/Generation/LedgerExtraction.swift)),
including the scene-word-aware `num_predict` budget and retry-on-empty.

**Reuse vs. fresh extraction.** Loom already extracts character facts into
`Character.knownFactsBySceneId` ([`Character.swift:23`](Sources/LoomCore/Models/Character.swift)).
The audit *consumes* those accepted facts as `attribute` / `knowledgeState`
claims for free — but it cannot rely on them alone (they are character-only and
suggestion-gated; the user may not have accepted everything). The audit runs
its own complete extraction pass covering settings, objects, temporal and
spatial claims, and treats accepted ledger facts as a high-confidence subset.

### 3.2 Typed fact-base (deterministic)

Claims accumulate into a store keyed by `(subjectEntityId, type, attributeKey)`.
For `attribute` claims this makes drift a **cheap deterministic diff** — two
claims with the same key and incompatible values, no LLM needed for the
*candidate* step. High-precision for typed attributes; LLM is reserved for
deciding whether the two values are genuinely incompatible (§3.4).

### 3.3 Candidate-conflict retrieval

Never compare all O(n²) scene pairs. For each claim, retrieve only **prior
claims about the same subject and same dimension** as conflict candidates,
using the entity name/alias index and the existing CoreML Wegmann embedder for
fuzzy subject/attribute matching. This bounds the number of LLM adjudication
calls to roughly the number of genuinely-overlapping claim pairs.

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
- **Timeline** — extract temporal anchors per scene, build an ordering against
  `flatSceneIds` (the canonical narrative order — [`ManuscriptWalk.swift:12`](Sources/LoomCore/Editing/ManuscriptWalk.swift)),
  flag interval/age/duration violations deterministically. The LLM only
  *normalises* vague time expressions ("a few weeks later") into comparable
  form. Note: Loom does not yet model flashbacks / out-of-order scenes — the
  audit assumes `flatSceneIds` is chronological, and §11 flags this.

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

**Phase B — Production engine.** Claim extraction, typed fact-base + diffing,
candidate retrieval, adjudication, deterministic knowledge-state + timeline
checks, finding assembly, `ContinuityAuditStore`. Covers classes 1–3.

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
2. Tune the extraction prompt toward the ledger extractor's recall; add the
   retry-on-empty guard for the schema empty-content case.
3. Goetia adjudication is ~one call per candidate pair — fold into the §8 cost
   model (background, progress indicator).

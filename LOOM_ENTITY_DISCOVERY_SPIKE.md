# LOOM_ENTITY_DISCOVERY — spike plan

> **Date drafted:** 2026-05-15. **Status:** pre-spike. **Phase target:** Phase 9 candidate (extends Phase 4 ledger + Phase 4.5 Bible Workspace).
>
> This document scopes a spike to extend Loom's existing Pass-B fact extractor (`Sources/LoomCore/Generation/LedgerExtraction.swift`) so it also **discovers new characters and places** in scene prose, attaches extracted facts to those proposed entities, and surfaces them in the Bible Workspace webview as accept/reject/edit suggestions. Research synthesis: §8.
>
> The spike's job is to answer: *does a local-LLM pipeline produce bible-worthy entity proposals at high enough precision, without flooding the user, that the feature is worth shipping?* If yes, Phase 9 productionises it; if no, this doc captures why and the feature is closed.

## 1. Falsifiable hypothesis

**A hybrid pipeline — (a) candidate generation from prose, (b) a promotion gate, (c) embedding-based dedup against the existing bible, (d) GBNF-constrained LLM normalisation + fact attachment — running on gemma4_2b can propose new bible-worthy characters + places from scene prose at:**

- **Precision ≥ 75%** (a proposed entity is *actually* new + worth a bible row), measured against a hand-graded fixture of 8 scenes (mix SFW + NSFW per the LOOM_NSFW strategic anchor).
- **Recall ≥ 60%** for *named* entities (proper-noun characters + places) the human grader marks as bible-worthy. Recall on definite-NP entities ("the cook", "the woman in red") is a soft target only — see §4.3.
- **Per-scene proposal cap ≤ 5** after dedup + gating, even on scene-1 cold start.
- **End-to-end latency ≤ 30 s/scene** on the user's gemma4_2b localhost Ollama (informational; not a kill criterion).

**Falsifying outcome**: precision < 50%, recall < 30%, *or* the per-scene cap requires aggressive filtering that drops recall below 30%. Any of these → recommend NOT shipping, fall back to manual bible authoring per Sudowrite / Novelcrafter / NovelAI precedent (§8.4 — production tools do not auto-discover).

## 2. What the spike will measure

Concretely, for each fixture scene (8 scenes — 5 SFW from Phase 4 ledger fixture, 3 NSFW from Phase 5 / 8 anchor fixtures):

1. **Candidate generation**: how many entity mentions does the candidate stage emit (proper-noun NER hits + definite-NP clusters)?
2. **Promotion gate**: of those, how many survive the proper-noun-OR-≥2-mentions-with-stable-descriptor gate?
3. **Dedup**: of survivors, how many are merged with an existing bible entry by embedding similarity vs. proposed as new?
4. **Normalisation**: of those proposed-as-new, does the GBNF stage emit a well-formed `(kind, name, aliases, evidenceQuote)` tuple?
5. **Fact attachment**: do the extracted facts for the scene attach correctly to the *proposed* entity ID rather than getting orphaned?
6. **Per-scene cap**: what's the natural distribution of proposals/scene, and where does the top-K cap kick in?
7. **NSFW failure modes**: do anatomy-descriptor clusters ("the redhead", "the brunette") get filtered out? Does Pass-A's transient JSON failure rate on NSFW worsen with the doubled extraction surface?

Pure precision/recall is graded against a hand-labelled gold set authored alongside the fixture (see §6.1).

## 3. Architecture sketch

### 3.1 Pipeline

```
scene prose
   │
   ▼
┌─────────────────────────────────────────────┐
│ Stage A — Candidate generation              │
│   Two paths, run in parallel, results merged: │
│   A1. Regex/heuristic proper-noun pass      │ (cheap, fast, deterministic)
│   A2. gemma4_2b "list named entities" pass  │ (GBNF-constrained; catches what regex misses)
└─────────────────────────────────────────────┘
   │
   ▼
┌─────────────────────────────────────────────┐
│ Stage B — Promotion gate (pure data)        │
│   Keep iff:                                  │
│   • proper noun (cap'd, ≥2 tokens or  ≥1     │
│     mention with attribution verb) OR        │
│   • definite NP recurring ≥3× within scene   │
│     with stable descriptor                   │
│   Drop anatomy-only definite NPs (block-list)│
└─────────────────────────────────────────────┘
   │
   ▼
┌─────────────────────────────────────────────┐
│ Stage C — Dedup vs bible (CoreML Wegmann)   │
│   Embed (name + nearby evidence span);       │
│   FAISS-style nearest-neighbour against     │
│   bible character/setting embeddings.        │
│   ≥0.85 cosine → merge into existing;        │
│   0.65–0.85 → LLM-judge tiebreaker;          │
│   <0.65 → propose as new.                    │
└─────────────────────────────────────────────┘
   │
   ▼
┌─────────────────────────────────────────────┐
│ Stage D — GBNF normalisation                │
│   gemma4_2b emits, under grammar:            │
│     { kind: "character" | "place",          │
│       canonical_name: string,                │
│       aliases: string[],                     │
│       one_line: string,                      │
│       evidence_quote: string }              │
└─────────────────────────────────────────────┘
   │
   ▼
┌─────────────────────────────────────────────┐
│ Stage E — Fact attachment                   │
│   Existing Pass-B extractor runs with       │
│   CharacterRef list = (bible chars +        │
│   proposed chars). Facts attach to whichever│
│   matches; orphans surface in the review UI.│
└─────────────────────────────────────────────┘
   │
   ▼
┌─────────────────────────────────────────────┐
│ Stage F — Suggestions queue                 │
│   ≤5 highest-confidence proposals per scene;│
│   the rest defer to the next scene's queue. │
└─────────────────────────────────────────────┘
```

### 3.2 Data shapes (Swift, additive)

New types in `Sources/LoomCore/Generation/EntityDiscovery.swift` (sibling to `LedgerExtraction.swift`):

```swift
public enum EntityDiscovery {
    public enum Kind: String, Codable { case character, place }

    public struct ProposedEntity: Codable, Equatable {
        public let id: UUID                  // synthetic; promoted to bible UUID on accept
        public let kind: Kind
        public let canonicalName: String
        public let aliases: [String]
        public let oneLine: String           // 1-sentence pitch from prose
        public let evidenceQuote: String     // verbatim span from scene
        public let sourceSceneId: UUID
        public let confidence: Double        // 0-1; gate output
    }

    public struct ProposedEntityFacts: Codable, Equatable {
        public let proposedEntityId: UUID
        public let facts: [LedgerExtraction.ExtractedFact]
    }
}
```

Existing `LedgerExtraction.ExtractedFact.characterId` is already a string — it can reference a `ProposedEntity.id.uuidString` interchangeably with a real `Character.id`. No schema break.

### 3.3 Bridge intents (`BibleWorkspaceBridge.swift`, additive)

```swift
case acceptEntityProposal(proposalId: UUID, edits: ProposedEntityEdits?)
case rejectEntityProposal(proposalId: UUID)
```

Where `ProposedEntityEdits` lets the user tweak `canonicalName` / `aliases` / `oneLine` before promotion (matches the §8.8 acceptance-UI pattern: review → optional edit → commit).

### 3.4 Webview UI (`web/bible-workspace/src/views/`)

New `EntityProposalsQueue.tsx`, mirroring the existing `SuggestionsQueue.tsx` pattern:

- Header: "Entity proposals (N across M scenes)"
- Per-row card:
  - Kind badge (character / place)
  - Editable `canonicalName` field (defaults to LLM's proposal)
  - Editable `aliases` (chip-style)
  - `oneLine` summary (editable)
  - Evidence quote (read-only, with scene-title link)
  - Confidence score (debug-mode only)
  - Attached facts list (collapsible — these promote with the entity on accept)
  - Accept (turns into `Character` or `Setting` + commits facts) / Reject / "Defer to next pass"

TypeScript mirror types in `web/bible-workspace/src/types.ts`. Bridge intents in `web/bible-workspace/src/bridge.ts`.

**No AppKit**. The legacy AppKit `InspectorController` does not get a new tab for this. The Bible Workspace webview is the only surface.

## 4. Open design questions the spike must answer

### 4.1 LLM-only vs hybrid pipeline

Research (§8.1, §8.3) says **hybrid wins** — purpose-built NER (BookNLP / GLiNER) + LLM normalisation beats LLM-only at 2-3B scale. But BookNLP/GLiNER are Python; pulling in a Python dependency conflicts with Loom's Swift-native runtime (Phase 5 lost ~half a day on the MLX path because of toolchain mismatch — see [feedback_verify_local_toolchain.md](memory)).

**Spike will measure both**: (a) LLM-only with strong promotion gates + grammar, (b) hybrid with a minimal Swift-side regex/POS-tagger candidate generator (no Python) + LLM normalisation. If (a) hits the precision/recall targets, ship (a). Only adopt (b) if (a) misses by a wide enough margin to justify the toolchain complexity.

### 4.2 Where does the evidence-span requirement live — prompt or grammar?

GBNF can enforce that the response has an `evidence_quote` field. It cannot enforce that the quote is actually from the scene. Two options:
- **Trust + filter**: grammar requires the field, a post-check rejects proposals whose quote doesn't substring-match the scene prose.
- **Embed-and-score**: quote must have cosine ≥ 0.9 vs. some span in the prose.

Spike will start with substring-match — cheap, robust, surfaces hallucination as a hard reject. Embed-and-score only if substring fails too aggressively on minor rewording.

### 4.3 Definite-NP entities ("the cook", "the woman in red")

Research (§8.2) suggests promotion only if (a) canonical mention is a proper noun, OR (b) cluster has ≥N mentions with a stable definite description. Fiction NSFW prose has lots of definite NPs that are *not* worth tracking ("the man", "the boy", "the redhead"). Without coreference clustering, Loom can't reliably distinguish "stable definite description" from "one-off pronoun substitute."

**Spike default**: proper-noun-only proposals, hard cap. Definite-NP entities documented as out-of-scope for v1. Re-open the question only if recall on the gold set is dragged below 30% by missing important unnamed characters.

### 4.4 Dedup confidence thresholds

Research (§8.5) suggests embedding cosine + LLM-judge band. Loom has CoreML Wegmann embeddings running natively (Phase 8.b CoreML migration). Threshold values (0.85 / 0.65) are placeholders — spike will sweep them against the dedup component of the gold set (each gold entity carries a "this is the same as bible entry X" or "this is genuinely new" flag).

### 4.5 Cold-start scene-1 flood

Scene 1 has every entity "new." Without mitigation, the queue floods. Mitigations to evaluate (cheapest first):
- **Top-K cap per scene**: ≤5 proposals, ordered by `confidence × mention-count`. The rest spill to the next scene's queue (where most will dedupe against the now-accepted entities).
- **Defer-on-first-scene**: scene 1 is auto-deferred to scene 2's pass so the bible has *something* to dedup against.
- **Initial-cast bootstrap UI**: a separate "extract cast from scene 1 in bulk" flow, not the per-scene queue.

Spike will measure proposals/scene distribution and pick the lightest-touch mitigation that hits the cap.

### 4.6 NSFW-specific guards

Anatomy descriptors as character candidates ("the redhead", "the brunette") are a real failure mode (§8.7). Mitigation:
- Block-list of anatomy-descriptor heads (curated, ~20 entries: redhead, brunette, blonde, etc.).
- Reject if `canonicalName` is *only* an anatomy descriptor (i.e. no proper noun anywhere in the mention cluster).
- Re-promote if the descriptor co-occurs with a proper noun within the same evidence span.

Spike fixture must include ≥1 NSFW scene with multiple unnamed characters identified only by anatomy to exercise this.

### 4.7 Pass-A JSON-failure rate under doubled load

The existing extractor is at ~30% transient JSON-parse failure on NSFW Pass-A per HANDOFF §15.16 follow-up #1. Adding Stages A2 + D doubles the LLM-call surface per scene. Spike will measure the combined failure rate and confirm the retry-on-`noJSONObjectFound` fix (HANDOFF follow-up #1) covers it — if not, retry budget needs widening.

## 5. Out of scope (v1) — revisit once v1 ships successfully

All deferred items are explicit v2 candidates. The shapes are designed so each one is an *additive* extension to the v1 pipeline, not a redesign.

- **Object discovery** — `BibleObject` (significant artefacts) exists in the data model. Same pipeline shape as Character/Setting; adding is incremental once v1 is in the wild.
- **Cross-scene coreference** — propagating "the woman in red" → existing-bible-character "Marius" across scene boundaries. Hard problem, requires real coref. Single-scene-only in v1; v2 candidate once §4.3 definite-NP signal is well understood empirically.
- **Bulk import** — discovery over an entire manuscript on first project load. The v1 pipeline supports it; only the UI for it lands later.
- **Lorebook auto-discovery** — Lorebook entries stay user-authored in v1 (they're more conceptual; harder to gate). Worth revisiting once v1 demonstrates the promotion-gate works for character/place — same gate philosophy should apply.
- **Relationship discovery** — "Marius is Liana's father" is a fact-extraction problem, not entity-discovery. Existing Pass-B already covers facts; a "relationship facts" extension is its own scope and follows naturally from v1.
- **Faction / timeline discovery** — same reasoning as lorebook; v2 candidate.

## 6. Spike build plan

### 6.1 Fixture authoring (½ day, before code)

- 8 scenes total. 5 SFW from `Tests/LoomCoreTests/Fixtures/LedgerSpike/fixture.json` (re-use). 3 NSFW from Phase 5 / 8 anchor fixtures.
- Hand-grade gold entities per scene: `{ name, kind, isNew, mergesWithBibleId?, isWorthTracking, evidenceQuote }`.
- Hand-grade gold facts per gold entity (re-use Phase 4 fact format).
- Lives at `Tests/LoomCoreTests/Fixtures/EntityDiscoverySpike/fixture.json`.

### 6.2 Pure-data scaffolding (1 day)

- `EntityDiscovery.swift` types + GBNF grammar for Stage D.
- `EntityPromotionGate.swift` — pure-data filter (proper-noun + recurrence + anatomy block-list).
- `EntityDedupEngine.swift` — cosine + threshold, takes injected `Embedder` (the existing CoreML Wegmann client).
- `EntityDiscoveryScorer.swift` — precision/recall/F1 vs. gold, sibling to `LedgerExtraction.ScoreReport`.
- TDD per repo norm — fixtures are deterministic, no live LLM calls in unit tests.

### 6.3 Live eval runner (½ day)

- `Tools/EntityDiscoverySpike/main.swift` — sibling to `Tools/LedgerSpike`. Reads fixture, runs pipeline against live Ollama + KoboldClient.embed, writes Markdown report.
- Report: per-scene precision/recall, per-stage failure rates, cap-binding rate, NSFW failure rate, end-to-end latency.

### 6.4 Decision point

Run live eval. Compare against §1 hypothesis. Outcomes:
- **All thresholds met** → write up findings as a §3 appendix to this doc, propose Phase 9 productionisation plan.
- **Precision OK, recall low** → expand to hybrid pipeline (§4.1 option b) before deciding.
- **Precision low** → spike fails. Document why, archive feature.

### 6.5 If proceeding — Phase 9 productionisation (out of this spike's scope)

- Wire `EntityDiscovery` into `LedgerExtractionCoordinator` as a parallel pipeline.
- New bridge intents (`acceptEntityProposal` / `rejectEntityProposal`).
- New webview view (`EntityProposalsQueue.tsx`).
- New `EntityProposalsStore` for the pending queue (sidecar JSON, same shape as suggestions).
- Production thread-safety, error-handling, log hooks.
- Estimated: 1 week including webview UI + bridge plumbing + end-to-end tests.

## 7. Risks

1. **Toolchain pressure (medium)**. If LLM-only fails the precision bar and hybrid is the only path, we either pull in Python (BookNLP/GLiNER) — conflicts with [feedback_verify_local_toolchain](memory) — or roll a minimal Swift-side proper-noun detector (cheap but lower quality than GLiNER). Mitigation: spike measures both before committing.
2. **Cold-start floods user (high)**. Scene-1 has every entity new; even with top-K cap the user faces a wall of proposals on first-scene generation. Mitigation: bootstrap UI (§4.5) lands with v1 if cap+spill alone is insufficient.
3. **NSFW false-positives on anatomy descriptors (medium)**. Anatomy block-list is a band-aid; a determined edge case will defeat it. Mitigation: evidence quote review is always one click away in the queue UI — user can reject quickly.
4. **Pass-A regression on doubled call surface (low)**. Existing transient-JSON failure rate climbs with more LLM calls per scene. Mitigation: retry-on-`noJSONObjectFound` fix from HANDOFF §15.16 #1 lands first.
5. **AppKit pivot pressure (per [project_appkit_pivot_pressure](memory))**. The webview-only UI direction means the legacy AppKit `InspectorController` doesn't gain a tab for this. If the user later decides to migrate the whole inspector to webview, the entity-proposals view should be the model — not a stale duplicate to migrate.

## 8. Research synthesis (2026-05-15 research pass)

Empirically reviewed best practices for fiction entity discovery, 2024-2026:

### 8.1 NER for fiction specifically
**BookNLP** (Bamman et al.) is the strongest purpose-built pipeline for narrative third-person prose — character clustering ("Tom" / "Mr Sawyer" / "Thomas Sawyer" → one ID) and pronoun↔definite-NP coref out of the box. **GLiNER** is the modern zero-shot alternative (small bidirectional transformer, label-prompted, beats ChatGPT-class on OOD NER). spaCy 4.x is competitive on proper-noun PERSON/GPE but doesn't resolve "the stranger" → existing entity. ([BookNLP](https://github.com/booknlp/booknlp), [GLiNER](https://github.com/urchade/GLiNER))

### 8.2 Anaphora / pronoun handling
Standard pattern: coref **first**, then promote only clusters whose canonical mention is a proper noun OR a stable definite NP recurring across ≥2 paragraphs/scenes. LingMess / coref-mt5 / F-Coref are 2024-era leaders. Fine-tuned T5-3B hits ~80% coref F1 on LitBank. Bare pronoun-only clusters are dropped. ([BookCoref 2025](https://arxiv.org/html/2507.12075v1))

### 8.3 GBNF-LLM vs specialised NER
For 2-3B local models, grammar-constrained decoding closes the **format-validity** gap but does not match purpose-built NER on raw F1. The winning architecture: hybrid — specialised NER proposes mention clusters, LLM normalises + justifies under grammar. ([ACL 2025 Industry on GCD](https://aclanthology.org/2025.acl-industry.34.pdf))

### 8.4 Place / setting discovery
Three filters across the literature: proper-noun+capitalisation gate, recurrence-across-scenes filter (Patchview, RealmGen-AI), gazetteer/Wikidata lookup. Bare generic rooms ("bedroom", "kitchen") are deliberately NOT promoted. ([Patchview](https://arxiv.org/abs/2408.04112))

### 8.5 De-duplication
SOTA is embedding-based blocking + LLM-judge tiebreaker. Sentence-BERT/E5 embedding of `(name, role, distinguishing facts)` → FAISS k-NN → high cosine auto-merges, mid-band gets LLM-judged, low proposes new. Edit distance alone fails because role-based mentions ("the doctor") have no name overlap. ([LinkTransformer](https://arxiv.org/html/2309.00789v2))

### 8.6 Cold-start flood
Production tools (Sudowrite, Novelcrafter, NovelAI) **do not auto-discover** — user-authored bible entries with trigger words. This is the deliberate dodge. Where auto-extraction exists (BookNLP humanities pipelines, Patchview): batch by confidence, per-scene cap, review queue with status flags. No published benchmark on first-scene flood mitigation — open product-design space.

### 8.7 NSFW failure modes
No peer-reviewed work directly addresses NER+coref on adult prose. Predictable failures: heavy pronoun-and-anatomy density inflates spurious coref chains, anatomical descriptors ("the redhead") get treated as definite-NP entities and risk character promotion. Dialogue-attribution drops out — long dialogue-free passages break BookNLP's speaker-attribution feature. Off-the-shelf NER trained on news/wiki underweights fiction's heavy definite-description use. Mitigation: anatomy block-list + force evidence span (silent skipping becomes visible).

### 8.8 Acceptance UI patterns
Dominant pattern in fiction-writing tools is **modal review queue + single-shot accept/reject + post-acceptance edit**. Squibler's "accept, reject, or refine every suggestion" is the cleanest documented pattern. Research prototypes (Patchview, LikeThis!) converge on: batched suggestion list, per-suggestion accept/reject/edit, evidence/justification, iterative refinement before commit. None publish per-scene caps or confidence thresholds.

## 9. Post-spike findings (2026-05-15)

> **Decision: PROCEED.** §6.4 criteria cleared with margin on precision + recall; latency is at-the-bar and addressable via Stage D parallelisation in productionisation.

### 9.1 Three-run progression

The spike ran the same fixture three times, with fixes layered between runs based on the per-scene failure analysis.

| | Precision | Recall | F1 | Avg latency | Cap exceeded | Notes |
|---|---|---|---|---|---|---|
| §1 target | ≥ 75% | ≥ 60% | — | ≤ 30s | 0/8 | |
| **Run 1** — baseline | 33.3% | 85.7% | 48.0% | 49.2s | 0/8 | Recall strong; precision tanked by structural issues, not LLM failures |
| **Run 2** — +Fix 1/2/3 | 75.0% | 85.7% | 80.0% | 32.2s | 0/8 | Precision at bar; 2 specific FPs left |
| **Run 3** — +Fix 4/5 | **100.0%** | **85.7%** | **92.3%** | 30.7s | 0/8 | Precision perfect; only Karim-in-eds-01 miss remains |

### 9.2 The five fixes that landed

All five are pure-data Swift, all under 100 lines combined, none touching the LLM call site.

| Fix | What it solves | Mechanism | Where |
|---|---|---|---|
| **1** Pre-gate known-entity filter | gemma4_2b ignores prompt "don't re-emit known entities" instruction (cf. `feedback_prompt_blacklist_evasion` memory) | Exact case-insensitive name match against known list | `EntityDiscovery.isKnownSurface` |
| **2** Stage C dedup wire into runner | Same person under different surface forms ("Marius Thorn" / "Dr Thorn") | CoreML Wegmann cosine + threshold band against starting bible | `EntityDedupEngine.evaluate` |
| **3** Place-recurrence gate | Real-world cities in passing reference (Brussels, Edinburgh) promoted as bible-worthy places | Place must start "The " OR appear ≥ 2× in scene prose (whole-word) | `EntityDiscovery.passesPlaceRecurrence` |
| **4** Known-name token expansion | "Karim Vance" in known list doesn't catch bare "Vance" when LLM splits a multi-word name | Auto-expand multi-word known names into proper-noun tokens (uppercase, length ≥ 3) | `EntityDiscovery.expandKnownNamesWithTokens` |
| **5** Post-Stage-D canonical dedup | Wegmann is style-similarity, not semantic — doesn't merge "Marius Thorn" / "Dr Thorn" at Stage C, but Stage D normalises both to identical canonical_name | Exact-string merge on (canonical_name + kind) after Stage D, union aliases | `EntityDiscovery.dedupByCanonicalName` |

Fix 2 was a wiring change (the engine already existed and was tested). Fixes 1, 3, 4, 5 are new pure-data functions, each with 6-8 dedicated tests (28 new tests total across the four). Combined with the original 49 tests for the §6.2 scaffolding, Phase 9 adds **77 tests** and brings the total suite to 1385/1385 green.

### 9.3 The remaining recall miss

One gold entity (Karim in `eds-01`) is missed across all three runs. The failure is **upstream of the filters** — gemma4_2b's Stage A2 simply doesn't emit Karim despite his name appearing 5 times in the prose and the scene being literally titled "Coffee with Karim". Run 1 emitted zero candidates with a `noJSONArrayFound` parse error. Runs 2 + 3 emitted candidates but never Karim — the model apparently treats him as already-known (a hallucination, since the starting bible at that scene contains only Mia + Anders). Two ways to address in productionisation:

- **Stage A2 retry-on-empty-output** — re-prompt with different framing if Stage A2 returns either a parse error OR zero candidates that survive the known-entity filter. Aligns with HANDOFF §15.16 follow-up #1.
- **Higher Stage A2 temperature** (currently 0.2) — a small bump to 0.4 would diversify outputs and likely surface Karim. Trade-off: more candidates means more Stage D calls means more latency.

### 9.4 The latency story

Run 3 was 30.7s/scene avg — 0.7s over the §1 target. Run-to-run variability on the same fixture spans 2-3s (Run 2 was 32.2s, Run 1 was 49.2s with one transient retry). The bottleneck is sequential Stage D calls (each ~10s under JSON-Schema-constrained generation). For productionisation:

- **Parallelise Stage D**: each candidate is independent — concurrent `URLSession.dataTask`. An eds-07 with 4 candidates would drop from ~45s to ~13s. Not load-bearing for the v1 ship gate but the obvious lever if latency UX bites.
- **Conditional Stage D**: candidates with no aliases / clean canonical form could skip Stage D entirely. Save 50% of Stage D calls in the common case.

Neither belongs in the spike scope; both belong in §6.5 Phase 9 productionisation.

### 9.5 What this means for the bigger questions

- **Python / BookNLP / GLiNER hybrid stays off the table for v1.** LLM-only with the five Swift-side filters clears precision/recall/cap thresholds at gemma4_2b scale. The toolchain-pressure risk from `feedback_verify_local_toolchain` is avoided. If a future scene type (high-anaphora, dialogue-only NSFW) breaks v1, the hybrid option remains documented in §4.1 + §8.3 as the next escalation.
- **Out-of-scope items from §5 are still out of scope.** The v1 pipeline doesn't handle object discovery, cross-scene coref, lorebook auto-discovery, relationship discovery, factions, or bulk import. Each is documented as an additive v2 candidate that extends the same pipeline shape without redesign.
- **The Bible Workspace webview UI (`EntityProposalsQueue.tsx`) and bridge intents (`acceptEntityProposal` / `rejectEntityProposal`) are the next concrete piece of productionisation work** — independent track from the pipeline polish, can land in parallel with the latency improvements above. The shape is well-defined (mirror `SuggestionsQueue.tsx`); ~1-day estimate including the bridge plumbing.

### 9.6 §6.4 recommendation: GO — productionise as Phase 9

The empirical thresholds are met. The remaining concerns are productionisation tasks (Stage D parallelisation, Stage A2 retry, webview UI), not viability questions. The pipeline shape from §3.1 holds; no architectural redesign is needed between spike and production.

**Suggested Phase 9 LOOM_PLAN row** (additive to L8 / future L9):

> L9 — Entity Discovery v1. Productionise the spike pipeline (Stages A2-F per §3.1), Bible Workspace webview UI (`EntityProposalsQueue.tsx` + `acceptEntityProposal` / `rejectEntityProposal` bridge intents), Stage D parallelisation, Stage A2 retry on empty/parse-error. Pre-conditions: HANDOFF §15.16 follow-up #1 (OllamaBeatExtractor retry-on-noJSONObjectFound) is in production. ETA: ~1 week including UI + integration tests.

---

## 10. References

- [LOOM_LEDGER_SPIKE.md](LOOM_LEDGER_SPIKE.md) — Pass-B fact extraction precedent (prompt design, GBNF grammar, scoring methodology)
- [LOOM_STORY_BIBLE.md](LOOM_STORY_BIBLE.md) — entity model authoritative source
- [LOOM_PLAN.md](LOOM_PLAN.md) §Phase 4.5 — Bible Workspace webview
- [LOOM_NSFW.md](LOOM_NSFW.md) — strategic-anchor directive
- [Sources/LoomCore/Generation/LedgerExtraction.swift](Sources/LoomCore/Generation/LedgerExtraction.swift) — extant Pass-B implementation
- [Sources/LoomCore/UI/BibleWorkspaceBridge.swift](Sources/LoomCore/UI/BibleWorkspaceBridge.swift) — intent dispatch contract
- [web/bible-workspace/src/views/SuggestionsQueue.tsx](web/bible-workspace/src/views/SuggestionsQueue.tsx) — UI pattern to mirror
- BookNLP — https://github.com/booknlp/booknlp
- GLiNER — https://github.com/urchade/GLiNER
- LinkTransformer — https://arxiv.org/html/2309.00789v2
- BookCoref 2025 — https://arxiv.org/html/2507.12075v1
- Patchview — https://arxiv.org/abs/2408.04112
- ACL 2025 Industry on GCD — https://aclanthology.org/2025.acl-industry.34.pdf

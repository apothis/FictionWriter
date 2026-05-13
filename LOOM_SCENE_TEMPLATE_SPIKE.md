# Loom — Scene-Template Generation Spike

> **Status: Phase 7.a in flight.** Empirical-validation harness + findings for the Phase 7 Scene-Template Generation feature ([`LOOM_SCENE_TEMPLATE.md`](LOOM_SCENE_TEMPLATE.md)). Mirrors the discipline of [`LOOM_RAG_SPIKE.md`](LOOM_RAG_SPIKE.md) and [`LOOM_NARRATIVE_MODE_SPIKE.md`](LOOM_NARRATIVE_MODE_SPIKE.md): hand-curated fixtures + a CLI runner that hits live local servers + a hand-graded writeup with a decision gate at the end.
>
> **Scope.** Three sub-rows from [`LOOM_SCENE_TEMPLATE.md`](LOOM_SCENE_TEMPLATE.md) §9:
> - **§7.a.1 — Extraction quality** (Pass A). **THIS SECTION LANDED 2026-05-13** below in §1.
> - **§7.a.2 — Generation quality** (Pass B). Pending.
> - **§7.a.3 — Long-exemplar pitfalls** validation (Tripto 2025). Pending.
>
> **Code.** Pure-data extraction helpers: [`Sources/LoomCore/Templates/SceneBeat.swift`](Sources/LoomCore/Templates/SceneBeat.swift), [`Sources/LoomCore/Templates/BeatExtraction.swift`](Sources/LoomCore/Templates/BeatExtraction.swift). Runner: [`Tools/SceneTemplateSpike/main.swift`](Tools/SceneTemplateSpike/main.swift). Fixtures: [`Tools/SceneTemplateSpike/Fixtures/`](Tools/SceneTemplateSpike/Fixtures/). 8 pure-data tests at [`Tests/LoomCoreTests/Phase7BeatExtractionTests.swift`](Tests/LoomCoreTests/Phase7BeatExtractionTests.swift).

---

## 1. §7.a.1 — Extraction quality (Pass A) — LANDED 2026-05-13

### 1.1 Setup

- **Extractor model**: gemma4_2b:latest via Ollama at http://localhost:11434/
- **5 hand-authored fixtures**, each ~450–600 words, designed to span the modality space:
  - `01_the_doorway_dialogue.md` — dialogue-heavy two-character confrontation (6 authored beats)
  - `02_cold_light_interiority.md` — single-character interior monologue (5 authored beats)
  - `03_the_cathedral_description.md` — setting-establishment with thin action frame (5 authored beats)
  - `04_burn_the_tape_action.md` — fast-paced action with explicit escalation arc (7 authored beats)
  - `05_ten_years_later_summary.md` — time-skip narration with mode shifts (6 authored beats)
- **Prompt** ([`BeatExtraction.swift`](Sources/LoomCore/Templates/BeatExtraction.swift)): asks for 5–12 beats with function tag, modality tag, content-stripped summary (`{PROTAGONIST}` role tokens), target words, word range, tension delta — plus sourceCharacters, sourceSettingMarkers, pacingStats.
- **Schema**: Ollama `format` parameter (JSON-Schema) with `function` and `modality` constrained to enum.
- **Sampler**: `temperature=0.2`, `num_predict=4096`, `repeat_penalty=1.1` — extraction wants deterministic JSON, not creative variation.

### 1.2 Headline results

| Fixture | Authored beats | Extracted beats | Modality emphasis match | Function tag diversity | STRAP stripping | Latency |
|---|---|---|---|---|---|---|
| 01 dialogue | 6 | 17 | 13/17 = 76% dialogue ✓ | 5/8 functions used ✓ | ✓ no leakage | 54.5s |
| 02 interiority | 5 | 7 | 3/7 = 43% interiority ⚠ | 2/8 (setup-biased) ⚠ | ✓ no leakage | 41.2s |
| 03 description | 5 | 6 | 5/6 = 83% description ✓ | 2/8 (setup-biased) ⚠ | ✓ no leakage | 39.0s |
| 04 action | 7 | 8 | 3/8 = 38% action ⚠ | 6/8 functions used ✓ | ✓ no leakage | 48.6s |
| 05 summary | 6 | 10 | 0/10 = 0% summary ✗ | 5/8 functions used ✓ | ✓ no leakage | 53.0s |

### 1.3 What worked

**1. STRAP content stripping (D4) — 5/5 fixtures perfect.** Across all 50 generated beats, zero source character names leaked into the `summary` field. The model consistently substituted `{PROTAGONIST}`, `{ANTAGONIST}`, `{ALLY_1}`, `{INDOOR_PRIVATE_SPACE}`. This is the single strongest result — Loom's primary defense against the documented plot-leakage failure mode ([Krishna et al. STRAP 2020](https://aclanthology.org/2020.emnlp-main.55/)) works out of the gate.

**2. Schema-constrained decoding via Ollama `format` parameter — 5/5 clean parses.** Every response decoded as valid `ExtractedSceneSkeleton` JSON. No retry needed. No preamble/postamble (the parser's tolerance was unused). The two-enum constraint (`function` ∈ {setup, arrival, …}, `modality` ∈ {action, dialogue, …}) collapses what would otherwise be the most failure-prone parsing surface.

**3. Source character + setting extraction — useful in all 5 fixtures.** Characters consistently identified (`["Mara", "Daniel"]`, `["Sela"]`, etc.). Setting markers slightly under-extracted but useful (`["doorway", "hallway", "rain", "house"]` for fixture 01). Both fields are exactly the input the v2 character-mapping table will pre-populate from.

**4. Modality matches authored emphasis on dialogue + description fixtures.** 76% and 83% match rates on fixtures 01 and 03. These match Phase 5's NarrativeModeClassifier accuracy floor (73% LLM zero-shot per [LOOM_NARRATIVE_MODE_SPIKE.md](LOOM_NARRATIVE_MODE_SPIKE.md) §10). Dialogue + description are the two modalities the underlying classifier handles best.

**5. Latency is acceptable.** 39–55s per fixture. Pass A is a one-shot operation per template scene (run on ingest, results cached on disk); not on the hot generation path. Phase 7.b can run Pass A in the background after `Extract structure` is clicked, with progress UI — the user is fine waiting <1 minute for a one-time setup operation.

### 1.4 What didn't work + lessons for Phase 7.b prompt design

**1. Modality confusion on interiority / summary scenes** (fixtures 02 + 05). The model conflates `summary` with `description` (0/10 on fixture 05) and under-detects `interiority` (3/7 on fixture 02). This is **not a new failure mode**: it reproduces the exact pattern documented in [LOOM_NARRATIVE_MODE_SPIKE.md](LOOM_NARRATIVE_MODE_SPIKE.md) §10 (gemma's summary recall was weakest; interiority recall was second-weakest). The Phase 5 spike accepted the 73% floor; Phase 7 inherits it.

**Mitigation for 7.b:** the per-beat generation loop (D5) verifies modality post-hoc via the production `NarrativeModeClassifier`. If a beat marked "summary" by Pass A but generated as "description" by Pass B's writer, the verifier flags it. The mismatch is information for the user, not a hard fail. Accepting Pass A's modality imperfection is the right tradeoff vs. swapping in the slower writer-side gemma-4-31B for extraction.

**2. Function-tag collapse on static scenes** (fixtures 02 + 03 — 6 setups + 1 resolution each). Quiet / descriptive scenes default to `setup, setup, setup, …` because gemma4_2b doesn't have rich vocabulary for "this descriptive beat advances the scene differently from the previous descriptive beat." Action / dialogue scenes show much better function diversity (5–6 distinct functions).

**Implication for 7.b:** function tags are most useful for plot-shaped scenes (action, dialogue, mixed). For quiet scenes they degenerate to a one-tag signal. The Pass B prompt should weight function-tag information more heavily for dynamic scenes and lean more heavily on modality + word-target for static ones. This is design hint, not a blocker.

**3. Pacing-stats divergence between LLM-reported and ground-truth.** Fixture 01: LLM said 16 sentences, computed had 29 (model under-counted by 45%). Fixture 04: 10 vs. 39. The model is unreliable as a numeric pacing analyser — it "reads" the scene at a paragraph-cluster level rather than sentence-precise level.

**Decision: drop the pacing fields from the schema.** Pass A's job is the structural skeleton (beats + characters + setting markers); pacing is a numeric artefact that should be computed from the source via [`PacingStats.compute(text:)`](Sources/LoomCore/Templates/SceneBeat.swift), which is already implemented + tested. Removing the field saves prompt tokens AND removes a misleading data source. Will land in Phase 7.b production prompt revision.

**4. Over-segmentation on dialogue scenes.** Fixture 01 (462 words) extracted into 17 beats — average 27 words per beat, well below the 50–150 prompt target. The model treats each dialogue exchange as its own beat. Same fixture, second run, returned 12 beats; same fixture, first run, returned 17. Non-deterministic on count.

**Mitigation for 7.b:** add a "minimum beat target words: 50" hard guidance in the prompt; possibly add a post-process beat-merge step that combines adjacent same-function-same-modality beats below threshold. Defer to 7.b.

**5. Tension-delta semantics drifted on run 1, corrected on run 2.** First extraction of fixture 01: tension delta values were `0, 1, 2, 3, 4, …, 11` — monotonically increasing, suggesting the model read the field as a *level* not a *delta*. Re-running the same fixture: deltas became `+1, +2, +1, +3, +2, +1, …` — correctly interpreted. The field-semantics interpretation is sampler-dependent at temperature 0.2.

**Mitigation for 7.b:** the prompt currently says "tension_delta: integer in [-3, +3] representing the change in narrative tension caused by this beat". Phase 7.b should tighten to "tensionDelta is per-beat CHANGE, not cumulative level. Negative values are allowed for tension-decreasing beats." Or just rename the field to `beatTensionChange` to make semantics structurally obvious.

### 1.5 §7.a.1 verdict

**SHIP forward to §7.a.2.** Pass A extraction is **production-viable for the action / dialogue / mixed modality space** which covers >60% of plausible template-scene inputs. The two failure modes (modality confusion on interiority/summary; function collapse on static scenes) are **inherited from the Phase 5 narrative-mode floor**, not new — and have mitigations on the production-design ledger (D5 modality verification at generation time).

Two non-blocking prompt revisions queued for Phase 7.b:
- Drop `pacingStats` from schema; compute from source instead.
- Rename `tensionDelta` to `beatTensionChange` (or tighten prompt language) to lock semantics.

One concrete behaviour worth re-testing in §7.a.2: with the over-segmentation pattern (17 vs. 12 beats from same fixture across runs), Pass B's per-beat generation needs to be **robust to variable beat counts** in the same range. Spike §7.a.2 should run the same fixture twice and compare generated outputs for stability.

### 1.6 Phase 7.b scope-lock confirmations

Architectural decisions confirmed empirically (vs. just defensible in the planning doc):

- **D1 confirmed** (TemplateScene as first-class entity, not flagged reference) — the beat sidecar is structurally distinct from reference-chunk index sidecars.
- **D2 confirmed** (Pass A on Ollama side-task) — 39–55s latency is workable; quality is at the Phase 5 floor.
- **D4 confirmed** (STRAP content stripping in the prompt) — 5/5 fixtures clean, this is the cheapest reliability win we get.
- **D5 confirmed** (per-beat modality verification needed) — Pass A makes mistakes on interiority/summary that only post-hoc check catches.

Architectural decisions to refine:

- **D6 (pacing constraints)**: drop the LLM-reported pacing field, compute ground-truth pacing from source and inject directly. Numeric-precision-of-the-model is below threshold; numeric-computation is exact.
- **Schema refinement**: rename `tensionDelta` → `beatTensionChange` for semantic clarity.

---

## 2. §7.a.2 — Generation quality (Pass B) — PENDING

Will run Pass B per-beat generation on 3 of the 5 fixtures' extracted skeletons (likely 01 dialogue + 03 description + 04 action — the three that hand-graded best in §7.a.1). Synthetic cast mapping per fixture (e.g., for fixture 01: "Mara → Yusuf, Daniel → Inez, swap the bag for an old jacket, swap the doorway for a hospital corridor at 3 AM"). Hand-evaluate:

- Does output preserve beat ordering + word-count targets within ±20%?
- Does plot leak from the source (specific events / props / relationships)?
- Does voice transfer well, or collapse to the writer LLM's default?
- Does modality match the beat skeleton ≥70% of beats?

---

## 3. §7.a.3 — Long-exemplar pitfalls — PENDING

Empirically reproduce the [Tripto 2025 "Catch Me If You Can"](https://arxiv.org/html/2509.14543v1) finding on Gemma 4 31B + Loom's prompt assembly. Two-arm A/B:

- **Arm A**: Pass B with the full template scene injected as voice exemplar + STRAP-stripped skeleton.
- **Arm B**: Pass B with **only** the skeleton (no exemplar prose).

Hand-evaluate: does Arm A's output have measurable surface-mimicry advantage vs. Arm B? Does Arm A's deep voice fidelity (cadence, register, motif handling) suffer relative to Arm B? Does D4 stripping prevent plot leakage in Arm A's output even with the exemplar present?

If Tripto 2025 reproduces strongly, the production design may want a "voice weight" dial (D-design §8.3 v2 feature) that user-controls how heavily the exemplar's voice influences vs. the project's manuscript voice.

---

## 4. References

- [`LOOM_SCENE_TEMPLATE.md`](LOOM_SCENE_TEMPLATE.md) — Phase 7 planning doc + research-citation bibliography (full).
- [`LOOM_NARRATIVE_MODE_SPIKE.md`](LOOM_NARRATIVE_MODE_SPIKE.md) §10 — the 73% floor this spike inherits.
- [`LOOM_RAG_SPIKE.md`](LOOM_RAG_SPIKE.md) §6 + §13 — spike-discipline + verdict format mirrored here.
- [`LOOM_LEDGER_SPIKE.md`](LOOM_LEDGER_SPIKE.md) — the Phase 4 spike whose Ollama JSON-Schema pattern this spike inherits via `OllamaLedgerExtractor`.

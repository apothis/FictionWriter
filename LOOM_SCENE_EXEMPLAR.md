# Loom — Unified Scene Exemplar (Phase 8 proposal)

> **Status: Phase 8 design proposal (2026-05-14). NOT YET LOCKED.** Planning + research-call document for unifying the two existing scene-imitation pipelines (Phase 5 References → style-RAG retrieval, Phase 7 Templates → structural skeleton) into a single ingest action that contributes BOTH signals to a generated scene. The user-facing flow becomes: paste a scene, name it, then point any new generation at it for "same shape, same voice, same content register."
>
> Companion to:
>
> - [`LOOM_PLAN.md`](LOOM_PLAN.md) — new Phase 8 row to be added after design-lock.
> - [`LOOM_SCENE_TEMPLATE.md`](LOOM_SCENE_TEMPLATE.md) — Phase 7 design decisions (D1–D8) that this proposal builds on. Many remain load-bearing (per-beat generation; D4 STRAP content-stripping is now debatable — see §5.3).
> - [`LOOM_RAG_SPIKE.md`](LOOM_RAG_SPIKE.md) — Phase 5 retrieval pipeline empirical findings (StyleDistance vs. mxbai / bge embedders).
> - [`LOOM_NSFW.md`](LOOM_NSFW.md) — strategic anchor; the user's primary motivating use case is NSFW scene generation where matching explicit register + content patterns is critical.
> - [`LOOM_SCENE_TEMPLATE_SPIKE.md`](LOOM_SCENE_TEMPLATE_SPIKE.md) — empirical findings on Phase 7 voice-descriptor extraction, STRAP stripping, beat-segmentation reliability.
> - [`LOOM_SCENE_EXEMPLAR_RESEARCH.md`](LOOM_SCENE_EXEMPLAR_RESEARCH.md) — Phase 8.a §6.6 prior-art + embedder audit (landed 2026-05-14). Key findings: §6.1 candidate set narrowed (StyleDistance + iBERT + one retrieval baseline); NSFW exclusion in StyleDistance training corpus is structurally confirmed via C4 LDNOOBW filter; unified-exemplar market gap survives.
>
> **Scope.** Identify the gap, propose the unified data shape, enumerate the design choices that need empirical resolution before lock, lay out a spike (Phase 8.a) and production (Phase 8.b) plan, and specify the test surface up front so the spike outputs map cleanly into TDD-driven implementation work.
>
> **What this doc deliberately does NOT do.**
> - Lock the embedder choice. StyleDistance is the Phase 5 incumbent but may underperform on NSFW register matching; §6.1 lists the spike that resolves this.
> - Lock the chunking strategy. Sentence-window vs. beat-window vs. paragraph-window all have plausible cases.
> - Lock the data-model migration. Whether Reference + Template merge into one type, or stay separate with a shared "exemplar" abstraction layered above, is a Phase 8.b decision after the spike.
> - Pre-commit to deprecating Phase 5 References or Phase 7 Templates as user-facing concepts. The unification is at the ingest + generation surface; existing data on disk should keep working through Phase 8.

---

## 1. Concept

**End-user pitch.** "Paste a scene you love — or one whose style and content register you want to imitate. Loom learns it. Now any new scene in your project can borrow that scene's shape, voice, vocabulary, and explicit-content patterns — pick from your library at generation time."

**Mental model.** A *scene exemplar* is a single artifact that captures everything the writer can learn from one example scene:

| Signal | Where it lives in the artifact | How it reaches the writer prompt |
|---|---|---|
| **Beat skeleton** (5–12 functional units, modality + function + target word count) | `.beats.json` sidecar from Pass-A extraction (existing Phase 7) | `[BEAT SKELETON]` block in per-beat writer prompt |
| **Voice descriptor** (5-field structured fingerprint: cadence, dialogue density, flourish, register, distinctive techniques) | Same sidecar (existing Phase 7) | `[VOICE TARGET]` block — positive constraints |
| **Full source prose** | The exemplar's body (existing) | `=== TEMPLATE SCENE (voice reference; do not reuse plot) ===` block — voice exemplar |
| **Chunked + embedded passages** (NEW — currently only on References) | `.index` sidecar, chunks with StyleDistance vectors | `[STYLE EXEMPLARS]` block — top-K retrieved per beat |
| **Source characters + setting markers** | Same sidecar (existing Phase 7) | `[NEW CAST]` mapping informs the user's substitutions |

The new piece is the bottom row: each exemplar gets BOTH the structural skeleton (Phase 7) AND a chunked vector index (Phase 5). At generation, every beat call retrieves top-K style-similar chunks *from the exemplar being used as the template* (and optionally from other exemplars in the project library), and the writer sees both the structural scaffolding AND fresh per-beat style cues drawn from passages with similar modality and register.

**Why this matters specifically for NSFW.** Phase 7.b validates voice transfer (sentence cadence, register tag, distinctive techniques) but the 5-field descriptor compresses a lot. The §15.14 smoke test surfaced a real case where:

- Source: dense NSFW prose with specific anatomical vocabulary, explicit-direct register, specific act patterns.
- Cast mapping: "Maya is alone with Daniel" (tells writer the cast but not the *acts*).
- Result: writer generates a scene with the source's beat shape, hits the explicit-direct register from the voice descriptor, but invents act-content because the prompt explicitly forbids reusing the source plot.

With per-beat style retrieval, beat 3 (a `dialogue/escalation` modality+function) of the new scene would retrieve top-K chunks from the source whose modality+function tags match, giving the writer concrete vocabulary and rhythm patterns *appropriate to this beat type*. That's the missing signal.

---

## 2. Current-state diagnosis

### 2.1 What exists today (state at 2026-05-14)

**Phase 5 References.**
- User adds a Reference text via Bible Workspace → "+ Add reference."
- Body is paste-into-textarea (no upper bound enforced).
- Clicking "Ingest" runs `BibleWorkspaceWindowController.ingestReference` → `AppState.ingestReference` → background Python subprocess (`PythonStyleDistanceClient`) chunks + embeds.
- Per-reference sidecar: `references/<uuid>.index` (chunks + StyleDistance vectors).
- Used at generation time ONLY by `GenerationCoordinator.styleRetriever` (the closure resolves the project's `RetrievalService` at every call). Retrieved chunks land in the writer prompt as `[STYLE EXEMPLARS]` via `StyleExemplarsLayer.format`.
- **Not currently used by** `TemplateGenerationCoordinator`.

**Phase 7 Template Scenes.**
- User adds a Template via Bible Workspace → "+ Add template."
- Body is paste-into-textarea.
- Clicking "Extract" runs `BibleWorkspaceWindowController.extractTemplateScene` → `AppState.extractTemplateScene` → Ollama gemma4_2b call → `OllamaBeatExtractor` produces an `ExtractedSceneSkeleton`.
- Per-template sidecar: `templates/<uuid>.beats.json` (beats + sourceCharacters + sourceSettingMarkers + voiceDescriptor).
- Used at generation time ONLY by `TemplateGenerationCoordinator` (per-beat writer call loop). Skeleton + voice descriptor + full source body all land in the writer prompt.
- **Does not retrieve from References** at any point.

### 2.2 The gap

A user with one NSFW scene they'd like to use as a complete imitation source must today:

1. Open Bible Workspace → References → "+ Add reference" → paste → "Ingest."
2. Wait for chunking + embedding.
3. ALSO open Templates → "+ Add template" → paste the same text → name it → "Extract."
4. Wait for Pass-A extraction.
5. Now they have two artifacts holding the same body in two different shapes. To use both, they invoke Continue with retrieval *or* Template-generate, but not both simultaneously.

Even if both pipelines composed cleanly, the user is doing dual-ingest of the same source, paying duplicate disk + duplicate compute, and managing two artifacts that should logically be one.

### 2.3 The dual-source case

A subtler case: what if a user wants exemplar A (for shape) and exemplar B (for content register)? The current Phase 5 retrieval *can* pull from multiple References simultaneously (top-K is across all `.index` sidecars). The proposed Phase 8 unified flow should preserve that: at template-generation time, the writer should still be able to retrieve style chunks from any exemplar in the project, not just the chosen template. This is captured in §4 as the "retrieval scope" decision.

---

## 3. End-state user-facing flow (Phase 8.b v1 target)

1. User opens **Bible Workspace → Scene Exemplars** (new merged surface; existing References + Templates rows can either fold under this OR remain as views over the same underlying type — see §5.1 for the data-model decision tree).
2. Clicks **+ Add scene exemplar**, pastes prose (~500–5000 words), names it.
3. Clicks **Ingest**. ONE background pipeline runs:
   - Pass-A extraction (gemma4_2b → `.beats.json`) — beats + voice descriptor + characters + setting markers.
   - Chunking + embedding (Python subprocess → `.index`) — chunks tagged with their parent beat's modality + function from Pass-A's output, so beat-aware retrieval becomes possible (§6.3).
   - Both sidecars share the same UUID + parent body.
4. Workspace UI surfaces the exemplar with two state indicators ("N beats on disk", "M chunks on disk"); both come from the same ingest action.
5. Editor: user invokes "Write scene from exemplar" — the existing Phase 7 menu, renamed.
6. Generation runs per-beat. For each beat the writer prompt assembles:
   - Skeleton (existing).
   - Voice descriptor (existing).
   - Full source body (existing, optionally controllable — see §5.4).
   - Cast mapping (existing).
   - **NEW:** top-K retrieved chunks from the exemplar's `.index`, filtered by matching modality + function tag where possible (§6.3).
7. Result: a new scene with the exemplar's shape, voice, AND chunk-level explicit-content vocabulary patterns.

### 3.1 Alternative entry points (Phase 8.b v2+)

- **Continue/Expand with exemplar guidance.** Normal Continue/Expand calls (`GenerationCoordinator`) can take an optional exemplar argument from the editor's tray — the writer gets the exemplar's `[STYLE EXEMPLARS]` chunks (retrieval) and `[VOICE TARGET]` block (descriptor) but no beat scaffolding.
- **Whole-scene mode.** "Write whole scene from exemplar at cursor" without a beat-by-beat loop — useful when the user wants speed over structural fidelity.

These are explicit future work; the v1 deliverable is the unified ingest + template-style generation path.

---

## 4. Architectural decisions (proposed; will become D1–Dn after research)

These are **proposed** in this draft. Each D-decision should either be locked after empirical evidence from Phase 8.a, or deferred to Phase 8.b with a clearly-documented "still open" status.

- **D1 (proposed): single ingest, dual sidecar.** One user action ("Ingest exemplar") triggers both Pass-A extraction (`.beats.json`) AND chunking-embedding (`.index`). Both sidecars share the exemplar's UUID; the exemplar body is the single source of truth on disk.
- **D2 (proposed): chunks inherit Pass-A modality + function tags.** When the embedder chunks the body, each chunk records the modality + function of the beat it overlaps. Beat-aware retrieval (§6.3) uses this for filtered top-K.
- **D3 (proposed): retrieval at template-generation per beat, scoped to the chosen exemplar by default, with explicit project-wide opt-in.** The writer prompt for beat N retrieves top-3 chunks from the exemplar's `.index` whose modality + function match (with fallback to unfiltered top-3 if no matches). User can override scope to "all exemplars" via a Phase 8.b setting.
- **D4 (DEFERRED to spike):** is StyleDistance the right embedder for NSFW register matching, or do we need a content-aware embedder for this use case? See §6.1.
- **D5 (DEFERRED to spike):** does per-beat retrieval (re-query per beat) measurably beat per-scene retrieval (one query, same exemplars across all beats)? See §6.2.
- **D6 (DEFERRED to spike):** does beat-aware chunking (chunks aligned to Pass-A beats) measurably beat sentence-window chunking (Phase 5 default)? See §6.3.
- **D7 (DEFERRED to design):** does the existing Phase 7 instruction "Do NOT reuse plot, characters, settings, or specific events" need softening? The §15.14 smoke test surfaced a user who *wants* the writer to keep specific act patterns. See §5.3.
- **D8 (DEFERRED to design):** how do we name + surface the merged concept in the UI without breaking existing user mental models? See §5.1.

---

## 5. Open design questions (no empirical work needed)

### 5.1 Data model unification

**Option A: full type merge.** Drop `ReferenceText` + `TemplateScene` as distinct user-facing types. One new type `SceneExemplar` with a body, an optional `.beats.json` sidecar, and an optional `.index` sidecar. Both sidecars are always built at ingest time. Existing on-disk data is migrated via a one-shot Phase 8.a migration (References → exemplars without `.beats.json`; Templates → exemplars without `.index`).

**Option B: shared-storage with separate UI surfaces.** Keep References + Templates as user-facing types (some users may have non-overlapping mental models for "a chapter excerpt I want to embed" vs. "a structurally important scene I want to imitate"). Add a new "Ingest exemplar" action that creates BOTH a Reference and a Template pointing to the same body. The Bible Workspace shows both — UI complexity stays the same but the user only has to ingest once.

**Option C: rename + soft-merge.** Rename the user-facing surface to "Scene Exemplars" but keep the two backing types under the hood. Each ingest creates both. The UI surface is unified ("Scene Exemplars" pane shows one card per body), and "References" + "Templates" become internal storage details. Migration path: existing References + Templates remain as-is on disk; the workspace UI merges them by body-content hash for de-duplication where possible (or simply lists them as two cards from different ingest histories).

**Recommendation: Option C** for v1. Lowest migration risk, lets users continue to think in their existing model, gradual transition. Option A is the right long-term shape; defer until Phase 8.c if Option C proves to add complexity.

### 5.2 Concurrent vs. sequential extraction-and-embedding

The Pass-A extraction (gemma4_2b, ~30s) and the embedding pass (StyleDistance via Python subprocess, ~5-10s per 1000 words) are independent. Running them concurrently halves end-to-end ingest latency for the user. But they share machine resources (Ollama + Python on the same box) — empirical decision on whether concurrency causes interference is a Phase 8.a probe.

If concurrent: extraction surfaces "X beats" while embedding surfaces "Y chunks" in parallel, both with their own in-flight indicators on the same card.

### 5.3 Should we soften the "do not reuse plot" instruction?

The Phase 7 D4 STRAP decision was: aggressive content stripping (character names → role tokens; setting markers held in a separate list) plus a writer-prompt instruction to NOT reuse plot. The §7.a.3 spike validated zero source-character-name leakage across 31 beats.

But the §15.14 + 2026-05-14 smoke test surfaced a use case where the user *wants* the writer to reuse specific act patterns (NSFW exemplar case). The current pipeline tells the writer "do not reuse" — and the writer dutifully invents content.

**Three positions:**

1. **Keep D4 as-is.** Add per-beat retrieval; the writer indirectly sees the source's vocabulary via retrieved chunks, but the prompt still says "do not reuse plot." Retrieval supplies the *pattern*; the cast mapping supplies the *content*. This is the cleanest narrative — retrieval is the new lever, the existing scaffolding stays consistent.

2. **Make D4 user-controllable.** Add an "imitate content" toggle to the template-generation menu. Off (default): current behavior. On: prompt drops the "do not reuse" instruction; retrieval still drives per-beat style; writer can lift surface vocabulary from the source.

3. **Drop D4 entirely.** With retrieval supplying chunks at every beat, the writer will naturally lean on the source's vocabulary. The "do not reuse plot" instruction becomes self-contradictory ("don't reuse — here are 3 chunks of the source to use as reference").

**Recommendation: position 2 for Phase 8.b.** Default-off so existing behavior is preserved; a Phase 8.b spike (§6.4) measures whether default-on produces measurably better outputs for the NSFW exemplar case.

### 5.4 Should the full source body remain in the writer prompt when per-beat retrieval is also present?

Phase 7's `BeatGeneration.buildBeatPrompt` includes the full source body as a voice exemplar in the system framing. With per-beat retrieval added, this becomes potentially redundant — the retrieved chunks ARE substrings of the source. Token-wise, a 3000-word source body + 3×~150-word retrieved chunks = ~3500 tokens of "voice signal" per beat call, which is expensive on a 16k-context model when you also need beat history + cast mapping + voice descriptor.

**Three positions:**

1. **Keep both.** Belt and braces; the writer sees the whole scene AND fresh per-beat retrieved snippets. Costs tokens, gains insurance.
2. **Drop the full body when retrieval is configured.** Per-beat retrieval is more targeted; the full body is now overkill.
3. **Truncate the full body to head + tail.** Show the opening + closing paragraphs as "voice example," let retrieval supply the middle.

**Recommendation: 2 for Phase 8.b** if the §6.5 spike shows per-beat retrieval matches or exceeds the current full-body-only baseline. If retrieval underperforms full-body, fall back to position 1 (keep both) or position 3 (truncate).

### 5.5 In-flight indicator design for the unified ingest

The current Phase 7.b in-flight indicator (post-2026-05-13 commit) flips the editor's button to "Extracting…" during Pass-A. The unified pipeline runs TWO async passes (extraction + embedding). UI question: one combined "Ingesting…" state, or two distinct states ("Extracting beats…" / "Embedding chunks…")?

**Recommendation:** one combined state that displays whichever sub-pass is currently active. Implementation: extend `AppState`'s in-flight set to track exemplar UUIDs (not just `extractingTemplateIds`), and label the in-flight phase ("beats" / "chunks" / "ingesting") in the snapshot field.

---

## 6. Open research questions (calls for spike work in Phase 8.a)

Each of these should be resolved by a focused empirical probe before Phase 8.b lock. The spike runner pattern from `Tools/SceneTemplateSpike` (existing) is the model — add subcommands as needed.

### 6.1 Is StyleDistance the right embedder for NSFW register matching?

**Hypothesis under test.** StyleDistance is trained for style similarity in general fiction (per [Patel et al., NAACL 2025](https://arxiv.org/abs/2410.12757)); its training distribution underrepresents explicit/NSFW prose, so embedding cosine-similarity between two explicit passages may collapse toward "all explicit content looks alike" — losing the discrimination we need for register matching.

> **Post-audit note (2026-05-14, see [`LOOM_SCENE_EXEMPLAR_RESEARCH.md`](LOOM_SCENE_EXEMPLAR_RESEARCH.md)).** The hypothesis is structurally near-certain rather than merely plausible: StyleDistance's training set (SynthSTEL) is built from C4 sentences paraphrased by GPT-4, and C4 applies the LDNOOBW blocklist (whole pages deleted on any explicit term). The §6.1 candidate set below is also revised: of the six original candidates, only StyleDistance is style-trained — the other five (mxbai, bge, E5-mistral, Voyage-3, Linq) are *retrieval/topical* embedders. The audit recommends narrowing to **StyleDistance + iBERT (EACL 2026, arXiv:2510.09882, +8 STEL points) + one retrieval baseline (mxbai-embed-large)**.

**Probe.** Hand-curate 6–10 NSFW passages spanning register axes:
- Clinical (medical/textbook tone)
- Euphemistic (literary, indirect)
- Explicit-direct (anatomically specific, present-tense)
- Explicit-poetic (lyrical, metaphor-heavy)
- Explicit-mundane (workmanlike, low-flourish)

Compute pairwise StyleDistance cosine, mxbai-embed-large cosine, and bge-large cosine. Score: does the embedding give higher cosine to same-register pairs than cross-register pairs? Repeat for SFW passages spanning similar style axes as a baseline.

**Decision rule.** If StyleDistance pairwise cosine separates NSFW registers as well as it separates SFW styles, keep it. If it underperforms (e.g. same-register cosine within 0.05 of cross-register cosine), test mxbai-embed-large + bge-large as candidates. If none of the three discriminate cleanly, escalate: the embedder choice becomes a Phase 8.b open scope, possibly requiring a custom NSFW-fine-tuned embedder.

**Stretch probe.** Test [E5-mistral-7b](https://huggingface.co/intfloat/e5-mistral-7b-instruct) and [Voyage-3](https://docs.voyageai.com/) — larger embedders that may have broader training-data coverage. Cost/benefit: bigger embedder = slower per-chunk embedding at ingest, but better discrimination at gen-time.

### 6.2 Per-beat retrieval vs. per-scene retrieval

**Hypothesis under test.** Per-beat retrieval (one query per beat, using beat summary + cast mapping as query string) supplies more targeted style cues than per-scene retrieval (one query at scene start, same chunks used across all beats).

**Probe.** Pick 3 exemplars and 3 cast mappings each (9 total scenarios). Run generation in both modes (per-beat / per-scene), 2 seeds each. Hand-grade outputs blind on a 1–5 voice-fidelity scale.

**Decision rule.** If per-beat ≥ per-scene by 0.5+ on the rubric, lock per-beat. If they're tied, lock per-scene (cheaper — N-1 fewer retrieval calls per generation).

### 6.3 Beat-aware chunking vs. sentence-window chunking

**Hypothesis under test.** Chunks aligned to Pass-A beat boundaries (one chunk per beat, even if 200 words) carry stronger modality+function signal than uniform sentence-windowed chunks (the Phase 5 default).

**Probe.** Re-index the same exemplar two ways:
- (A) Sentence-window: existing Phase 5 chunker.
- (B) Beat-aligned: chunk = beat. Each chunk inherits the beat's modality + function tags as metadata.

For each, run modality-filtered retrieval (only retrieve chunks tagged with the current beat's modality+function). Compare output quality on the same 9 scenarios from §6.2.

**Side benefit.** Beat-aligned chunking lets us answer a subtler question: does the writer benefit more from "match this modality" or from "match this register"? Test (C): unfiltered top-K against beat-aligned chunks. If (C) ≈ (B), filtering by modality is mostly cosmetic.

### 6.4 Soft-D4 spike (allow content reuse)

**Hypothesis under test.** When the user wants the writer to imitate explicit-content patterns, softening the "do not reuse plot" instruction (per §5.3 option 2) produces measurably better outputs.

**Probe.** Same 9 scenarios from §6.2. Run with:
- (A) Default prompt (D4 strict): "Do NOT reuse its plot, characters, settings, or specific events."
- (B) Softened prompt: drop the "specific events" clause; instruct "Substitute the cast described below; preserve the source's content register, vocabulary, and act patterns where appropriate."

Score: voice fidelity (1–5) + content-pattern overlap (lexical similarity between source and output on a hand-curated "explicit vocabulary" word list).

**Decision rule.** If (B) > (A) for voice fidelity AND content-pattern overlap is measurably higher without character-name leakage, recommend D4 soft default for the "imitate content" toggle. If character names leak, fall back to a more restrictive softening.

### 6.5 Full-body-in-prompt vs. retrieval-only

**Hypothesis under test.** Per-beat retrieval can replace the full source body in the writer prompt without quality loss, freeing ~3000 tokens of context budget.

**Probe.** Same 9 scenarios. Run with:
- (A) Current: full body in prompt + no retrieval (Phase 7 baseline).
- (B) Per-beat retrieval + no full body.
- (C) Both.

Score voice fidelity + content-pattern overlap. If (B) ≥ (A): drop full body. If (C) > (B) but (B) ≥ (A): keep retrieval; full body becomes opt-in (could be useful for very short exemplars).

### 6.6 Pre-existing-art audit — LANDED 2026-05-14

**Deliverable:** [`LOOM_SCENE_EXEMPLAR_RESEARCH.md`](LOOM_SCENE_EXEMPLAR_RESEARCH.md). ~1900 words, 19 numbered sources.

**Conclusions in two lines:**
- **No prior-art surfaced that obsoletes Phase 8.** Sudowrite's Style Examples + scene-bullet objectives (Story Engine 3.0, 2026) is closer than the Phase 7 audit captured, but it's still user-authored structure, not extracted-from-prose. Market gap survives.
- **§6.1 candidate set is partially miscalibrated; revised in the audit conclusions.** See post-audit note in §6.1 above and the audit's "Recommendations" section.

The original §6.6 search-term brief is preserved in the audit doc. Future re-audits should cite this version as the baseline.

---

## 7. Test plan

TDD-always (per repo convention). Each component below is delivered with a failing test → green → commit cycle. Where the component is pure-data (prompt assembly, query construction, decision logic), it's unit-testable via TestKit. Where it's async-with-completion (extraction, retrieval), it uses the deferred-stub pattern (snapshot-then-clear-then-fire) — never synchronous `completion(...)` inside test stubs.

### 7.1 Unit tests (pure data)

**Per-beat retrieval query construction.**
- Given a beat (summary + modality + function), cast mapping, and prior-beats prose, produce a query string. Test that the query includes beat summary, cast mapping, and the last prior-beat sentence as recency anchor.
- Test that the query string doesn't leak source-character names (cast-mapping substitution applied first).

**`BeatGeneration.buildBeatPrompt` with style exemplars.**
- Empty exemplar list → no `[STYLE EXEMPLARS]` block in output.
- Non-empty exemplar list → block present, formatted via `StyleExemplarsLayer`.
- Test that the block lands BEFORE `[INSTRUCTION]` (writers benefit from style cues being visible at decision time).

**Chunk-with-beat-metadata Codable.**
- Chunk shape now carries `modality: NarrativeMode?` + `function: BeatFunction?`. Test round-trip via JSONEncoder/Decoder.
- Test backward-compat: chunks on disk pre-Phase-8 (no modality+function fields) decode with both as nil.

**Beat-filtered retrieval filter logic.**
- Given a chunk list + current beat (modality + function), produce a filtered candidate list. Test:
  - Exact-modality+function match → in candidate set.
  - Same modality, different function → in candidate set with weaker score.
  - Different modality → fall-back candidate (only if no better matches).
- Test the fallback: when zero chunks match modality, the filter degenerates to unfiltered top-K.

**Snapshot field `inFlightExemplarIds: [UUID]`.**
- Extending the existing `extractingTemplateIds` to cover the combined extraction-and-embedding phase. Test Codable + the legacy-decode path (empty default when field missing).

### 7.2 Integration tests (async-with-completion)

**`AppState.ingestExemplar(id:)` (NEW).**
- Single entry point that fans out to Pass-A extraction AND embedding. Test:
  - Posts in-flight-start notification before either sub-task fires.
  - Posts in-flight-end only when BOTH sub-tasks complete.
  - Partial-failure handling: if extraction succeeds but embedding fails, the exemplar carries a `.beats.json` but no `.index`. Test that this state is recoverable (user can re-trigger ingest).
- Uses the deferred-stub pattern for both sub-tasks.

**`TemplateGenerationCoordinator` with style retriever.**
- Per-beat: writer prompt includes top-K retrieved chunks. Test via a stub retriever that records each query string and returns canned chunks; assert chunks land in the prompt at the right position.
- Test that retrieval is per-beat (N retrieval calls for N beats), not per-scene (1 call), when configured that way.
- Test the retrieval-scope decision (D3): default-on retrieves only from the chosen exemplar; opt-in retrieves project-wide.

**End-to-end fixture-driven test.**
- Curate a single ~2000-word exemplar (NSFW or non-NSFW; either works for plumbing tests).
- Bootstrap: ingest, await both passes, then invoke generation with a known cast mapping.
- Assert: writer was called N times (one per beat). Each call's prompt contained the skeleton, voice descriptor, retrieved chunks, cast mapping. Generated output has at least N×50 words.

### 7.3 Spike tests (Phase 8.a empirical)

These are NOT unit tests — they're empirical-validation tests run via the spike runner (`Tools/SceneExemplarSpike`, new — or extend `Tools/SceneTemplateSpike`). Outputs land in a Markdown report graded against fixtures.

- §6.1 embedder discrimination: pairwise cosine matrix across 8-10 NSFW + 8-10 SFW passages, three embedders.
- §6.2 per-beat vs. per-scene: 9 scenarios, 2 seeds each, hand-grade voice fidelity.
- §6.3 beat-aware vs. sentence-window chunking: same 9 scenarios.
- §6.4 strict vs. softened D4 prompt: same 9 scenarios.
- §6.5 full-body vs. retrieval-only: same 9 scenarios.

Each spike test outputs a structured Markdown report with the rubric scores so hand-grading is reproducible. Findings land in `LOOM_SCENE_EXEMPLAR_SPIKE.md` (companion empirical doc, parallels `LOOM_SCENE_TEMPLATE_SPIKE.md`).

### 7.4 UI smoke tests

Driven manually by the user (per existing smoke-test pattern, e.g. HANDOFF.md §15.14). Not unit tests. Items:

1. Single ingest action creates both sidecars; UI surfaces both state indicators.
2. In-flight indicator shows during BOTH sub-passes; clears on completion.
3. Partial-failure recovery (embedding fails but extraction succeeds): UI shows the exemplar with "N beats on disk · 0 chunks (re-ingest)" or similar; clicking re-ingest only re-runs embedding.
4. Generation against an exemplar produces a scene whose register/vocabulary visibly tracks the source's (subjective; the spike fixtures provide a more rigorous version).
5. Cancel mid-extraction: extraction stops; embedding proceeds (or also stops? — design decision in 8.b).
6. The merged UI surface ("Scene Exemplars") doesn't surprise existing users who had References + Templates.

---

## 8. Phasing

### Phase 8.a — Spike (empirical-only, no production code changes)

**Goal:** answer §6.1–6.5 with empirical data + an updated literature audit (§6.6). No production code changes; the spike runner is additive.

**Sub-rows:**
- 8.a.1 — **LANDED 2026-05-14.** Fixture set at `Tools/SceneExemplarSpike/fixtures/` — 10 NSFW × 5 register axes (clinical / euphemistic / explicit-direct / explicit-poetic / explicit-mundane, 2 fixtures per axis) + 10 SFW × 5 matched style axes (clinical-procedural / baroque-Victorian / clipped-Hemingway / lyrical-McCarthy / mundane-workmanlike, 2 fixtures per axis). Each fixture is ~400-440 words of original prose with YAML frontmatter (`fixture_id`, `title`, `nsfw`, `register`, `style_axis`, `source`, `word_count`, `notes`). Total 8570 words of original prose; all hand-authored, no third-party source attribution required.
- 8.a.2 — **LANDED 2026-05-14.** §6.6 literature + competitor audit at [`LOOM_SCENE_EXEMPLAR_RESEARCH.md`](LOOM_SCENE_EXEMPLAR_RESEARCH.md). 1900 words, 19 cited 2024–2026 sources. Headline findings: §6.1 hypothesis structurally near-certain (StyleDistance trained on C4-with-LDNOOBW + GPT-4 paraphrases); §6.1 candidate set should narrow to **StyleDistance + iBERT (EACL 2026) + one retrieval baseline (mxbai-embed-large)**; unified-exemplar market gap survives the 2025-Q4 → 2026-Q1 commercial landscape; StyleDistance arXiv ID corrected (2410.12757, was 2403.05841).
- 8.a.3 — §6.1 embedder discrimination probe. Spike runner subcommand. Deliverable: pairwise cosine matrix + ranking + recommendation.
- 8.a.4 — §6.3 chunking strategy probe. Spike runner subcommand. Deliverable: per-strategy retrieval recall + qualitative chunk inspection.
- 8.a.5 — §6.2 + §6.5 generation-quality probes. Spike runner subcommand that drives end-to-end generation in 3 modes; hand-grade rubric.
- 8.a.6 — §6.4 prompt-softening probe. Spike runner subcommand that runs the same scenarios with strict + softened prompt; hand-grade for register fidelity AND for the failure modes the strict prompt was guarding against (character-name leakage in particular).
- 8.a.7 — Spike write-up. Compile findings into `LOOM_SCENE_EXEMPLAR_SPIKE.md`; turn each D5–D7 deferred decision into a locked D-decision.

**Exit criteria:** all D-decisions locked OR explicitly punted to Phase 8.b with documented rationale. Doc updated with a "Status: design lock" header.

### Phase 8.b — Production

**Goal:** implement the unified ingest + generation flow per the Phase 8.a locked design.

**Sub-rows (rough cut — subject to revision once 8.a lands):**
- 8.b.1 — Data model: `SceneExemplar` type (or shared abstraction, per §5.1 decision) + on-disk layout.
- 8.b.2 — `AppState.ingestExemplar(id:)` — fan-out to Pass-A + embedding, in-flight tracking, notification surface.
- 8.b.3 — `BeatGeneration.buildBeatPrompt` extension: accept `styleExemplars: [StyleExemplar]`, render via `StyleExemplarsLayer`. Pure-data.
- 8.b.4 — `TemplateGenerationCoordinator` retrieval wiring: per-beat query construction + retrieval call + injection.
- 8.b.5 — `RetrievalService` extension: beat-aware filtering if §6.3 lands beat-aligned chunks. May require a new index format version.
- 8.b.6 — Bible Workspace UI: merged "Scene Exemplars" surface per §5.1 Option C. Migrate the existing Templates + References surfaces.
- 8.b.7 — In-flight indicator unified per §5.5.
- 8.b.8 — D4 soft toggle per §6.4 if the spike validates it.
- 8.b.9 — Smoke-test queue + HANDOFF update.

### Phase 8.c — Polish (post-MVP)

- §3.1 alternative entry points (Continue/Expand with exemplar; whole-scene mode).
- Cross-exemplar retrieval scope toggle.
- If §5.1 Option C is the v1 choice, evaluate whether Option A (full type merge) becomes worth the migration in 8.c.
- Per-beat re-roll (carried over from LOOM_SCENE_TEMPLATE.md §11 future work).

---

## 9. Risks + mitigations

| Risk | Mitigation |
|---|---|
| Spike work surfaces no clear winner (StyleDistance ≈ mxbai ≈ bge for NSFW) | Default to the cheapest-to-run (Phase 5 incumbent); document the tie + revisit when a better embedder appears. |
| Per-beat retrieval adds N×retrieval-latency to template generation | Cache retrieval results across re-rolls; allow user toggle "fast / quality" if the latency cost is unwelcome. |
| Beat-aware chunking requires re-index migration | Versioned `.index` format; provide a one-shot migration in 8.b.5; old chunks still work via the unfiltered fallback path. |
| Softened D4 (per §5.3 option 2) re-introduces character-name leakage | Hard floor: the per-beat prompt still strips source-character names via the existing role-token substitution. The softening targets surface vocabulary, not names. |
| UI churn from §5.1 surface change confuses existing users | Pick Option C (rename + soft-merge), not Option A (full type merge), for v1. Keep existing data interpretable. |
| NSFW retrieval pulls inappropriate chunks (e.g. retrieves graphic content for a non-NSFW project) | Per-exemplar NSFW flag (already exists); retrieval respects it. If the active project doesn't have NSFW flagged exemplars, NSFW chunks don't surface. |
| Spike outputs lean on hand-grading; subjective | Pair every rubric with a programmatic auxiliary metric (StyleDistance cosine of output vs. source; lexical overlap with a curated vocabulary list) so the spike has at least one objective signal. |

---

## 10. References (to chase during §6.6 audit)

- **Patel et al., StyleDistance (NAACL 2025)** — [arXiv:2410.12757](https://arxiv.org/abs/2410.12757). The §6.6 audit confirmed: SynthSTEL is built from C4 (which applies the LDNOOBW filter, deleting whole pages on any explicit term) + GPT-4 paraphrases. NSFW exclusion is structurally certain. Earlier draft of the design doc cited arXiv:2403.05841 — that was the wrong arXiv ID for this line of work.
- **Anand et al., iBERT (EACL 2026)** — [arXiv:2510.09882](https://arxiv.org/abs/2510.09882). Sparse-sense decomposition over RoBERTa-base; +8 points on STEL style benchmark over SBERT-style baselines. Identified by the §6.6 audit as the right addition to the §6.1 probe.
- **DRAMATRON (Mirowski et al., CHI 2023)** — [arXiv:2209.14958](https://arxiv.org/abs/2209.14958). Reference point from Phase 7 §3.2 audit; check for follow-on work in 2024-2025.
- **Sudowrite "Match My Style"** — current product. Phase 7 audit noted 2000-word cap; check for changes.
- **NovelCrafter "Scene Beats"** — current product. Re-audit for any exemplar-based feature additions since 2025-Q3.
- **Phase 5 RAG spike** (`LOOM_RAG_SPIKE.md`) — empirical findings on retrieval; check §13.3(d) framing on "voice, not content" instruction. This phrasing may need revisiting under D7-soft.
- **Voyage-3 / E5-mistral-7b / Linq-Embed-Mistral** — recent embedders that may outperform StyleDistance for fiction; cost vs. benefit analysis in §6.1.
- **Loom memory entry: "Verify research-doc gap claims before designing around them"** — before locking the §6.1 embedder recommendation, run a focused web-search pass. The Phase 5 spike would have missed StyleDistance otherwise.
- **Loom memory entry: "Prompt blacklists get evaded by paraphrase"** — relevant to D4 softening. If we drop "do not reuse plot" the writer may still need positive constraints ("use the cast described below as the primary source of new content") rather than a negative blacklist.

---

## 11. Glossary

- **Exemplar.** A scene-sized prose body (~500–5000 words) that the user has ingested as both a structural template and a stylistic reference. Captures shape (via Pass-A skeleton) + voice (via voice descriptor) + content register (via embedded chunks).
- **Pass-A extraction.** gemma4_2b extraction of beats + voice descriptor + sourceCharacters + sourceSettingMarkers from an exemplar body. Phase 7 incumbent.
- **Pass-B generation.** Per-beat writer call loop. Phase 7 incumbent.
- **Style exemplar (lowercase).** Phase 5 terminology for a retrieved chunk used as a few-shot example in the writer prompt. Distinct from "Scene Exemplar" (the unified Phase 8 ingest artifact).
- **Retrieval scope.** Whether per-beat retrieval pulls from the chosen exemplar only (default) or from all exemplars in the project (opt-in). Captured in D3.
- **D4-strict vs. D4-soft.** Phase 7's "do not reuse plot/characters/settings/specific events" instruction (strict) vs. a Phase 8 candidate softening that drops "specific events" so explicit-content patterns can transfer (soft).

# Loom — Plan

> **Status: Phase 0 design lock (2026-05-10).** Research synthesised in [`LOOM_RESEARCH.md`](LOOM_RESEARCH.md). This document supersedes [`PLAN.md`](PLAN.md) — that file is retained as historical scaffolding. Mirrors the shape of `/Volumes/SSD1/Code/RPClient/V2_PLAN.md` (inventory table, phase list with status, references).
>
> **Repo state:** `main` branch only, local-only (remote not yet configured). No code in tree — design docs only.

## 0. What Loom is

A **local-LLM-powered fiction-writing app for macOS**, built on the same kobold backend as RPClient. Long-form work (essays, short stories, novellas, novels) with persistent characters, settings, events, and timeline. Heavy NSFW-friendly (the user's local uncensored model handles content; Loom is the tool). Single-user, no collab/cloud sync. TTS deferred indefinitely.

**Metaphor:** Scrivener with AI grafted in — a long-form document editor as the primary surface, with AI generation as inline insertions and side-pane controls, **never as a chat transcript**.

**The non-negotiables** (per [`LOOM_RESEARCH.md`](LOOM_RESEARCH.md) §N):

- Local kobold backend, no cloud, no filtering.
- Story Bible as a structured-but-skippable entity composition (Sudowrite[A2] + Campfire[K1]).
- Memory + Author's Note + Lorebook trichotomy from NovelAI/KoboldAI/SillyTavern[C2][D1][H1].
- Scene-as-markdown-file on disk; project-as-directory (Obsidian Longform[J5]).
- Generation-context transparency (Sudowrite History chiclets[A5]).
- Knowledge-state-per-character (Re3 Edit module[L4]) — Loom's distinctive engineering.

---

## 1. Inventory + status

| # | Loom item | Status | Phase | Pointer |
|---|---|---|---|---|
| L0 | Phase 0 — research + design docs | ✅ landed 2026-05-10 | 0 | this doc + [`LOOM_RESEARCH.md`](LOOM_RESEARCH.md) + [`LOOM_MEMORY.md`](LOOM_MEMORY.md) (memory deep-dive) + [`LOOM_FANFIC.md`](LOOM_FANFIC.md) (fanfic-mode feature) + [`LOOM_NSFW.md`](LOOM_NSFW.md) (heavy-NSFW posture) + [`LOOM_UI_RESEARCH.md`](LOOM_UI_RESEARCH.md) (live-captured UI prior art driving design language §14 updates) |
| L1 | Editor MVP (single-window, NSTextView, kobold wired, Continue + Expand, .md export) | ✅ landed 2026-05-10 (+Phase 1.5: Rewrite, per-call instruction box, A/N depth-N, Cmd-, Settings) | 1 | [`LOOM_PHASE1_EDITOR_MVP.md`](LOOM_PHASE1_EDITOR_MVP.md) |
| L2 | Story Bible v1 (Characters + Settings + basic Timeline; injection into prompts) | ✅ landed 2026-05-11 (+Phase 2.5 polish: @-popover, mention sparkline bar, hover preview) — see [`HANDOFF.md`](HANDOFF.md) §11 + §12 | 2 | [`LOOM_STORY_BIBLE.md`](LOOM_STORY_BIBLE.md), [`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md) |
| L3 | Hierarchical structure + navigation (Project tree → Parts → Chapters → Scenes; Corkboard view; word counts) | ✅ §A–§F landed 2026-05-11 — see [`HANDOFF.md`](HANDOFF.md) §13 | 3 | [`HANDOFF.md`](HANDOFF.md) §13 |
| L4 | Generation-mode expansion (Rewrite sub-modes, Show-don't-tell, Brainstorm, Critique, Bridge, Roll-Outcome); per-mode prompt templates; knowledge-state-per-character extraction; NSFW polish (Continue-from-refusal, Sphiratrioth pack, WritingDirection, DynamicSheets, anti-slop banned_strings, per-character kinks + anatomy) | ✅ feature-complete (Phase 4.x residuals — extractor coverage variance on NSFW + a broader pressure-test pass — remain deferred). Per HANDOFF §15. Landed: rewriteVoice + rewriteTense + rewriteLength + rewritePOV + show-don't-tell prompt layers + a coherent Rewrite sub-mode picker UI (Voice/Tense/Length/POV-per-character/SDT/Generic) with the POV path threading `LedgerKnowledge.compute` through `RewritePOVDescriptor.build` to fill the §4.3 KNOWLEDGE_LEDGER_HINT slot, scope-discipline clause across all rewrite-family system prompts (closes most of the Gemma 4 over-contextualization failures surfaced in live testing), Lorebook section in the Bible inspector (rename / edit content / edit keys / flip Constant↔Keyed), Qwen3.6-27B vs Gemma 4 31B writer A/B comparison run across Tests 1–7 (full results in [HANDOFF.md §15.9](HANDOFF.md); strategic verdict: Gemma preferred despite ~5× latency, scope clause closed its main weaknesses), Continue-from-refusal, Sphiratrioth pack, Roll-Outcome action, knowledge-ledger feasibility spike (5 rounds), **knowledge-ledger pipeline #7 sub-tasks 1–8 shipped end-to-end** (Ollama role-routed extractor, debounced post-scene side-call, diff-vs-existing, Suggestions panel UI, bible persistence, scene-exposure-based `unknown` derivation, `[KNOWLEDGE-LEDGER]` prompt layer, sidebar "Set POV" submenu, §10.5 production filters — embedding dedup + evidence-quote validation + prompt-leakage). Live verified 2026-05-11 evening: paste prose → ~30s → suggestions queue populates with per-character breakdown. Phase 4 #7 is feature-complete; remaining gaps (extractor coverage variance + NSFW pressure-test) are Phase 4.x deferred. | 4 | [`LOOM_GENERATION_MODES.md`](LOOM_GENERATION_MODES.md), [`LOOM_STORY_BIBLE.md`](LOOM_STORY_BIBLE.md), [`LOOM_NSFW.md`](LOOM_NSFW.md), [`LOOM_LEDGER_SPIKE.md`](LOOM_LEDGER_SPIKE.md) |
| L4.5 | **Bible Workspace** — dedicated second NSWindow for entity management, rendered via **WKWebView** (React + Vite + TS + Tailwind + shadcn/ui) as a contained pivot away from AppKit. Closes the cramped-side-pane UX surfaced during 2026-05-13 live testing. Houses: full character editors (every `Character` field); **accepted-facts examiner** (per-character KNOWS grouped by scene with delete affordance — fills the Phase 4 #7 gap where accepted ledger facts are invisible after acceptance); Lorebook power-user fields (priority / group / weight / sticky / positionMode / depth / secondaryKeys / enabled — deferred from §14.1 #10 v1); suggestions queue review. Side-pane inspector + main editor stay AppKit. **All five sessions landed 2026-05-12 → 2026-05-13. Phase 4.5 complete; see [`LOOM_BIBLE_WORKSPACE.md`](LOOM_BIBLE_WORKSPACE.md) for authoritative plan + per-session ledger + tech-stack rationale.** **Session 1 ✅ 2026-05-12** — WKWebView shell + bridge + Vite/React/TS/Tailwind build pipeline + read-only entity list rendering live snapshots from Swift; 17 new TestKit pure-data tests. **Session 2 ✅ 2026-05-12** — full character editor (every `Character` field surfaced as a form, debounced JS→Swift intent dispatch via `CharacterPatch` + `BibleWorkspaceIntent.patchCharacter`); +20 TestKit. **Session 3 ✅ 2026-05-12** — full lorebook editor (all 13 LorebookEntry fields, conditional `depth` when positionMode=depthN, add/delete affordances, NumericField helper fixing the controlled-numeric-input quirk); +19 TestKit. **Session 4 ✅ 2026-05-13** — accepted-facts examiner closes the §15.9 audit gap (facts grouped by source scene with certainty pills + delete affordance); Tabs primitive on the character editor; SnapshotCharacter projection re-keys `[UUID: [KnownFact]]` to string keys for JS-friendly JSON-object form; +10 TestKit. **Session 5 ✅ 2026-05-13** — cross-character suggestions queue review surface; accept/reject intents wired through `AppState.acceptLedgerSuggestion` / `rejectLedgerSuggestion`; suggestions observer pushes fresh snapshots on queue mutations; pending-count pill in entity-list header opens the surface; +3 TestKit. **Phase 4.5 complete** at 880/880 tests across the five-session arc. | ✅ landed 2026-05-13 | 4.5 | [`LOOM_BIBLE_WORKSPACE.md`](LOOM_BIBLE_WORKSPACE.md) |
| L5 | Style ingestion (RAG-for-style; chunk reference texts; embed via D Wegmann (was StyleDistance, pivoted in L8) + E function-word z-score hybrid index; per-NSFW-status retrieval) | ✅ production complete 2026-05-13 — engine + writer-prompt integration (§15.12), `AppState.styleRetriever` injection into `GenerationCoordinator` (A1, `964f242`), Swift+React Bible Workspace References surface (A2.1 `cd9a476` / A2.2 `3081579`) all landed. L8 CoreML migration (Phase 8.c) removed the Python subprocess so the 7.65s subprocess cold-start UX gap is moot. **Live-app integration smoke still pending** (the §15.13 carry-over list, items A1/A2.1/A2.2) — pipeline is verified at test-suite + spike-runner level (1116/1116) but the real `Loom.app` flow (open project → add reference → Ingest → write scene → confirm `[gen] style-retrieval: N exemplars` log + exemplars shape prose) has not been driven end-to-end. | 5 | [`LOOM_RAG_SPIKE.md`](LOOM_RAG_SPIKE.md) §13 (verdict: PIVOT, D+E hybrid); [`LOOM_NARRATIVE_MODE_SPIKE.md`](LOOM_NARRATIVE_MODE_SPIKE.md) §10 (modality classifier); [`LOOM_MLX_PORT_SPIKE.md`](LOOM_MLX_PORT_SPIKE.md) §12 (venv pivot); [`LOOM_RESEARCH.md`](LOOM_RESEARCH.md) §O.4; [`HANDOFF.md`](HANDOFF.md) §15.13 carry-over list |
| L5b | Canon-brief storage on Bible entities; user-paste fandom canon ingestion (re-uses L5 pipeline) | pending | 5.b | [`LOOM_FANFIC.md`](LOOM_FANFIC.md) §3.2 |
| L5c | Fanfic Mode — Project kind, ATTG header, Ship/AU/Trope schemas, bundled trope library, fandom templates, fanfic-specific generation modes | pending | 5.c | [`LOOM_FANFIC.md`](LOOM_FANFIC.md) §9 |
| L6 | Polish + export (Markdown / RTF / .docx / ePub; search; autosave + version history; AO3-conformant frontmatter export) | pending | 6 | TBD |
| L7 | **Scene-Template Generation** — ingest a scene-sized prose chunk (500–5000 words) as a *template scene*; user asks Loom to write a new scene that preserves the source's beat ordering, modality flow, and pacing curve but with new characters / setting / surface content. Two-pass DOC-style architecture (extract structural skeleton via Ollama side-task with GBNF; per-beat instantiation via writer LLM with template framed as voice-exemplar-only). New `TemplateScene` entity (mirrors Phase 5 A2 References pattern); reuses `NarrativeModeClassifier` for per-beat modality verification (Phase 5 carry); reuses `OllamaLedgerExtractor` JSON-schema pattern (Phase 4 carry). Closes a market gap identified in extensive 2026-05-13 prior-art research: no current tool (Sudowrite Match-My-Style, NovelCrafter Codex, NovelAI Modules-defunct, SillyTavern Lorebook, DreamGen Opus) ships a "scene-as-structural-blueprint" primitive distinct from outline-down planning or voice-only style matching. Documented failure modes (surface mimicry overriding voice with long exemplars per Tripto 2025; plot leakage per Krishna 2020 STRAP; pacing flattening per Re3/DOC ablations) each have a concrete mitigation locked in the design. **Spike (7.a.1/2/3/4) + production v1 (7.b.1–6) all landed 2026-05-13** — full architecture in production code; live-app empirical pass remains (see HANDOFF §15.14 smoke-test list 5–10). 7.a.4 added explicit voice-descriptor extraction + injection on top of the planned 7.b architecture; verified to measurably move prose toward target voice (LOOM_SCENE_TEMPLATE_SPIKE.md §4). | 🚧 architecture complete; live-app smoke pending | 7 | [`LOOM_SCENE_TEMPLATE.md`](LOOM_SCENE_TEMPLATE.md), [`LOOM_SCENE_TEMPLATE_SPIKE.md`](LOOM_SCENE_TEMPLATE_SPIKE.md) |
| L8 | **Unified Scene Exemplar** — collapse the dual-ingest friction surfaced during Phase 7 live testing. One user action ("+ Add scene exemplar" in Bible Workspace) creates a Reference + Template under a shared UUID; one "Ingest" fans out to BOTH Pass-A extraction AND chunking+embedding. Per-beat writer prompts retrieve top-K style chunks from the project's references (Wegmann-cosine, beat-modality-aware), so the writer sees structural skeleton + voice descriptor + per-beat retrieved chunks + cast mapping together. "Imitate content" toggle softens the D4 prompt for the NSFW-exemplar case + an "Additional instructions" per-call hint field for per-generation steering. Field state persists per-template (`<project>/template-gen-state/<id>.json`) with gen-log backfill so iterating on regenerations doesn't require re-typing the cast. **Phase 8.a (design + spike)**: §6.6 prior-art audit ✅; §6.1 4-candidate embedder probe locked **D4 to Wegmann** (StyleDistance underperformed even the topical baseline; Wegmann Style-Embedding +0.285 separation vs. +0.086 for StyleDistance); D5–D8 design-locked per §5.x. Phase 5 retrieval migrated from StyleDistance to Wegmann inside this arc. **Phase 8.b (production)**: 8.b.1/3/4/5/6/7/8 landed + smoked through 4 iteration rounds (meta-block leakage with cascade-breaking sanitizer + extended stop sequences + SYSTEM clause, mid-word truncation via numPredict bump, leading-char placeholder race, end-of-gen editor-view reconciliation with coordinator's canonical insertedText). 8.b.2 deferred to 8.c. **Phase 8.b-runtime**: Wegmann inference migrated from Python subprocess to native CoreML via huggingface/swift-transformers + Apple's MLModel; cosine-equivalent to 1e-4; Loom.app drops ~3GB of Python deps. | ✅ Phase 8.a + 8.b complete + smoked; CoreML migration landed | 8 | [`LOOM_SCENE_EXEMPLAR.md`](LOOM_SCENE_EXEMPLAR.md), [`LOOM_SCENE_EXEMPLAR_RESEARCH.md`](LOOM_SCENE_EXEMPLAR_RESEARCH.md), [`LOOM_SCENE_EXEMPLAR_SPIKE.md`](LOOM_SCENE_EXEMPLAR_SPIKE.md) |

| L9 | **Entity Discovery** — extends Phase 4 Pass-B (fact extraction on known characters) to also discover new characters, places, and named significant objects in scene prose, attach extracted facts, and surface them in the Bible Workspace as accept/reject/edit suggestions. Six-stage pipeline (Stage A2 candidate gen via Ollama gemma4_2b + JSON Schema → Stage B promotion gate (proper-noun-only, anatomy block-list, place-recurrence) → Stage C cosine dedup against existing bible (CoreML Wegmann) → Stage D normalisation → post-Stage-D dedup → ProposedEntitiesStore). Triggers: auto via piggyback on `LedgerExtractionCoordinator.onExtractionComplete` (gated by `EntityDiscoveryTrigger` 500-word per-scene baseline), manual via Bible menu, demo via `swift run EntityDiscoverySpike --into <project>`. Spike empirically validated **precision 100% / recall 85.7% / F1 92.3%** across 8 hand-graded fixture scenes (5 from LedgerSpike + 3 newly-authored NSFW scenes for entity-discovery signals). Surface: amber "Discovering N scene(s)…" pulse-dot indicator while running; emerald "N entity proposals →" badge when results land; per-row card with editable canonical_name + aliases + one_line + evidence quote + collapsible attached facts; accept promotes to real `Character` / `Setting` / `BibleObject` with facts attached to `knownFactsBySceneId`. Stage A2 + beat-extractor both retry on `noJSONObjectFound`/`noJSONArrayFound` (catches the ~30% transient parse-fail rate on NSFW). Out of scope at v1 (additive v2 candidates documented in spike §5): cross-scene coref, lorebook auto-discovery, relationship-fact discovery, faction discovery, bulk import. | ✅ Phase 9 v1 + object kind shipped, GO @ §6.4; live smoke pending | 9 | [`LOOM_ENTITY_DISCOVERY_SPIKE.md`](LOOM_ENTITY_DISCOVERY_SPIKE.md) |

| L10 | **Continuity Audit** — automated whole-manuscript contradiction detection across four classes (factual attribute drift, knowledge-state violations, timeline/chronology, spatial/world). Pipeline architecture: per-scene typed-claim extraction (LLM, schema-constrained) → deterministic typed fact-base + attribute diffing → candidate-conflict retrieval (entity index + Wegmann embeddings) → pairwise NLI adjudication (LLM, one claim pair at a time) → severity-ranked evidence-cited review queue in the Bible Workspace. Knowledge-state checks reuse `LedgerKnowledge.compute`; timeline checks walk `flatSceneIds`. Verified market gap (no fiction tool ships cross-scene contradiction auditing — competitors prevent-at-generation). Naive whole-document LLM judging rejected per ContraDoc (GPT-4 ~54% precision). False-positive defenses: source-attribution (dialogue = character belief, not world-fact), time-indexed facts, defeasible reveals, evidence-grounding, ranked human-review queue. Phasing: A spike (de-risk pairwise adjudication precision) → B engine → C Bible Workspace surface + on-demand trigger → B.2 spatial class → D incremental trigger. Triggers: on-demand first, incremental later. **Phase A spike complete 2026-05-17 — GO**: pairwise adjudication F1 0.89 (precision 80% / recall 100%) with Goetia as adjudicator, far above the ~54% ContraDoc whole-document baseline; small models (gemma4_2b/4b) fail the gate. **Phase B built + architecturally validated 2026-05-18** — ~12 TDD modules (`ContinuityAudit*`, `OllamaContinuityExtractor`, `ContinuityClaimFilterPipeline`, `ContinuityAuditEngine`/`Store`), 1855 tests green; extraction two-staged + tuned (Goetia 24B), claim-filter embedder wired, knowledge check routed through the adjudicator, run end to end against the live models. Honest state (§19): the pipeline is sound and surfaces real contradictions, but per-run coverage is **stochastic** (extraction recall ~83%) and precision is imperfect — a usable review aid, not yet polished. Remaining: sustained extraction recall/precision tuning (the dominant lever — needs its own eval harness), then Phase C (Bible Workspace surface). **§22–§28 (2026-05-19/20) ran the tuning arc end to end.** §22 built the eval harness and shipped the retrieval/filter rewrite (per-run recall ~17%→35%, pass@k 65%). §23–§24 diagnosed and rebuilt the `knowledge_violation` path with seven TDD fixes + a writer-model A/B; on Gemma-4-31B abliterated + the fixes, knowledge went 0/4→3/4 at k=1. §25–§26 explored a DeBERTa-v3 NLI proposition gate (Part A): built end to end, measured no win, ripped out. §27–§28 explored a same-fact-LLM ledger (Part B) in two shapes (global ledger; per-k cosine top-K): built end to end, measured a net negative on Goetia (knowledge 0/4 vs legacy's 1/4; overall recall 35% vs legacy's 44%), reverted. Honest state of L10 today: the §24 legacy path is the best available; Gemma-4-31B abliterated is best for `knowledge_violation` (3/4) but Goetia is the default writer model (1/4 there). Phase C (Bible Workspace review-queue surface) is still pending — and is now the highest-leverage next move on L10. | 🚧 Phase B built + tuned + bounded; Phase C (Bible Workspace surface) pending | 10 | [`LOOM_CONTINUITY_AUDIT.md`](LOOM_CONTINUITY_AUDIT.md) §22–§28 |

**Deferred indefinitely:** voice/TTS, multi-user collab, cloud sync, mobile companion.

**Possible scope additions surfaced by research, parked:**

- **Plottr-shaped 2D Timeline × Plotline grid**[E1] — high value, large scope; Phase 4+ candidate (after generation modes are settled).
- **Snapshots-before-AI-rewrite**[J1] — small implementation, high user value; could shift forward into Phase 2 if cheap.
- **Focus mode (current-paragraph emphasis)**[iA Writer] — Phase 1 candidate if cheap; otherwise defer.
- **Pinned spans (raw paragraphs, never evicted)** [character.ai pattern, [`LOOM_MEMORY.md`](LOOM_MEMORY.md) §A2.3] — Phase 2 candidate; cheap to implement, high trust value.
- **Bracketed `[...]` Author's Note convention** [AI Dungeon pattern, [`LOOM_MEMORY.md`](LOOM_MEMORY.md) §A2.2] — Phase 1 default framing; free.
- **Subcontext-packing for keyed bible entries** [NovelAI pattern, [`LOOM_MEMORY.md`](LOOM_MEMORY.md) §A2.6] — Phase 2.
- **Eviction-order surfacing in History tab** [AI Dungeon pattern, [`LOOM_MEMORY.md`](LOOM_MEMORY.md) §A2.7] — Phase 1 if cheap.

---

## 2. Differences from RPClient

| Axis | RPClient | Loom | Source |
|---|---|---|---|
| Primary surface | Chat transcript (turns) | Long-form document editor (NSTextView) | research §M.1 |
| Data shape | Chat → Turn (linear, branching) | Project → Part → Chapter → Scene → Beat (hierarchical) | research §J.1, §K |
| Generation paradigm | Reply to user message | Insert / expand / rewrite at cursor; multiple modes | research §M.3 |
| Memory | Rolling summary + entities | Story bible (entity sheets, knowledge ledger, timeline) + per-scene recap chain | research §L, §M.2 |
| Reference text | Character cards (~5KB) | Full reference works (200k+ words) chunked + retrieved | research §O.1, §O.4 |
| Multi-character | Cast + speaker selection (turn-by-turn) | POV character per scene (document-level) | research §M.2 |
| Prompt assembly | PromptBuilder (chat-shaped) | New PromptBuilder (story-shaped: bible + adjacent scenes + author's note + style) | research §O.6 |
| Audio | TTS pipeline | Deferred indefinitely | PLAN §1 |
| Branching | Per-turn variant tree | Per-scene drafts (similar pattern, different unit) | research §J.1 (Snapshots) |

---

## 3. Tooling carry-over from RPClient

Same Swift Package layout, same Swift+AppKit posture. **Carry-over with minor adapters:**

- `KoboldClient`, `ServerProbe`, `KoboldClientRegistry` — direct reuse, rename namespace `LoomCore`.
- `DebugLog` — direct reuse with new subsystems (`[editor]`, `[bible]`, `[rag]`, `[style]`, `[gen]`).
- `Storage` — pattern reused; layout shifts to per-project-directory (research §M.1).
- `Settings` skeleton — direct reuse; remove chat-specific fields.
- TestKit — direct reuse.
- `build.sh` / `run.sh` — sed `RPClient` → `Loom` during Phase 1 bootstrapping.

**Do not carry:** `ChatViewController`, `TurnView`, `FlowPillRow`, `CardCreator*`, `Speaker*`, anything chat-shaped (research §O.6).

**Inherit-then-mutate:** `PromptBuilder` — different shape but the layered-injection pattern (system / memory / world-info / history) is the right primitive; rebuild for story-mode rather than reuse.

---

## 4. Plan documents — produced in Phase 0

In dependency order. Every doc cites [`LOOM_RESEARCH.md`](LOOM_RESEARCH.md) for non-trivial claims.

| # | Doc | Status | Contains |
|---|---|---|---|
| 1 | [`LOOM_RESEARCH.md`](LOOM_RESEARCH.md) | ✅ landed 2026-05-10 | Citation-grounded prior-art survey: Sudowrite, Novelcrafter, NovelAI, KoboldAI/SillyTavern, Scrivener, Plottr, Campfire, Backyard, AutoCrit + r/LocalLLaMA culture + long-context engineering literature. Cross-cutting synthesis. Load-bearing-for-Loom + gap-finding sections. |
| 2 | `LOOM_PLAN.md` (this doc) | ✅ landing 2026-05-10 | Master plan, mirrors V2_PLAN.md shape. |
| 3 | [`LOOM_DESIGN_LANGUAGE.md`](LOOM_DESIGN_LANGUAGE.md) | ✅ landing 2026-05-10 | RPClient V2 Design Language verbatim foundation + Loom-specific surfaces appended (long-form editor, Bible inspector, project tree, History chiclets, empty-state, generation-mode buttons). |
| 4 | [`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md) | ✅ landing 2026-05-10 | Project / Part / Chapter / Scene / Beat shapes. Entity sheets (Character, Setting, Object, Faction). Knowledge ledger per character. Timeline event. Style sheet. Codable + on-disk layout. |
| 5 | [`LOOM_GENERATION_MODES.md`](LOOM_GENERATION_MODES.md) | ✅ landing 2026-05-10 | Per-mode prompt templates. Continue, Expand, Rewrite (voice / tense / POV / length variants), Show-don't-tell, Brainstorm, Critique, Bridge. Per-mode context-assembly strategy. Token-budget allocation at 8k/16k/32k. |
| 6 | [`LOOM_STORY_BIBLE.md`](LOOM_STORY_BIBLE.md) | ✅ landing 2026-05-10 | The consistency engine: entity stamping, fact pinning, knowledge-state evolution per scene per character, prompt injection mechanics. Builds on Re3 Edit module (research §L.2). |
| 7 | [`LOOM_PHASE1_EDITOR_MVP.md`](LOOM_PHASE1_EDITOR_MVP.md) | ✅ landing 2026-05-10 | First-shippable slice. Sub-step contracts (mirrors V2_UI_OVERHAUL.md §4.11). |
| 8 | `HANDOFF.md` | ✅ landing 2026-05-10 | What's settled, what's open, sub-step ordering, where research changed PLAN.md's strawman. |
| 9 | [`LOOM_SCENE_TEMPLATE.md`](LOOM_SCENE_TEMPLATE.md) | ✅ landing 2026-05-13 | Phase 7 design lock proposal: ingest-scene-then-generate-like-it feature. Prior-art-grounded architectural decisions (two-pass DOC-style, STRAP content stripping, per-beat modality verification), failure-mode catalogue with mitigations, scope locks, sub-row breakdown, spike plan. ~2100 LOC new + ~1400 LOC leveraged from Phases 4/4.5/5. |
| 10 | [`LOOM_SCENE_EXEMPLAR.md`](LOOM_SCENE_EXEMPLAR.md) | 🚧 landing 2026-05-14 | Phase 8 design proposal (NOT YET LOCKED): unify the Phase 5 Reference + Phase 7 Template ingest paths into a single "Scene Exemplar" workflow so one source body contributes BOTH structural skeleton AND style-RAG retrieval signal to a generated scene. Specifies the five-question Phase 8.a spike (embedder discrimination on NSFW register; per-beat vs. per-scene retrieval; beat-aware vs. sentence-window chunking; strict vs. softened "do-not-reuse-plot" prompt; full-body-in-prompt vs. retrieval-only) + the data-model unification choice (full type merge / shared storage / rename + soft-merge — proposes the third for v1) + full test plan (unit + integration + spike + UI smoke). |

---

## 5. Phasing (refined from PLAN.md §5)

### Phase 0 — Research + design docs (this phase)
Five intended parallel research subagents collapsed to a single parent-context research pass when subagent web access proved unavailable in this sandbox. Findings synthesised in [`LOOM_RESEARCH.md`](LOOM_RESEARCH.md). All seven design docs land together for a single commit set. **End-state:** every Phase 1 sub-step has a citation or an explicit "going beyond prior art" rationale.

### Phase 1 — Editor MVP
Single-window app, NSTextView-based scene editor, kobold client wired, two generation modes (Continue + Expand), bare-bones project/scene model with sidebar, save as Markdown.

**MVP completeness gate** (research-validated):

- Project tree (Binder)[J1] — Scrivener pattern; minimal: list of scenes for one project.
- Scene editor (NSTextView) — long-form prose with markdown rendering on demand.
- Kobold backend wired (KoboldClient + ServerProbe) — direct RPClient reuse.
- 1–3 minimal character sheets (name + paragraph) — no Bible inspector yet, just storage + injection.
- Two generation modes: Continue (from cursor), Expand (from selection)[A6].
- Author's Note field for the project (carry from RPClient memory subsystem).
- **History chiclets** — one-line "what was sent?" disclosure[A5] (cheap; sets the transparency norm from day 1).
- Markdown export (single .md file with frontmatter).

**End-state:** user types a sketch → clicks Expand → gets prose. Or types a paragraph → cursor at end → clicks Continue → gets prose. Edits freely. Saves as `.md`.

See [`LOOM_PHASE1_EDITOR_MVP.md`](LOOM_PHASE1_EDITOR_MVP.md) for sub-step contracts.

### Phase 2 — Story Bible v1
Character sheets (full Sudowrite-style[A2] schema), Setting sheets, basic Timeline. Bible content **selectively injected** into generation context per the constant/keyed/vectorised trichotomy[H1].

- Bible inspector pane (extends RPClient's inspector grammar).
- Codex-style entity references in prose (Novelcrafter `{{character.name}}` grammar[B3] adapted).
- Always-inject (constant) + keyword-trigger (keyed) modes. Vectorised deferred to Phase 5.
- Author's Note depth-N injection mechanic[C3] (existing concept made explicit in UI).
- **Snapshots before AI rewrite** if cheap — Scrivener[J1] pattern, considered for shift-left from Phase 5+.

### Phase 3 — Hierarchical structure + navigation
Project → Part → Chapter → Scene tree, drag-rearrange, word counts at every level, target-words per scene/chapter/project, **Corkboard view**[J2] (drag-rearrange scene cards). Per-scene metadata (POV, time, location, conflict, outcome — yWriter[J7] schema).

### Phase 4 — Generation-mode expansion + knowledge ledger
Rewrite (with sub-modes: voice / tense / POV / length / formality), Show-don't-tell, Brainstorm, Critique, Bridge. **Per-character knowledge ledger** built and queried at generation time (Re3 Edit pattern[L4], extended per-scene). This is Loom's distinctive engineering.

- Each new scene's prose is post-processed by a side-call extractor (RPClient's `summarizer` role server, like RPClient Phase 4[V2_PLAN] §2.4).
- Extractor produces character-fact tuples: `(character, fact, scene, certainty)`.
- At generation time, the model is told what the speaking character does and doesn't yet know.

### Phase 4.5 — Bible Workspace (dedicated entity-management window)
Phase 4's knowledge-ledger work shipped the data flow (extract → suggest → accept → persist → render-in-prompt) but exposed two UX gaps under live testing 2026-05-13:

- No surface displays the **accepted** ledger facts back to the user. Once a suggestion is accepted, it persists onto `Character.knownFactsBySceneId` and feeds the `[KNOWLEDGE-LEDGER]` prompt layer, but disappears from the visible inspector. The user can't audit what their POV character "knows" without `jq`-ing `project.json`.
- The Lorebook editor (§14.1 #10 v1) covers only 4 of 11 `LorebookEntry` fields; power-user knobs (priority, group, weight, sticky, positionMode, depth, secondaryKeys, enabled) deferred because the side-pane is already cramped at 4 fields.

The right shape is a **second NSWindow** ("Bible Workspace") dedicated to entity management, **rendered via WKWebView** as a contained pivot away from AppKit. Decision context: the AppKit cost ledger (Phase 1.5 ~3h on macOS-26 layout bugs + Phase 4 2026-05-11 ~1h+ on the auto-refit-to-fittingSize cascade, with brittle workarounds stacking) reached the threshold where the workspace's form-heavy surfaces (multi-pane layouts, complex schemas, eventually a corkboard) are no longer the right shape for AppKit. The main editor + side-pane inspector + Plan view + manuscript sidebar all stay AppKit; this is a scoped pilot on one new window. Stack: React + Vite + TypeScript + Tailwind + shadcn/ui; bridge via WKScriptMessageHandler with Swift as source of truth.

Houses:

- Full character editor — every `Character` field (relationships, canon-brief, custom fields, etc.).
- Per-character **Accepted-facts examiner** — KNOWS list grouped by sceneId with fact text + certainty pill + a delete affordance (undo an accepted fact).
- Suggestions-queue review surface (the per-character chip moves here too, freeing the side-pane).
- Lorebook full editor (all 11 fields, position/depth/group pickers, sticky toggle, etc.).
- Future: factions, timeline events, style sheets (Phase 5+ entity types); Phase 5+ corkboard for scene cards drops into the same stack.

Side-pane inspector stays for always-visible mode + inject-pill workflow. The workspace window is for **deep editing**, not for the always-glanceable summary.

Landing this BEFORE Phase 5 means style ingestion's reference-text management UI surfaces in the new architecture from day one rather than retrofitting later.

**Authoritative scope, session breakdown, bridge contract, TDD discipline, risks + rollback, and per-session ledger live in [`LOOM_BIBLE_WORKSPACE.md`](LOOM_BIBLE_WORKSPACE.md).** Five-session arc, ~16h total estimated. Session 1's exit criteria are the abandon-pivot decision point — if WKWebView fights us catastrophically, the doc carries the rollback path (delete `web/`, ship remaining sessions as AppKit forms; cost lost = Session 1 only).

### Phase 5 — Style ingestion (RAG-for-style)

Chunk reference texts, embed via a **hybrid D + E index**, retrieve relevant style exemplars per generation.

**Spike verdict (2026-05-13):** [`LOOM_RAG_SPIKE.md`](LOOM_RAG_SPIKE.md) §13 ran a 5-path eval over a 4-style × 3-topic fixture (8 NSFW / 4 SFW). Path D ([StyleDistance](https://huggingface.co/StyleDistance/styledistance), Oct 2024 SOTA contrastive style embedder, encoder-only via Python sidecar) won the headline (NDCG@3 0.883, preference +0.833) but showed a ~25% NSFW derank — the §3 Reddit-skew hypothesis confirmed. Path E (150-dim function-word z-score, ~50 LOC of numpy, zero deps) **tied D on NDCG** and was the most NSFW-parity-balanced path. Path C (writer-LLM-distilled GBNF descriptors) failed below floor (NDCG 0.485) because gemma-31B descriptors collapsed to default enums across very different prose. Paths A/B (semantic embedders nomic, mxbai, bge) passed NDCG by retrieving NSFW-content rather than style — the §1 "topic not style" failure mode confirmed, with "topic" being "NSFW status."

**Architecture decision: D + E hybrid index.** Per the §7 PIVOT branch + the user's 2026-05-13 call: reference texts index in both spaces. At retrieval time the system surfaces top-K from each and merges by normalised score (always-retrieve-from-both keeps the content-neutrality directive of [LOOM_NSFW.md §3](LOOM_NSFW.md) intact — no NSFW classifier, no moderation gate). E is so cheap (150-dim, possibly portable to pure Swift in an afternoon) that the second index is essentially free. This sidesteps the Reddit-skew NSFW derank in D and protects against the §13.3(b) caveat (E ties D on the spike fixture; may diverge on real reference texts, in which case the hybrid degrades gracefully to D alone).

**Production scope locks needed at Phase 5 start:**

1. ~~**StyleDistance deployment.**~~ ✅ **Python subprocess via existing venv, closed 2026-05-13** after the MLX-Swift path was pivoted from per [`LOOM_MLX_PORT_SPIKE.md`](LOOM_MLX_PORT_SPIKE.md) §12. Initially planned to ship MLX via [`MLXEmbedders`](https://github.com/ml-explore/mlx-swift-lm) but runtime failed with missing `default.metallib` (mlx-swift's documented limitation: "SwiftPM command-line cannot build Metal shaders — has to be done via Xcode"); user's machine has CLT only + 29 GB disk free (Xcode minimal install needs ~15-20 GB on a near-full volume), so pivoted to a long-lived Python subprocess (`Sources/LoomCore/Retrieval/PythonStyleDistanceClient.swift`) running StyleDistance via the existing `sentence-transformers` venv. Bit-identical (cosine 1.000000) against the canonical PyTorch baseline. Subprocess dies with parent; no daemon, no port management. ~7.65s cold start, 0.05-0.2s per warm embed. Phase 5.5 deployment work: bundle Python + venv into `Loom.app/Contents/Resources/` (~1 GB) and add ML-native-lib code-signing to build.sh.
2. **E (function-word z-score) Swift port.** ~50 LOC in `Sources/LoomCore/Retrieval/`, vendor `Tools/RagSpike/Python/embed_offline.py`'s `embed_path_e` directly. No external dependency.
3. **Reference-text entity type in the Bible Workspace.** Mirrors Phase 4.5 Sessions 2–5 patterns; the React-side scaffolding already covers list/editor/intent dispatch. Add a new `Reference` snapshot kind + view + intent cases. Storage at `references/<id>.md` + `<id>.index` per [LOOM_PLAN.md §7](LOOM_PLAN.md).
4. ~~**Hybrid retrieval merge policy.**~~ ✅ **RRF k=10 with equal weights, closed 2026-05-13** per [`LOOM_RAG_SPIKE.md`](LOOM_RAG_SPIKE.md) §13.8. Pre-implementation research surveyed RRF / DBSF / convex-combination / cross-encoder rerank prior art and confirmed RRF is the right tool for two-complementary-dense-embedders (vs the usual dense+sparse hybrid). k=10 instead of Cormack 2009's k=60 because Loom retrieves top-3 over ~50 chunks, not TREC top-1000. Empirically validates: hybrid NDCG@3 0.926 vs individual 0.883, preference +0.917 vs +0.833 / +0.750, NSFW hit rate 0.875 vs D-alone 0.750. Implemented as `RankingMetrics.reciprocalRankFusion(rankings:k:weights:)`, ~30 LOC. Fallbacks (convex combination with per-query z-score; user-tag-driven weight shifts) trivially extend the same API if real-corpus data exposes a limit.
5. ~~**Per-scene-type retrieval pillar.**~~ ✅ **Two-pass hybrid (heuristic dialogue-gate + gemma-31B zero-shot + flat GBNF), closed 2026-05-13** per [`LOOM_NARRATIVE_MODE_SPIKE.md`](LOOM_NARRATIVE_MODE_SPIKE.md) §10. Taxonomy extended from [LOOM_RESEARCH.md §O.4](LOOM_RESEARCH.md)'s 4 to **6** ({action, dialogue, interiority, description, summary, mixed}) — pre-spike research surfaced `summary` (Marshall 1998 / Card 1999) as a load-bearing missing category. Empirical eval over 52-chunk hand-labeled gold: heuristic 55.8% (below 70% floor, but 100%/87.5% precision/recall on dialogue specifically), zero-shot LLM 73.1% (above floor, dialogue recall weak at 37%), 4-shot LLM 51.9% with 31.7% NSFW parity gap (violates spike spec — drop). Hybrid composition exploits heuristic dialogue strength + LLM residual coverage. Implemented at [`Sources/LoomCore/Retrieval/NarrativeModeClassifier.swift`](Sources/LoomCore/Retrieval/NarrativeModeClassifier.swift); `modality` schema slot on [`ReferenceTextIndex.Chunk`](Sources/LoomCore/Models/ReferenceText.swift) accepts every [`NarrativeMode`](Sources/LoomCore/Models/NarrativeMode.swift) raw value.

This is still Loom's largest single phase. The spike collapses the R&D risk that was the original gate; what remains is production architecture.

### Phase 6 — Polish + export
Markdown / RTF / .docx / ePub via Compile-style pipeline[J1]. Search across project. Find/replace. Autosave + version history.

### Phase 7 — Scene-Template Generation

Ingest a scene-sized prose chunk (500–5000 words) as a *template scene*; user asks Loom to write a new scene that preserves the source's beat ordering, modality flow, and pacing curve but with new characters and surface content.

**Product positioning** (2026-05-13 prior-art research, full citations in [`LOOM_SCENE_TEMPLATE.md`](LOOM_SCENE_TEMPLATE.md) §3): no current tool ships a "scene-as-structural-blueprint" primitive. Sudowrite's Match-My-Style handles voice with a 2k cap; NovelCrafter is outline-down (beat description → prose); NovelAI Modules — the closest historical analog — was discontinued in Oct 2024 and has no announced replacement; SillyTavern's Lorebook is keyword-triggered retrieval, not structural priming; DreamGen Opus is instruction-driven, not example-driven. Loom occupies the gap.

**Architecture** (DOC Yang et al. ACL 2023 pattern, scoped to scene granularity): two-pass — Pass A extracts structural skeleton (beat list with function + modality + target words + pacing stats) via Ollama side-task with GBNF-constrained JSON; Pass B instantiates per-beat on the writer with the template framed explicitly as voice-exemplar-only. STRAP-style content stripping (Krishna et al. 2020) defends against plot leakage; per-beat modality verification via [`NarrativeModeClassifier`](Sources/LoomCore/Retrieval/NarrativeModeClassifier.swift) (Phase 5 carry) catches modality drift; positive numerical pacing constraints (ZeroStylus 2025) preserve cadence where adjectival prompts collapse to model default.

**Phase 7.a — Spike.** Empirical validation gates on 3 axes (extraction quality, generation quality, long-exemplar pitfalls) over 5 hand-curated scenes. Mirrors the Phase 5 RAG + Narrative Mode spike discipline. Decision gate at exit: ship v1 production architecture as-is, refine, or pivot.

**Phase 7.b — Production v1.** Scope locks contingent on 7.a outcomes. Anticipated: TemplateScene entity + storage; BeatExtractionPipeline; `.generateFromTemplate` mode with per-beat loop; Bible Workspace surface (Template Scenes section, mirrors Phase 5 A2 References); in-editor picker + free-form cast hint field. ~60–70% leveraged from existing infrastructure (RagChunker, NarrativeModeClassifier, OllamaLedgerExtractor pattern, BibleWorkspace bridge pattern, GenerationCoordinator); ~2100–2300 LOC new (data model, pipeline, per-beat loop, UI).

**Phase 7.c — v2 features.** Two-dial UI (match-shape / match-voice), structured cast-mapping table, modality flow editor, per-beat re-roll, character-voice integration with Bible. Contingent on 7.b production validation.

**Authoritative scope, prior-art summary, failure-mode catalogue with mitigations, sub-row breakdown, and citations live in [`LOOM_SCENE_TEMPLATE.md`](LOOM_SCENE_TEMPLATE.md).**

### Phase 8 — Unified Scene Exemplar

Surfaces a friction discovered during Phase 7 live testing (smoke-test session 2026-05-14): a user with one source scene they want to imitate must currently ingest it twice — once via the Phase 5 References path (chunked + StyleDistance-embedded so it surfaces in style-RAG retrieval for normal Continue/Expand) and again via the Phase 7 Templates path (Pass-A skeleton extracted so it can drive template-style generation). The two pipelines don't compose: `TemplateGenerationCoordinator` doesn't currently consult `styleRetriever`, and ingest is a manual dual-action burden.

**Motivating use case** (per the LOOM_SCENE_EXEMPLAR.md §1 NSFW exemplar example): the Phase 7 voice-descriptor extraction captures sentence cadence + register + 2–5 distinctive techniques, but a 5-field structured fingerprint under-resolves the surface vocabulary patterns that distinguish, say, clinical-explicit prose from explicit-poetic prose. The chunks already exist on the Phase 5 References side — they just need to be plumbed into the template-generation prompt path.

**Phase 8.a — Spike.** Five empirical probes resolve the open D-decisions before production lock:

- §6.1 Is StyleDistance the right embedder for NSFW register matching, or do mxbai-embed-large / bge-large / E5-mistral-7b discriminate better? Pairwise cosine across hand-curated 8–10 NSFW + 8–10 SFW passages spanning register axes.
- §6.2 Per-beat retrieval (re-query per beat) vs. per-scene (one query) — 9 scenarios, 2 seeds, hand-grade rubric.
- §6.3 Beat-aware chunking (chunks aligned to Pass-A beats, modality+function tagged) vs. sentence-window (Phase 5 default).
- §6.4 D4-strict vs. D4-soft prompt: does softening "do NOT reuse plot/characters/settings/specific events" produce measurably better register fidelity without reintroducing character-name leakage?
- §6.5 Full source body in prompt + retrieval vs. retrieval-only (token-budget question — current full-body-in-prompt costs ~3000 tokens per beat call on a 16k context model).

Plus a literature/competitor re-audit (§6.6) — has any 2025-Q4 / 2026-Q1 work changed the embedder or the unified-exemplar landscape since the Phase 7 prior-art pass?

**Phase 8.b — Production v1.** Locked scope depends on 8.a outcomes; anticipated: unified `SceneExemplar` surface (per §5.1 Option C: rename + soft-merge, both backing storage types retained); `AppState.ingestExemplar(id:)` fans out to Pass-A + embedding with combined in-flight tracking; `BeatGeneration.buildBeatPrompt` extension to accept retrieved chunks; `TemplateGenerationCoordinator` retrieval wiring with beat-aware filtering (if §6.3 lands beat-aligned chunks); Bible Workspace merged "Scene Exemplars" surface; optional D4-soft toggle if §6.4 validates it.

**Phase 8.c — Polish.** Continue/Expand with exemplar guidance (currently only the template-generation path uses exemplars); whole-scene-from-exemplar mode (no beat-by-beat loop); evaluation of `SceneExemplar` full-type-merge (per §5.1 Option A) if soft-merge proves overly complex.

**Authoritative scope, design decisions, open research questions, test plan, and risk catalogue live in [`LOOM_SCENE_EXEMPLAR.md`](LOOM_SCENE_EXEMPLAR.md).**

### Phase 9 — Entity Discovery (in production, 2026-05-15)

Extends Phase 4 Pass-B (fact extraction on known characters) to also **discover new characters and places** in scene prose, attach extracted facts, and surface them in the Bible Workspace webview as accept/reject/edit suggestions. Pipeline shape (per LOOM_ENTITY_DISCOVERY_SPIKE §3.1): Stage A2 candidate generation (Ollama gemma4_2b w/ JSON Schema) → Stage B promotion gate (proper-noun-only at v1, anatomy block-list, place-recurrence) → Stage C cosine dedup against existing bible (CoreML Wegmann) → Stage D normalisation (Ollama again, per-candidate canonical-name + alias-union + one-line) → post-Stage-D dedup by canonical name → write to `ProposedEntitiesStore`. Spike empirically validated precision 100% / recall 85.7% / F1 92.3% across 8 fixture scenes; latency ~33s/scene at the model's Stage A2 floor.

**Surface**: new `EntityProposalsQueue.tsx` view in the Bible Workspace; emerald "N entity proposals →" header badge alongside the existing accent-colored "N pending suggestions →" badge. Per-row card with editable canonical_name + aliases + one_line + evidence quote + collapsible attached facts. Accept promotes to real `Character` or `Setting` (with facts attached to `knownFactsBySceneId`); reject drops from store.

**Triggers**: (a) auto via piggyback on `LedgerExtractionCoordinator.onExtractionComplete`, gated by `EntityDiscoveryTrigger` (500-word per-scene baseline so heavily-edited scenes re-fire); (b) manual via the Bible menu's "Discover Entities in Current Scene…"; (c) demo via `swift run EntityDiscoverySpike --into <project>`.

**Out of scope at v1** (additive v2 candidates documented in §5): object discovery, cross-scene coref, lorebook auto-discovery, relationship discovery, factions, bulk import.

**Authoritative scope, falsifiable hypothesis, run-to-run findings, and productionisation appendix live in [`LOOM_ENTITY_DISCOVERY_SPIKE.md`](LOOM_ENTITY_DISCOVERY_SPIKE.md).**

---

## 6. Provisional MVP definition (Phase 1 specifically)

User can:

1. Create a new project — directory `MyNovel.loom/` with `project.json` + `scenes/`.
2. Add 1–3 character cards (name + paragraph description). Hand-paste OK; full editor Phase 2.
3. Type a scene sketch (a few hundred words) into the main editor.
4. Highlight the sketch, click **Expand** → AI generates 1500–2500 words, replaces selection.
5. Position cursor at end, click **Continue** → AI continues writing.
6. Edit freely (NSTextView gives undo/redo, find, etc. for free).
7. View **History chiclets**: one-click reveal of "what was sent to the model" for the last generation.
8. Save as a `.md` file with frontmatter for project metadata.

That's it. Everything else is Phase 2+.

---

## 7. On-disk format

Decided 2026-05-10 from research §M.1 + §J.4 (Obsidian Longform pattern):

```
MyNovel.loom/
  project.json            # project metadata (uuid, title, author, settings)
  scenes/
    <scene-id>.md         # scene prose with YAML frontmatter (round-trippable)
  bible/
    characters/<id>.json  # entity sheets
    settings/<id>.json
    objects/<id>.json
    timeline.json         # ordered events
    style.json            # style sheet
  references/             # Phase 5
    <ref-id>.md           # raw reference text (chunked at runtime)
    <ref-id>.index        # embedding index sidecar
  knowledge/              # Phase 4
    <scene-id>.json       # extracted character-fact tuples per scene
  generation-log/         # Phase 1+
    <iso-timestamp>.json  # what was sent + what came back per generation
```

**Round-trip property:** opening any `.md` in another editor and saving it back must not corrupt the project. Frontmatter is YAML and tool-agnostic.

**`generation-log/`** is the History-chiclets backing store; gives users the "what was actually sent" disclosure[A5] without an in-memory state requirement.

---

## 8. Open questions for Phase 1 kickoff

Settle before §1.a sub-step starts:

- **NSTextView vs TextKit 2.** TextKit 2 is the current direction but RPClient uses TextKit 1 (NSTextView default). Phase 1 likely follows RPClient; revisit at Phase 5 if styling complexity demands TextKit 2.
- **Project window vs document-based architecture.** AppKit's `NSDocument` framework gives multi-document support free; or single-window with a project picker. RPClient is single-window; Loom may want multi-document. **Decision: single-window with explicit project switcher for Phase 1**, revisit if user demand surfaces.
- **Variant drafts at the scene level.** Phase 5+. How does the user navigate between alternative versions of the same scene without losing the "main" thread? Scrivener Snapshots is the obvious answer; verify in Phase 2.
- **Generation context budget at 8k/16k/32k.** Specified in [`LOOM_GENERATION_MODES.md`](LOOM_GENERATION_MODES.md) §5; refine empirically once Phase 1 lands.

---

## 9. Cross-cutting

### 9.1 Diagnostic logging
Per RPClient convention (see RPClient `feedback_diagnostic_logging` memory): every new subsystem emits `[subsystem] event: data` lines from day 1. Loom subsystems: `[editor]`, `[project]`, `[bible]`, `[gen]`, `[rag]`, `[style]`, `[ledger]`.

### 9.2 TDD posture
Pure-data helpers get tests-first (TestKit, not XCTest). UI/glue layers get honest smoke tests (no faked tests, no pixel-snapshot diffs without a stable harness). Mirrors RPClient's `feedback_tdd_workflow` posture.

### 9.3 What this plan does NOT do

- **TTS / voice.** Deferred indefinitely.
- **Multi-user collaboration.** Single-user only.
- **Cloud sync.** Local-only by design — research §F.3 anti-pattern: anything cloud-touching for fiction is at-risk.
- **Mobile companion.** macOS only.
- **Content moderation, safety filters, refusal handling beyond signalling.** The local model handles content; Loom must remain neutral.

---

## 10. References

**Internal (this repo):**
- [`PLAN.md`](PLAN.md) — original meta-plan; superseded by this doc.
- [`LOOM_RESEARCH.md`](LOOM_RESEARCH.md) — research synthesis (every claim above traces here).
- [`LOOM_DESIGN_LANGUAGE.md`](LOOM_DESIGN_LANGUAGE.md) — design language.
- [`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md) — data shapes.
- [`LOOM_GENERATION_MODES.md`](LOOM_GENERATION_MODES.md) — prompt templates.
- [`LOOM_STORY_BIBLE.md`](LOOM_STORY_BIBLE.md) — consistency engine.
- [`LOOM_PHASE1_EDITOR_MVP.md`](LOOM_PHASE1_EDITOR_MVP.md) — first-phase sub-steps.

**External (RPClient repo):**
- `/Volumes/SSD1/Code/RPClient/V2_DESIGN_LANGUAGE.md` — design language inherited.
- `/Volumes/SSD1/Code/RPClient/V2_UI_OVERHAUL.md` — sub-step format precedent (§4.11).
- `/Volumes/SSD1/Code/RPClient/V2_PLAN.md` — plan-shape precedent.
- `/Volumes/SSD1/Code/RPClient/Sources/RPClientCore/{KoboldClient,ServerProbe,KoboldClientRegistry,DebugLog,Storage}.swift` — direct-reuse plumbing.

**External (web, dated 2026-05-10):** all in [`LOOM_RESEARCH.md`](LOOM_RESEARCH.md).

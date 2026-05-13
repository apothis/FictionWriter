# Loom — Scene-Template Generation

> **Status: Phase 7 design lock proposal (2026-05-13).** Planning document for the **Scene-Template Generation** feature: user ingests a scene-sized prose chunk (500–5000 words) as a *template scene*, then asks Loom to write a new scene that **preserves the source's structure, pacing, and modality flow** but **substitutes new characters, setting, and surface content**.
>
> Companion to [`LOOM_PLAN.md`](LOOM_PLAN.md) §5 (new Phase 7 row added), [`LOOM_GENERATION_MODES.md`](LOOM_GENERATION_MODES.md) (new mode §16 to be appended in Phase 7.a kickoff), and [`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md) (new entity type proposal §3.x).
>
> **Scope.** Product positioning, prior-art-grounded architectural decisions, scope locks, data-model additions, multi-pass pipeline, prompt strategy, UI design, failure-mode catalogue with mitigations, phasing + sub-row breakdown, and a spike plan. The empirical-validation gates land in Phase 7.a (spike), production architecture in Phase 7.b. Research bibliography in §13.
>
> **What this doc deliberately does not do.** Lock UX final shapes — those are Phase 7.b decisions after the spike empirically validates the core pipeline. Pre-commit to v2 features (two-dial UI, structured character-mapping table, post-hoc stylometric verification, per-beat re-roll). Those land contingent on Phase 7.a outcomes.

---

## 1. Concept

**End-user pitch.** "Paste a scene you love. Loom learns its shape. Now write a new scene in your project — same beats, same pacing, same modality flow — with your characters."

**Why this is different from style-RAG (Phase 5).** Phase 5's style-RAG handles **chunk-level voice influence** for normal Continue / Expand / Rewrite — it retrieves top-K style-similar chunks from a reference corpus and injects them as few-shot exemplars. Scene-Template Generation handles **whole-scene structural transfer**: a single *scene* (not a chunk) is the donor of structural skeleton (beat ordering, modality flow, pacing curve, POV-shift positions) for a *new scene* (not a continuation). The two pipelines compose — Phase 5 retrieval can populate an exemplar slot *alongside* the template scene at generation time.

**Product positioning.** The market gap analysis in §3.2 identifies a specific white space: **no current tool separates "structural shape" from "voice" when imitating an example scene.** Sudowrite's "Match my Style" handles voice but caps at 2,000 words and ignores structure. NovelCrafter's Scene Beats is outline-down (beat description → prose), not example-up. NovelAI's Custom Modules were the closest historical analog and were [discontinued in late 2024](https://x.com/novelaiofficial/status/1849493848038211603). DRAMATRON-style hierarchical generation (Mirowski et al., CHI 2023, [arXiv:2209.14958](https://arxiv.org/abs/2209.14958)) produces useful skeletons but evaluators called the prose "formulaic". The market position is genuinely empty.

---

## 2. End-state user-facing flow (Phase 7.b v1 target)

1. User opens **Bible Workspace → Template Scenes** (new entity type, mirrors Phase 5 A2 References pattern).
2. Clicks **+ Add template scene**, pastes ~500–5000 words of prose, names it ("Hemingway's farewell scene", "Anna Karenina ballroom").
3. Clicks **Extract structure**. Side-task LLM (Ollama / gemma4_2b) runs:
   - Beat segmentation (5–12 functional beats per scene, ~50–150 words each)
   - Per-beat modality tag (action / dialogue / interiority / description / summary / mixed — reuses [NarrativeMode](Sources/LoomCore/Models/NarrativeMode.swift))
   - Per-beat function tag (arrival / reveal / conflict / reaction / escalation / exit / setup / resolution)
   - Per-beat target word count (preserves source pacing)
   - Pacing stats (mean sentence length, σ, short/long sentence ratio)
   - Character/setting marker list (the entities that will be substituted)
4. Extracted beats render as an **editable strip** in the Workspace UI (per-beat function tag, modality tag, word target, one-line summary). User can tweak before generation.
5. In the main editor, user invokes the new generation mode **"Write scene like template"** (selection: cursor position only). Loom prompts:
   - Pick template scene (dropdown of ingested templates)
   - Cast mapping (free-form in v1 — "the antagonist is Maya, the setting is the cabin"; structured table in v2)
6. Loom runs **per-beat generation** in sequence (Pass B): for each beat, the writer LLM gets the skeleton + the previous beats' generated output + the modality + word-count target + a positive numerical pacing constraint + (optionally) retrieved style exemplars from the project's reference corpus.
7. Result: a new scene, ~same length as the template, with the template's shape and the user's cast.

---

## 3. Prior art — the load-bearing summary

Full citations in §13. This section gives the synthesis that drives the architectural decisions in §4.

### 3.1 Academic landscape

- **Text style transfer at paragraph/document level**: 2021–2025 surveys (Toshevska & Gievska 2021 [arXiv:2109.15144](https://arxiv.org/abs/2109.15144); Jin et al. 2022) confirm SOTA is sentence-level. STRAP (Krishna et al. EMNLP 2020, [arXiv:2010.05700](https://arxiv.org/abs/2010.05700)) introduced the canonical **paraphrase-then-restyle** decoupling. **ZeroStylus** (Wu et al. 2025, [arXiv:2505.07888](https://arxiv.org/abs/2505.07888)) is the closest published analog — sentence-and-paragraph template repositories with multi-granular matching — though it targets *style domains* (formal/informal/literary), not narrative scaffolding.
- **Structural narrative transfer** has a thin LLM-era literature. The Propp-grammar lineage (Gervás 2013) treats narrative function as CFG-style rules but generates forward from schema, not extracts from prose. MINSTREL (Turner 1993) does case-based adaptation of past stories — conceptually closest, but symbolic, not LLM. **No widely-cited LLM-era paper takes a single prose scene as input and extracts its beat/modality skeleton for re-realization with new content.** This is a genuine gap, verified across multiple targeted searches.
- **Beat extraction**: Papalampidi et al. 2019 ([arXiv:1908.10328](https://arxiv.org/abs/1908.10328)) defined 5 screenwriting turning points but these are *act-level*, too coarse for in-scene segmentation. 2024–25 workshop papers (e.g. WNU 2024) use Claude/Sonnet-style prompted extraction over scene granularity — this is the SOTA pattern Loom should mirror.
- **Long-form story generation**: Re3 (Yang et al. EMNLP 2022) → DOC (Yang et al. ACL 2023, +22.5% plot coherence over Re3) → DRAMATRON (Mirowski et al. CHI 2023). All three enforce structure through an **abstract symbolic plan** (outline / plot points / character cards), never through a concrete prose exemplar. Loom's proposal is genuinely different — *the template is itself prose* — but **DOC's hierarchical-outline-control mechanism is directly transplantable** as the Pass-B controller.
- **In-context learning with long single exemplars**: Min et al. EMNLP 2022 ([arXiv:2202.12837](https://arxiv.org/abs/2202.12837)) — demonstrations convey format more than ground-truth mapping; favourable for our case. **Liu et al. TACL 2024 "Lost in the Middle"** ([arXiv:2307.03172](https://arxiv.org/abs/2307.03172)) — performance is U-shaped; instruction goes at recency. **Critically for us:** Tripto et al. EMNLP Findings 2025 ([arXiv:2509.14543](https://arxiv.org/html/2509.14543v1)) shows that **long single exemplars improve surface mimicry but reduce deeper style-fidelity variation** — concrete pitfall that Loom's design must defend against (§5.1).
- **Modality / scene-mode sequence modeling**: zero public classifier for the {action, dialogue, interiority, description, summary, mixed} taxonomy over fiction. Verified across 3 targeted searches. Loom already has [NarrativeModeClassifier](Sources/LoomCore/Retrieval/NarrativeModeClassifier.swift) per [LOOM_NARRATIVE_MODE_SPIKE.md](LOOM_NARRATIVE_MODE_SPIKE.md) §10 — directly reusable for per-beat tagging.

### 3.2 Commercial landscape — what the market does NOT do

| What's preserved | Where tools currently live |
|---|---|
| Voice / vocabulary / sentence cadence | **Sudowrite Match My Style** (2k cap, voice-only); **NovelAI Modules** (defunct since Oct 2024); **KoboldAI Author's Note** |
| Plot beats | **Sudowrite Story Engine** outline; **NovelCrafter scene beats**; **DreamGen `<instruction>` tag** |
| Structural shape — beat order, POV pivots, dialogue/action timing, pacing curve | **Nothing currently** |

The third row is the opening. None of Sudowrite / NovelCrafter / NovelAI / AI Dungeon / SillyTavern / KoboldAI / DreamGen ships a "scene-as-structural-blueprint" primitive. Sources: [Sudowrite Style docs](https://docs.sudowrite.com/using-sudowrite/1ow1qkGqof9rtcyGnrWUBS/style/4gqKgVVjdN6XTKo71HChqV), [NovelCrafter Codex docs](https://www.novelcrafter.com/help/docs/codex/the-codex), [NovelAI Modules announcement](https://blog.novelai.net/custom-ai-modules-dbc527d66081) + [discontinuation](https://x.com/novelaiofficial/status/1849493848038211603), [SillyTavern Lorebook](https://docs.sillytavern.app/usage/core-concepts/worldinfo/), [DreamGen Opus docs](https://dreamgen.com/docs/models/opus/v0).

The **community workaround pattern** (r/WritingWithAI, r/LocalLLaMA practitioner writeups; [PromptHub few-shot guide](https://www.prompthub.us/blog/the-few-shot-prompting-guide); [LessWrong fiction prompting](https://www.lesswrong.com/posts/D9MHrR8GrgSbXMqtB/creative-writing-with-llms-part-1-prompting-for-fiction)) is to paste the scene into a single prompt with "write a new scene in this shape". This suffers from three documented failure modes that motivate Loom's structural design rather than prompt-only solution:

1. **Plot leakage** — model reuses concrete events/names from the example. Negative-list mitigation ("do not reuse X") gets paraphrased away (Loom's own [feedback memory](memory/feedback_prompt_blacklist_evasion.md)). The STRAP fix is to **strip content before generation**, not instruct against it.
2. **Voice-shape entanglement** — when user wants a hotter scene in the same shape, the model imports the *temperature* of the example along with the structure. Two-pass extraction decouples these.
3. **Context-budget pressure** — pasting a 3,000-word example crowds out characters/situation. Loom's prompt-budget machinery handles this gracefully via eviction priority; commercial tools don't expose the tradeoff.

### 3.3 Implementation techniques

- **Two-pass DOC-style architecture** is the SOTA pattern (Yang et al. ACL 2023). Pass A extracts skeleton (constrained JSON via GBNF); Pass B instantiates per-beat with style exemplar in a separate slot. ~2× tokens vs single-pass but radically more controllable; DOC reports +22% plot coherence and +28% outline relevance over single-pass.
- **GBNF for structured extraction**: KoboldCpp and Ollama both support grammar-constrained decoding; Loom has precedent in [`KoboldNarrativeModeRequest.grammar`](Sources/LoomCore/Retrieval/KoboldNarrativeModeClassifier.swift) (flat-enum alternation, per "Lost in Space" Bastan et al. 2025 fix from [LOOM_NARRATIVE_MODE_SPIKE.md](LOOM_NARRATIVE_MODE_SPIKE.md)). Direct extension for beat extraction.
- **Per-beat generation** with post-hoc modality verification + re-roll: matches DOC's per-passage controller. Composes with [NarrativeModeClassifier.classify](Sources/LoomCore/Retrieval/NarrativeModeClassifier.swift) to verify each generated beat hits the target modality.
- **Pacing as positive numerical constraints**: ZeroStylus shows that explicit pacing targets (mean sentence length, σ, short/long ratio) preserve cadence where adjectival framings ("write in short sentences") collapse to model default. Aligns with Loom's [feedback_prompt_blacklist_evasion](memory/feedback_prompt_blacklist_evasion.md) — positive constraints over negative.
- **Character substitution**: single-pass LLM substitution suffers from coreference drift, cultural-marker leakage, and stylometric collapse (ZeroStylus, RewriteLM [arXiv:2305.15685](https://arxiv.org/abs/2305.15685), LLM-DA [arXiv:2402.14568](https://arxiv.org/html/2402.14568v1)). v1 ships the simpler approach (free-form hint); v2 ships a coreference map.
- **Lost-in-the-middle for our prompt**: instruction at recency (end); 5000-word template scene in middle (it's structural input, not load-bearing for attention since the *skeleton* near the end is the load-bearing structural signal); skeleton + cast mapping + instruction near end.
- **Gemma 3 27B/31B-specific findings**: short structured system prompts (100–500 tokens) outperform long (1000+ token) prompts; uncensored merges (Glitter / Nidum) confirm pre-trained weight mixing restores natural prose for fiction; Q4_K_M is the quality sweet spot. Loom's writer (gemma-4-31B Q4_K_M) is already in this regime.

---

## 4. Architectural decisions

Numbered for ledger traceability with the Phase 7 sub-row table (§9).

### D1 — Template scene is a first-class entity, NOT a flagged reference

A `TemplateScene` is its own entity type with its own storage layer (`templates/<id>.md` + `templates/<id>.beats.json`), distinct from `ReferenceText`. **Rationale:** beats are a structural artefact specific to template scenes; conflating them with reference-text chunks would muddle the retrieval surface (Phase 5 references retrieve by D + E vector similarity; templates retrieve by **identity** — the user picks one explicitly). Storage layout mirrors [ReferenceStorage](Sources/LoomCore/Storage/ReferenceStorage.swift) (.md body + JSON sidecar).

### D2 — Two-pass architecture: side-task extraction + writer per-beat generation

Pass A (extraction) runs on the **extractor server** (Ollama, gemma4_2b — the same server Phase 4's ledger extractor uses). Cheap, reliable, structured. Pass B (instantiation) runs on the **writer server** (KoboldCpp, gemma-4-31B uncensored). Per-beat loop with KV-cache reuse: the long template-scene prefix is computed once per scene, each beat is a short suffix. **Rationale:** mirrors DOC's hierarchical pattern (Yang et al. 2023) and exploits the existing two-server architecture from [Phase 4 #7](LOOM_PLAN.md) (ledger extraction).

### D3 — Template scene is a first-class prompt slot, NOT retrieved alongside style exemplars

When generating from a template, the template's prose sits in its own `[TEMPLATE SCENE]` layer with high priority (never evicted during the generation). Phase 5's style-RAG retrieval continues to populate a separate `[STYLE EXEMPLARS]` layer that ranks ALL candidates (including, optionally, sub-passages of the template). If the user has *also* uploaded a reference corpus, those retrieved exemplars reinforce the template's stylistic signature. **Rationale:** mixing the template into the retrieval pool risks RRF demoting it; the template's role is structural-donor, not style-exemplar.

### D4 — STRAP-style content stripping defends against plot leakage

Before generation, the extracted beat skeleton is **content-stripped** (Krishna et al. 2020): named characters are replaced with role tokens (`{PROTAGONIST}`, `{ANTAGONIST}`); concrete settings are abstracted (`{INDOOR_PRIVATE_SPACE}`); distinctive props are abstracted. Pass B receives the stripped skeleton **plus** the user's cast/setting mapping, so the new scene's surface content is constructed fresh against the user's project rather than imported from the template. The raw template prose is still available as a style exemplar but is **explicitly framed** in the prompt as "study the *prose voice* of this passage, not the *plot*."

### D5 — Per-beat modality verification + re-roll

After each beat is generated, [NarrativeModeClassifier](Sources/LoomCore/Retrieval/NarrativeModeClassifier.swift) (heuristic dialogue gate + Kobold LLM) classifies it. If the generated modality doesn't match the target (beat 3 was supposed to be `interiority` but classifier says `action`), Loom **re-rolls that beat** once with an explicit "switch to interiority" framing. Two consecutive mismatches → accept the model's output but flag in the generation log. **Rationale:** matches DOC's per-passage controller; cheap to compose; the existing classifier is already production-validated at 73%+ accuracy per [LOOM_NARRATIVE_MODE_SPIKE.md](LOOM_NARRATIVE_MODE_SPIKE.md) §10.

### D6 — Pacing constraints as positive numerical statements, not adjectives

Per-beat prompt includes lines like *"Cadence target: mean sentence length 11.4 words (σ 6.2). ~30% of sentences under 8 words. Two should be single clauses or fragments."* Verified post-hoc with [FuncwordZEmbedder](Sources/LoomCore/Retrieval/FuncwordZEmbedder.swift)-derived pacing stats; flagged in log if outside δ. **Rationale:** Loom's [feedback_prompt_blacklist_evasion](memory/feedback_prompt_blacklist_evasion.md) memory — positive constraints work, negative phrasing gets paraphrased. ZeroStylus 2025 confirms empirically.

### D7 — v1 ships free-form cast/setting mapping; v2 ships structured table

v1 accepts a single string: *"Maya is the antagonist, the setting is the cabin in winter, swap the gun for a knife"*. The string is concatenated into the cast-mapping prompt slot. v2 (post-spike validation) builds a structured `[SourceEntity → TargetEntity]` table that pre-populates from the extracted character list and lets the user edit cells. **Rationale:** v1 is enough to validate whether the core pipeline produces useful outputs; v2 addresses the documented coreference-drift failure mode (§5.4) but adds significant UI complexity.

### D8 — Phase 7.a is a spike, not production

The empirical-validation gates (Does beat extraction produce useful skeletons? Does per-beat generation feel natural? Does content stripping prevent plot leakage in practice?) need answering before locking the production architecture. Phase 7.a runs over 3–5 hand-curated templates with hand-evaluation. Phase 7.b commits scope locks contingent on 7.a outcomes. Mirrors the discipline from [LOOM_RAG_SPIKE.md](LOOM_RAG_SPIKE.md) and [LOOM_NARRATIVE_MODE_SPIKE.md](LOOM_NARRATIVE_MODE_SPIKE.md).

---

## 5. Failure modes (the catalogue this design must defend against)

Each row cites the prior-art evidence and the design mitigation. Phase 7.a validates the mitigations empirically.

### 5.1 Surface mimicry overrides deep voice with long single exemplars

**Evidence.** Tripto et al. EMNLP Findings 2025 ([arXiv:2509.14543](https://arxiv.org/html/2509.14543v1)): matching exemplar length improves surface consistency but reduces deeper stylistic-fidelity variation. Models latch onto lexical/syntactic surface features and miss voice.

**Mitigation.** D4 (STRAP-style stripping reduces surface signal); D3 (template prose is *framed as voice exemplar only*, not as content source); D6 (positive numerical pacing rather than implicit imitation). v2 may add a "voice match" dial that lets the user explicitly down-weight the template's voice when they want their existing manuscript's voice to dominate.

### 5.2 Content / plot leakage from exemplar

**Evidence.** Krishna et al. STRAP 2020 ([arXiv:2010.05700](https://arxiv.org/abs/2010.05700)) — without aggressive content stripping, "style transfer" outputs leak source content. Documented in vision (StyleDrop, FineStyle NeurIPS 2024) and text few-shot (OpenAI dev community thread, Liang et al. arXiv:2403.16139). Long-exemplar regime is *especially* prone.

**Mitigation.** D4 (content stripping). The beat skeleton uses role tokens, not character names. Pass B's prompt explicitly says "the template provides structure; your output's plot, characters, setting come from the new cast mapping." Phase 7.a validates that this prevents leakage in practice — if not, the spike can pivot to "redact then re-substitute" (mask source entities pre-injection, fill in with target entities at generation).

### 5.3 Pacing flattening

**Evidence.** Re3/DOC ablations and ZeroStylus (Wu et al. 2025) — without explicit pacing control, LLMs default to uniform cadence and lose source rhythm (long flowing sentences become short choppy ones or vice versa).

**Mitigation.** D6 (positive numerical pacing targets per beat). Post-hoc verification via E embedder cosine similarity between generated-beat pacing vector and target pacing vector; if Δ > threshold, log + (v2) auto-reroll.

### 5.4 Voice collapse / drift under character substitution

**Evidence.** No direct citation, but follows from Character-LLM 2023 ([arXiv:2310.10158](https://arxiv.org/abs/2310.10158)) and narrative-planning critique ([arXiv:2506.10161](https://arxiv.org/html/2506.10161v1)). When characters change, distinctive voice features (idiolect, register, motif) either attach to the wrong agent or flatten across the narrator.

**Mitigation.** v1: lean on the writer LLM's voice-following from recent prose (Loom's existing scene-context layer keeps the project's voice anchored). v2: structured character mapping with per-character voice descriptors pulled from the Loom Bible character cards (the existing Bible Workspace already stores `voice` field per character).

### 5.5 Coreference drift on substitution

**Evidence.** LLM-DA (Ye et al. 2024 [arXiv:2402.14568](https://arxiv.org/html/2402.14568v1)) — single-pass entity substitution loses pronoun agreement for gendered/numbered cast changes ("she" sticks around after the protagonist swaps from F → M).

**Mitigation.** v1 accepts this risk: free-form cast mapping is brittle for pronoun changes. The writer LLM does well-enough on local pronoun coherence within a single beat. v2: pre-extract a coreference map from the source scene (spaCy or LLM-prompted) and apply structured substitution before beat-by-beat generation.

### 5.6 Formulaic output

**Evidence.** DRAMATRON evaluation (Mirowski et al. CHI 2023): industry users found the system useful for world-building and exploring alternatives but called the prose "formulaic". Recurring critique of all hierarchical generation pipelines.

**Mitigation.** The retrieved style exemplars (Phase 5 D + E hybrid) populate a separate layer that injects *non-template* prose voice into Pass B's per-beat generation. Empirically this is the strongest counter-formulaic signal in Loom's existing pipeline. v2 may add a "creative liberty" knob that loosens the beat-target word counts and lets beats merge.

### 5.7 Homogenization across users

**Evidence.** Doshi & Hauser 2024 (Science Advances) and Anderson, Shah & Kreminski C&C 2024 — group-level diversity collapses even when individual outputs look creative.

**Mitigation.** Local-only deployment means each user's reference corpus + writer-model sampler settings differ; the homogenization concern is muted relative to cloud-tool aggregation. Logged in §5 as documented behaviour, not blocked.

### 5.8 Beat-extraction misclassification

**Evidence.** No specific paper; failure mode inferred from [LOOM_NARRATIVE_MODE_SPIKE.md](LOOM_NARRATIVE_MODE_SPIKE.md) §10 results — 73% LLM zero-shot accuracy on the 6-class taxonomy.

**Mitigation.** D5 (post-hoc verification + re-roll). The user can also edit the extracted beat strip in the Bible Workspace before generation — wrong tags get fixed manually. The system never silently re-uses a misclassified beat.

---

## 6. Data model additions

Proposed schema. Lands in [LOOM_DATA_MODEL.md](LOOM_DATA_MODEL.md) §3.x at Phase 7.a kickoff.

### 6.1 `TemplateScene` — top-level entity

```swift
public struct TemplateScene: Codable, Equatable {
    public let id: UUID
    public var name: String
    public var nsfw: Bool
    public var createdAt: Date
    public var body: String                     // raw source prose (.md body)
    public var extractedBeats: [SceneBeat]?    // populated by Pass A; nil = not yet extracted
    public var pacingStats: PacingStats?       // populated by Pass A
    public var sourceCharacters: [String]?     // extracted character names (Pass A)
    public var sourceSettingMarkers: [String]? // extracted setting tokens (Pass A)
    public var extraFrontmatter: [String: String]
}
```

On disk: `templates/<id>.md` (frontmatter + body, mirrors `ReferenceFile.encode`). Sidecar at `templates/<id>.beats.json` carries the extracted artefacts (beats, pacing, characters, settings) so the .md remains a tool-agnostic round-trippable artefact.

### 6.2 `SceneBeat` — the load-bearing structural unit

```swift
public struct SceneBeat: Codable, Equatable {
    public let index: Int                     // ordinal in scene (0-based)
    public let summary: String                // one-sentence content-stripped summary
    public let modality: NarrativeMode        // reuses Phase 5 taxonomy
    public let function: BeatFunction         // arrival / reveal / conflict / ...
    public let targetWords: Int               // pacing preservation
    public let wordRange: Range<Int>          // span in source body
    public let tensionDelta: Int              // -3..+3, narrative arc signal
}

public enum BeatFunction: String, Codable, CaseIterable {
    case setup, arrival, escalation, reveal, conflict, reaction, resolution, exit
}
```

`BeatFunction` taxonomy is drawn from common screenwriting craft (arrival/exit are the most universally agreed; escalation/reveal/conflict come from the Story Genius / Save the Cat lineage). Empirically validated in Phase 7.a — if the taxonomy doesn't map well to extracted scenes, extend / refine before lock.

### 6.3 `PacingStats` — pacing fingerprint

```swift
public struct PacingStats: Codable, Equatable {
    public let meanSentenceLengthWords: Double
    public let sentenceLengthStdDev: Double
    public let shortSentenceRatio: Double     // < 8 words
    public let longSentenceRatio: Double      // > 20 words
    public let paragraphLengthMean: Double
    public let paragraphLengthStdDev: Double
    public let dialogueRatio: Double          // % of words inside quote marks
}
```

Reused both as Pass-A output (per-template) and as the runtime comparator for D6 post-hoc verification.

### 6.4 `TemplateGenerationRequest` — per-call payload

```swift
public struct TemplateGenerationRequest: Codable {
    public let templateSceneId: UUID
    public let castMapping: String           // v1: free-form hint
    public let voiceWeight: Double           // 0.0..1.0, v2 dial (v1: hardcoded 0.5)
    public let shapeWeight: Double           // 0.0..1.0, v2 dial (v1: hardcoded 1.0)
}
```

### 6.5 `GenerationMode.generateFromTemplate` — the new mode case

New case in [GenerationMode](Sources/LoomCore/Models/Scene.swift). Branches:
- [`PromptBuilder.swift`](Sources/LoomCore/Generation/PromptBuilder.swift) gets a new per-mode instruction template (§7).
- [`RetrievalQueryBuilder.swift`](Sources/LoomCore/Retrieval/RetrievalQueryBuilder.swift) gets a new branch — query is derived from the *next beat to generate* (so retrieved style exemplars match the beat's modality), not the recent prose.
- [`GenerationModeAvailability.swift`](Sources/LoomCore/Models/) — available when a template scene is selected; UI surfaces this as a dropdown in the tray.

---

## 7. Prompt strategy

### 7.1 Pass A: extraction (Ollama side-task)

Single prompt to gemma4_2b with GBNF-constrained JSON output:

```
You are analyzing a narrative scene to extract its structural skeleton.

Read the scene below carefully. Identify 5–12 discrete narrative beats —
functional units of 50–150 words each that advance the scene.

For each beat, output JSON:
- function: arrival / reveal / conflict / reaction / escalation / exit / setup / resolution
- modality: action / dialogue / interiority / description / summary / mixed
- summary: one sentence, with character names replaced by {PROTAGONIST} / {ANTAGONIST} / etc.
- target_words: approximate word count for this beat
- tension_delta: -3 to +3

Also extract:
- sourceCharacters: distinct character names in the scene
- sourceSettingMarkers: place / time / object tokens that anchor the setting
- pacingStats: numerical pacing fingerprint (sentence length, dialogue ratio, etc.)

Scene:
{TEMPLATE_BODY}

Output JSON:
```

GBNF grammar follows the [`KoboldNarrativeModeRequest.grammar`](Sources/LoomCore/Retrieval/KoboldNarrativeModeClassifier.swift) flat-enum pattern but extended with JSON object structure. Specific grammar in Phase 7.a spike doc.

Response parsing: tolerate preamble/postamble (matches [LedgerExtraction.parseExtractedFacts](Sources/LoomCore/Generation/LedgerExtraction.swift) pattern); drop invalid entries; surface error in Workspace UI if extraction yields 0 valid beats.

### 7.2 Pass B: per-beat instantiation (Kobold writer)

For each beat N of M, the prompt is structured as:

```
[SYSTEM]
You are a fiction writer. You are writing beat N of M in a scene whose
structural skeleton is given below. Follow the beat's modality and target
length precisely; the surrounding beats anchor the scene's flow.

The TEMPLATE SCENE below is provided as a STYLE EXEMPLAR — study its prose
voice, sentence rhythm, and modality handling. Do not reuse its plot,
characters, settings, or specific events. Those come from the NEW CAST
mapping.

[MEMORY] [BIBLE-CONST] [STYLE EXEMPLARS retrieved by Phase 5 RAG]

=== TEMPLATE SCENE (voice reference; do not reuse plot) ===
{TEMPLATE_BODY}
=== END TEMPLATE SCENE ===

[BEAT SKELETON]
Beat 1 (setup, description): {STRIPPED_SUMMARY_1} — target 120 words
Beat 2 (arrival, action): {STRIPPED_SUMMARY_2} — target 80 words
...
Beat N (CURRENT, {MODALITY}, {FUNCTION}): {STRIPPED_SUMMARY_N} — target {TARGET_WORDS} words
...

[NEW CAST]
{USER_PROVIDED_CAST_MAPPING}

[PACING TARGET FOR THIS BEAT]
Mean sentence length {X.X} words (σ {X.X}). ~{Y}% short sentences (<8w),
~{Z}% long (>20w).

[BEATS 1..N-1 ALREADY GENERATED]
{GENERATED_PROSE_SO_FAR}

[INSTRUCTION]
Write beat N. Modality: {MODALITY}. Target length: {TARGET_WORDS} words.
End at a natural sentence boundary that leads into beat N+1.
```

The instruction sits at recency (per "Lost in the Middle"). The template scene is in the middle (attention is weakest there, but it's structural reference only — the load-bearing structural signal is the beat skeleton, which sits near the end). The instructions explicitly frame the template as voice-only, not content.

### 7.3 KV-cache management

The prompt prefix above `[BEATS 1..N-1 ALREADY GENERATED]` is **stable across all M beats in a generation pass** — same system prompt, same template scene, same skeleton, same cast mapping. Phase 4.5 / Phase 5's existing cache machinery treats this prefix as the cache line. Per-beat generation reuses the prefix; only the tail (generated prose so far + instruction) changes. Cost: one expensive prefix compute + M cheap tail completions, instead of M full prompt computes.

---

## 8. UI/UX design

### 8.1 Template Scenes in the Bible Workspace

Mirrors the Phase 5 A2 References surface exactly:
- **List view**: section in `EntityList.tsx` ("Template Scenes" — N), each row shows name + extraction state (`5 beats extracted` / `not yet extracted`) + a "Hemingway scene" preview snippet.
- **Detail editor**: `TemplateSceneEditor.tsx` with three sections:
  - **Identity** (Name, NSFW toggle, Created timestamp)
  - **Body** (large textarea with the source prose)
  - **Structure** — visible after extraction: a horizontal *beat strip* showing each beat's function tag, modality tag, target word count, and one-line summary. Editable inline.
- **Actions**: `Extract structure` (or `Re-extract` if already done) + `Delete template`. Extraction runs in background, posts notification on completion (mirrors Phase 5 A2's `ingestReference`).

### 8.2 In-editor generation flow

New entry in the generation tray ("Write scene like template..."). Available when cursor is in editor and no selection (mode replaces nothing; output appends at cursor). Click opens a small inline picker:
- Dropdown: choose a template scene (only those with extracted structure)
- Free-form text field: cast mapping ("Maya is the antagonist, setting is the cabin")
- "Generate" button → runs Pass B per-beat with live token streaming, same as Continue

### 8.3 v2 features (post-spike validation)

- **Two-dial UI** ("match shape" 0–100%, "match voice" 0–100%) — the commercial gap analysis (§3.2) identifies this as the product opening. Maps to `voiceWeight` / `shapeWeight` in `TemplateGenerationRequest`. Shape weight controls how strictly Pass B obeys the beat skeleton (lower = more freedom to merge/skip beats); voice weight controls how heavily the template's voice signal influences vs. the project's existing manuscript voice.
- **Structured character mapping table** — pre-populates from `sourceCharacters`; user maps each to a Bible character or types a new name.
- **Modality flow editor** — drag-reorder beats, change modality/function tags, before generation.
- **Per-beat re-roll** — accept/reject per beat post-generation; re-roll a single beat without losing the rest.

### 8.4 Loom Bible character voice integration

Once a user has Bible characters with `voice` field populated (Phase 4.5 already ships this), the cast mapping table can auto-inject each target character's voice descriptor into the Pass B prompt as a per-character constraint. This is the strongest defense against voice collapse / character drift (§5.4).

---

## 9. Phasing — sub-row breakdown

| # | Sub-row | Description | Status |
|---|---|---|---|
| 7.a.1 | Spike — extraction quality | Run Pass A on 5 hand-curated diverse scenes (literary, genre, NSFW, short, long). Hand-evaluate: are beats useful? Are modality tags accurate? Are pacing stats faithful? Decision gate: refine prompts/grammar OR pivot to alternative extraction approach. | pending |
| 7.a.2 | Spike — generation quality | For each successful extraction, run Pass B with a synthetic cast mapping. Hand-evaluate: does output preserve shape? Does plot leak? Does voice transfer or collapse? Decision gate: ship v1 architecture as-is OR identify which §5 mitigations need strengthening. | pending |
| 7.a.3 | Spike — long-exemplar pitfalls | Empirically reproduce the Tripto 2025 "long exemplar → surface mimicry" finding on Loom's Gemma 4 31B + a curated set of 3 scenes. Validate that STRAP-style stripping + framing-as-voice-only mitigates. Decision gate: confirm or strengthen D4. | pending |
| 7.b.1 | TemplateScene entity + storage | `TemplateScene` Codable + `TemplateSceneStorage` (mirrors `ReferenceStorage`). | pending |
| 7.b.2 | Beat extraction pipeline | `BeatExtractionPipeline` (mirrors `ReferenceIngestPipeline` shape) + Ollama-side prompt + GBNF grammar + response parser. | pending |
| 7.b.3 | `.generateFromTemplate` mode | New `GenerationMode` case; `PromptBuilder` per-beat assembly; `RetrievalQueryBuilder` per-beat query extraction. | pending |
| 7.b.4 | Per-beat generation loop | `GenerationCoordinator` extension: orchestrates the M-step beat loop, calls `NarrativeModeClassifier` for per-beat verification, surfaces aggregate stream to editor. | pending |
| 7.b.5 | Bible Workspace surface | Template Scenes section in EntityList + TemplateSceneEditor with beat strip; intent cases mirror Phase 5 A2 References. | pending |
| 7.b.6 | In-editor flow | Generation tray entry + inline picker (template dropdown + cast hint field). | pending |
| 7.b.7 | Empirical validation pass | 10–15 generations across 3 templates × 3 cast mappings. Hand-evaluate. Tune defaults (voiceWeight / shapeWeight). | pending |
| 7.c | v2 features | Two-dial UI, structured cast mapping, modality flow editor, per-beat re-roll, character-voice injection. Contingent on v1 production validation. | parked |

**Estimates (rough, pre-spike).** 7.a (spike) ≈ 1 session (focused empirical exploration over 5 templates). 7.b (production v1) ≈ 3–4 sessions, similar to Phase 5 production cadence. 7.c (v2) ≈ 2–3 sessions, scoping depends on 7.b outcomes.

**MVP gate for 7.b ship.** A user can: ingest a template scene, click extract, see a beat strip, paste cast hint, click generate, and receive prose that:
- Preserves the beat ordering and target lengths within ±20%
- Hits target modality on ≥70% of beats (mirrors the 73% LLM-zero-shot accuracy from [LOOM_NARRATIVE_MODE_SPIKE.md](LOOM_NARRATIVE_MODE_SPIKE.md) §10 — we don't expect to beat the floor)
- Does not reuse the source's character names or specific plot events
- Has pacing stats within δ of the target (δ TBD empirically in 7.a.3)

---

## 10. What's reusable vs new — the cost ledger

From the in-codebase survey (full results in agent transcript). Approximate LOC.

| Component | Status | LOC saved |
|---|---|---|
| `GenerationCoordinator` (mode-agnostic) | ✅ reuse, add per-beat extension | ~300 |
| `PromptBuilder` (add new branch) | ✅ reuse + extend | ~200 |
| `RetrievalQueryBuilder` (add per-beat query branch) | ✅ reuse + extend | ~80 |
| `NarrativeModeClassifier` + `KoboldNarrativeModeClassifier` | ✅ direct reuse for D5 | ~150 |
| `RagChunker` | ✅ direct reuse | ~50 |
| `ReferenceStorage` pattern (mirror for templates) | ✅ pattern reuse | ~100 |
| `OllamaLedgerExtractor` pattern (mirror for beat extraction) | ✅ pattern reuse | ~150 |
| `BibleWorkspace` intent + bridge + snapshot (mirror Phase 5 A2 References) | ✅ pattern reuse | ~300 |
| `AppState` retrieval injection (Phase 5 A1) | ✅ extension point | ~50 |
| **New: `TemplateScene` + `SceneBeat` + `PacingStats`** | NEW | ~250 |
| **New: `TemplateSceneStorage`** | NEW | ~120 |
| **New: `BeatExtractionPipeline`** | NEW | ~200 |
| **New: GBNF for beat extraction** | NEW | ~80 |
| **New: `PerBeatGenerationLoop` extension on `GenerationCoordinator`** | NEW | ~250 |
| **New: pacing stats computation (sentence tokenizer)** | NEW | ~100 |
| **New: `TemplateSceneEditor.tsx` + EntityList section** | NEW | ~350 |
| **New: in-editor template picker UI** | NEW | ~150 |
| **New: tests** | NEW | ~600–800 |

**Total new code:** ~2100–2300 LOC. **Total leveraged from existing:** ~1400 LOC of reusable infrastructure. The "60–70% reuse" intuition holds: this is genuinely an *extension* of the existing pipeline, not a from-scratch second feature.

---

## 11. Risks + rollback

### 11.1 Spike disconfirmation outcomes

If Phase 7.a.1 finds that gemma4_2b's beat extraction is too noisy (e.g., < 50% hand-validated beats are useful): pivot to **prompted gemma-4-31B extraction on the writer server**. Slower (per-template; not on hot path) but the writer is the most capable model available; matches the Phase 4 ledger-extraction fallback precedent.

If Phase 7.a.2 finds that per-beat generation produces fragmented/incoherent scenes (each beat is fine, but the scene as a whole doesn't flow): pivot to **two-stage generation** — beat 1 generates with full context, beats 2..M generate with a smaller "coherence" rolling context that includes only the immediately preceding beat + the upcoming beat's skeleton. Tradeoff: faster but loses some big-picture cohesion.

If Phase 7.a.3 finds STRAP-style stripping doesn't prevent plot leakage: pivot to **explicit redact-then-substitute** — replace source entities with redaction tokens in the template prose itself before injection, so the model never sees the original names. More aggressive but pure mechanical defense.

### 11.2 Cost of abandonment

The spike is contained: Phase 7.a runs over hand-curated templates with no production wiring. If the feature genuinely doesn't work at acceptable quality, Phase 7.a sub-rows are abandonable cleanly (delete spike scripts; restore prior `LOOM_PLAN.md` row). Phase 7.b is the commitment point.

### 11.3 Scope creep into v2 features

v2 features (§8.3) are seductive — two-dial UI in particular addresses the commercial-gap product positioning directly. Discipline: ship v1 first with hardcoded defaults; validate empirically; only then build v2. Reuses the Phase 5 production discipline (engine first, UI luxury after).

---

## 12. Open questions for Phase 7 kickoff

Settle before Phase 7.a starts:

- **Extraction model choice**: gemma4_2b (cheap, fast, already configured) vs. mxbai-embed-large-as-classifier (no — wrong task shape) vs. writer-side gemma-4-31B (slower but more capable). Default: gemma4_2b; pivot if 7.a.1 shows quality is too low.
- **Beat granularity**: 5–12 beats per scene is a range; what's the sweet spot? Phase 7.a.1 sweeps 3–15 over 5 templates and finds the empirical floor where coherence breaks.
- **Cast mapping format v1**: free-form vs. simple key-value. Default: free-form; v2 → structured.
- **NSFW templates**: templates marked NSFW should follow Loom's content-neutral policy — no retrieval-time filtering. Verified consistent with [LOOM_NSFW.md](LOOM_NSFW.md) §3.
- **Where the template-scene voice exemplar sits vs. retrieved exemplars when both are present**: D3 says separate layers, but priority? Spike 7.a.2 explores empirically.
- **Pacing tokenizer**: which sentence-splitter? Use existing `SentenceSplitter` from Phase 4.5 (the dialogue-aware one used in ledger extraction). Verify it handles the 5 spike templates without false-positive splits on dialogue.

---

## 13. References

### 13.1 Academic (cited inline)

- Toshevska & Gievska 2021 — [A Review of Text Style Transfer using Deep Learning](https://arxiv.org/abs/2109.15144) (IEEE TAI)
- Jin et al. 2022 — Deep Learning for Text Style Transfer: A Survey (Computational Linguistics)
- Krishna, Wieting & Iyyer 2020 — [STRAP: Reformulating Unsupervised Style Transfer as Paraphrase Generation](https://aclanthology.org/2020.emnlp-main.55/) (EMNLP)
- Reif et al. 2022 — [A Recipe for Arbitrary Text Style Transfer with Large Language Models](https://aclanthology.org/2022.acl-short.94.pdf) (ACL Short)
- Hu et al. 2017 — [Toward Controlled Generation of Text](https://arxiv.org/abs/1703.00955) (ICML)
- Wu et al. 2025 — [ZeroStylus: Long Text Style Transfer via Sentence and Paragraph Structure](https://arxiv.org/abs/2505.07888) (arXiv)
- Cao et al. 2024 — [SC2: Towards Enhancing Content Preservation and Style Consistency in Long Text Style Transfer](https://arxiv.org/abs/2406.04578) (arXiv)
- Papalampidi, Keller & Lapata 2019 — [Movie Plot Analysis via Turning Point Identification](https://arxiv.org/abs/1908.10328) (EMNLP-IJCNLP)
- Yang, Tian, Peng & Klein 2022 — [Re3: Generating Longer Stories With Recursive Reprompting and Revision](https://arxiv.org/abs/2210.06774) (EMNLP) — [repo](https://github.com/yangkevin2/emnlp22-re3-story-generation)
- Yang, Klein, Peng & Tian 2023 — [DOC: Improving Long Story Coherence With Detailed Outline Control](https://arxiv.org/abs/2212.10077) (ACL) — [repo](https://github.com/yangkevin2/doc-story-generation)
- Mirowski et al. 2023 — [Co-Writing Screenplays and Theatre Scripts with Language Models (DRAMATRON)](https://arxiv.org/abs/2209.14958) (CHI) — [repo](https://github.com/google-deepmind/dramatron)
- Min et al. 2022 — [Rethinking the Role of Demonstrations: What Makes In-Context Learning Work?](https://arxiv.org/abs/2202.12837) (EMNLP)
- Liu et al. 2024 — [Lost in the Middle: How Language Models Use Long Contexts](https://arxiv.org/abs/2307.03172) (TACL)
- Tripto et al. 2025 — [Catch Me If You Can? Not Yet: LLMs Still Struggle to Imitate the Implicit Writing Styles of Everyday Authors](https://arxiv.org/html/2509.14543v1) (EMNLP Findings)
- Ye et al. 2024 — [LLM-DA: Data Augmentation via Large Language Models for Few-Shot NER](https://arxiv.org/html/2402.14568v1) (arXiv)
- Shao et al. 2023 — [Character-LLM: A Trainable Agent for Role-Playing](https://arxiv.org/abs/2310.10158) (EMNLP)
- Wang et al. 2025 — [Can LLMs Generate Good Stories? Insights and Challenges from a Narrative Planning Perspective](https://arxiv.org/html/2506.10161v1) (arXiv)
- Doshi & Hauser 2024 — Generative AI enhances individual creativity but reduces the collective diversity of novel content (Science Advances)
- Anderson, Shah & Kreminski 2024 — [Homogenization Effects of LLMs on Human Creative Ideation](https://mkremins.github.io/publications/Homogenization_C&C2024.pdf) (C&C)
- Bertsch et al. 2024 — [In-Context Learning with Long-Context Models](https://arxiv.org/html/2405.00200v1) (arXiv)
- Agarwal et al. 2024 — [Many-Shot In-Context Learning](https://arxiv.org/html/2404.11018) (NeurIPS)
- Survey 2026 — [Narrative Theory-Driven LLM Methods for Automatic Story Generation and Understanding](https://arxiv.org/html/2602.15851v1) (arXiv)
- Awesome-Story-Generation index — https://github.com/yingpengma/Awesome-Story-Generation

### 13.2 Commercial / community

- [Sudowrite Style docs](https://docs.sudowrite.com/using-sudowrite/1ow1qkGqof9rtcyGnrWUBS/style/4gqKgVVjdN6XTKo71HChqV) + [Story Bible docs](https://docs.sudowrite.com/using-sudowrite/1ow1qkGqof9rtcyGnrWUBS/what-is-story-bible/jmWepHcQdJetNrE991fjJC)
- [NovelCrafter Codex docs](https://www.novelcrafter.com/help/docs/codex/the-codex) + [Codex Recipes](https://www.novelcrafter.com/courses/codex-cookbook/codex-scenes)
- [NovelAI Custom Modules announcement](https://blog.novelai.net/custom-ai-modules-dbc527d66081) + [discontinuation tweet (Oct 2024)](https://x.com/novelaiofficial/status/1849493848038211603)
- [SillyTavern Lorebook / World Info](https://docs.sillytavern.app/usage/core-concepts/worldinfo/) + [Context Template](https://docs.sillytavern.app/usage/prompts/context-template/)
- [KoboldAI Memory / Author's Note / World Info wiki](https://github.com/KoboldAI/KoboldAI-Client/wiki/Memory,-Author's-Note-and-World-Info)
- [DreamGen Opus V0 docs (steerable story writing)](https://dreamgen.com/docs/models/opus/v0)
- [PromptHub few-shot prompting guide](https://www.prompthub.us/blog/the-few-shot-prompting-guide)
- [LessWrong: prompting for fiction](https://www.lesswrong.com/posts/D9MHrR8GrgSbXMqtB/creative-writing-with-llms-part-1-prompting-for-fiction)
- [Plottr Scene Card Templates](https://plottr.com/custom-scene-character-templates/)

### 13.3 Implementation techniques

- [llama.cpp grammars README](https://github.com/ggml-org/llama.cpp/blob/master/grammars/README.md) + [json_schema_to_grammar.py](https://github.com/ggml-org/llama.cpp/blob/master/examples/json_schema_to_grammar.py)
- [Devshorts: GBNF explained](https://www.devshorts.in/p/gbnfggml-bnf-explained-an-approach)
- [Simon Willison: llama-cpp-python grammars TIL](https://til.simonwillison.net/llms/llama-cpp-python-grammars)
- [Instructor library (structured outputs)](https://github.com/567-labs/instructor)
- [Outlines (token-level constraint)](https://dottxt-ai.github.io/outlines/)
- [Chain of Density](https://learnprompting.org/docs/advanced/self_criticism/chain-of-density)
- [Markaicode: Gemma 3 prompting techniques](https://markaicode.com/gemma-3-text-generation-prompting-techniques/)
- [Hugging Face: Gemma-3-Glitter-27B](https://huggingface.co/allura-org/Gemma-3-Glitter-27B)
- [Hugging Face: Nidum-Gemma-3-27B-it-Uncensored](https://huggingface.co/nidum/Nidum-Gemma-3-27B-it-Uncensored)
- [LocalLLM.in: Quantization explained](https://localllm.in/blog/quantization-explained)

### 13.4 Internal (this repo)

- [`LOOM_PLAN.md`](LOOM_PLAN.md) — master plan; Phase 7 row added.
- [`LOOM_GENERATION_MODES.md`](LOOM_GENERATION_MODES.md) — companion; `.generateFromTemplate` mode to be appended §16.
- [`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md) — companion; `TemplateScene`, `SceneBeat`, `PacingStats` schemas to be appended §3.x.
- [`LOOM_NARRATIVE_MODE_SPIKE.md`](LOOM_NARRATIVE_MODE_SPIKE.md) — the modality classifier this feature reuses for D5 verification.
- [`LOOM_RAG_SPIKE.md`](LOOM_RAG_SPIKE.md) — Phase 5 RAG architecture; reused for style-exemplar retrieval alongside the template.
- [`LOOM_BIBLE_WORKSPACE.md`](LOOM_BIBLE_WORKSPACE.md) — pattern for the new Template Scenes entity surface.
- [`LOOM_NSFW.md`](LOOM_NSFW.md) — content-neutrality directive; template scenes inherit.
- [`HANDOFF.md`](HANDOFF.md) — session ledger; Phase 7.a kickoff adds §15.x row.

### 13.5 Memory (load-bearing for design decisions)

- [`feedback_prompt_blacklist_evasion`](memory/feedback_prompt_blacklist_evasion.md) — drives D4 (positive content stripping, not negative instructions) and D6 (positive pacing constraints).
- [`feedback_verify_research_claims`](memory/feedback_verify_research_claims.md) — drove the "verify gap claims" discipline in this doc; §3.1 and §3.2 gap statements are explicitly verified.
- [`feedback_verify_local_toolchain`](memory/feedback_verify_local_toolchain.md) — Phase 7.a runs against current Loom toolchain (gemma4_2b for extraction, gemma-4-31B for generation, Python venv for embeddings) all already verified.

---

*Phase 0 lock proposal complete. Phase 7.a (spike) ready to begin pending user approval. Phase 7.b (production v1) commits scope locks contingent on 7.a outcomes.*

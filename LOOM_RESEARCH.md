# LOOM_RESEARCH.md

> **Status: Phase 0 research synthesis (2026-05-10).** This document is the citation-grounded prior-art survey that every subsequent design doc cites back to. The user's directive: build Loom from the best of existing systems plus their stated extensions. Every later design decision either points back to a finding in this doc or stands as a flagged "going beyond" extension with rationale.
>
> **Methodology note.** Originally scoped as five parallel research subagents. The subagents do not have web access in this sandbox; the load-bearing fetch work was done at the parent level via `WebSearch` / `WebFetch`. Research was conducted on 2026-05-10 against live sources. Where a claim is supported by a single source, it is marked `[1S]`. Where a feature has shifted on a monthly cadence, the current-as-of date is the search date. Marketing-only claims (no third-party corroboration) are flagged inline.
>
> **Quality criteria.** Every non-trivial claim carries a citation. Specific feature names, schemas, and UX terms are quoted, not paraphrased into vagueness. "What users complain about" is treated as load-bearing as "what works."

---

## 0. Source legend

Inline citations use bracketed superscripts; full URLs at the end of each section. `[1S]` = single-source claim, treat with caution. Unmarked claims are corroborated by ≥ 2 sources or by the tool's own documentation cross-checked with an independent reviewer.

Search-date for all 2025/2026 feature claims: **2026-05-10**.

---

## A. Sudowrite — deep dive

### A.1 Project structure

Sudowrite organizes work as a project containing chapters; each chapter holds prose and is linked to a Story Bible. Chapters can be linked in sequence so the Write feature reads prior chapters as Chapter Continuity.[A1] The Draft interface is the writing surface; Story Bible is the inspector-shaped sibling that holds entity sheets and structural metadata.

### A.2 Story Bible — the canonical schema

Sudowrite's Story Bible is the gold-standard fiction-bible UX. The schema is **a deliberate sequence**, where each section feeds the next:

1. **Braindump** — raw material: scene fragments, character ideas, thematic hunches, plot threads.[A2]
2. **Genre + Style** — genre shapes tone/convention expectations; Style is the author's voice.[A2]
3. **Synopsis** — generated from Braindump and Genre. Drives Characters, Worldbuilding, Outline.[A2]
4. **Characters** — defines characters and how they speak/decide/interact.[A2]
5. **Worldbuilding** — settings, items, lore.[A2]
6. **Outline** — built on synopsis + characters + world; not in a vacuum.[A2]
7. **Scenes / Chapters** — drafting surface; Bible is referenced during generation.[A2]

Critically, the Story Bible is *generative*: it takes a one-line idea and progressively builds out each layer. Sudowrite's marketing positions this as "How to Write a Novel in 7 Clicks."[A3] What's load-bearing for Loom: the **dependency-ordered field schema** is what makes Bible content auto-fillable from earlier fields.

### A.3 Context assembly — what gets sent to the model

Sudowrite's Write feature reads up to **20,000 words of preceding text** plus **all Story Bible data** (Genre, Style, Synopsis, Character cards, Worldbuilding) on every generation.[A4][A5] If chapters are linked in sequence, prior chapters become Chapter Continuity context.[A5]

Context surfacing: a **History card** in the right column displays "chiclets" highlighting what context Sudowrite took into account for that generation.[A5] **This is rare — most tools hide their prompt assembly. Loom should adopt this pattern.**

There's also a **Key Details box in Write Settings** for ad-hoc context the user wants in the prompt for that specific generation.[A5]

### A.4 Generation modes

- **Write** — advanced autocomplete; 50–2,000 words from cursor.[A6]
- **Describe** — sensory/object/feeling expansions on a selection.[A6]
- **Brainstorm** — idea generator for plot points, settings, names.[A6]
- **Rewrite** — improve phrasing/flow/tone of existing passage.[A6]
- **Expand** — adds length to a draft (slow pacing, flesh out moments).[A6]
- **Canvas** — visual outline / character-relationship map with drag-drop cards/boxes.[A6]
- **Story Engine** — older flagship feature; "Story Engine" is a legacy term now used interchangeably with Story Bible.[A6] Some 2026 reviewers still describe it as a distinct feature that takes Braindump + Genre + Style + Character List and autonomously generates chapter beats and prose adhering to specific narrative arcs.[A6][1S — treat the "Story Engine 3.0" framing as marketing-adjacent.]

### A.5 Pricing — proxy for feature priority

As of 2026-05-10:[A7][A8]

| Tier | Monthly (annual) | Credits | Notes |
|---|---|---|---|
| Hobby & Student | $10 (annual) / $19 (monthly) | 225,000 | Credits expire monthly |
| Professional | $22 (annual) / $29 (monthly) | 1,000,000 | Credits expire monthly |
| Max | $44 (annual) / $59 (monthly) | 2,000,000 | 12-month rollover |

All plans have full feature access; tier difference is credit allocation + rollover. **Signal:** Sudowrite monetises *throughput*, not *features*. Story Bible isn't gated behind a higher tier — they want users using it. This validates the bible-as-foundation posture.

Free trial: 10,000 credits, no time limit until consumed.[A7]

### A.6 What users complain about

Cross-source pattern (third-party reviewers + Trustpilot):

- **Random crashes, slow load times, occasional loss of story progress** — frustrating on long projects.[A9]
- **Credit-system glitches**: clicking generate, seeing credits debited, getting nothing back.[A9]
- **High credit consumption**: 10,000 trial credits enough for ~3 characters' worth of generation.[A9]
- **Workflow friction at scale**: manually reconnecting 41 chapters after a chapter add/split was described as "a wasted hour" by one user.[A9]
- **Support unresponsive**: Trustpilot users report sending screenshots repeatedly to support and being ignored.[A9]
- **Structural rigidity**: the dependency-ordered Bible (Braindump → Synopsis → Characters → ...) is great for new projects but painful for retrofitting existing manuscripts.[A9][1S]

Sudowrite has no Reddit subreddit; the active community is on Discord.[A9] **Signal for Loom:** users want transparency (failed-generation refund), reliability (no progress loss), and the option to skip the Bible's strict dependency order.

### A.7 What users praise

- The **Write button's prose quality** is consistently called the killer feature.[A6][A9]
- **Story Bible's auto-fill** ("clicks 1–7") gets new authors past blank-page paralysis.[A3]
- **History chiclets** (context transparency) — power users who try Sudowrite and Novelcrafter both often prefer Sudowrite's transparency here.[A5]

### A.8 Sources

- [A1] Sudowrite Docs — Write — `https://docs.sudowrite.com/using-sudowrite/1ow1qkGqof9rtcyGnrWUBS/write/pvxUvbQqYybfEosqx1sXjY`
- [A2] Sudowrite Docs — Story Bible overview — `https://docs.sudowrite.com/using-sudowrite/1ow1qkGqof9rtcyGnrWUBS/what-is-story-bible/jmWepHcQdJetNrE991fjJC`
- [A3] Sudowrite Blog — Story Bible Template — `https://sudowrite.com/blog/story-bible-template-how-to-build-one-and-how-sudowrite-does-it-for-you/`
- [A4] Sudowrite Docs — The Basics — `https://docs.sudowrite.com/getting-started/dQph1snuwbfMWG9wRjsNug/the-basics/po46R9SPcwQ6D7Uzq7tbkP`
- [A5] Sudowrite Feedback — Expanded Input Capacity — `https://feedback.sudowrite.com/p/expanded-input-capacity-and-long-form-project-management-tools`
- [A6] Sudowrite Docs — Glossary — `https://docs.sudowrite.com/getting-started/dQph1snuwbfMWG9wRjsNug/glossary/1Symu5y4wtu65nQVYHjhxa`
- [A7] Sudowrite Docs — Plans — `https://docs.sudowrite.com/plans--account/wBnmhtSyMcWtk2BLzifGkz/what-plans-are-available/mwfVvj2rGcKYs1BQy4Pdcb`
- [A8] CostBench — Sudowrite Pricing 2026 — `https://costbench.com/software/ai-writing-tools/sudowrite/`
- [A9] Trustpilot reviews + Nerdynav 2026 review — `https://uk.trustpilot.com/review/www.sudowrite.com`, `https://nerdynav.com/sudowrite-review/`

---

## B. Novelcrafter — deep dive

### B.1 Project structure + Codex

Novelcrafter's project model is a **Codex** — a structured database of entries (characters, locations, factions, objects, etc.) plus a Manuscript, plus Outlines.[B1] Reviewers consistently characterise Novelcrafter's Codex as "deeper / more flexible" than Sudowrite's Bible, while Sudowrite is "more guided."[B2]

### B.2 Codex injection mechanics

Novelcrafter exposes a **prompt-function grammar**.[B3] Users can write `codex.get(name_or_alias)` inside prompt templates to pull one or more Codex entries by name. Functions auto-convert input into something the model can use. Codex entries can also act as **shortcuts in Chat** — mentioning a framework's name pulls the entire entry into context without manual copy-paste.[B3]

Novelcrafter detects scene beats, codex entries, or outlines automatically to reduce copy-paste work.[B4] (How aggressive the detection is is the load-bearing question for power users.)

The reviewer signal: **Novelcrafter exposes more of its prompt internals than Sudowrite, but at the cost of a steeper onramp.**[B5]

### B.3 BYOK + AI cost model

Unlike Sudowrite, Novelcrafter is **Bring Your Own Key (BYOK)** — users connect OpenRouter / OpenAI / Anthropic / etc. and pay for tokens directly to the provider. Subscription is for the workspace, not the AI.[B5]

| Tier | Monthly (annual) | What |
|---|---|---|
| Scribe | $4 ($40/yr) | Org features, no AI |
| Hobbyist | $8 ($80/yr) | External AI integrations |
| Artisan | $14 ($140/yr) | Full chat features + advanced customization |
| Specialist | $20 ($200/yr) | Team / collaboration |

Active novel writing with Claude/GPT runs an additional **$10–$30+/month in API fees** depending on use.[B5][B6]

**Signal for Loom:** Loom is BYOM (bring your own model — local kobold). The BYOK experience pain Novelcrafter inherits — credentials, key management, model selection — is what Loom inherits structurally. The lesson is to make the model-config experience invisible-when-default and explicit-when-needed.

### B.4 What users complain about

- **Steep BYOK onramp**: non-technical writers don't have an API key lying around. "That's developer work, not writer work" was a reviewer's blunt summary.[B6][B7]
- **Codex is "exhausting" to populate manually** for new users.[B7]
- **Restricted creative freedom**: users complain they don't have full control over what goes into the prompt; the AI relies on summaries and they have to keep going back and editing summaries per scene.[B7][1S]
- **Setup overhead**: connecting AI keys, choosing models, making writers feel they need to be "AI gurus."[B6]

### B.5 Sources

- [B1] Novelcrafter Help — The Codex — `https://docs.novelcrafter.com/en/articles/8675743-the-codex`
- [B2] Sudowrite Blog — Sudowrite vs. Novelcrafter — `https://sudowrite.com/blog/sudowrite-vs-novelcrafter-the-ultimate-ai-showdown-for-novelists/`
- [B3] Novelcrafter Help — Prompting Terminology — `https://docs.novelcrafter.com/en/articles/8678119-prompt-functions-custom-instruction-grammar`
- [B4] Novelcrafter — Features — `https://www.novelcrafter.com/features`
- [B5] DreamGen — Novelcrafter Review — `https://dreamgen.com/blog/articles/novelcrafter-review`
- [B6] Novelcrafter — Pricing — `https://www.novelcrafter.com/pricing`
- [B7] Medium — Novelcrafter Review (April 2026) — `https://ilampadmanabhan.medium.com/novelcrafter-review-64d391c629a2`

---

## C. NovelAI — closest in spirit to local-model setup

### C.1 Lorebook

The Lorebook is a repository for supplemental information added to context "as each entry comes up in your story."[C1] Mechanics:

- **Activation Keys** per entry. Entry text is inserted when an activation key is found in the recent context.[C1] `&` in a key means multiple keys must co-occur in the activation window.
- **Search Range** controls how many characters of recent story are scanned for keys (max 10,000).[C2]
- **Placement tab** controls where in context the entry text is inserted; entries placed lower in the prompt have stronger influence.[C2]

### C.2 Memory and Author's Note (the "VIP lorebooks")

**Memory** and **Author's Note** are always-active fields, can't be deleted, live in the right-hand sidebar.[C2]

- **Memory**: inserted at the top of every request — "always remember" content.[C3] (Plot setup, premise.)
- **Author's Note**: inserted near the *end* — controls the *mood/behavior* of the AI.[C3] **A/N Strength** controls insertion depth: closer to end = stronger influence on the next generation.[C3]

This is the single most copied pattern in the local-model fiction space. KoboldAI Lite, SillyTavern, Backyard.ai all expose Memory + Author's Note + Lorebook in the same shape.[D1][G1][H1] **Loom should adopt this trichotomy verbatim**: persistent setup at the top, recency-keyed selective injection in the middle, mood/style steering at the bottom.

### C.3 AI Modules — style training (now deprecated)

NovelAI's AI Modules let users prompt-tune the model on a `.txt` corpus to mimic a specific author's style or learn a series' characters.[C4] Training: input split into 256-token chunks, randomly shuffled, ~5 steps/sec. A 1,000-step module trains in ~3 minutes.[C4]

**Important update:** user support for training new modules was discontinued in late 2024, citing infrastructure incompatibility. Today NovelAI considers Lorebook + Memory effective enough to substitute.[C5][1S]

**Signal for Loom:** users want *style ingestion* as a first-class feature. The deprecation is a tooling/infrastructure call, not a user-demand call. Loom's style-ingestion phase (Phase 5 in the strawman PLAN.md) should view this as a confirmed user need.

### C.4 Sources

- [C1] NovelAI Documentation — Lorebook — `https://docs.novelai.net/en/text/lorebook/`
- [C2] TapWaveZodiac NovelAI Knowledgebase — Lorebook — `https://tapwavezodiac.github.io/novelaiUKB/Lorebook.html`
- [C3] TapWaveZodiac — Context — `https://tapwavezodiac.github.io/novelaiUKB/Context.html`
- [C4] Anlatan / NovelAI Blog — Custom AI Modules — `https://blog.novelai.net/custom-ai-modules-dbc527d66081`
- [C5] NovelAI Documentation — Modules — `https://docs.novelai.net/en/text/modules/`

---

## D. KoboldAI Lite + KoboldCpp — the canonical local-model story UI

### D.1 Memory / Author's Note / World Info

KoboldAI Lite's "Memory, Author's Note and World Info" trio is the inherited NovelAI shape:[D1]

- **Memory**: inserted at the top of every request — content the AI must always remember.
- **Author's Note**: inserted *near the end* of the text. **A/N Strength** controls insertion depth — closer to end = stronger.
- **World Info Groups**: segmentable lore (per place / person / event); each group toggleable on/off.

### D.2 Story / Adventure / Chat formats

KoboldAI Lite distinguishes story-mode (raw prose continuation), adventure-mode (turn-based interactive fiction), and chat-mode (turn-taking conversation). For Loom's purposes, **story-mode is the only correct paradigm**. The adventure/chat formats both contaminate fiction prose with structural artifacts (turn separators, instruction prefixes) that bleed into the model's outputs.

### D.3 KoboldCpp = the deployed runtime

KoboldCpp wraps llama.cpp with KoboldAI-compatible endpoints. The user's RPClient already wires `KoboldClient` against this. Loom inherits this directly — same `/api/v1/generate`, `/api/extra/version`, `/api/extra/true_max_context_length` endpoints.[D2]

### D.4 Sources

- [D1] KoboldAI Wiki — Memory, Author's Note and World Info — `https://github.com/KoboldAI/KoboldAI-Client/wiki/Memory,-Author's-Note-and-World-Info`
- [D2] KoboldCpp on GitHub — `https://github.com/LostRuins/koboldcpp`

---

## E. Plottr — gold-standard visual outliner (no AI)

### E.1 Timeline view

The Timeline is a 2D grid: **chapters/scenes on one axis, plotlines on the other** — each plotline a coloured row scrolling horizontally.[E1] Drag-drop scene cards. Multiple plot lines visible simultaneously.[E2] Plottr supports tracking main plots, subplots, character arcs, story structures, and beats all on the same surface.[E2]

### E.2 Outline view

The Outline section provides a traditional linear view, automatically generated from the Timeline's content + structure.[E3] Outline V2 adds Plan and Fulltext tabs.[E3] Filtering by plotline lets the user audit a subplot's progression in isolation.[E3]

### E.3 Templates

40+ plot outlining templates (Snowflake, Save the Cat, Hero's Journey, etc.).[E4]

### E.4 Signal for Loom

The 2D Timeline-Plotline grid is the single most-imitable structural UX in fiction tooling. Sudowrite has no equivalent; Novelcrafter has neither. Loom doesn't need this for Phase 1, but **a Phase 4+ outliner with a Plottr-shaped timeline is high-value and unmatched in AI-fiction tools**.

### E.5 Sources

- [E1] Plottr — Features — `https://plottr.com/features/`
- [E2] Plottr Docs — Timeline Plotlines — `https://docs.plottr.com/article/56-timeline-plotlines`
- [E3] Plottr Docs — Outline Overview — `https://docs.plottr.com/article/68-outline-overview`
- [E4] Plottr Blog — Outline Books — `https://plottr.com/outline-books/`

---

## F. AI Dungeon — the cautionary tale

### F.1 What happened

April 2021: OpenAI (then AI Dungeon's primary backend) detected users generating CSAM. OpenAI required Latitude (the developer) to act.[F1][F2] Latitude deployed an aggressive content filter and announced manual moderator review of *private* stories.[F1][F2]

### F.2 What broke

- **Filter false-positive rate**: flagged phrases like "an 8-year-old laptop."[F2]
- **Privacy invasion**: private stories reviewed by humans triggered the loudest user backlash.[F1]
- **Trust collapse**: users could not predict what the model would refuse.

Latitude rolled back manual moderation in August 2021; eventually shifted to a hybrid where OpenAI-flagged generations are routed to Latitude's own (smaller, less-restricted) models.[F3]

### F.3 Signal for Loom

Three load-bearing anti-patterns:

1. **Server-side filtering of fiction** is incompatible with the use case. Loom uses local models — this is a structural advantage, not just a feature.
2. **Manual review of private writing** breaks the user contract. Loom never sends prose anywhere.
3. **Opaque refusal** destroys author trust. Loom should expose what was sent and received fully (Sudowrite's History chiclets pattern, but more complete).

### F.4 Sources

- [F1] Trust and Safety Foundation — AI Dungeon case study — `https://www.trustandsafetyfoundation.org/blog/blog/game-developer-deals-with-sexual-content-generated-by-users-and-its-own-ai-2021`
- [F2] TechSpot — AI Dungeon censored — `https://www.techspot.com/news/89571-machine-learning-text-adventure-ai-dungeon-now-censored.html`
- [F3] AI Dungeon Help — OpenAI and Filters — `https://help.aidungeon.com/faq/openai-and-filters`

---

## G. Backyard.ai (formerly Faraday)

Local-first character/chat app with desktop binary running models offline. 100% local data; uncensored chatting with no content filtration.[G1] Features: **Author's Note** for scene-setting/style steering, **Lorebooks** for context, and **Grammars** for enforcing structural output formats.[G1] 1,000+ pre-made characters in their hub.[G1]

**Signal for Loom:** Backyard validates the local-first uncensored posture but is character-chat-shaped, not story-shaped. The Author's Note + Lorebook + Grammars triad is more modular than NovelAI's; **Grammar-constrained output** is a feature Loom should consider for structured generation modes (e.g., "generate a scene-summary as JSON").

### G.1 Sources

- [G1] Backyard AI — Home + Advanced Tips — `https://backyard.ai/`, `https://backyard.ai/docs/creating-characters/advanced-tips`

---

## H. SillyTavern — story-mode reality

### H.1 Lorebook activation modes

SillyTavern's Lorebook (a.k.a. World Info) supports three activation modes:[H1]

- **Vectorized** — semantic-similarity retrieval (RAG-style).
- **Constant** — always injected (highest cost, no key check).
- **Normal** (keyed) — keyword-triggered.

Entries can be tagged with secondary keys (AND-gating). Selective injection, position-in-prompt control, depth-from-end control are all exposed.

### H.2 Story-mode preset culture

The dominant idiom for story-mode in SillyTavern is the "**NoAss**"-class preset (no assistant turn enforced; raw continuation).[H2][1S — NoAss as a *named* preset is community-grown; the *technique* is widespread.] Power-user setups typically:

- Use a **single Character Card as a "narrator"** rather than a chatting persona.
- **Constant** lorebook entries for setting/style; **keyed** entries for characters.
- Author's Note injected at depth N (typically 2–4 lines from end) carrying tone instructions.
- Heavy **Quick Replies** for one-click invocation of generation modes.

### H.3 Signal for Loom

The constant/keyed/vectorised trichotomy is the right axis. **Vectorised injection** — pre-Phase-5 RAG-for-style — is already a known pattern, not a Loom invention.

### H.4 Sources

- [H1] SillyTavern Docs — World Info — `https://docs.sillytavern.app/usage/core-concepts/worldinfo/`
- [H2] sphiratrioth666 / Hugging Face — SillyTavern Presets — `https://huggingface.co/sphiratrioth666/SillyTavern-Presets-Sphiratrioth`

---

## I. Local-model culture (r/LocalLLaMA + r/SillyTavernAI)

### I.1 Top-tier fiction models

**Round 3 update (2026-05-10):** the community model list rotated between research rounds. The original 2024-era Mistral Nemo finetune cluster (Magnum/Lumimaid/Cydonia/EVA/Stheno) is no longer the dominant recommendation; the April 2026 r/LocalLLaMA + r/SillyTavernAI consensus list[I1.RoundB] favors Gemma 4 abliteration variants. Both lists shown below; defer to the April-2026 list for production-default recommendations.

**April 2026 community-consensus list[I1.RoundB] (current):**

| Tier | Model | Best for |
|---|---|---|
| Tiny (~2B active MoE) | **Huihui Gemma 4 E2B Abliterated v2** | Lightweight checks; punches above weight |
| 7B | **SultrySilicon V2** | Creative writing, roleplay |
| 9B | **Gemma-2-Ataraxy-9B** | Creative writing; strong EQ-Bench |
| 9B | **Huihui-GLM-4.6V-Flash** | Vision + bilingual |
| 13B | **MythoMax-L2-13B** | The OG; ~59k GGUF downloads, sustained favorite |
| 24B | **Dan's PersonalityEngine V1.3.0** | Generalist roleplay + reasoning + multilingual |
| 27B | **Gemma 3 27B Abliterated** | Instruction-following, multimodal |
| 31B | **Huihui Gemma 4 31B Abliterated** | Strongest dense Gemma 4 |
| 70B | **Midnight Rose 70B v2.0.3** | High EQ-Bench at low quants |
| 70B | **Midnight Miqu 70B v1.5** | Sustained 2-year community favorite for prose |
| 671B (37B active) | DeepSeek V3 | **Hosted only** — not local-realistic |

**Original survey list (kept for archival; Round 1 from arsturn/insiderllm reviews):**

| Tier | Model family | Notes |
|---|---|---|
| 70B+ | Qwen 2.5 72B + Magnum/EVA finetunes | Was Round 1's pick; community since rotated to Midnight Miqu / Gemma 4 abliterations.[I1] |
| 30B-class | Gemma 2 27B | Mid-range; superseded by Gemma 3 27B Abliterated and Dan's PersonalityEngine 24B. |
| 12-15B sweet spot | Mistral Nemo 12B + Lyra/Lumimaid/Magnum/Cydonia/EVA finetunes | Community has rotated away from these specifically; Gemma 4 abliteration family + MythoMax-L2-13B are the laptop sweet spot now.[I1] |
| 7-8B floor | Llama 3.1 8B, Mistral 7B Instruct, Qwen 2.5 7B | Acceptable for summariser side-calls; SultrySilicon V2 7B more current for prose.[I1] |

**Mistral Large 2** is still praised for long-project consistency.[I1]

### I.2 Abliteration and uncensored finetunes

**Abliteration** — surgical removal of refusal-mechanism activations — is the current 2026 standard for uncensored local models.[I1] Preserves intelligence while removing safety refusals. Most NSFW finetunes (Magnum, Lumimaid, Cydonia, EVA, Stheno) are either abliterated or trained on uncensored datasets.

### I.3 Sampler culture

**XTC (Exclude Top Choices)** — removes the highest-probability tokens above a threshold; intended to reduce slop.[I2][I3]
**DRY (Don't Repeat Yourself)** — penalises sequences that have already occurred verbatim.[I2][I3]
**Min-P** — dynamic top-p; widely-adopted default for fiction.[I2]

Canonical sampler pipeline order (community consensus): `penalties → DRY → top_n_sigma → top_k → typ_p → top_p → min_p → XTC → temperature`.[I2]

The 2025 ICLR paper "AntiSlop" explicitly motivates XTC/DRY as anti-slop tooling: phrases like "voice barely above a whisper" appear thousands of times more often in LLM text than in human writing.[I3]

### I.4 Instruct templates for fiction

Fiction prose generation lives uneasily on top of chat-tuned models. Practical 2025 norms:[I4]

- **ChatML** (Qwen) — the most common; works for story-mode if the system prompt is firm.
- **Mistral V3/V7** — Mistral Instruct does *not* natively support system messages; care needed when assembling.[I4]
- **Llama 3** — `<|start_header_id|>` tokens; works but verbose.
- **Alpaca** — older but still common in finetune cards; some Mistral merges require it.[I4]

The mismatch trap: a model finetuned on Alpaca will degrade if prompted with ChatML, and vice versa. Loom must **respect the model card's stated template**, not pick a default.

### I.5 Sources

- [I1] InsiderLLM — Best Local LLMs for Writing — `https://insiderllm.com/guides/best-local-llms-writing-creative-work/`; ArSturn — Best Ollama Models — `https://www.arsturn.com/blog/a-guide-to-the-best-ollama-models-for-creative-writing-and-rp`
- [I1.RoundB] swyxio gist — r/localLlama + r/localLLM + r/sillytavernAI preferred models list (April 2026, last updated 2026-05-04) — `https://gist.github.com/swyxio/324fc884061bf20e97a2ecbe59bae34a`
- [I2] smcleod.net — LLM Sampling Parameters Guide — `https://smcleod.net/2025/04/llm-sampling-parameters-guide/`
- [I3] AntiSlop ICLR 2026 — `https://openreview.net/pdf/6916f45661bf884811be66da937b7467b97a9114.pdf`
- [I4] Unsloth Chat Templates — `https://unsloth.ai/docs/basics/chat-templates`; Mistral docs — `https://docs.mistral.ai/cookbooks/concept-deep-dive-tokenization-chat_templates`

---

## J. Scrivener + non-AI long-form editor patterns

### J.1 The five-thing canon

Scrivener's load-bearing structural primitives, in order of theft-priority:[J1][J2][J3]

1. **Binder** — hierarchical sidebar: project tree containing chapters, scenes, research, images.[J1] "Table of contents on steroids."
2. **Corkboard** — index-card layout of scenes; drag-rearrange; "transforms Scrivener from fancy Word into actual novel-planning software."[J2] Each card holds a scene's synopsis; the prose lives one click away.
3. **Inspector** — detail pane (synopsis / notes / keywords / metadata) per document.[J1]
4. **Snapshots** — version-history-per-document. Save before rewrite; compare later.[J1]
5. **Compile** — export pipeline: DOCX, PDF, ePub, Kindle.[J1]

Plus the secondary tier: **Composition mode** (full-screen distraction-free), **Outliner view** (table of all documents with metadata columns), **Project Targets** (word-count goals), **Collections** (saved-search-shaped groupings), **Document/Project Notes**, **Quick Reference panes** (split-screen reference docs).

### J.2 Why this matters for Loom

Loom's editor surface needs the Binder + the Corkboard at minimum. The Inspector is where the Story Bible lives in Loom's adapted version. Snapshots are how AI-generated drafts get version-locked before edits. Compile is Phase 6.

The MVP's claim ("AI-bolted-on Scrivener") only holds if Phase 1 has at least the Binder + a single editor surface. Corkboard can defer to Phase 3 (hierarchical structure + navigation per PLAN.md §5).

### J.3 Ulysses + iA Writer + Highland 2

**Ulysses** — markdown-first; library of "sheets" rather than file tree; goals system. Faster to *write* in but harder to *structure* a novel in. Power users prefer Scrivener for novels and Ulysses for essays.[J4][1S]

**iA Writer** — focus mode (current paragraph emphasised; rest dimmed); syntax highlighting for parts of speech; minimal chrome. Feature directly applicable to Loom: **focus mode is a Phase 1 candidate** (single-flag toggle on NSTextView).

**Highland 2** — screenwriting; the "Bin" (drag-drop reorderable scene cards) and revision-tracking colours are interesting but screenwriting-shaped.

### J.4 Obsidian + Longform — the DIY pattern

Longform plugin for Obsidian: dedicated sidebar collecting project files, drag-rearranging scenes, compilation to a single document with separators, daily/project word-count goals.[J5][J6] Not AI-aware but the **scene-as-its-own-markdown-file pattern** is exactly what Loom should adopt for its on-disk format (round-trippable plain markdown, not a .scriv-style opaque blob).

### J.5 Manuskript / yWriter / bibisco

**yWriter** — free; chapter+scene breakdown, character/location/item tracking, conflict/outcome fields per scene.[J7] Spartan but the per-scene metadata (POV, time, location, conflict, outcome) is a strong ontology.

**bibisco** — distraction-free editor + analysis features + worldbuilding; multi-platform; 15 languages.[J8]

**Manuskript** — open-source Scrivener clone with character/world-building modules. Smallest community of the three but the most Scrivener-like.

**Signal for Loom:** yWriter's per-scene metadata schema (POV / time / location / conflict / outcome) is a *better* scene-metadata starting point than Scrivener's free-form synopsis card. Loom's `Scene` type should default to these fields.

### J.6 AutoCrit + ProWritingAid — critique surfaces

AutoCrit is fiction-genre-aware (pacing, dialogue, POV consistency); ProWritingAid is more general-purpose with line-edit + grammar plus overall reports.[J9][J10] Both produce manuscript-level reports rather than inline suggestions.

**Signal for Loom:** the **Critique generation mode** should be modelled on AutoCrit's posture — fiction-specific (POV breaks, dialogue tags, pacing) rather than ProWritingAid's grammar-first posture. ProWritingAid's stylistic features partially compete with what Loom's "Rewrite" mode provides.

### J.7 Sources

- [J1] Zapier — How to Use Scrivener — `https://zapier.com/blog/how-to-use-scrivener/`
- [J2] Literature & Latte — Organize with Corkboard — `https://www.literatureandlatte.com/blog/organize-your-scrivener-project-with-the-corkboard`
- [J3] ProWritingAid — Scrivener Outliner + Corkboard — `https://prowritingaid.com/art/1555/using-scrivener-s-novel-outlining-tools.aspx`
- [J4] ScribeCount — Scrivener Guide — `https://scribecount.com/author-resource/writing-tools-for-authors/scrivener-for-novelists-guide`
- [J5] Longform on GitHub — `https://github.com/kevboh/longform`
- [J6] PD Workman — Write Book with Obsidian — `https://pdworkman.com/write-book-with-obsidian/`
- [J7] yWriter / bibisco SourceForge comparison — `https://sourceforge.net/software/compare/bibisco-vs-yWriter/`
- [J8] bibisco — `https://bibisco.com/`
- [J9] AutoCrit vs ProWritingAid (PWA) — `https://prowritingaid.com/autocrit-vs-prowritingaid`
- [J10] Pen and Glory — comparison — `https://www.penandglory.com/post/prowritingaid-vs-autocrit-comparison-and-review`

---

## K. Campfire Writing — the modular bible model

Campfire is a fiction-planning platform with **purchasable modules**:[K1][K2]

- **Characters** — sheets + reference imagery + relationship webs.
- **Timeline** — multipurpose timelines.
- **Worldbuilding family**: Encyclopedia, Cultures, Languages (with letter/symbol scripts + dictionaries), and others.

**Signal for Loom:** the modular bible — entity sheets that compose into a relationship graph + timeline — validates the "Story Bible as multiple linked entity types, not a single flat doc" posture. Loom's data model should expose at least Character, Setting, Timeline-event, and (Phase 5+) Relationship.

### K.1 Sources

- [K1] Campfire — `https://www.campfirewriting.com/`
- [K2] Campfire — Worldbuilding Tools — `https://www.campfirewriting.com/worldbuilding-tools`

---

## L. Long-context engineering — academic + applied

### L.1 Recursive book summarisation (Wu et al., OpenAI 2021)

The canonical paper for novel-length summarisation: Jeff Wu et al., *Recursively Summarizing Books with Human Feedback*, arXiv:2109.10862.[L1] Method: model summarises small sections; recursively summarises summaries; human labeler validates at each level. **Result:** the model can summarise books of unbounded length, unrestricted by transformer context length.[L2]

For Loom: this is the canonical pattern for **scene → chapter → part → book** summary chains. Each summary is regenerated only when its underlying content changes (incremental update).

### L.2 Re3 + DOC — story generation with structured outline + state tracking

Re3 (Yang et al. 2022, EMNLP): generates >2000-word stories via Recursive Reprompting + Revision.[L3][L4] Pipeline:

1. **Plan** — model constructs a structured overarching plan.
2. **Draft** — story passages generated with plan + current-state injected each step.
3. **Revise** — multiple continuations reranked for plot coherence + premise relevance.
4. **Edit** — Re3's Edit module **infers natural-language facts about each character and converts them to attribute-value pairs to track narrative state**.[L4]

DOC (Yang et al. 2023, ACL): improves on Re3 with detailed outlines, character development over time, more detailed events from outline leaf nodes, future context, and explicitly-extracted setting/characters.[L5] DOC was specifically motivated by the observation that Re3's outlines were "insufficiently concrete and do not scale to longer stories."[L5]

**For Loom:** this is the strongest academic prior art for **knowledge-state-per-character-per-scene**, the user's stated novel-territory feature. Re3's character-fact-extraction pattern should be Loom's starting point. The state is queried at generation time to constrain what each character knows.

### L.3 SCORE — story coherence + retrieval

SCORE (2025, arXiv:2503.23512) extends the pattern: temporal knowledge graphs and narrative entity knowledge graphs to track character states/actions/facts; reduces contradiction and increases continuity.[L6]

### L.4 LlamaIndex — applied hierarchical retrieval

The **Document Summary Index** stores a summary per document plus all its nodes; retrieval first inspects summary, then pulls nodes if relevant.[L7] The **Tree Index** builds a bottoms-up summary tree; each parent summarises children.[L8]

For Loom: the Tree Index pattern *is* the scene→chapter→part→book summary chain, ready-made.

### L.5 RAG fundamentals (chunking + embedding)

Standard RAG patterns survey:[L9]

- **Chunking**: sentence vs paragraph vs semantic chunks. For prose-style retrieval, paragraph or semantic-block chunks (~256–512 tokens) with ~50-token overlap is the common default.
- **Embedding**: BGE / E5 / gte are open / free; Voyage and OpenAI's embeddings are paid but better. For *style* retrieval specifically, generic semantic embeddings are imperfect — the document explicitly notes "ranking and reconciling style/tone are also key" when using multiple retrieved passages.[L9]
- **HyPE (Hypothetical Prompt Embeddings)** — precompute hypothetical prompts at index time; transforms retrieval into question-question matching.[L9]

**Gap finding:** there is *no* widely-adopted "stylistic embedding model" in 2026. Style retrieval in production systems uses semantic embeddings as a proxy (which works partially — adjacent prose tends to share style). Loom's Phase 5 (style ingestion) sits in genuinely under-explored territory.

### L.6 Sources

- [L1] Wu et al. — Recursively Summarizing Books — `https://arxiv.org/abs/2109.10862`
- [L2] OpenAI — Summarizing books with human feedback — `https://openai.com/index/summarizing-books/`
- [L3] Re3 paper — `https://arxiv.org/abs/2210.06774`
- [L4] Re3 PDF — `https://nlp.cs.berkeley.edu/pubs/Yang-Tian-Peng-Klein_2022_Re3_paper.pdf`
- [L5] DOC paper — `https://aclanthology.org/2023.acl-long.190.pdf`
- [L6] SCORE — `https://arxiv.org/html/2503.23512v1`
- [L7] LlamaIndex — Document Summary Index — `https://www.llamaindex.ai/blog/a-new-document-summary-index-for-llm-powered-qa-systems-9a32ece2f9ec`
- [L8] LlamaIndex — How Each Index Works — `https://docs.llamaindex.ai/en/stable/module_guides/indexing/index_guide/`
- [L9] Prompt Engineering Guide — RAG — `https://www.promptingguide.ai/research/rag`

---

## M. Cross-cutting synthesis

### M.1 Editor-surface UX patterns (the tier list)

| Pattern | Where it's done well | Steal for Loom? |
|---|---|---|
| **Project tree (Binder)** | Scrivener[J1], Obsidian Longform[J5] | Yes — Phase 1 |
| **Scene = file (round-trippable)** | Obsidian Longform[J5] | Yes — Phase 1 disk format |
| **Corkboard / index cards** | Scrivener[J2], Highland 2 | Yes — Phase 3 |
| **2D Timeline × Plotline grid** | Plottr[E1] | Yes — Phase 4+ |
| **Inspector panel** | Scrivener, RPClient[V2_UI_OVERHAUL §4] | Yes — Phase 2 (Bible inspector) |
| **Snapshots / version-per-doc** | Scrivener | Yes — Phase 5+ (auto-snap before AI rewrite) |
| **Focus mode (current-paragraph emphasis)** | iA Writer | Yes — Phase 1 if cheap, defer if not |
| **History chiclets (what context was sent)** | Sudowrite[A5] | **Strong yes** — Phase 1 if feasible; Phase 2 latest |
| **Compile / multi-format export** | Scrivener | Phase 6 |
| **Plotline filter / outline view** | Plottr[E3] | Phase 4+ |

### M.2 Story bible / consistency engineering

| Approach | Tool | Loom posture |
|---|---|---|
| Free-form bible doc | Most early ones | Reject — too vague |
| Dependency-ordered fields (Braindump → Synopsis → Characters → ...) | Sudowrite[A2] | **Adopt the field set; relax the strict ordering** (a complaint of Sudowrite's[A9]) |
| Codex with named entries + alias-driven prompt-function injection | Novelcrafter[B3] | Adopt the prompt-function grammar (`{{character.name}}`-style) |
| Lorebook with constant/keyed/vectorised modes | SillyTavern[H1] | Adopt the trichotomy |
| Modular bible (Characters + Timeline + Cultures + ...) | Campfire[K1] | Adopt as data model; surface only what's needed per Phase |
| Knowledge-state-per-character (attribute-value pairs from Re3 Edit) | Re3[L4] / DOC[L5] | **This is Loom's novel territory** — adopt the pattern, extend per-scene |

### M.3 Generation modes — cross-tool inventory

Continue / Expand / Rewrite / Brainstorm / Critique / Bridge appears in nearly every tool.[A6][B1] Sudowrite has the cleanest *named* set; Loom should adopt these names with thoughtful additions (Show-don't-tell, Bridge between scenes are explicit; POV-swap and Tense-swap are Rewrite variants, not separate modes).

### M.4 Long-context strategies — what we know works

| Strategy | Strongest evidence | Loom Phase |
|---|---|---|
| Hierarchical summary tree (scene → chapter → part → book) | Wu et al. 2021[L1], LlamaIndex Tree Index[L8] | Phase 2 (per-scene summaries), Phase 3+ (rest) |
| Recent-prose continuity (last N adjacent scenes verbatim) | Sudowrite (20k words)[A4], every story-mode tool | Phase 1 |
| Bible-entry selective injection (constant + keyed) | NovelAI[C1], SillyTavern[H1], Novelcrafter[B3] | Phase 2 |
| RAG-for-style (vectorised retrieval of past prose) | SillyTavern Vectorized mode[H1], experimental | Phase 5 |
| Author's Note depth-N injection (mood/style steering) | NovelAI[C3], KoboldAI[D1] | Phase 1 (carry from RPClient) |
| Knowledge-state attribute-value tracking | Re3 Edit module[L4] | Phase 4 (story bible v2) |

### M.5 Style ingestion — the open territory

The honest assessment:

- **NovelAI deprecated AI Modules** (the only commercial style-ingestion-via-fine-tuning) in late 2024.[C5]
- **No widely-adopted stylistic embedding model exists.** Generic semantic embeddings work *partially* for style.[L9]
- **Few-shot style examples in the prompt** is the dominant working pattern.

Loom's Phase 5 sits in genuine R&D territory. Plausible approaches, in order of complexity:

1. User-authored **Style Sheet** entity (tone descriptors, sentence-length profile, lexicon, sample paragraphs). Always-injected. Cheap, partially effective.
2. **Few-shot retrieval** from user-uploaded reference texts via semantic similarity. Effective for "matched-tone passages."
3. **Per-scene-type retrieval** (action / dialogue / interiority / description). Requires upstream scene-type classification.
4. **LoRA fine-tuning** on the user's reference corpus. Most effective; out of Loom Phase 5 scope.

### M.6 NSFW-tool reality

The community's actual choices, not the marketing:

- **Local model + abliterated/uncensored finetune** (Magnum, Lumimaid, Cydonia, EVA, Stheno on Mistral Nemo / Qwen 2.5).[I1]
- **KoboldCpp / Ooba / ExLlamaV2** as backend.
- **SillyTavern story-mode-coerced** or **KoboldAI Lite story mode** as UI.[D1][H1]
- **Author's Note + Lorebook** for steering.
- **Sampler config visible and editable** (Min-P + DRY + XTC at minimum).[I2]

What's missing in this stack that the community actually wants:

- **A real long-form editor** (not chat-shaped) that respects the Author's Note + Lorebook + Memory triad. This is *exactly* Loom's gap.
- **Persistent project structure** beyond a single SillyTavern session.
- **Style ingestion** that survives a model swap (NovelAI's modules required staying on NovelAI).

### M.7 Pricing-as-feature-priority signal

| Tool | Monetisation | Implication |
|---|---|---|
| Sudowrite | Credits-per-month, all features unlocked | Bible + modes are the product |
| Novelcrafter | Subscription + BYOK | Workspace + integration is the product |
| NovelAI | Subscription + included generations | Closed model is the moat |
| KoboldAI Lite + KoboldCpp | Free / OSS | Community-led |
| Campfire | Per-module purchases | Bible modules are the product |
| Scrivener | One-time license | Stable, not aggressive on feature growth |

**Loom signal:** local-first + zero recurring cost is differentiating against everyone but Kobold/SillyTavern. Local-first + serious editor is differentiating against Kobold/SillyTavern.

### M.8 Pain-point inventory (across tools)

Themes that repeat across user complaints:

1. **Opaque prompt assembly** — "what was actually sent?" Universal complaint.
2. **Glitchy state under long-form work** — Sudowrite[A9] crashes/lost progress; Novelcrafter[B7] stale-summary friction.
3. **Steep onramp / "AI guru" required** — Novelcrafter BYOK[B6][B7]. **Loom faces this same risk** with model selection / sampler config / instruct templates.
4. **Server-side filtering** — AI Dungeon[F2]; NovelAI's softer take. Avoided by local-first.
5. **Lock-in formats** — Scrivener's `.scriv` blob, Sudowrite's project DB. Obsidian's "scene = file" is the antidote.
6. **AI-generated content not visually distinct** from human-written — universal across AI-fiction tools. Loom should solve this.
7. **No version history of prose** before AI rewrites. Snapshots solve it; few AI tools have them.

---

## N. What's load-bearing for Loom (ranked, opinionated)

The 8–12 ideas the design docs should treat as anchors:

1. **Story Bible as a structured, dependency-ordered-but-skippable set of entity types** (Sudowrite[A2] schema; Campfire[K1] modular composition). Phase 2.
2. **Local kobold backend + uncensored model + visible sampler config** (KoboldCpp[D2]; r/LocalLLaMA[I1]; sampler culture[I2]). Phase 1.
3. **Memory + Author's Note + Lorebook trichotomy** (NovelAI[C2]; KoboldAI[D1]; SillyTavern[H1]). Phase 2.
4. **Selective injection: constant + keyed + (Phase-5) vectorised** (SillyTavern[H1] is the canonical model). Phase 2 / Phase 5.
5. **Scene-as-markdown-file on disk; project-as-directory** (Obsidian Longform[J5]). Phase 1.
6. **Binder-shaped project tree + Inspector panel** (Scrivener[J1]; RPClient design language). Phase 1 (binder), Phase 2 (inspector).
7. **Hierarchical summary tree (scene → chapter → book)** (Wu et al.[L1]; LlamaIndex Tree Index[L8]). Phase 2 (per-scene), Phase 3+ (chains).
8. **Generation context transparency — History chiclets** (Sudowrite[A5]). Phase 1 if feasible, Phase 2 floor.
9. **Knowledge-state-per-character (attribute-value pairs from Re3 Edit)** (Re3[L4], DOC[L5]). Phase 4 — this is Loom's distinctive engineering.
10. **20k-word recent-prose context window** (Sudowrite[A4] empirically validates this scale). Phase 1 (sub-32k local-model variant; budget allocation in LOOM_GENERATION_MODES.md).
11. **Snapshots before AI rewrite** (Scrivener[J1]). Phase 5+ (cheap; consider Phase 2).
12. **Plottr-shaped 2D Timeline × Plotline grid** (Plottr[E1]). Phase 4+ — differentiator.

---

## O. What gaps prior art doesn't fill (the user's stated extensions)

Six user-stated requirements, mapped to closest prior art and where Loom must go beyond:

### O.1 Long-text ingestion (>>model context)

**Closest prior art:** LlamaIndex Tree Index + Document Summary Index.[L7][L8] OpenAI's recursive book summarisation pipeline (Wu et al. 2021).[L1]

**Going beyond:** Loom's reference-text ingestion isn't for QA (LlamaIndex's typical use case) — it's for **style and persona reuse during generation**. The pipeline:

1. User drops in a 200k-word reference (their own past novels, an author they admire).
2. Loom chunks (paragraph or scene boundaries), embeds, indexes.
3. Per-scene background pass: extract style markers, scene-type classification, character-voice samples.
4. At generation time: retrieve style-matched passages, insert as few-shot exemplars constrained by sub-32k context.

**Open R&D:** scene-type classification accuracy, style-vs-content disentanglement at retrieval.

### O.2 Persistent entities + events with consistency tracking

**Closest prior art:** Re3 Edit module's character-fact extraction[L4]; DOC's explicit setting+character extraction[L5]; Campfire[K1] modular bible.

**Going beyond:** prior art tracks character *attributes* but not knowledge-state-per-scene. Loom's distinctive engineering:

- For each character, maintain a **knowledge ledger** of facts the character knows-as-of-scene-N.
- Facts entered manually (bible) and extracted automatically (Re3-style fact extraction post-scene).
- At generation time, the model is told which facts the speaking character **does and doesn't know yet**.

This is the user's "what does Bob know at scene 12 vs 18" requirement made concrete. Phase 4 territory.

### O.3 Both lightweight prompts AND detailed scaffolding (gap-fill)

**Closest prior art:** Sudowrite's Bible auto-fills from a Braindump.[A2][A3] Novelcrafter requires manual Codex.[B7]

**Going beyond:** Loom should expose **both modes natively**:

- **Sketch-and-grow** (lightweight): user types a paragraph sketch, clicks Expand → 1500-2500 words of prose. Bible references are inferred from the sketch text.
- **Scaffold-first** (detailed): user populates Bible first, then writes; Bible content is the always-on context.

The user can move along this axis per-scene. Phase 1 ships the Sketch-and-Grow flow (Continue + Expand on sparse content); Phase 2 wires the Bible for Scaffold-first.

### O.4 Style/action-type reuse from very-long examples

**Closest prior art:** NovelAI AI Modules (deprecated)[C5]; SillyTavern Vectorized lorebook mode[H1]; few-shot prompting (universal).

**Going beyond:** generic similarity retrieval is imperfect for style. Loom's pipeline should support:

- **Style sheet** entity (tone descriptors, sentence-length profile, lexicon) — always-on.
- **Scene-type-tagged corpus**: action / dialogue / interiority / description chunks tagged on ingestion.
- **Generation-mode-aware retrieval**: when user invokes "write an action scene like the one I uploaded," retrieve scene-type=action chunks, not generic semantic-similar chunks.

Phase 5. Genuinely under-explored.

> **§O.4 update — 2026-05-13.** The "no widely-adopted stylistic
> embedding model exists" claim in [§L.5](#l-5-rag-fundamentals-chunking--embedding)
> and §M.5 below is **stale**. The Phase 5 spike ([LOOM_RAG_SPIKE.md](LOOM_RAG_SPIKE.md))
> ran a 5-path empirical eval and found three viable approaches:
>
> 1. **StyleDistance** (Oct 2024, [Patel et al. arXiv:2410.12757](https://arxiv.org/pdf/2410.12757))
>    — contrastive style embedder trained on SynthSTEL (40 style features)
>    + Reddit authorship pairs. RoBERTa-base, 768-dim, open-weights,
>    Apple-Silicon-runnable via sentence-transformers. The spike's NDCG@3
>    leader (0.883 vs semantic-embedder 0.809). The category does
>    exist; the literature just hadn't filtered down into RAG
>    practitioner guides by 2026-05-10.
> 2. **Wegmann Style-Embedding** (RepL4NLP 2022) — predecessor;
>    explicit "same topic ≠ same style" training objective.
> 3. **Burrows' Delta function-word z-score baseline** — 19th-century
>    stylometric primitive, ~50 LOC of numpy. **Tied StyleDistance on
>    NDCG@3 in the spike (0.883)** and was the most NSFW-parity-balanced
>    path. Either the spike fixture's styles separate too cleanly via
>    function-word frequency, or style genuinely is dominated by
>    function-word patterns at this corpus size. Phase 5 production
>    will re-test on real reference texts.
>
> Loom's Phase 5 architecture: **D + E hybrid index** (StyleDistance +
> function-word z-score), reference texts indexed in both spaces, all
> retrievals merge results from both. The "no stylistic embedder
> exists" framing was load-bearing for the original spike scope; it
> shaped the writer-LLM-distillation Path C, which then failed below
> floor when the GBNF descriptors collapsed under gemma-31B. Worth
> keeping the lesson: when foundational R&D literature claims an open
> territory, *verify with a focused research pass before sinking
> implementation hours into workarounds*.

### O.5 Heavy NSFW with zero limits

**Closest prior art:** local kobold + uncensored finetune + SillyTavern.[I1][H1]

**Going beyond:** the *model* handles content; the *tool* must not contaminate it. Specifically:

- No content moderation in Loom — ever.
- The instruct template must be respected per model, not picked by Loom.
- The system prompt must be user-editable, with a sane uncensored default.
- Refusal-detection is a *signal to the user* (their model refused), never a blocking event in Loom.

Phase 1 inheritance from RPClient covers most of this. The novel piece is making sure no part of the editor surface assumes safety language (e.g., placeholder prose, example bibles, tooltips) — the entire UX must be neutral about content.

### O.6 Same kobold backend as RPClient (local, uncensored)

**Closest prior art:** RPClient[V2_PLAN.md]. Direct reuse of `KoboldClient`, `ServerProbe`, `KoboldClientRegistry`.

**Going beyond:** RPClient's chat-shaped concepts (Turn, speakerId, Cast, Director) don't carry. Loom's prompt assembly is fundamentally different — there's no "prior turn"; there's "preceding prose + bible + style + author's note." Phase 1's PromptBuilder is a *new* module, not an inheritance.

---

## P. Falsifiable claims worth testing in Phase 2/3

Hypotheses to verify, not assert:

1. **20k-word context (Sudowrite-scale) outperforms 8k context** for long-form continuity in local-model generation. Easy to A/B once Phase 1 lands.
2. **Constant + keyed Bible injection beats always-inject-everything** at the 8k/16k context budgets common to local models. Token-budget pressure is real.
3. **Per-scene knowledge-state extraction (Re3-style) is feasible at <13B model size** for the side-call. If not, Loom needs a higher-tier extractor model (mirrors RPClient's `summarizer` role server pattern).
4. **Few-shot style retrieval beats system-prompt style descriptors** for prose imitation. Likely true; verify.
5. **Scene-type classification (action/dialogue/etc.) is doable with a 7B model** in a side-call, accuracy > 80% on user corpus. If true, Phase 5 viable; if not, it's a manual-tag-required feature.

---

## Q. Methodology limitations

- Web search dated 2026-05-10; tool feature lists drift on monthly cadence (especially Sudowrite + Novelcrafter — both ship feature changes monthly).[A][B]
- Reddit traffic for r/sudowrite, r/Novelcrafter, r/AIWriting was searched indirectly via review aggregators; threads themselves were not deep-read for individual quotes (would require browser MCP, blocked in this sandbox). Reviewer-aggregated complaints are still cited.
- **Single-source claims marked `[1S]`** should be verified before being load-bearing for a design call.
- The five planned subagents could not access web; this synthesis is parent-context, single-thread research. The angle that suffered most: deep Reddit thread-reading. Loom's design docs flag where decisions are based on Reddit-shaped consensus we couldn't independently quote.

---

## R. References (consolidated)

All URLs in §A–§L plus the primary RPClient internal references:

- [`PLAN.md`](PLAN.md) — original meta-plan.
- [`/Volumes/SSD1/Code/RPClient/V2_DESIGN_LANGUAGE.md`](../../RPClient/V2_DESIGN_LANGUAGE.md) — design language inherited verbatim.
- [`/Volumes/SSD1/Code/RPClient/V2_UI_OVERHAUL.md`](../../RPClient/V2_UI_OVERHAUL.md) — sub-step format precedent (§4.11).
- [`/Volumes/SSD1/Code/RPClient/V2_PLAN.md`](../../RPClient/V2_PLAN.md) — plan shape precedent.

External sources are cited in-line per section. No claim in this document should be load-bearing for an irreversible decision without a re-check against current sources at the time of that decision.

---

## S. Round 4 — depth on AI fiction tools, NSFW ecosystem, fanfic genre system

User-directed research push (2026-05-10 evening): "Make sure research on long-form AI fiction writers is as thorough as possible — approach, UI, how the overall approach works. Don't be afraid to look at code where available. Heavy NSFW and extreme topics as the focus. Plus a new feature idea: pick a specific fanfic genre, gather details, write on-topic stories with user guidance."

This section is the source of truth for the new feature docs:

- [`LOOM_FANFIC.md`](LOOM_FANFIC.md) — fanfic genre / fandom feature spec.
- [`LOOM_NSFW.md`](LOOM_NSFW.md) — heavy-NSFW + extreme-topics posture.

Citations below use `[S.*]` IDs. Each finding is verified from a primary source (WebFetch where allowed, WebSearch where blocked).

### S.1 Sudowrite Fandom Helper — verified shallow

Fetched the live page[S.SUDOWRITE-FANDOM]. Features:

- **Canon Lookup tool** — paste a passage, ask a canon question, get an answer.
- **Custom Fandom Creation** — beyond pre-loaded options.
- **Pre-built fandoms**: **Harry Potter, BTS, Marvel Cinematic Universe** (3 fandoms total).
- Integration with core Sudowrite features (Describe, Write, Rewrite, Expand).
- "Trope suggestions" mentioned but not detailed.

What it explicitly **lacks**:

- No slow-burn pacing mechanics.
- No AU scaffolding tools.
- No structured ship/relationship typing.
- No fanfic-specific generation modes.

This is Loom's closest competitor for the fanfic feature, and it's not deep. [`LOOM_FANFIC.md`](LOOM_FANFIC.md) §12 documents what Loom adds beyond.

### S.2 NovelAI Erato system prompt — the ATTG format

Verified from the unofficial NovelAI knowledgebase[S.ERATO]. The Erato system prompt format:

```
[ Author: Jacqueline Carey; Title: Amazing Story; Tags: adventure, modern day; Genre: contemporary fiction, prose ][ S: 4 ]
```

`S` parameter ranges 2-4 — "stylistic adherence" stage; higher = stronger compliance. "Datasetter Zaltys' recommendation" per the source.

**Lorebook structure recommended for steering:**

| Lorebook | Insertion Order | Position | Prefix | Reserved tokens |
|---|---|---|---|---|
| ATTG | 1 | 0 | (none) | small |
| INSTRUCTIONS (category) | 2 | 0 | `----\n` | 1000 |

Inside INSTRUCTIONS:
- "Lore of Lorebooks" (LoL) — meta-entry defining what "lore" means
- "Rules" lorebook — narrative constraints, tense/POV, banned concepts, character muting

Roles defined: **Lore** (information separated by `----`), **Narrative** (story), **Narrator** (model). This vocabulary is what Loom adopts in its prompt assembler when configured to mimic Erato's posture for NSFW work.

### S.3 AI Dungeon Story Cards — full schema

Verified from the official help page[S.AID-STORY-CARDS]:

**Five fields:**
- **Type** — Character / Class / Race / Location / Faction / Custom. **Not visible to AI**, organisation-only.
- **Name** — for user reference, **not visible to AI**.
- **Entry** — the only field the AI sees, prefaced with `World Lore:` automatically.
- **Triggers** — comma-separated keywords, case-insensitive, leading/trailing spaces matter, substring-matching ("boat" triggers on "boats"; warning about "cat" matching within words).
- **Notes** — not visible to AI.

**Activation persistence**: "Story Cards stay activated for a variable period depending on your context size" after a key match — temporal lingering, not just per-turn.

**Timing**: triggers are not instant — if an AI's mid-response output triggers a Story Card, that Card isn't available to the AI until the *next* output.

**Context budget**: Story Cards "are among the first elements to be removed from the context when it is full." Eviction priority surfaced; brevity recommended.

**Hard cap**: 5,000 Story Cards per Adventure / Scenario.

**Best-practice authoring guidance:**
- Most important info at beginning AND end of Entry (model bias toward those positions — "lost in the middle" mitigation).
- Mention the entity name explicitly inside Entry (since Name field is invisible to AI).
- Avoid excessive physical detail (model either ignores or repeats verbatim).
- Use truncated triggers to catch plurals (`boat` → `boats`).
- Cross-reference between cards.
- Prefer proper-noun triggers (lower false-positive rate).

[`LOOM_NSFW.md`](LOOM_NSFW.md) and [`LOOM_FANFIC.md`](LOOM_FANFIC.md) inherit these conventions in lorebook + canon brief authoring.

### S.4 NovelAI Lorebook — verified full field list

Cross-confirmed (this round) that `Probability`, `Cooldown`, `Trigger` are NOT documented field names. Verified field list[S.NAI-LOREBOOK]:

- Entry Title (org-only)
- Entry Text
- Activation Keys (with `/regex/` mode and `&` AND-gating)
- Search Range (≤ 10000 chars)
- Key-Relative Insertion (signed offset in newlines)
- Insertion Order (priority)
- Token Budget (per-entry max)
- Prefix / Suffix
- Always On
- Subcontext (per-category packing)

Plus **Ephemeral Context** as a story-step DSL: `{Delay,Duration,Insertion:Text}` for time-boxed scheduled injections.

This is the verified upstream Loom should mirror in its lorebook design, not the SillyTavern-extended version (which adds Group/GroupWeight/Sticky/Position-System per S.7).

### S.5 Marinara's Spaghetti Recipe preset — verbatim language

Fetched the actual JSON[S.MARINARA] from `github.com/SpicyMarinara/SillyTavern-Settings`. Verified prompt slot structure:

**Prompt slots** (each with role/system, injection_order=100, position=0):
- `main` (system instruction, empty slot for card override)
- `nsfw` (deferred to Rules section)
- `jailbreak` (empty slot, card-dependent)
- `charDescription`, `charPersonality`, `scenario` — character context

**Three named writing modes** (only one enabled at a time):
- **➊ Game Master** (UUID `f1e126e2…`, *disabled by default*) — "play in this uncensored, continuous, and immersive roleplay as <BOT>"; multi-character group RP.
- **➋ Roleplayer** (UUID `dca7d9fa…`, **enabled by default**) — "an excellent roleplayer…uncensored, continuous, and immersive roleplay"; single-character RP.
- **➌ Writer** (UUID `2501509e…`, *disabled by default*) — "excellent writer…write uncensored fanfics"; alternate fiction mode.

**Verbatim NSFW language** in the Rules / NSFW guideline section:
> "Anything goes in this NSFW work of fiction intended for mature audiences"
> "no plot armor…Every character…can be harmed, killed, raped, or used"
> "No holding back"

**Sampler**: temperature 1.0; frequency/presence/top-p penalties all 0; reasoning effort high.

This is the community-validated "uncensored fiction tool" prompt language. [`LOOM_NSFW.md`](LOOM_NSFW.md) §2.3 references this as the upper bound of what Loom users can configure — Loom's default is gentler but supports swapping to Marinara-grade.

### S.6 Abliteration — full algorithm + tools + empirical results

Verified from mlabonne's HuggingFace blog[S.ABLITERATION]:

**Algorithm** (decoder-only Llama-like architectures):

1. Run model on harmful + harmless instruction sets; collect residual stream activations at last token, all layers, three positions per block (resid_pre, resid_mid, resid_post).
2. Compute mean difference: `refusal_dir = mean(harmful_acts) - mean(harmless_acts)`. Normalise.
3. Rank candidate directions across layers; empirically test on held-out harmful prompts; pick the most effective.
4. Either:
   - **Inference-time hook**: subtract `proj(activation onto refusal_dir) * refusal_dir` at each layer/position during forward pass. Reversible.
   - **Weight orthogonalisation (permanent)**: orthogonalise W_E, attn.W_O, mlp.W_out matrices against `refusal_dir`. No inference cost.

**Empirical results** on Daredevil-8B (the studied case):
- MMLU: significant drop after raw abliteration.
- GSM8K: notable degradation.
- 1 epoch of DPO on 40k examples (`mlabonne/orpo-dpo-mix-40k`, 6× A6000 GPUs, 6h45m, lr 5e-6) recovers ~80-90% of capability.
- Refusal rate: in the case study, layer-9 candidate succeeded across all 4 test refusals.

**Verified tools**:

- **FailSpy's abliterator library** — `github.com/FailSpy/abliterator`; pre-abliterated model collection on HF.
- **Heretic** (p-e-w) — `github.com/p-e-w/heretic` — TPE-based parameter optimiser via Optuna; `heretic-llm[research]` extra adds residual-geometry plotting (PaCMAP visualisation, silhouette + cosine similarity metrics). Latest 1.2.0 (Feb 2026).
- **AutoAbliteration** — newer, simplified pipeline (recommended over manual notebook).
- **Projected Abliteration** (grimjim) — improved variant using decomposition, preserves matrix norms, better UGI Leaderboard scores.
- **Norm-Preserving Biprojected Abliteration** (grimjim) — further refinement.

**Limitations honestly flagged**:
- Performance degradation without recovery DPO.
- Architecture-specific (TransformerLens compatibility).
- "Deceptive compliance risk": model may mask refusals rather than truly remove (Heretic research raised this).
- Primarily validated on English; cross-lingual unverified.

For the Qwen3-14B-Abliterated case[S.QWEN-ABLITERATED], the practical numbers: refusals 97/100 → 19/100; KL divergence ~0.98 to original (capability mostly preserved).

[`LOOM_NSFW.md`](LOOM_NSFW.md) §2.1 references abliterated variants as the recommended path when a base model refuses too much for the user's content.

### S.7 sphiratrioth lorebook-as-active-scenario — the new pattern

Already documented in [`LOOM_MEMORY.md`](LOOM_MEMORY.md) §B3. Cited here for §S consolidation:[S.SPHIRATRIOTH]

Field schema for "active" lorebook entries (SillyTavern-specific, not in upstream NovelAI):

- **Group** (string, shared across N entries pooling probability)
- **Group Weight** (`100/N` per entry; weights sum to 100 per group)
- **Position**: `(System)` (auto-evicts from context after read)
- **Sticky**: ≥ 4 messages (persistence)
- **Trigger**: 100 (standard strength)
- **Prevent recursion**: ON

Phrasing template: `"{{char}} will instantly [ACTION]"`. Effective across Mistral / LLaMA / Qwen / Gemma model families.

Use cases per the recipe:
- Combat resolution (success / failure / critical)
- Social encounters (NPC reactions)
- Random events (weather, time-of-day, world state)
- Exploration outcomes
- Character behaviour consistency
- **Positive-bias countering for NSFW** — explicit "the action will instantly fail/miss/refuse" overrides default LLM cooperativeness

Loom Phase 4+ adopts this as a generation primitive. New mode: "Roll outcome." See [`LOOM_NSFW.md`](LOOM_NSFW.md) §2.5.

### S.8 AO3 dataset controversy — controlling precedent for Loom's fanfic feature

Verified from the disabled HuggingFace dataset page[S.AO3-DATASET]:

- ~12.6 million publicly-available works scraped (from IDs 1 to 63.2M processed).
- 164GB compressed JSONL.zst.
- Per-work fields: `id`, `title`, `text`, plus metadata (Archive Warning, Category, Characters, Fandom, Language, Rating, Relationship, Series, author, chapters, completed, published, words).
- **Status: permanently disabled.** Both the AO3 dataset and a related PaperDemon dataset removed.
- Reason: copyright + ToS dispute. AO3 is a non-profit fan-run archive with explicit creator-protection policies. Mass-scraping violates ToS; transformative-works status doesn't extend to consent for AI training.

**For Loom**: this is the controlling precedent. Loom does NOT scrape fanfic archives. Canon ingestion is user-paste only ([`LOOM_FANFIC.md`](LOOM_FANFIC.md) §3.2). Fandom templates are *schemas*, not facts.

### S.9 AO3 tagging system — Loom's adopted taxonomy

Per the AO3 Tags FAQ + Fanlore wiki[S.AO3-TAGS]:

**Folksonomy + canonical-tag wrangling**: users tag freely; volunteer wranglers normalise synonymous tags to a canonical form. Loom doesn't replicate the wrangling labour — it adopts the canonical tag *categories* as schema.

**Categories**:
- Rating: General Audiences / Teen And Up / Mature / Explicit (4 levels)
- Archive Warnings: 5 standardised warnings + "Choose Not To Use" + "No Archive Warnings Apply"
- Categories: Gen / F/F / F/M / M/M / Multi / Other (relationship-form taxonomy)
- Fandoms (canonical names per fandom)
- Characters (canonical names within fandom)
- Relationships (slash `/` for romantic/sexual; ampersand `&` for non-romantic — the convention itself is canonical)
- Additional Tags / Freeform (where tropes live: "Slow Burn", "Hurt/Comfort", etc.)

[`LOOM_FANFIC.md`](LOOM_FANFIC.md) §3.1's `FanficMetadata` schema mirrors these directly.

### S.10 Fanfic tropes — the inventory Loom ships

Cross-referenced from Fanlore canonical entries (search-summary level — fanlore.org returned 403 on direct fetch this round) + community trope lists[S.FANFIC-TROPES]:

**Top-loved tropes** (community-ranked):
1. Slow Burn
2. Hurt/Comfort
3. Enemies-to-Lovers (#20 most-loved by direct ranking)
4. Friends-to-Lovers
5. Mutual Pining
6. Fake Dating
7. Soulmates AU
8. Coffeeshop AU (#53 — surprisingly mid-tier)
9. There Was Only One Bed
10. Time Travel Fix-It
11. Royalty AU
12. Bed Sharing

[`LOOM_FANFIC.md`](LOOM_FANFIC.md) §5.2 ships ~80-120 of these as the bundled trope library.

Slow Burn convention specifics (search summary): typically 20+ chapters / often longer than typical novel; pacing/emotional escalation foregrounded over plot speed; deferred romantic/sexual resolution. Canonical structural midpoint = ~70% completion for "first kiss" beat.

### S.11 FanFabler — the fanfic-fine-tuned LLM precedent

Fetched the Towards Data Science article[S.FANFABLER]:

- **Base model**: Llama 3 8B
- **Method**: LoRA via unsloth; rank 64, alpha 64
- **Training data**: 4,000 chat interactions × 40 languages = 800 language/property pairs × 5 interactions
- **Synthetic data generation**: GPT-3.5 Turbo simulated multi-turn writing-assistant conversations
- **Wikipedia integration**: `>>>` marker for canon lookups in-context
- **Training cost**: single epoch, batch size 2, lr 2e-4, ~2h20m on NVIDIA L2 GPU
- **Dataset on HF**: `huggingface.co/datasets/robgonsalves/Multilingual-FanFic-Chat-4K`

**Lessons for Loom** (Phase 5 / Phase 7+):
- Synthetic-data-via-stronger-LLM is a viable path for niche-domain fine-tunes.
- LoRA r=64/α=64 is a working baseline (vs the more conservative 16/16).
- External knowledge integration (Wikipedia in their case; user's canon brief in Loom's) materially helps.
- Loom does NOT ship FanFabler; the few-shot pipeline ([`LOOM_NSFW.md`](LOOM_NSFW.md) §2.5 — sphiratrioth + style sheet) is the realistic v1; LoRA fine-tuning is Phase 7+ R&D when MLX/Apple-Silicon tooling matures.

### S.12 DreamGen — the unfiltered-AI-fiction-tool comparison

Verified from DreamGen's own comparison post[S.DREAMGEN]:

The 10 tools tested by DreamGen (with their NSFW/fiction posture):

1. **DreamGen** — fiction-shaped, "no rules, no restrictions."
2. **DeepFiction AI** — erotic story focus.
3. **Sudowrite** — long-form creative; ToS-bound.
4. **NovelAI** — fiction-optimized, mostly uncensored.
5. **AI Dungeon** — role-play; rating-tagged.
6. **Pirr** — mobile platform.
7. **Claude** — requires workarounds.
8. **ErosWriter** — erotica-specific desktop.
9. **RedQuill** — community remix.
10. **My Spicy Vanilla** — couples / audio.

DreamGen specs (from same source):
- **Context windows**: 5k (Starter) / 15k (Advanced) / 30k (Pro)
- **Pricing**: $6.26 – $33.81/month
- **Modes**: Story Writing + Role-Play
- **Features**: Story Bible, Story Steering, Scenario Generator
- **Posture**: "We don't filter your stories, and we don't censor your creativity"

DreamGen is the closest competitor for "explicitly unfiltered fiction tool." Loom's differentiator: local-only (no cloud retention concern), no per-token cost, no monthly subscription, no context-budget tier-gating.

### S.13 Longform plugin (Obsidian) — verified scene-as-file architecture

Fetched the plugin README[S.LONGFORM]:

- **Project identification**: any note with `longform: true` in YAML frontmatter is a Longform project.
- **Multi-scene project**: an "index file" (e.g., `My Novel/Index.md`) with `scenes:` list in frontmatter; scenes are individual .md files in the project directory.
- **Single-scene project**: project frontmatter inline in the single scene file.
- **Scene reorder**: drag UI updates the `scenes:` array; supports nesting (drag right = indent).
- **Compile**: custom workflow chain with multiple steps; community extensions available.
- **Hard guarantee**: plugin **never alters scene contents**; only the index file is rewritten.

This is exactly the format Loom adopts ([`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md) §7) — scenes are markdown files with YAML frontmatter; project metadata lives in `project.json`; round-trip safe.

### S.14 Open-source novel writers — feature comparison

Search-level summaries[S.OSS-WRITERS]:

- **Manuskript** — Snowflake-method-shaped; one-paragraph idea progressively expanded; Scrivener-like storyboard with chapter list + scene fields.
- **bibisco** — character-lore focused via prompts and questions; self-contained Java; PDF/DOCX/TXT export.
- **yWriter** — utilitarian; per-scene metadata (POV, conflict, outcome, time, location); word-count targets per scene/chapter.

Loom inherits the **per-scene metadata** schema from yWriter (already in [`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md) §2). yWriter's specifically-fictional fields (conflict, outcome) are the right primitives — Scrivener's free-form synopsis card is too unconstrained for AI generation context.

### S.15 References (Round 4 sources)

- [S.SUDOWRITE-FANDOM] Sudowrite — Fandom Helper — `https://sudowrite.com/fandom-helper`
- [S.SUDOWRITE-MODELS] aitoolsdevpro — Sudowrite Guide (model routing claim) — `https://aitoolsdevpro.com/ai-tools/sudowrite-guide/`
- [S.ERATO] Tapwave Zodiac — Erato System Prompt — `https://tapwavezodiac.github.io/novelaiUKB/Erato-System-Prompt.html`
- [S.AID-STORY-CARDS] AI Dungeon Help — Story Cards — `https://help.aidungeon.com/faq/story-cards`
- [S.AID-AUTHORS-NOTE] AI Dungeon Help — Author's Note — `https://help.aidungeon.com/faq/what-is-the-authors-note`
- [S.NAI-LOREBOOK] NovelAI Documentation — Lorebook (re-verified) — `https://docs.novelai.net/en/text/lorebook/`
- [S.NAI-AUTHORS-NOTE] Tapwave Zodiac NovelAI — Context — `https://tapwavezodiac.github.io/novelaiUKB/Context.html`
- [S.MARINARA] Marinara's Spaghetti Recipe (raw JSON) — `https://raw.githubusercontent.com/SpicyMarinara/SillyTavern-Settings/main/Marinara's%20Essentials/Preset/Marinara's%20Spaghetti%20Recipe.json`; landing — `https://spicymarinara.github.io/`
- [S.SUKINO] Sukino's SillyTavern-Settings-and-Presets — `https://huggingface.co/Sukino/SillyTavern-Settings-and-Presets`
- [S.HUIHUI] Huihui-AI HuggingFace (abliterated model collection) — `https://huggingface.co/huihui-ai`
- [S.QWEN-ABLITERATED] Qwen3-14B-Abliterated stats — `https://skywork.ai/blog/models/qwen3-14b-abliterated-free-chat-online-skywork-ai/`
- [S.ABLITERATION] mlabonne — Uncensor any LLM with abliteration — `https://huggingface.co/blog/mlabonne/abliteration`
- [S.HERETIC] p-e-w/heretic — `https://github.com/p-e-w/heretic`; PyPI `heretic-llm` 1.2.0 (Feb 2026)
- [S.SPHIRATRIOTH] sphiratrioth666 — Lorebooks_as_ACTIVE_scenario_and_character_guidance_tool — `https://huggingface.co/sphiratrioth666/Lorebooks_as_ACTIVE_scenario_and_character_guidance_tool`
- [S.SAMPLER-DEFAULTS] smcleod LLM Sampling Parameters Guide — `https://smcleod.net/2025/04/llm-sampling-parameters-guide/`
- [S.ANTISLOP] AntiSlop ICLR 2026 — `https://openreview.net/pdf/6916f45661bf884811be66da937b7467b97a9114.pdf`
- [S.AO3-DATASET] HuggingFace `nyuuzyou/archiveofourown` (DISABLED) — `https://huggingface.co/datasets/nyuuzyou/archiveofourown`
- [S.AO3-TAGS] AO3 Tags FAQ — `https://archiveofourown.org/faq/tags`; Fanlore — `https://fanlore.org/wiki/AO3_Tagging_System`
- [S.FANFIC-TROPES] Fansplaining "Five Tropes Fanfic Readers Love" — `https://www.fansplaining.com/articles/five-tropes-fanfic-readers-love-and-one-they-hate`; Fanlore Slow Burn — `https://fanlore.org/wiki/Slow_Burn_(trope)`; She's Got Plans — `https://shesgotplans.com/common-fanfiction-tropes/`
- [S.FANFABLER] Towards Data Science — FanFabler — `https://towardsdatascience.com/fanfabler-fine-tuning-llama-3-to-be-a-multilingual-fanfic-writing-assistant-dfc664ed4a72/`; dataset — `https://huggingface.co/datasets/robgonsalves/Multilingual-FanFic-Chat-4K`
- [S.DREAMGEN] DreamGen Blog — 10 Best NSFW AI Writers — `https://dreamgen.com/blog/articles/ai-story-writing-unfiltered`
- [S.LONGFORM] kevboh/longform README — `https://github.com/kevboh/longform/blob/main/README.md`
- [S.OSS-WRITERS] AlternativeTo bibisco — `https://alternativeto.net/software/bibisco/`; Linux Magazine — Open Source Novel Tools — `https://www.linux-magazine.com/Online/Features/Write-a-Novel-with-Open-Source-Tools`
- [S.MODEL-LIST] swyxio gist — April 2026 model list (referenced from Round 3 §B5) — `https://gist.github.com/swyxio/324fc884061bf20e97a2ecbe59bae34a`
- [S.INKFLUENCE] Inkfluence AI Fanfic Writer — `https://www.inkfluenceai.com/ai-fanfiction-writer`

### S.16 What's still NOT verified after Round 4

- **Sudowrite's actual wire-format prompt assembly.** Round 4 didn't try DevTools-capture (browser MCP available but the user is on the doc-writing track, not running Sudowrite in a tab). Phase 5 evaluation harness can attempt this — capture once, document, ignore future drift.
- **Reddit thread depth.** Round 4 covered AI Dungeon, Sudowrite via aggregator pages but not direct r/AIDungeon / r/sudowrite / r/Novelcrafter / r/fanfiction megathreads. Useful if a specific community-wisdom claim needs validation.
- **Fanlore canonical-trope full inventory.** Fanlore returned 403 on direct WebFetch this round; trope summary uses search-result excerpts. Phase 5.c implementation should re-fetch when bundling the trope library — direct from `fanlore.org` if accessible, or community-canonical lists otherwise.
- **Heretic abliteration latency / VRAM cost** for novice users. README mentions "no expensive post-training" but exact compute budget isn't quoted. Phase 7+ R&D direction; not blocking.
- **Whether Marinara's preset language causes refusal in some abliterated models** ("everything goes" sometimes triggers paradoxical-cooperation refusal). Empirical question; user-tunable.

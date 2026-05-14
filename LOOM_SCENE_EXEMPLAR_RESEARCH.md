# Loom — Phase 8.a §6.6 Prior-Art + Embedder Audit

> **Status: research deliverable for Phase 8.a, 2026-05-14.** Companion to [`LOOM_SCENE_EXEMPLAR.md`](LOOM_SCENE_EXEMPLAR.md). Audit covers prior-art for the unified-exemplar concept (Band A), embedder advances since StyleDistance (Band B), and documented evidence about NSFW representation in modern embedding-model training corpora (Band C, the load-bearing premise for §6.1).
>
> Quality bar: every claim is tied to a 2024–2026 source by URL or arXiv ID. Where searches surfaced no direct evidence, the audit says so explicitly rather than guessing. Sources numbered [1]–[19] in the final list.
>
> Bottom-line preview (full reasoning below): the unified-exemplar concept is **still defensible as a market gap**, but two things have shifted since the Phase 7 audit. (a) Sudowrite's "Style Examples + Scenes with bullet objectives" (2026 Story Engine 3.0 era) is now the closest commercial analog — it's *not* a unified-exemplar, but it's closer than the Phase 7 audit captured. (b) The §6.1 candidate set should be **narrowed, not widened**: StyleDistance's training data (C4) is documented as filtered with the LDNOOBW bad-word list, which deletes pages containing explicit terms — a structurally stronger NSFW-coverage problem than the Phase 8 doc anticipated. iBERT (EACL 2026, arXiv:2510.09882) is the most interesting late-breaking embedder; it should be added to the §6.1 probe.

---

## Band A — Prior-art / competitor audit

### Academic literature since the Phase 7 audit (2025-09)

- **Hatzel & Biemann, "Story Embeddings — Narrative-Focused Representations of Fictional Stories,"** EMNLP 2024 main [1]. Trains an embedder where two reformulations of the same narrative are pulled close in vector space. This is **the opposite signal** from what Loom needs for §6.1 — Loom wants chunks with similar *style/register* close, regardless of plot. Useful as a contrast, not a replacement. Published model: `uhhlt/story-emb` on HF.
- **iBERT: Interpretable Embeddings via Sense Decomposition** (Anand, Alshomary, McKeown), arXiv:2510.09882, EACL 2026 [2]. RoBERTa-encoder variant that decomposes each token into sparse non-negative mixtures over *k* sense vectors. **Reports +8 points on the STEL style benchmark over SBERT-style baselines**, and explicitly demonstrates "editing embeddings for controlled style transfer." Direct relevance to §6.1: this is a 2026 release that targets the same style-discrimination problem StyleDistance does, with interpretability bonuses (you can probe and ablate specific sense dimensions). Adding it to the §6.1 probe is cheap and the highest-information move.
- **STORYWRITER (arXiv:2506.16445)** and **"Learning to Reason for Long-Form Story Generation"** (arXiv:2503.22828) [3][4]: multi-agent long-form story generation. Neither uses a *single concrete prose exemplar* as a unified structural+stylistic source. The Phase 7 audit's claim that "no widely-cited LLM-era paper takes a single prose scene as input and extracts its beat/modality skeleton for re-realization" **still holds** as of 2026-Q1.
- **mStyleDistance** (Findings of ACL 2025) [5]: same authors, multilingual extension. Not relevant to NSFW register-matching directly but confirms the StyleDistance line is alive and being extended; suggests a v2-with-NSFW-coverage release is *possible* but not announced.
- **Survey: A Survey on LLMs for Story Generation** (Findings of EMNLP 2025) [6]. Catalogs the field through late 2025. **No category for "single prose-scene as unified exemplar" appears**, consistent with the Phase 7 gap claim.

### Commercial landscape — what's shifted since 2025-09

- **Sudowrite (2025-Q4 → 2026-Q1)** — closest commercial analog, and closer than the Phase 7 audit captured. Per the official "Story Bible" docs [7] and 2026 product writeups [8]: the **"Style Examples"** feature now ingests 2–3 prose samples and conditions all generation; the **"Scenes" subdivision of the Draft tool** lets the user define 3–7 bullet *objectives* per scene which are then drafted into prose with Story Bible context. This is structurally similar to Loom's beat-skeleton + voice-descriptor stack — but it's NOT a unified exemplar. The bullets are user-written, not LLM-extracted from a source scene. Sudowrite still does not ingest a single example scene and decompose it into "shape + voice + retrievable chunks." **Conclusion: Sudowrite has narrowed the gap; the gap is not closed.** Sudowrite's own NSFW guide [9] confirms it relies on mainstream models with content filters and **explicitly recommends users generate explicit cores elsewhere** — i.e. Sudowrite has chosen NOT to compete in the NSFW exemplar space.
- **Sudowrite changelog (sampled 2026-01-29 → 2026-05-12)** [10]: model additions (Claude Opus 4.7, 2026-04-17), Import Report (2026-04-16), Chat (2026-05-12). **Nothing matching "scene-as-exemplar," beat-extraction-from-source-scene, or unified ingest."** The closest term they use is "Story Engine 3.0" (autonomous beat generation from braindump + genre + style + characters — generative, not extractive).
- **NovelCrafter (Q4 2025 → Q1 2026)** [11][12]: May 2025 prompting overhaul (attach context to scene beats, scene-summarization word-count knob); subsequent updates focused on Codex tracking, model adapters (Gemini 3, Claude 4.5, GPT-5), exports. **"Extract from Snippets"** [13] pulls codex entries and scene cards out of existing prose — close to Loom's Pass-A in spirit, but the extracted artifact is codex entries (entities, world facts), not beat/voice/chunk sidecars. No unified-exemplar feature.
- **NovelAI** [14]: custom Module training for Sigurd/Euterpe **was discontinued** in 2024-10; not restored. New efforts in 2025 focus on image generation (Vibe Transfer, anime art). Text-side, no replacement for custom Modules has shipped. The market vacuum Phase 7 identified remains.
- **DreamGen Opus** [15]: continues to ship uncensored steerable RP/story models with `<setting>` + `<instruction>` tags. Fine-tuned models, not a Loom-style ingest tool. Orthogonal to the unified-exemplar question.

### Honest gap re-statement

The market position the Phase 7 audit identified — **"no current tool extracts a single prose scene into structural + stylistic primitives for re-realization with new content"** — survives the 2025-Q4 → 2026-Q1 audit. Sudowrite has the closest analog (Style Examples + scene bullets), but it's still *user-authored* structure, not extracted-from-prose structure. **No prior-art surfaced that would make the Phase 8 design obsolete.**

---

## Band B — Embedder advances since StyleDistance

### Update the citation

The Phase 8 doc cites `arXiv:2403.05841` for StyleDistance. That's outdated — the canonical paper is now **arXiv:2410.12757, "StyleDistance: Stronger Content-Independent Style Embeddings with Synthetic Parallel Examples,"** Patel et al., NAACL 2025 [16]. This is the same line of work but the v1-of-record changed during 2024. The Phase 8 reference list should update.

### What's new since 2024-10

- **mStyleDistance** [5] — multilingual extension, same authors, Findings of ACL 2025. Not English-NSFW-relevant.
- **iBERT, EACL 2026** [2] — see Band A. +8 points on STEL style benchmark, RoBERTa-base, sparse sense decomposition. **Should be added to the §6.1 probe.**
- **MTEB English leaderboard as of 2026-Q1** [17][18]: top open-weight is BGE-M3 (~63.0 avg); proprietary leaders are Voyage-3-large and Cohere embed-v4 (~65+). **None of these is a *style*-similarity model.** MTEB measures retrieval, classification, STS — not authorship-style discrimination. **STEL** (the style-similarity benchmark StyleDistance and iBERT both report on) is a separate track; no consolidated 2026 leaderboard surfaced in this audit beyond the individual paper reports.
- **Voyage-context-3** [19] — late 2025 release, focus on chunk-level retrieval with global doc context. Retrieval-tuned, not style-tuned. Useful potentially as a chunking-aware retriever but doesn't change the §6.1 question.

### Net effect on §6.1

The §6.1 candidate list in the design doc is: StyleDistance, mxbai-embed-large, bge-large, E5-mistral-7b, Voyage-3, Linq-Embed-Mistral. **All six are retrieval/STS-trained except StyleDistance.** That's a category mistake the spike will surface if not pre-empted: cosine in a retrieval embedder primarily reflects *topical* similarity, not style. Phase 7's Phase-5 spike already observed this (per `LOOM_RAG_SPIKE.md`). The §6.1 candidate set should be re-cast as:

1. **Style-trained:** StyleDistance, iBERT (NEW), [optionally] LISA-style funcword embedders (Loom has FuncwordZEmbedder in-tree).
2. **Topical/retrieval, as control:** one of {mxbai-embed-large, bge-large} as a "topical cosine" baseline so the spike can show *whether style cosine even matters* vs. topical cosine for the NSFW register-matching case.

Running all six retrieval embedders would be expensive and unlikely to discriminate well — they're correlated on the topical axis and none was trained for style.

---

## Band C — NSFW representation in embedding-model training corpora

This is the load-bearing §6.1 premise. The evidence is **stronger than the Phase 8 doc anticipated** in one specific direction: StyleDistance is **demonstrably trained on a corpus filtered against an explicit-word list**.

### StyleDistance — confirmed NSFW exclusion via C4 filtering

Per the arXiv HTML body [16] and HF model card: SynthSTEL (the StyleDistance training set) is constructed by sampling sentences from **C4**, then generating synthetic paraphrases via GPT-4. C4 itself [16, supporting source: Knowing Machines / Dodge et al.] applies the **"List of Dirty, Naughty, Obscene, and Otherwise Bad Words" (LDNOOBW) filter** — a 400+-word blocklist originally built by Shutterstock to sanitize autocomplete. **Any web page containing any LDNOOBW term is deleted from C4 entirely** (not the sentence — the whole page). Dodge et al. (and the Knowing Machines essay [16-supporting]) documented that this aggressively excludes content about marginalized groups *and* explicit content. Net result for §6.1: **StyleDistance has never seen explicit prose during pretraining of its source corpus or during contrastive fine-tuning**. The §6.1 hypothesis isn't just plausible — it's structurally near-certain. The spike should test it but the prior is very strong.

Additionally, **GPT-4 is the paraphrase generator** for SynthSTEL. GPT-4 has its own safety training and will not produce explicit paraphrases at scale. So even if a borderline sentence survived C4 filtering, the synthetic-paraphrase positive/negative pairs are GPT-4-mediated and inherit GPT-4's content moderation. The 40 style features [16] are syntactic/graphical/emotional/lexical — **none of them is "register: clinical/euphemistic/explicit-direct/explicit-poetic/explicit-mundane"** (the axes §6.1 wants to discriminate).

### mxbai-embed-large — no explicit filtering disclosed

Per the model card [no explicit NSFW disclosure on HF README] and the launch blog [no explicit NSFW disclosure]: Mixedbread documents that they scraped a large portion of the internet and cleaned it, avoiding MTEB-overlap. **No mention** of LDNOOBW, NSFW exclusion, content moderation filters in either the HF card or the launch blog. Trained on 700M pairs + 30M triplets via AnglE loss; teacher-distillation in the high-quality phase. **Likely contains some explicit material** by virtue of broad web scrape; but not documented and not contrastively selected for it. As a *retrieval* embedder this still leaves it embedding NSFW prose by topical content rather than register.

### bge-large-en-v1.5 — no NSFW filtering disclosed

HF model card and BAAI MTP technical materials [no explicit NSFW disclosure on standard documentation]: training data released 2023-09-15 on data.baai.ac.cn/details/BAAI-MTP. **The model card does not mention NSFW filtering**, but it also doesn't claim broad coverage. Retrieval-trained, RetroMAE pretraining + contrastive fine-tuning. Same caveat as mxbai: a retrieval embedder; topical cosine, not style cosine.

### E5-mistral-7b-instruct — no NSFW filtering disclosed; training data underspecified

Per HF README [no explicit NSFW disclosure]: "fine-tuned on a mixture of multilingual datasets" with MS-MARCO as the documented primary; the underlying *Mistral-7B-v0.1* foundation has its own undocumented training data. **No public NSFW filtering claim**, no public NSFW inclusion claim. The HF discussion thread #33 (queried in audit) confirms multiple users have asked about training data details that are not provided. Net: opaque but unlikely to be deliberately NSFW-trained. Still a retrieval embedder.

### Voyage-3 — no public training data disclosure

Per Voyage AI docs and the voyage-3-large launch blog [no public NSFW disclosure]: no published details about training data sourcing, content filtering, or NSFW handling. As a commercial API, Voyage's terms of service govern allowed *use*, not training-data composition. **Cannot be audited for NSFW representation from public sources.**

### Linq-Embed-Mistral — no NSFW filtering disclosed

Per the HF README and Linq Alpha blog [no NSFW disclosure]: built on E5-mistral-7b-instruct + Mistral-7B-v0.1; advanced "data crafting, data filtering, and negative mining" for high-quality triplets. **"Filtering" here is task-quality, not safety filtering** — but the absence of an explicit safety carve-out doesn't mean inclusion. Inherits E5-mistral-7b-instruct's opacity.

### Summary table

| Embedder | NSFW-exclusion disclosed? | Source quality | Embedding type |
|---|---|---|---|
| StyleDistance (v1 / NAACL 2025) | **Yes — confirmed structurally** (C4 LDNOOBW filter + GPT-4 paraphraser) [16] | Strong — paper + corpus docs | Style |
| iBERT (EACL 2026) | Not disclosed (likely same C4/RoBERTa pipeline) [2] | Recent paper, partial disclosure | Style |
| mxbai-embed-large | Not disclosed; broad web scrape | HF card + blog [moderate] | Retrieval |
| bge-large-en-v1.5 | Not disclosed | HF card + BAAI MTP page | Retrieval |
| E5-mistral-7b-instruct | Not disclosed | HF card opaque on training data | Retrieval |
| Voyage-3 | Not disclosed (proprietary) | Docs + launch blog | Retrieval (proprietary) |
| Linq-Embed-Mistral | Not disclosed | Inherits E5-mistral opacity | Retrieval |

**Headline:** the only embedder where NSFW exclusion is *structurally certain from public documentation* is StyleDistance itself — exactly the embedder the §6.1 hypothesis is most suspicious of. The other candidates are opaque but not deliberately filtered; broad web scrape implies *some* NSFW representation by accident. Retrieval embedders will still embed NSFW prose by topic, not register — which means they may discriminate "anatomical/clinical vs. metaphorical" by lexical co-occurrence but won't separate "explicit-direct vs. explicit-poetic" within the same lexical space.

---

## Conclusions

### Findings that contradict the proposal

1. **§6.1's candidate set is partially miscalibrated.** mxbai-embed-large, bge-large, E5-mistral-7b, Voyage-3, Linq-Embed-Mistral are all *retrieval/topical* embedders, not style embedders. Running all five against StyleDistance for NSFW *register* discrimination will likely produce ties on the cross-register axis (because all five primarily encode topic). The Phase 8 doc treats them as interchangeable style alternates; they aren't.
2. **The §6.1 hypothesis is structurally near-certain, not merely plausible.** C4's LDNOOBW filtering [16-supporting] removes whole pages containing explicit terms; GPT-4 paraphrasing inherits content-moderation. StyleDistance has never seen explicit prose during training. The §6.1 spike can be expected to *confirm* the hypothesis; the question is more "by how much" than "yes or no."
3. **The §6.6 "is there a unified-exemplar tool" search has a small revision:** Sudowrite's Style Examples + scene-bullet objectives (2026 Story Engine 3.0 era) [7][8] is closer to Loom's design than the Phase 7 audit captured. It's still not a unified exemplar (user authors structure, doesn't extract it from prose), but the diff is narrower. The Phase 7 audit's "third row of the table is the opening" claim survives, but with less margin.
4. **The Phase 8 doc cites the wrong arXiv ID for StyleDistance.** It cites `arXiv:2403.05841`; canonical is `arXiv:2410.12757` (NAACL 2025) [16]. Cosmetic but should be corrected before lock.

### Findings that support the proposal

1. **No prior-art surfaced that would obsolete the Phase 8 design.** Across academic literature (story embeddings, multi-agent story generation, structural narrative transfer) and commercial tools (Sudowrite, NovelCrafter, NovelAI, DreamGen), nothing extracts a single prose scene into structural + stylistic primitives + retrievable chunks as a unified ingest. The market gap is real.
2. **Sudowrite explicitly recommends NOT using their tool for explicit content** [9]. The competitive moat for an NSFW-capable local-LLM tool is widening, not narrowing.
3. **iBERT (EACL 2026)** [2] confirms style-embedding remains an active 2026 research area with measurable gains (+8 STEL). Loom's Phase 5 incumbent (StyleDistance) is not the final word; an upgrade path exists.
4. **No NSFW-tuned embedder has emerged** in 2025-Q4 / 2026-Q1. Anyone building NSFW-capable retrieval still has to choose between general-purpose retrieval embedders (topical bias) and style embedders (NSFW-excluded by construction). Loom isn't late.

### Recommendations

- **§6.1 spike candidate set:** narrow to **three** — StyleDistance (incumbent), **iBERT** (NEW; +8 STEL gains, freshly available, RoBERTa-base so similar runtime cost), and **one retrieval embedder as a topical baseline** (recommend mxbai-embed-large; cheapest local-friendly option, already in the Loom Python harness). Drop bge-large, E5-mistral-7b, Voyage-3, Linq-Embed-Mistral from the v1 probe — they're redundant on the topical axis and the spike's discrimination budget is small. If StyleDistance and iBERT both underperform the topical baseline on NSFW register-matching, *that's the signal* — escalate to a fine-tuned embedder track in 8.b.
- **D-decision changes motivated by audit:**
  - **D4 (embedder):** add iBERT to candidate list; cite arXiv:2410.12757 not 2403.05841; mark the *structural* NSFW-exclusion finding in C4 as a strong prior for the hypothesis.
  - **D5/D6/D7/D8** are unaffected by this audit (no prior-art surfaced that bears on per-beat-vs-per-scene retrieval, beat-aware chunking, D4-soft prompt, or UI surface).
- **Prior-art reading list before lock:** (a) **iBERT (arXiv:2510.09882)** — primary; (b) Hatzel & Biemann's Story Embeddings paper [1] — useful as a contrast point for what *not* to optimize; (c) Sudowrite Story Bible / Style Examples docs [7] — to articulate the "we extract structure from prose, they ask the user to author structure" diff cleanly for the design doc.
- **One small follow-up if time permits:** run a quick STEL-style sanity probe on the NSFW fixture set (does StyleDistance vs. iBERT vs. mxbai actually separate the five register axes §6.1 cares about?) before designing the full §6.1 probe. STEL is the right benchmark, not MTEB.

---

## Addendum — 2026-05-14 availability check (post-audit, pre-spike)

Pre-implementation toolchain verification surfaced two corrections to the audit's recommendations:

1. **iBERT is paper-only.** GitHub repo `vishalanand/iBERT` (linked from arXiv:2510.09882) explicitly states "Code and model will be released in April 2026" — the April target has slipped as of 2026-05-14; HF user profile has 0 public models. The audit's recommendation to "add iBERT to the §6.1 probe" is blocked. Even when iBERT ships, integration is non-trivial: Backpack-formulation with k=8 sparse sense vectors + three custom pooling variants — not a `SentenceTransformer(...)` drop-in.

2. **Substitute for the style-alternate slot: `AnnaWegmann/Style-Embedding`.** It is the SBERT-style baseline iBERT positions itself against on STEL — so any benchmark built around it is directly comparable when iBERT eventually ships. Sentence-transformers-compatible, drop-in, available now.

3. **LUAR (`gabrielloiseau/LUAR-MUD-sentence-transformers`) added as a predicted negative control.** Available, ungated, ST-compatible, 512-dim, 82M params. Trained on Pushshift Reddit; NSFW filtering is **not** documented (Band-C risk profile similar to mxbai/bge). The load-bearing caveat: LUAR optimizes "same author across posts" — per Wegmann et al. TACL ("Can Authorship Representation Learning Capture Stylistic Features?") and the StyleDistance paper, LUAR conflates style with author/topical signal, scoring same-register-different-author pairs as dissimilar. For §6.1's "same register, different authors → high cosine" criterion, LUAR is **expected to fail**. It enters the spike as a contrastive datapoint, not a primary candidate.

### Revised §6.1 candidate set

| Slot | Model | Type | Role | HF id |
|---|---|---|---|---|
| Incumbent | StyleDistance | Style | Hypothesis-under-test | `StyleDistance/styledistance` |
| Style alternate | Wegmann Style-Embedding | Style | Primary §6.1 candidate (canonical STEL baseline; iBERT substitute) | `AnnaWegmann/Style-Embedding` |
| Authorship alternate | LUAR-MUD (sentence-transformers wrapper) | Authorship | Predicted negative control | `gabrielloiseau/LUAR-MUD-sentence-transformers` |
| Retrieval baseline | mxbai-embed-large | Retrieval | Topical-cosine baseline | served via Ollama |

The Phase 8.a §6.1 spike runner (`Tools/SceneExemplarSpike`) iterates all four against the 20-fixture set and reports same-axis-vs-cross-axis separation scores per embedder.

---

## Sources

1. Hatzel & Biemann, "Story Embeddings — Narrative-Focused Representations of Fictional Stories," EMNLP 2024 main. https://aclanthology.org/2024.emnlp-main.339/ — Story-similarity embedder; useful as *contrast* to what Loom wants.
2. Anand, Alshomary, McKeown, "iBERT: Interpretable Embeddings via Sense Decomposition," arXiv:2510.09882, EACL 2026. https://arxiv.org/abs/2510.09882 — +8 STEL points; should be added to §6.1 probe.
3. STORYWRITER multi-agent framework, arXiv:2506.16445. https://arxiv.org/pdf/2506.16445 — multi-agent long-form gen, no single-exemplar extraction.
4. "Learning to Reason for Long-Form Story Generation," COLM 2025, arXiv:2503.22828. https://arxiv.org/pdf/2503.22828 — reasoning-augmented long-form; no exemplar extraction.
5. "mStyleDistance: Multilingual Style Embeddings," Findings of ACL 2025. https://aclanthology.org/2025.findings-acl.869/ — same authors, multilingual extension; not English-NSFW relevant.
6. "A Survey on LLMs for Story Generation," Findings of EMNLP 2025. https://aclanthology.org/2025.findings-emnlp.750.pdf — no category for single-prose-scene unified exemplar.
7. Sudowrite Story Bible documentation, retrieved 2026-05. https://docs.sudowrite.com/using-sudowrite/1ow1qkGqof9rtcyGnrWUBS/what-is-story-bible/jmWepHcQdJetNrE991fjJC — Style Examples + Scenes feature surface.
8. "Best Story Writing for Fiction in 2026," Sudowrite blog. https://sudowrite.com/blog/best-story-writing-for-fiction-in-2026/ — Story Engine 3.0 and Style Examples described.
9. "AI for Adult Writing: The Uncensored Guide to Crafting Erotica," Sudowrite blog. https://sudowrite.com/blog/ai-for-adult-writing-the-uncensored-guide-to-crafting-erotica/ — Sudowrite explicitly recommends users generate explicit cores elsewhere.
10. Sudowrite Changelog (sampled 2026-01-29 → 2026-05-12). https://feedback.sudowrite.com/changelog — no scene-as-exemplar, beat-extraction, or unified-ingest entries in the Q4 2025 → Q2 2026 window.
11. NovelCrafter Changelog. https://feedback.novelcrafter.com/changelog — Codex/model adapters/exports through 2026-03; no scene-imitation feature.
12. NovelCrafter "May 2025 Update: The New Prompting System." https://www.novelcrafter.com/blog/may-2025-new-prompting-system-update — context attachment to scene beats; user-authored structure.
13. NovelCrafter Features overview. https://www.novelcrafter.com/features — "Extract from Snippets" pulls codex entries (entities), not beat/voice skeletons.
14. NovelAI Module discontinuation notice, 2024-10. https://x.com/novelaiofficial/status/1849493848038211603 — text-side Modules discontinued; no replacement shipped 2025/2026.
15. DreamGen Opus model documentation. https://dreamgen.com/docs/models/opus/v1 — uncensored steerable RP/story models; orthogonal to ingest tooling.
16. Patel et al., "StyleDistance: Stronger Content-Independent Style Embeddings with Synthetic Parallel Examples," NAACL 2025, arXiv:2410.12757. https://arxiv.org/abs/2410.12757 + html: https://arxiv.org/html/2410.12757v1 — SynthSTEL built from C4 sentences + GPT-4 paraphrases; 40 style features enumerated; RoBERTa-base. Supporting: C4 LDNOOBW filter documented in Knowing Machines essay https://knowingmachines.org/publications/9-ways-to-see/essays/c4 and Dodge et al. https://sites.rutgers.edu/critical-ai/wp-content/uploads/sites/586/2021/09/dodge2021documentingC4.pdf
17. MTEB Leaderboard, HF Space. https://huggingface.co/spaces/mteb/leaderboard — top open-weight BGE-M3 (~63.0), proprietary Voyage-3-large / Cohere embed-v4 (~65+). Retrieval/STS only — *not* a style benchmark.
18. MTEB English Leaderboard Benchmark overview. https://www.emergentmind.com/topics/mteb-english-leaderboard — confirms task taxonomy is retrieval/STS/classification, no style track.
19. Voyage-context-3 release, late 2025. https://www.mongodb.com/company/blog/product-release-announcements/voyage-context-3-focused-chunk-level-details-global-document-context — chunk-aware retriever; retrieval-focused, not style-focused.

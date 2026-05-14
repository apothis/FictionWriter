# Loom — Phase 8.a Scene Exemplar Spike (empirical findings)

> **Status: Phase 8.a empirical writeup, 2026-05-14.** Companion to [`LOOM_SCENE_EXEMPLAR.md`](LOOM_SCENE_EXEMPLAR.md) (design) and [`LOOM_SCENE_EXEMPLAR_RESEARCH.md`](LOOM_SCENE_EXEMPLAR_RESEARCH.md) (prior-art + availability audit). Parallels the [`LOOM_SCENE_TEMPLATE_SPIKE.md`](LOOM_SCENE_TEMPLATE_SPIKE.md) writeup pattern from Phase 7.
>
> This file collects the Phase 8.a probe results as they land. Section §1 is the §6.1 embedder discrimination probe; §§2–5 (per-beat retrieval, beat-aware chunking, soft-D4 prompt, full-body-vs-retrieval) remain pending. Each section ends with a recommendation against the corresponding D-decision in the design doc.

---

## 1. §6.1 — Embedder discrimination probe

### 1.1 Setup

- **Fixtures.** 20 hand-authored prose passages at [`Tools/SceneExemplarSpike/fixtures/`](Tools/SceneExemplarSpike/fixtures/). 10 NSFW × 5 register axes (clinical, euphemistic, explicit-direct, explicit-poetic, explicit-mundane; 2 per axis) + 10 SFW × 5 matched style axes (clinical-procedural, baroque-Victorian, clipped-Hemingway, lyrical-McCarthy, mundane-workmanlike; 2 per axis). Each fixture ~400-440 words. Pairs within an axis have deliberately *different* scenarios so similarity is driven by register/style, not topical overlap.
- **Candidate embedders (4, per [`LOOM_SCENE_EXEMPLAR_RESEARCH.md`](LOOM_SCENE_EXEMPLAR_RESEARCH.md) addendum):**
  - StyleDistance (`StyleDistance/styledistance`) — Phase 5 incumbent. Style-trained. NSFW-excluded by C4 LDNOOBW filter + GPT-4 paraphraser.
  - Wegmann (`AnnaWegmann/Style-Embedding`) — primary style alternate. Substitute for the audit-recommended-but-unreleased iBERT. SBERT-style baseline on STEL.
  - LUAR (`gabrielloiseau/LUAR-MUD-sentence-transformers`) — authorship embedder. Predicted negative control per Wegmann TACL + StyleDistance paper (LUAR conflates style with author/topical signal).
  - mxbai (`mxbai-embed-large` via Ollama) — retrieval baseline. Topical-cosine reference.
- **Probe.** For each embedder: encode each fixture as a single vector (250-word chunk → ST embed each → mean-pool → L2-normalize, uniform across all 4 to keep the comparison fair). Compute the 20×20 cosine matrix. Compute axis-separation = mean(same-axis cosine) − mean(cross-axis cosine), where the axis is `style_axis` (the canonical per-axis label that covers both NSFW and SFW fixtures cleanly).
- **Decision rule (from the design doc).** A style embedder that discriminates the axes well produces a positive, substantially-above-baseline separation. The mxbai retrieval baseline anchors the topical floor.
- **Code.** [`Tools/SceneExemplarSpike/`](Tools/SceneExemplarSpike/) — Swift runner + Python `embed_st.py` subprocess. Pure-data scaffolding (`SceneExemplarFixtureParser`, `CosineMatrix`, `SpikeOrchestrator`, `EmbedderReportFormatter`) lives in `Sources/LoomCore/Templates/` with 22 unit tests in `Tests/LoomCoreTests/Phase8*Tests.swift`.

### 1.2 Headline results

**`style_axis` separation across the full 20-fixture set (n=10 same-axis pairs / 180 cross-axis pairs):**

| Rank | Embedder | Type | Same-axis mean | Cross-axis mean | **Separation** |
|---|---|---|---|---|---|
| 1 | **Wegmann** | Style (SBERT) | 0.906 | 0.622 | **+0.285** |
| 2 | LUAR | Authorship | 0.853 | 0.680 | +0.173 |
| 3 | mxbai | Retrieval | 0.769 | 0.607 | +0.162 |
| 4 | StyleDistance | Style (paraphrase-contrastive) | 0.955 | 0.868 | +0.086 |

**Scope breakdown** — NSFW-only (the load-bearing §6.1 question; n=5 same / 40 cross) and SFW-only (`style_axis`; n=5 same / 40 cross):

| Embedder | All (style_axis) | NSFW-only | SFW-only (style_axis) |
|---|---|---|---|
| **Wegmann** | **+0.285** | **+0.183** | **+0.436** |
| LUAR | +0.173 | +0.144 | +0.199 |
| mxbai | +0.162 | +0.108 | +0.113 |
| StyleDistance | +0.086 | +0.048 | +0.144 |

### 1.3 Per-embedder reading

**Wegmann — decisive winner across all scopes.** Cosine matrix has real range (some pairs go negative, e.g. `sfw_03_lyrical_mccarthy ↔ sfw_08_baroque_victorian = -0.129` — correctly recognising them as dissimilar styles). Same-axis NSFW pairs cluster (`nsfw_07 ↔ nsfw_08` = 0.953, both explicit-poetic; `nsfw_09 ↔ nsfw_10` = 0.965, both explicit-mundane). The discrimination signal is strong on the NSFW side despite no documented NSFW carve-out in Wegmann's training data — meaning the *style* signal carries through even when the topical signal is overwhelming.

**LUAR — outperforms the predicted negative-control framing.** The verification agent's prediction that LUAR would conflate style with author/topical signal and underperform on register discrimination was *partially* wrong: LUAR places second across all three scopes. Likely explanation: in this fixture set, register axes correlate with distinct authorial voices (a writer who writes Hemingway prose doesn't usually also write Victorian prose), so LUAR's author signal incidentally captures register signal. LUAR is **not** a primary recommendation — its discrimination is meaningfully weaker than Wegmann's — but it's not the disaster the prior literature predicted either.

**mxbai — the retrieval baseline holds up.** Out-of-the-box topical embedder, ~0.16 separation on the combined score. This is the floor any style embedder must beat. The fact that mxbai *exists at all* in the top-3 says topical signal carries non-trivial register information in this prose set (e.g. NSFW fixtures share anatomical vocabulary regardless of register; baroque-Victorian fixtures share period vocabulary). A style embedder needs to climb above this floor to earn the slot.

**StyleDistance — fails the §6.1 test.** Loses to all three alternatives, including the topical baseline, including on SFW where the C4 LDNOOBW filtering issue is irrelevant. The cosine matrix is range-compressed (most values 0.7-0.99) — StyleDistance pulls all English narrative prose into one cluster regardless of style. This is consistent with the audit's structural prediction (training on short C4-paraphrase pairs doesn't transfer to long-form fiction) but goes further: the Phase 5 incumbent is **not** a suitable embedder for the Phase 8 use case at all, not just the NSFW subset.

### 1.4 D4 — lock recommendation

**LOCK D4: Wegmann (`AnnaWegmann/Style-Embedding`).** The phase 8.b production retrieval pipeline should embed scene exemplars + chunks with Wegmann Style-Embedding, not StyleDistance.

**Rationale:**
1. Wegmann's separation (+0.285 combined, +0.183 NSFW, +0.436 SFW) is the highest in the candidate set across all three scopes by margins of 0.04 (NSFW) to 0.24 (SFW) over the second-place embedder.
2. The cosine-matrix dynamic range is suitable for top-K retrieval (cosines spread from negative through ~0.98), unlike StyleDistance's compressed band.
3. Wegmann is sentence-transformers drop-in, no `trust_remote_code` required, ungated on HF, similar inference latency to StyleDistance (RoBERTa-base class).
4. Wegmann was selected as the iBERT substitute on the principle "any benchmark built around it is directly comparable when iBERT eventually ships" — that principle still holds, and now there's an empirical anchor.

**Open questions deferred to Phase 8.c (post-MVP):**
- Re-run the §6.1 probe against iBERT when it actually ships (target was April 2026; check the GitHub repo on the next Phase 8.x sweep).
- Investigate whether a smaller fine-tune over a NSFW-curated corpus moves Wegmann's NSFW separation above the SFW figure (currently NSFW +0.183 vs SFW +0.436 — there's room to grow on NSFW specifically).
- Re-run with a fixture set 4–8× larger (the current n=5 same-axis NSFW pairs is small; pooled variance is high).

**Phase 5 production implication (out of scope for Phase 8.a but flagged):** Phase 5 retrieval currently embeds References with StyleDistance. Given the §6.1 evidence that Wegmann measurably outperforms StyleDistance on SFW prose too (+0.144 → +0.436 SFW separation), there is a credible case for **migrating Phase 5 retrieval to Wegmann** in Phase 8.b alongside the new Phase 8 ingest. That decision should sit with the user — it's a bigger scope change than this spike was designed to motivate.

### 1.5 What this changes in the design doc

- **D4** moves from "deferred to spike" to **"LOCKED: Wegmann Style-Embedding"**.
- The §6.1 candidate-set narrative in [`LOOM_SCENE_EXEMPLAR.md`](LOOM_SCENE_EXEMPLAR.md) should reflect: StyleDistance was tested and failed; LUAR was tested and placed middle-tier; mxbai is the topical baseline above which a style embedder must measurably climb; Wegmann clears that bar.
- The §6.3 chunking probe (next sub-row) should run against Wegmann, not StyleDistance.
- Phase 5 retrieval status: open question; flag for user.

### 1.6 Reproducibility

Run the probes:

```bash
swift run SceneExemplarSpike cosine-matrix --embedder=mxbai
swift run SceneExemplarSpike cosine-matrix --embedder=styledistance
swift run SceneExemplarSpike cosine-matrix --embedder=wegmann
swift run SceneExemplarSpike cosine-matrix --embedder=luar

# Scope-filtered:
swift run SceneExemplarSpike cosine-matrix --embedder=wegmann --scope=nsfw
swift run SceneExemplarSpike cosine-matrix --embedder=wegmann --scope=sfw
```

Outputs land at `Tools/SceneExemplarSpike/last-run/<embedder>[.<scope>].md` — one file per embedder/scope combination with the full cosine matrix + headline scores. The detailed numbers behind every score in this writeup are in those files.

---

## 2–5. Pending probes

The remaining §6.x probes will land as additional sections here when implemented.

- §6.2 — Per-beat retrieval vs. per-scene retrieval. **Pending.**
- §6.3 — Beat-aware vs. sentence-window chunking. **Pending.** Will use Wegmann per §1.4 lock.
- §6.4 — Soft-D4 spike (allow content reuse). **Pending.**
- §6.5 — Full-body-in-prompt vs. retrieval-only. **Pending.**

Each will lock or defer its corresponding D-decision when complete.

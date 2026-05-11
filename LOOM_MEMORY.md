# Loom Memory Architecture — long-form continuity at <32k context

> **Status: design lock, addendum to Phase 0 (2026-05-10).** This document is the load-bearing memory architecture for Loom. It supersedes the memory-related sections of [`LOOM_STORY_BIBLE.md`](LOOM_STORY_BIBLE.md) and [`LOOM_GENERATION_MODES.md`](LOOM_GENERATION_MODES.md) where they conflict; those docs are updated with cross-references to this one.
>
> **Provenance.** Synthesised from (a) RPClient's existing memory subsystem ([`/Volumes/SSD1/Code/RPClient/MEMORY_AUDIT.md`](../../RPClient/MEMORY_AUDIT.md) + [`MEMORY_V2_PLAN.md`](../../RPClient/MEMORY_V2_PLAN.md) + [`MEMORY_RESEARCH.md`](../../RPClient/MEMORY_RESEARCH.md), shipped 2026-05-03), (b) the broad research in [`LOOM_RESEARCH.md`](LOOM_RESEARCH.md), (c) a focused additional research pass on memory-over-very-long-stories conducted 2026-05-10 in parent context, and (d) three subagent research reports that returned successfully on the same day after the user requested permission pass-through (a fourth subagent was blocked early). Where the §A2/§A3 addendum at the end of this document materially extends or revises §1-§8, those sections are explicitly marked.

---

## 0. The problem statement

A 100,000-word novel cannot fit in any local-model context window. Even a 32k-context model holds ~24,000 words — about a quarter of a novel. The model must therefore generate scene N while *remembering* what happened in scenes 1 through N-1 with no direct access to most of that text.

"Remembering" decomposes:

- **Plot continuity** — what happened, in what order, and to whom.
- **Character continuity** — who they are, what they want, what they know.
- **Style continuity** — voice, tense, POV, prose register.
- **World continuity** — settings, items, factions, lore.
- **Thematic continuity** — running motifs, foreshadowing payoffs.

No single technique solves all five. The architecture is **layered**, with each layer authoritative for a specific category. Conflicts between layers are resolved by an explicit precedence contract.

---

## 1. RPClient's six-layer memory model — what we inherit

RPClient ships a working long-term memory subsystem for chat-shaped roleplay. The architecture has been validated empirically — including a documented regression (the 2026-05-03 "scene relocation" bug, [`MEMORY_AUDIT.md`](../../RPClient/MEMORY_AUDIT.md) §0) and the fix that landed (paths A–F). Loom inherits the architecture, adapts the specific layers to prose-shaped data, and adds two new layers (style ingestion, knowledge ledger) the chat use case didn't need.

### 1.1 The six RPClient layers

Per [`MEMORY_V2_PLAN.md`](../../RPClient/MEMORY_V2_PLAN.md) "How the layers interact":

| # | Layer | Source | Position | Authoritative for |
|---|---|---|---|---|
| 1 | **Pinned memory** | `Chat.memory: String` | Top, above cache boundary | Always-on instructions, world rules, narrator persona |
| 2 | **Scene summaries** | `Chat.sceneSummaries: [SceneSummary]` | Above cache | **Completed prior arcs only** (post 2026-05-03 fix) |
| 3 | **Rolling summary** | `Chat.summary: String + summarizedThrough: Int` | Above cache | The immediate prior period (unsummarized → summarised) |
| 4 | **Entity store** | `Chat.entities: [Entity]` with per-fact salience | **Below cache**, last user turn | Per-character/location/object timeless attributes; selective injection |
| 5 | **Vector retrieval** | `VectorStore` per chat | Below cache, last user turn | Semantic recall of older content |
| 6 | **Tail digest** | Derived from `Chat.memory` | Below cache, last user turn | Anti-drift reinforcement (Gemma first-turn fold) |

### 1.2 The precedence contract (the load-bearing fix)

[`MEMORY_AUDIT.md`](../../RPClient/MEMORY_AUDIT.md) §2 codifies the rule that resolves conflicts between layers — itself the *fix* for a real regression where vivid completed-arc prose out-weighed the recent verbatim turns. Verbatim, paraphrased for Loom:

> Pinned memory and entity store carry **timeless** facts (attributes, identities, relationships) and are always authoritative for those. **Recent verbatim turns are authoritative for current state.** The rolling summary is authoritative for the immediate prior period. Scene summaries are authoritative for **completed prior arcs only** — they must be framed as such and decoupled from "where are we now". Retrieval and tail digest are reinforcement aids, not sources of truth.

Adapted to prose-shaped Loom: replace "verbatim turns" with "active scene's prose tail" (the last N tokens directly before cursor / generation point).

### 1.3 The five empirical fixes (paths A–F)

[`MEMORY_AUDIT.md`](../../RPClient/MEMORY_AUDIT.md) §4 lists what shipped after the live failure. Each is a transferable lesson for Loom:

- **A. Typed metadata on summaries** — `[String]` → `[SceneSummary]` with `firstTurn`/`lastTurn` markers. Loom: scene summaries get scene-id + chapter-id + chronological-position metadata.
- **B. Past-tense framing in templates** — `[Scene N]` → `[Earlier in the story — completed arc N, turns X–Y]`. Loom: prior-chapter summaries get `[Earlier in the manuscript — Chapter N, ~scenes X–Y]` framing.
- **C. Current-scene anchor at prompt tail** — explicit "this is the source of truth" block telling the model the recent prose wins. Loom adopts this verbatim with prose-shaped framing.
- **D. Stale-arc compression** — scenes more than N units behind the head get their text compressed to a clause-level headline (~80 chars). **This was the load-bearing fix** — A+B+C alone weren't enough because vivid 552-char prose still out-weighed recent terse verbatim. Loom: prior-chapter summaries get aggressive compression once they're more than 1 chapter behind the active scene.
- **F. Entity dedup pass** for legacy/migrated entries. Loom: not relevant in Phase 1 (no legacy data) but the pattern (`schemaVersion` + on-decode normalisation) is inherited.
- **E (clothing only)** — render-time **transient-state-bucket supersession**: `clothing` facts get the most-recent-wins treatment automatically. Loom: extend buckets to include `location`, `mood`, `activity`, `possession`.

### 1.4 Salience ranking + selective injection

[`MEMORY_V2_PLAN.md`](../../RPClient/MEMORY_V2_PLAN.md) Step D: every `Fact` carries `addedTurn`, `lastReinforcedTurn`, `mentionCount`, `pinnedByUser`. Reinforcement bumps timestamps on entity-mention in recent prose. Eviction sorts by `(pinnedByUser desc, lastReinforcedTurn desc, mentionCount desc, addedTurn asc)` — pinned never evicts. Block is selective: only entities mentioned in the last N units of prose render at all.

Below-cache-boundary placement is critical: selective injection inherently changes per-prompt, which would invalidate the prefix cache if placed above the boundary. Cost is per-prompt prefill of the selective block (~0.3–1s on Apple Silicon for 200–600 tokens, vs. 15–60s cache miss).

### 1.5 Cache-aware prompt assembly

[`MEMORY_RESEARCH.md`](../../RPClient/MEMORY_RESEARCH.md) §9.10: the **single highest-leverage operational rule** is the cache boundary contract. The cache is valid up to the first differing token between new prompt and cached prompt. Layout for cache survival:

```
Above boundary (stable, cache-friendly):
  System prompt, Style block, Pinned memory, Rolling summary, Scene summaries,
  Stable older content
─── CACHE BOUNDARY ───
Below boundary (changes each generation, cheap to recompute):
  Vector retrieval hits, Recent verbatim, Author's note at depth N, Tail digest,
  New input
```

**Vector retrieval and selective entity injection must live below the boundary.** Putting them above breaks caching and adds 15–60s to every generation.

Loom inherits this contract verbatim. Loom's PromptBuilder (Phase 1 sub-step 1.i per [`LOOM_PHASE1_EDITOR_MVP.md`](LOOM_PHASE1_EDITOR_MVP.md)) bakes the cache boundary in from the first commit.

### 1.6 What RPClient *doesn't* solve

Two categories Loom must add:

- **Style ingestion at scale.** RPClient has a manual "Style block" (per [`MEMORY_RESEARCH.md`](../../RPClient/MEMORY_RESEARCH.md) §9.8) but no ingestion pipeline. Fiction needs the user to drop in a 200k-word reference and have its style become accessible.
- **Per-character knowledge state**. RPClient's entity store tracks facts *about* characters but not what each character *knows* at a given point. Fiction with non-linear narrative or POV shifts breaks without this.

Both are flagged as Loom's distinctive engineering. §6 below addresses them.

---

## 2. New research findings (additional pass, 2026-05-10)

Augmenting [`LOOM_RESEARCH.md`](LOOM_RESEARCH.md) with deeper memory-architecture coverage.

### 2.1 SillyTavern Vector Storage + Data Bank — summary-driven retrieval

SillyTavern's Vector Storage (chat vectorisation) is more sophisticated than the broad pass implied. Three integrated subsystems:[M1][M2]

1. **Chat vectorisation** — per-message embeddings; on each generation, last 1-2 messages embed → cosine search → relevant past messages **shuffled into context** at injection point.
2. **Data Bank (RAG)** — file-attached documents (PDF, txt, markdown) chunked + embedded; retrieved per-query.
3. **World Info vectorisation** — WI entries can be matched by semantic similarity, not just keyword.

The novel mechanic: **summary-driven retrieval indexing**.[M1]

> When a vector search matches the vector of a summarized message, the original message is retrieved from chat history and shuffled into context, while the summarized versions of the messages are retained in Vector Storage.

In other words: SillyTavern indexes **summaries** as the search keys, but returns **original prose** as retrieval results. Summaries make the index dense and cheap; original content gives the model what it needs to actually use.

**For Loom:** Phase 5 RAG-for-style should use summary-as-index, prose-as-payload. Each scene's summary embeds; matches retrieve the scene's actual prose chunks.

### 2.2 MemGPT / Letta — three-tier memory architecture

[MemGPT](https://arxiv.org/abs/2310.08560) (Packer et al. 2023) and its productisation Letta:[M3][M4]

| Tier | Analogy | Content | Mutability |
|---|---|---|---|
| **Core memory** | RAM | Always-in-context; small; essential facts/persona | Model can edit via tool calls |
| **Recall memory** | OS recent-files | Full conversation log; semantically searchable | Append-only; query-driven |
| **Archival memory** | Disk | Long-term arbitrary facts; vector-indexed | Model writes via tool calls |

The model itself decides when to page data between tiers via function calls (`core_memory_append`, `archival_memory_insert`, `archival_memory_search`).

**Tradeoff:** local 8–13B model tool-call reliability under sustained agent loops is **patchy** ([`MEMORY_RESEARCH.md`](../../RPClient/MEMORY_RESEARCH.md) §9.4). Failure modes documented: model forgets to call memory tools, infinite tool-call loops, prompt-budget bleed. RPClient explicitly **rejects** the full pattern for now; revisits at 32B+ default.

**For Loom:** the *tier mental model* is correct (timeless / recent / searchable archive); the *tool-call mechanism* is too risky for local 12-13B class. Loom uses **rule-based tiering** instead:

- Loom Core ≈ pinned memory + always-on bible
- Loom Recent ≈ active scene's prose + adjacent scenes verbatim
- Loom Archive ≈ scene summaries (recursive) + entity store + vector index

The model never invokes memory tools mid-generation. Tier movement is **automatic** based on chronological position, not model-driven.

### 2.3 RAPTOR — recursive embed-cluster-summarise tree

RAPTOR (Sarthi et al. 2024, ICLR):[M5][M6]

Algorithm:
1. Chunk the document.
2. Embed each chunk.
3. Cluster (Gaussian Mixture in soft mode); each cluster gets summarised.
4. Embed the summaries.
5. Recurse until a single root summary.

At query time, retrieval can hit any level of the tree (not just leaves) — so a query can match a high-level abstract summary OR a specific paragraph, depending on what's most relevant.

**Result:** 20% absolute accuracy improvement on QuALITY benchmark (long-document QA) when paired with GPT-4.[M5]

**For Loom:**

- The leaf level is per-scene prose chunks.
- Cluster level is per-chapter (or per-arc) summaries.
- Root level is the project synopsis.

Loom doesn't need full RAPTOR — the tree levels are *given* by the manuscript's hierarchy (scene → chapter → part → book). What Loom inherits is the **multi-level retrieval** posture: a query can match either a chapter summary OR a specific paragraph, and the assembler fetches whichever is more useful.

### 2.4 mem0 v2 — single-pass ADD-only with timestamp resolution

The mem0 paper (2024) originally specified two-LLM ADD/UPDATE/DELETE/NOOP. The 2025 architecture simplified:[M7][M8]

> Instead of two LLM passes that decided whether to ADD, UPDATE, or DELETE existing memories, Mem0's new pipeline uses a single-pass ADD-only extraction with hybrid retrieval that combines semantic, keyword, and entity signals. Timestamp-aware resolution at the application layer is the correct integration pattern for Mem0's ADD-only architecture, with treating the newest timestamped memory as the current value resolving the vast majority of apparent contradiction failures.

**Lesson:** complex contradiction-resolution LLM judges break under load and aren't worth the cost. Newest-timestamp-wins resolves "the vast majority" of apparent contradictions.

This **directly validates** RPClient's Path E (clothing-bucket supersession): newest-fact-per-bucket-wins is exactly the timestamp-resolution pattern, applied per-topic-bucket.

**For Loom:** extend RPClient's bucket pattern. Buckets:

- `clothing` (already in RPClient)
- `location` (where the character is)
- `mood` (emotional state)
- `activity` (what they're doing)
- `possession` (what they hold)
- `condition` (injuries, fatigue, hunger)
- `knowledge:fact-X` (whether they know fact X — this is the knowledge ledger §6 below)

Within each bucket, latest-scene-wins. Across buckets, all coexist.

### 2.5 GraphRAG — knowledge graph + community summaries

Microsoft GraphRAG (2024):[M9][M10]

Algorithm:
1. LLM extracts entities + relationships from source documents.
2. Community detection on the graph (Leiden algorithm); each community is a cluster of related entities.
3. LLM generates a **community summary** per cluster.
4. Query time: hits at entity, community, and document level.

**Result:** ~3× accuracy improvement on holistic narrative questions vs. baseline RAG.[M9]

**For Loom:**

- Entity graph already exists (Bible's `Character.relationships`, factions, settings).
- "Community summary" maps to **per-faction summary** or **per-relationship-cluster summary** — but the manuscript's natural communities are usually **scenes** (a small cluster of entities co-located in time and place).
- A scene summary already plays this role. **Loom doesn't need community detection** — the manuscript hierarchy gives it.

What's transferable: GraphRAG's posture that **multi-level retrieval beats flat retrieval**. Loom retrieves at scene-level, chapter-level, and project-level granularity per query. RAPTOR + GraphRAG converge on this conclusion.

### 2.6 Sudowrite Chapter Continuity — concrete numbers

Sudowrite's Chapter Continuity feature:[M11][M12]

> Sudowrite's Chapter Continuity maintains context across **up to 25 linked documents**, giving the AI access to **20,000 words** of your prior narrative each time it generates text. Write pulls in up to 20,000 words from the current document — again, starting at the end (or, the cursor position where you're using the Write feature) and working backward. This allows Write to stay grounded in the events, characters, and voice of your earlier chapters, with a **bias towards the more recent/relevant developments** when there's too much context.

**Concrete numbers:**

- Up to 25 linked chapters traversed.
- 20,000-word total prior-narrative budget per generation.
- **Bias toward more recent and more relevant content when overflowing budget** (recency-weighted truncation).
- Backward walk from cursor position.

**For Loom at 32k context:** 20,000 words ≈ 26,000 tokens. **Won't fit** at 32k context with bible + author's note + reply budget. Loom must be more aggressive than Sudowrite about *what to skip*. Two adaptations:

1. **Recent prose verbatim** budget capped at ~6,000 words (8k tokens) on a 32k-context model — see [`LOOM_GENERATION_MODES.md`](LOOM_GENERATION_MODES.md) §1.2.
2. **Older chapters** appear only as compressed summaries (the RPClient stale-arc compression pattern §1.3 D). Verbatim prose for active scene + maybe one prior; summaries beyond.

### 2.7 character.ai — the cautionary signal

User-facing reports of memory inconsistency:[M13]

> For some users, bots remember names, past conversations, and even preferences across chats, though others report no change at all — or worse, a decline in performance.

Character.ai is cloud-based and has substantial engineering resources; the quality is still inconsistent. **Signal:** users have low expectations from chat-paradigm tools and routinely escape *to* fiction-shaped tools (Sudowrite, Novelcrafter) for anything serious.

For Loom: the bar isn't "match cloud-tier consistency"; it's "do better than chat-paradigm tools at sustained continuity." That's achievable.

### 2.8 References (this section)

- [M1] SillyTavern Docs — Chat Vectorization — `https://docs.sillytavern.app/extensions/chat-vectorization/`
- [M2] SillyTavern Docs — Data Bank (RAG) — `https://docs.sillytavern.app/usage/core-concepts/data-bank/`
- [M3] Letta Docs — Memory Management — `https://docs.letta.com/advanced/memory-management/`
- [M4] Letta Blog — Agent Memory — `https://www.letta.com/blog/agent-memory`
- [M5] RAPTOR paper — `https://arxiv.org/abs/2401.18059`
- [M6] RAPTOR repo — `https://github.com/parthsarthi03/raptor`
- [M7] mem0 — Custom Update Memory Prompt — `https://docs.mem0.ai/open-source/features/custom-update-memory-prompt`
- [M8] mem0 paper (2024) — `https://arxiv.org/html/2504.19413v1`
- [M9] Microsoft Research — GraphRAG — `https://www.microsoft.com/en-us/research/blog/graphrag-unlocking-llm-discovery-on-narrative-private-data/`
- [M10] GraphRAG paper — `https://arxiv.org/html/2404.16130v1`
- [M11] Sudowrite Docs — Chapter Continuity — `https://docs.sudowrite.com/using-sudowrite/1ow1qkGqof9rtcyGnrWUBS/chapter-continuity/4KL8gFeLZQ6GSBjDWtSbV6`
- [M12] Sudowrite Blog — How to Avoid Plot Holes — `https://sudowrite.com/blog/how-to-avoid-plot-holes-sudowrites-chapter-continuity-feature-explained/`
- [M13] Convai — Long-Term Memory in AI Characters — `https://convai.com/blog/long-term-memeory`

---

## 3. Cross-cutting patterns that survive at <32k context

Distilling what consistently works across the prior art at *local-model* context budgets:

| Pattern | Source(s) | Why it survives | Loom adopts |
|---|---|---|---|
| **Cache-aware prompt assembly** (boundary contract) | RPClient §9.10 | Single highest-leverage operational rule; 10-30× TTFT savings | Yes — Phase 1 |
| **Selective injection of timeless facts** (entity store, below cache) | RPClient §9.3-D, NovelAI lorebook, SillyTavern WI | Pay-per-mention budget; off-stage entities cost zero | Yes — Phase 1 (always-include subset), Phase 2 (full bible) |
| **Hierarchical summary chain** (scene → chapter → book) | Wu 2021, RAPTOR, RPClient sceneSummaries | Compresses 100k words → 1-3k tokens of structured recall | Yes — Phase 2 (per-scene), Phase 3 (per-chapter) |
| **Past-tense framing + range markers on prior summaries** | RPClient Path B | Fixes the "completed arcs read as current state" bug | Yes — Phase 2 |
| **Stale-arc compression** | RPClient Path D | Vivid prose density beats recency without it | **Yes — load-bearing**, Phase 2 |
| **Current-scene anchor** at prompt tail | RPClient Path C | Tells model where authority lives | Yes — Phase 1 |
| **Salience ranking** (lastReinforced + mentionCount + pinned) | RPClient Step D | Eviction priority + UX surface for hot/stale | Yes — Phase 2 (mirrors Bible inspector) |
| **Transient-state buckets with newest-wins** | RPClient Path E + mem0 v2 | Resolves contradictions cheaply, no LLM judge | Yes — Phase 2; extend buckets |
| **Vector retrieval below cache, recency-excluded** | RPClient §9.1, SillyTavern Vector Storage | Cheap recall of relevant older content | Yes — Phase 5 |
| **Summary-as-index, prose-as-payload** | SillyTavern Vector Storage | Dense index, useful retrieval | Yes — Phase 5 |
| **Multi-level retrieval** (scene + chapter + project) | RAPTOR, GraphRAG | Different queries hit different abstraction levels | Yes — Phase 5 |
| **Author's Note at depth-N** | NovelAI, KoboldAI, RPClient §9.5 | Steering with strongest influence at end of prompt | Yes — Phase 1 |
| **Tail-reinforce digest** (anti-drift) | RPClient §9.6 | Cheap fix for first-turn-fold + lost-in-middle | Yes — Phase 1 (model-dependent) |
| **Manual scene-break button** (vs auto-detection) | RPClient §9.2 | High precision, no model overhead | **Auto in Loom** — scene boundaries are explicit (each scene is its own file) |
| **Tiered architecture conceptually** (core/recent/archive) | MemGPT/Letta | Mental model for what each layer is for | Yes (without tool calls) |
| **Recency-weighted truncation when overflowing** | Sudowrite Chapter Continuity | More recent content survives budget pressure | Yes — Phase 1 |

What does **not** survive at <32k:

- **20k-word verbatim recent prose** (Sudowrite). Loom caps at 6k words on 32k models, less on smaller.
- **Three-tier model-driven memory tools** (MemGPT). Tool-call reliability too patchy at 12-13B.
- **Two-LLM contradiction resolution** (mem0 v1). Replaced by timestamp-resolution.
- **Heavy infrastructure** (Qdrant, Postgres, Neo4j). Loom is single-binary, single-user.
- **Auto scene-boundary detection by classifier** (RPClient §9.2 considered). Not needed — Loom's scenes are explicit.

---

## 4. Loom's reference memory architecture

The concrete spec. Eight layers (RPClient's six, adapted to prose, plus two new for fiction).

### 4.1 The eight layers

| # | Layer | Loom implementation | Authoritative for | Cache position |
|---|---|---|---|---|
| 1 | **Project Memory** | `ProjectSettings.memory: String` | Always-on world rules, narrator persona, premise | Above boundary |
| 2 | **Style Sheet (Phase 5)** | `Bible.styleSheets[active]` | Voice, tense, POV, lexicon, prose register | Above boundary |
| 3 | **Project + Part summaries** | `Project.summary`, `Part.summary` | Highest-level narrative shape | Above boundary |
| 4 | **Chapter summaries** | `Chapter.summary`, with `summaryDirty` flag | Completed prior chapters (compressed) | Above boundary |
| 5 | **Bible — constant entries** | Always-include characters/settings + `LorebookEntry.activationMode == .constant` | Timeless attributes | Above boundary |
| 6 | **Bible — keyed entries** | Entities matching by name/alias in recent prose; lorebook `.keyed` | On-stage entity facts | **Below boundary** |
| 7 | **Knowledge ledger (Phase 4+)** | Per-POV-character `KnownFact[]` queried at chronological position | What this scene's POV character knows / doesn't know / mistakenly believes | Below boundary |
| 8 | **Recent prose** | Last N tokens before cursor; full active scene + adjacent scenes verbatim within budget | **Current state** | Below boundary |
| 9 | **Author's Note** | `ProjectSettings.authorsNote` at depth-N | Mood/style steering for next generation | Below boundary, depth-N |
| 10 | **Tail digest** (model-dependent) | Compressed reminder of highest-priority bible | Anti-drift for non-system-role models | Below boundary, last |

(The numbered layers above don't all map 1:1 to RPClient's six. Layers 1-5 are above-cache static; layers 6-10 are below-cache dynamic. Vector retrieval (Phase 5) isn't a separate layer — it produces additional content in layers 4-8 by retrieving relevant summaries / prose / style examples.)

### 4.2 The precedence contract (Loom edition)

Adapted from [`MEMORY_AUDIT.md`](../../RPClient/MEMORY_AUDIT.md) §2:

> 1. **Project Memory and Style Sheet are timeless** — always authoritative for their domains (world rules, voice).
> 2. **Bible entries are authoritative for entity attributes** — physical descriptions, relationships, goals.
> 3. **Knowledge ledger is authoritative for what each character knows.** Always queries by chronological position, never narrative position.
> 4. **Recent prose is authoritative for current state.** Where are the characters now? What just happened? The last 6,000 words win.
> 5. **Chapter summaries are authoritative for completed prior chapters.** Framed as past, never as ongoing. Compressed if more than 1-2 chapters behind.
> 6. **Project / Part summaries are authoritative for high-level narrative shape.** Premise, theme, arc.
> 7. **Vector retrieval and tail digest are reinforcement aids, not sources of truth.**

When two layers disagree about the *same fact*, the more-specific layer wins:

- Bible says Mia is 35; recent prose says she's 36 → **bible wins** (timeless attribute).
- Bible says Mia is at home; recent prose says she's at the bar → **recent prose wins** (current state — bible's "at home" was never a timeless attribute, it was a stale snapshot that should have been a transient bucket).

The **transient-state-bucket** pattern resolves this: location, mood, activity, possession, condition are *bucketed*; bucket newest-wins applies. Bible's `Setting.address` is timeless; "Mia is currently at the bar" is a bucket fact, not a bible attribute.

### 4.3 Summary-update pipeline

When a scene's prose is saved or substantially edited (>200-word change threshold per [`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md)):

1. **Mark dirty.** `Scene.summaryDirty = true`.
2. **Cascade dirty.** The chapter containing the scene gets `summaryDirty = true`; the part gets `summaryDirty = true`; the project's synopsis is *not* automatically dirtied (user can re-run on demand).
3. **Schedule regen.** Background side-call (RPClient `Summarizer` adapted) regenerates dirty summaries one level at a time, leaf-up.
4. **Token budget per level.**
   - Scene summary: ~80-150 tokens (~3-5 sentences).
   - Chapter summary: ~250-400 tokens (~10-15 sentences).
   - Part summary: ~400-800 tokens.
   - Project synopsis: user-authored; LLM can suggest from chapter summaries on demand.
5. **Compression for stale arcs.** When generating scene N, prior chapters' summaries get compressed at render time:
   - Active chapter's prior scenes: full scene summary.
   - Prior chapter (the one immediately before active): full chapter summary.
   - Earlier chapters: 1-clause headline (~80 chars), per RPClient Path D.
   - Earliest chapters (>5 back): roll up into part-level summary.

Side-call routing: the `Summarizer` runs against a small fast model (Mistral Nemo 12B class is fine; no need for the user's heavy generation model). RPClient's role-routed servers pattern (`summarizer` role) carries over.

### 4.4 Vector retrieval (Phase 5)

When Phase 5 lands:

- **Index level: per scene** (not per paragraph). Each scene's summary embeds; original prose is the payload (SillyTavern pattern[M1]).
- **Style-sheet ingestion**: reference texts (user's past novels, admired authors) chunked at scene boundaries (or paragraph if continuous prose); same index.
- **Query construction**: at generation time, embed the active scene's summary + the last 200 tokens of cursor prose + the active POV character name. Cosine search.
- **Retrieval**: top-K=5; threshold ≥ 0.55 (per RPClient §9.1 default for bge-small).
- **Recency exclusion**: scenes within 4 of active scene are excluded (already in recent-prose layer or chapter summary).
- **Injection**: results land in **layer 6 below the cache boundary** as "Relevant earlier scenes" or "Style example" (depending on whether retrieved chunk is from the project or from a reference text).
- **Storage**: per-project sqlite-vec index sidecar (`.loom/references/<id>.index`).
- **Embedding model**: `bge-small-en-v1.5` (384d, 130MB) default; nomic-embed-text-v1.5 (768d, multilingual) as alternative. Run via koboldcpp's `--embeddingsmodel` endpoint (no sidecar — RPClient §9.1 finding).

### 4.5 Knowledge ledger (Phase 4+)

Per [`LOOM_STORY_BIBLE.md`](LOOM_STORY_BIBLE.md) §3 — the one piece of memory architecture Loom invents rather than inherits.

Pipeline (already specified, recapped here for completeness):

1. **Trigger**: scene save with >200-word change.
2. **Extract**: side-call to summariser-role server; reads scene prose + bible character list; emits structured `[{character_id, fact, certainty, evidence_quote}]`.
3. **Diff + propose**: compare to existing ledger; surface new facts as Suggestions in Bible inspector.
4. **Persist**: accepted facts merge into `Character.knownFactsBySceneId`.
5. **Query at generation**: walk preceding scenes by *chronological order*; union facts; resolve buckets newest-wins; format as KNOWS / DOES NOT KNOW / MISTAKENLY BELIEVES context block.

**Falsifiable hypothesis**: per-scene knowledge-state extraction is feasible at <13B model size. Test with a small fixture corpus before committing UI in Phase 4.

**Update 2026-05-11 (post-spike, [`LOOM_LEDGER_SPIKE.md`](LOOM_LEDGER_SPIKE.md)):** Hypothesis confirmed and refined. The production extractor is `gemma4_2b` (4.6B actual params, abliterated, on Ollama) — well under the 13B threshold. Five-round empirical spike shipped:
- §8.1 GBNF / JSON-Schema constrained decoding is non-negotiable; eliminates malformed JSON, `<think>` leakage, and force-prefill workarounds as structural guarantees.
- §8.3 **`unknown` / `mistaken` are NOT extracted** — they're derived from a per-character scene-exposure graph at query time (SymbolicToM pattern). Local LLMs cannot reliably extract negative knowledge; the extractor's grammar emits `asserted` only.
- §10/§11/§12 empirical recall against the spike fixture: 0.80 aggregate, 100% on NSFW scenes; 43s/scene wall-clock against gemma4_2b. The §6.1 distinction (KNOWS / DOES NOT KNOW / MISTAKEN) survives but with the mechanism inverted: KNOWS via extraction, DOES NOT KNOW via scene-exposure set-difference, MISTAKEN via manual authoring.

### 4.6 Phase mapping

| Phase | New memory features |
|---|---|
| 1 | Project Memory, Author's Note, recent prose, current-scene anchor, History chiclets, cache boundary contract, always-include character bible, scene/chapter/part data shapes |
| 2 | Full Bible inspector; constant + keyed lorebook injection; per-scene summaries (auto-generated, dirty-flagged); transient-state buckets (location, mood, activity, possession, condition); past-tense + range-marker framing; stale-arc compression; salience ranking |
| 3 | Per-chapter summaries with hierarchical regen; Snapshots (Scrivener[J1]) before AI rewrites; History tab full functionality |
| 4 | Knowledge ledger (manual auth + auto-extract); per-scene knowledge-state context layer; consistency lints |
| 5 | Vector retrieval (chat history + reference texts); style-sheet ingestion; per-scene-type retrieval (action/dialogue/etc.); embeddings server wiring |
| 6 | Memory polish; compaction of generation-log; Compile pipeline reads summary chain |

---

## 5. Failure modes and mitigations

What we know fails, with concrete mitigations from RPClient + new findings:

| Failure mode | Cause | Mitigation | Source |
|---|---|---|---|
| Vivid prior-arc summary out-weighs recent verbatim | Density bias in models | Stale-arc compression to clause-level headline | RPClient Path D[M-RPClient] |
| "Off-stage" character contradicted by stale fact | Entity store has timeless + transient mixed | Transient-state-bucket supersession | RPClient Path E + mem0 v2[M7] |
| POV character references info they couldn't have | No knowledge tracking | Per-character knowledge ledger by chronological position | Re3 Edit[L4] (broad research) + this design §4.5 |
| Vector retrieval echoes recent verbatim | No recency exclusion | Threshold + recency-window exclusion (last K scenes) | RPClient §9.1 |
| Off-topic vector hits derail generation | Threshold too low / K too high | Threshold ≥ 0.55, K=5, threshold-tune per embedding model | RPClient §9.1 |
| Bible explosion (cast of 30; budget exhausted) | Always-include too eager | Selective injection: protagonists/antagonists always; supporting keyed-only; minor entity opt-in | RPClient §9.3-D |
| Summary drift over recursive regeneration | Each summary loses fidelity | Re-summarise from raw scenes when possible (storage cheap); promote recursive only when raw exceeds budget | RPClient §9.2 open question |
| Cache invalidation from changing entity selection above boundary | Entity block above cache boundary | **Place selective-injection layers below cache** | RPClient §9.10 — load-bearing |
| First-turn-fold drift on Gemma-style models | No system role; pinned memory buried | Tail digest reinforce in latest user-equivalent position | RPClient §9.6 |
| Lost-in-the-middle for early facts in long context | Attention attenuation in middle of long contexts | Author's Note depth-N; tail digest; selective injection of relevant-now bible | Liu et al. 2023 cited in RPClient §9.6 |
| Knowledge ledger pronoun ambiguity | Three "she"s in scene → wrong attribution | `evidence_quote` field for audit; user accept/reject in inspector | This design §4.5 |
| User refuses long compression of stale arcs | "I don't want my chapter 3 summarised away" | Stale-arc compression is *render-time only* — storage untouched; user can roll up vs full at any time | RPClient Path D |
| Generation time blows up on long projects | Extractor + summariser running every turn | Side-call cadence: extractor every 4 user-equivalent units; summary regen lazy on dirty | RPClient §9.4 cadence config |

---

## 6. Distinctive engineering — what Loom does that no prior art does

Three things Loom does that none of the prior art systems do at the local-model-fiction tier:

### 6.1 Knowledge ledger per character per scene with explicit unknowns and mistaken beliefs

Already specified in [`LOOM_STORY_BIBLE.md`](LOOM_STORY_BIBLE.md) §3. The novel piece is **explicit negative knowledge** — "Mia does NOT know that Anders is Bob's brother as of scene 7." Re3 / DOC track positive attributes; Loom tracks the negative space *as the engineering point*. Phase 4.

### 6.2 Per-scene-type retrieval for style ingestion

Generic semantic embeddings retrieve prose by *content* similarity. For style imitation, what's wanted is *type* similarity — "give me action scenes from this reference." Loom's pipeline:

1. On reference ingestion, classify each scene (or paragraph cluster) as `action` / `dialogue` / `interiority` / `description` / `mixed` / `transition`. Side-call classifier; cheap.
2. Tag chunks in the index by scene type.
3. At generation time, when the user invokes Continue/Expand on (e.g.) an action scene, retrieve preferentially from `scene_type=action` chunks.

Not in RAPTOR, not in GraphRAG, not in any tool surveyed. Phase 5; falsifiable hypothesis: scene-type classification is doable at 7-12B with >80% accuracy.

### 6.3 Generation-log as user-owned data, History chiclets as interaction UI

Per [`LOOM_DESIGN_LANGUAGE.md`](LOOM_DESIGN_LANGUAGE.md) §14.5.2 + [`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md) §6: every generation event writes a JSON log entry. The History inspector tab pages over them. Sudowrite has History chiclets[A5] showing labels of context; Loom shows the **full text** of what was sent + what came back, on every generation, owned by the user as files.

This is more transparency than any tool surveyed. It's also the substrate for several derived features (Re-roll, Insert-again, audit-the-prompt) that fall out for free.

---

## 7. Implementation notes (Phase 1 carry-overs)

What lands in Phase 1 to set the foundation correctly:

### 7.1 Cache boundary contract enforced from sub-step 1.i

[`LOOM_PHASE1_EDITOR_MVP.md`](LOOM_PHASE1_EDITOR_MVP.md) sub-step 1.i (PromptBuilder) enforces the cache layout from the first commit. Prompt assembly produces:

```
[ABOVE-CACHE]
  [SYSTEM]            # instruct-template wrap
  [PROJECT-MEMORY]    # ProjectSettings.memory
  [BIBLE-CONST]       # Always-include characters (Phase 1: protagonists)
  [PROJECT-SUMMARY]   # Phase 1: empty / user-authored only

[BELOW-CACHE]
  [BIBLE-KEYED]       # Phase 1: empty (constant only)
  [RECENT-PROSE]      # Last N tokens before cursor
  [CURRENT-SCENE-ANCHOR]  # The "recent is authoritative" reminder
  [AUTHORS-NOTE]      # depth-N
  [MODE-INSTRUCTION]
  [CURSOR/SELECTION]
```

Sub-steps later than 1.i extend the layers without disturbing the contract.

### 7.2 Diagnostic logging from day 1

`[gen]` subsystem prefix on every generation log line; `[mem]` for memory-subsystem events when they exist (Phase 2+). Per RPClient `feedback_diagnostic_logging` discipline.

Logs that must exist by Phase 1 sub-step 1.i:

- `[gen] continue: ctx=<tokens> reply=<tokens> model=<name> elapsed=<ms>`
- `[gen] cache: above=<tokens> below=<tokens> evicted=<list>` (when budget eviction fires)
- `[gen] recent-prose-window: chars=<count> tokens=<count> from-cursor=<offset>`

### 7.3 What Phase 1 *doesn't* implement

Even with the architecture spec'd, Phase 1 ships only the minimal subset needed for the demo (per [`LOOM_PHASE1_EDITOR_MVP.md`](LOOM_PHASE1_EDITOR_MVP.md) §2):

- No keyed lorebook (only constant always-include for protagonists).
- No per-scene summaries (no auto-summary chain).
- No transient buckets.
- No knowledge ledger.
- No vector retrieval.

The architecture document specifies all of them so Phase 2-5 land against a known target, not a blank canvas.

---

## 8. Open questions

Carried forward to phase-specific design:

- **Embedding-model choice**: bge-small-en-v1.5 (384d) is RPClient's default. Multilingual fiction wants nomic-embed-text-v1.5 (768d, Matryoshka). Per-project user choice. Phase 5 question.
- **Summary regeneration policy on user edits**: should every edit re-trigger the chain, or wait for the next save+pause? Phase 2 implementation question; lean toward debounce + threshold (>200 word change).
- **Per-character ledger query order**: chronological or narrative? Decided chronological (per [`LOOM_STORY_BIBLE.md`](LOOM_STORY_BIBLE.md) §11). Verify in Phase 4 against a flashback-heavy manuscript.
- **Cross-project memory** (a character that recurs across novels in a series). RPClient's §9.9 schema is a strawman. Phase 6+ question; not blocking.
- **Knowledge ledger granularity**: per-scene is the spec. Per-paragraph would be more accurate but extraction cost scales. Phase 4 empirical question.
- **Style ingestion scoping**: is style sheet per-project (one canonical voice) or per-POV-character? Phase 5 design question; lean per-project with per-character override.
- **MemGPT-lite revisit**: when 32B+ becomes Loom's default model size, single-`remember(fact)` tool may become reliable. Re-evaluate at Phase 6+.

---

## 9. References

**Internal:**
- [`LOOM_RESEARCH.md`](LOOM_RESEARCH.md) — broad prior-art (Sudowrite, Novelcrafter, NovelAI, etc.).
- [`LOOM_PLAN.md`](LOOM_PLAN.md) — phasing.
- [`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md) §3, §6 — schemas this doc references.
- [`LOOM_STORY_BIBLE.md`](LOOM_STORY_BIBLE.md) §3 — knowledge ledger.
- [`LOOM_GENERATION_MODES.md`](LOOM_GENERATION_MODES.md) §1 — prompt assembly.
- [`LOOM_PHASE1_EDITOR_MVP.md`](LOOM_PHASE1_EDITOR_MVP.md) sub-step 1.i — PromptBuilder contract.

**External (RPClient):**
- [`/Volumes/SSD1/Code/RPClient/MEMORY_AUDIT.md`](../../RPClient/MEMORY_AUDIT.md) — six-layer model + precedence contract + paths A-F empirical fixes.
- [`/Volumes/SSD1/Code/RPClient/MEMORY_V2_PLAN.md`](../../RPClient/MEMORY_V2_PLAN.md) — implementation handoff.
- [`/Volumes/SSD1/Code/RPClient/MEMORY_RESEARCH.md`](../../RPClient/MEMORY_RESEARCH.md) — §9.x research; cache-boundary §9.10.
- `Sources/RPClientCore/Memory/{Summarizer, FactExtractor, RetrievalEngine, TokenBudget, WorldInfoInjector, VectorStore, Chunker, ContextBlurber}.swift` — direct reuse / pattern reference for Loom Phase 1+.

**External (web; dated 2026-05-10):** all in §2.8 and §A4 below.

---

## A. Addendum — Round 2 research (subagent reports, 2026-05-10 PM)

After the first synthesis (§1–§9 above), three subagents returned with substantially deeper cited material than the parent-context first pass had. This addendum expands §2 (new findings), refines §4 (reference architecture), and adds §A3 (concrete prompt-skeleton recommendation) and §A4 (additional sources).

The subagents that returned: (1) Sudowrite + Novelcrafter long-form memory deep dive, (2) AI Dungeon / NovelAI / character.ai / ChatGPT+Claude Projects / OSS frameworks, (3) Academic + OSS architectures (MemGPT, RAPTOR, GraphRAG, HippoRAG, LightRAG, SCORE, Lost-in-Stories/ConStory, DOC, Re3, STORM, StoryWriter, NexusSum, LangChain/LlamaIndex chains). The fourth (SillyTavern / KoboldAI / Ooba memory plugins) was blocked on `WebFetch` before producing material.

### A1. Concrete numbers we now have

| Tool | Mechanism | Hard limits |
|---|---|---|
| Sudowrite Chapter Continuity | Manually-curated chapter graph; recency-biased truncation; **no summarisation step** | 25 docs / 20,000 words; falls back to most-recent N docs when exceeded[A1.1][A1.2] |
| Sudowrite Match My Style | Pasted prose sample analysed → style prompt; **last in prompt position** for recency bias | 2,000 words sample[A1.3] |
| Sudowrite Story Bible Saliency | Server-side opaque relevance filter; plugin authors can bypass via `{{ characters_raw }}` / `{{ worldbuilding_raw }}` | Bible content + 20k chapter readback share single prompt[A1.4] |
| Novelcrafter Codex Tracking | Per-entry mode: Always-on / Detected-on-mention / Off | Author chooses; alias-based detection[A1.5] |
| Novelcrafter prompt grammar | Functions: `codex.get(...)`, `codex.list()`, `scene()`, `chapter()`, `storySoFar()`, `storyToCome()`, `include()`, `if()`, `local()` (May 2025) | Turing-ish DSL; conditional injection[A1.6][A1.7] |
| Novelcrafter Scene Summaries | Auto-generated; user-overridable; configurable target | 80 / 120 / 300 words or custom; default 80[A1.8] |
| Novelcrafter Beat (generation unit) | ~500 words per beat; user-authored bullet drives | 6+ beats per scene typical[A1.9] |
| AI Dungeon Memory Bank | Auto-summary every 6 player actions; embed; cosine-retrieval ranked by **most-recent-action** query | ~25% of context budget when active; activates only after history overflows[A1.10] |
| AI Dungeon priority cuts | Explicit eviction order published | Story Summary cut first → AI Instructions → Plot Essentials → Author's Note last[A1.11] |
| AI Dungeon Author's Note | Bracketed `[...]` near end of prompt; exploits web-fiction prior in training | One-line UI; large coherence payoff[A1.12] |
| NovelAI Lorebook entry fields | Activation Keys (substring; `/regex/` for regex; `&` for AND); Search Range (≤10000 chars); Always On; Key-Relative Insertion (offset in newlines); Insertion Order (priority); Phrase Bias; Subcontext (per-category packing) | Multiple injection-position knobs per entry[A1.13][A1.14] |
| NovelAI Ephemeral Context | DSL: `{Delay,Duration,Insertion:Text}` for time-boxed Story Step injections | Inline scripting language[A1.15] |
| NovelAI Erato model (2024) | Llama-3-70B-base + continued pretrain on Nerdstash + finetune on NovelAI lit corpus | **8192-token context** — small[A1.16] |
| character.ai Pinned Messages | User-pinned **raw messages** (not facts) survive eviction | Hard cap: **15 messages** per chat[A1.17] |
| character.ai Chat Memories | Free-form text per (user, character) pair | 400 chars[A1.17] |
| character.ai Auto Fact Extraction (paid c.ai+) | LLM-side post-turn extraction; user-reviewable structured tabs | "Closest production analogue to Loom's planned auto-extraction"[A1.18] |
| ChatGPT Memory | Saved facts injected verbatim **into every chat**; not relevance-gated | 30+ facts documented per user; project-scoping rolled out 2025-08[A1.19] |
| Claude.ai Projects | 200K context; 20 (Plus) / 40 (Pro) knowledge files; RAG-style retrieval | Quality drops at ~65% fill; community ceiling 60–80K tokens for fiction[A1.20][A1.21] |
| ConStory benchmark errors | LLM judge over 8k–10k word outputs; 5 categories, 19 subtypes | **Errors cluster at the middle of long narratives, not the ends; factual+temporal dominate**[A1.22] |

### A2. Patterns we hadn't seen — prioritised for Loom

These came out of the subagent reports as patterns absent from §2's first-pass:

1. **AI Dungeon Memory Bank (auto-summarise → embed → retrieve by cosine to most-recent action).**[A1.10] Sudowrite/Novelcrafter/NovelAI all expect *the user* to write facts; AI Dungeon writes its own summaries every N actions and retrieves them by similarity to the most-recent action. **For Loom:** auto-summary chunks per-scene already in §4.3; this validates that mechanic. Add the embedding-retrieval lookup as part of Phase 5 vector retrieval.

2. **Author's Note as `[bracketed]` near end of prompt.**[A1.12] Distinct from system prompt; exploits a **model prior** (web fiction conventions) rather than a chat convention. **For Loom:** local models trained on web fiction will respond to bracketed authorial instructions. Phase 1 Author's Note framing should use this convention by default.

3. **character.ai Pinned Messages (raw messages, user-marked, never evicted).**[A1.17] Cheap, transparent, user-controlled; preserves voice/dialogue verbatim. **For Loom:** add `Scene.pinnedSpans: [TextRange]` schema and right-click "Pin paragraph" UX. Pinned spans bypass eviction and count against recent-prose budget. Phase 2 candidate.

4. **character.ai Auto Fact Extraction with user review.**[A1.18] The user-review-and-edit step is what makes this trustworthy. **For Loom:** mirrors the planned knowledge-ledger Suggestions pattern (Phase 4) but extended to entity attributes too. Fold into Phase 4 implementation.

5. **NovelAI Ephemeral Context — time-boxed scheduled injections.**[A1.15] DSL: `{Delay,Duration,Insertion:Text}`. **For Loom:** maps to scene-targeted injections. Phase 4+ candidate; example: "in scenes 12-15 of chapter 3, inject: 'the storm is escalating'." Schema: `LorebookEntry` gains `appliesToScenes: [UUID]` and `appliesToChapters: [UUID]` optional fields.

6. **NovelAI Subcontext — category-level packing.**[A1.13] When N entries from one category fire at once, pack them as one block (with their own internal ordering); the *block* gets placed as a unit. Avoids spreading similar info across the prompt — important under "lost in the middle" pressure. **For Loom:** when 5 character entries match at once, pack them under one `## Cast in this scene` header with internal ordering by recency-of-mention. Phase 2.

7. **AI Dungeon's explicit cut-priority list, exposed in UI.**[A1.11] Most tools don't show the eviction order. **For Loom:** when budget pressure forces eviction, the History chiclets should show what was cut and in what order. Trust-building. Phase 1 if cheap, Phase 2 floor.

8. **NovelAI Context Viewer (color-coded reveal of exact assembled prompt).**[A1.14] Beloved at NovelAI. **For Loom:** [`LOOM_DESIGN_LANGUAGE.md`](LOOM_DESIGN_LANGUAGE.md) §14.5.2 already specifies History tab with full prompt + colour-coded chiclets. **Loom's History tab is exactly this pattern.** Confirmed.

9. **StoryWriter's "compress history conditioned on what we're about to write."**[A1.23] Context selection should be **prospective**, not just chronological. **For Loom:** when generating scene N, the chapter summaries injected aren't "the most recent," they're "the most relevant to the upcoming beat" (from `Scene.conflict` / `Scene.summary` of the active scene). Phase 3+ refinement.

10. **NexusSum's Dialogue-to-Description normalisation before summarising.**[A1.24] Standardises surface form before summary chain. **For Loom:** scene summaries should describe events in narrative third-person past, not preserve dialogue verbatim. Already implied by the "factual paragraph" summary spec; make it explicit in the summary prompt.

11. **DOC's outline-metadata-as-state insight.**[A1.25] Don't try to *infer* characters and settings at draft time; populate them as structured metadata on the outline beat. Loom already has `Scene.pov`, `Scene.location`, `Scene.conflict`, `Scene.outcome` fields ([`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md) §2). **Confirmed by DOC's empirical results.**

12. **LightRAG's incremental graph updates.**[A1.26] Killer feature for an authoring tool: adding a new scene only re-extracts triples for that scene; no full reindex. **For Loom:** Phase 4+ entity-graph subsystem should be incremental from day one. Don't ever do full reindex.

13. **HippoRAG-lite (entity tags on summaries + graph-walk).**[A1.27] Loom doesn't need full Personalised PageRank; the manuscript's natural graph (Bible relationships + scene co-occurrence) is small enough that a simple "for each entity in active scene, fetch all summaries that mention this entity within 2 hops" walk suffices. Phase 5.

14. **LangChain Refine vs MapReduce summary chains.**[A1.28] Refine is serial (each chunk + running summary → new running summary); MapReduce is parallel. Refine produces tighter summaries but slower; MapReduce faster but coarser. **For Loom:** scene-summary regeneration is per-scene-isolated → MapReduce. Chapter-summary regeneration walks scenes serially → Refine. Already implied by §4.3; make it explicit.

15. **Lost-in-Stories/ConStory: errors cluster mid-novel.**[A1.22] Specific finding worth designing UX around — coherence-checking should be *more aggressive* in the middle 40-60% of a manuscript than at the start or end. Phase 4+ consistency-lint scheduling.

### A3. Refined Loom prompt skeleton at 32k local-model budget

Pulled together from multiple sources, this is the concrete recommendation:

```
[ABOVE CACHE BOUNDARY — stable, cache-friendly]
  [SYSTEM ~500 tokens]              # instruct-template wrap; voice/tense/POV anchors
  [PROJECT MEMORY ~500 tokens]      # always-on world rules, narrator persona, premise
  [STYLE GUIDE ~300-500 tokens]     # distilled from Match-My-Style; not the raw 2k-word sample
  [PROJECT/PART SUMMARY ~200-400]   # high-level shape; only when relevant to active beat
  [BIBLE constants ~500-1500]       # Subcontext-packed: Cast (always-on chars) + Story rules
  [ANCESTOR SUMMARIES ~1k-2k]       # last 5-10 scene summaries × 80-150 tokens; chapter-so-far summary; book synopsis
  [SCENE BRIEF ~100-200]            # current scene's conflict + outcome from Scene metadata (DOC pattern)

─── CACHE BOUNDARY ───

[BELOW BOUNDARY — recomputed each generation, cheap]
  [BIBLE keyed ~500-1500]           # Subcontext-packed entities matching recent prose
  [VECTOR HITS ~500-1500]           # Phase 5: relevant earlier scenes (summary-as-index, prose-as-payload)
  [KNOWLEDGE LEDGER ~300-1000]      # Phase 4: POV character's KNOWS / DOES NOT KNOW / MISTAKEN
  [PINNED SPANS ~200-800]           # Phase 2: user-pinned paragraphs
  [RECENT PROSE ~3000-6000]         # last N tokens of active scene + tail of prior scene
  [CURRENT SCENE ANCHOR ~50]        # "recent prose is authoritative"
  [AUTHORS NOTE ~200]               # bracketed [...] at depth-N from end
  [MODE INSTRUCTION ~100]
  [CURSOR/SELECTION]

Total assembled: ~9000-15000 tokens at 32k.
Reply budget: ~3000-4500 tokens.
Headroom: ~12000-16000 tokens for thinking traces or unforeseen growth.
```

Numbers are upper-bound budgets per layer; actual use is opportunistic — empty layers contribute zero. Eviction priority when assembled context exceeds budget (per AI Dungeon's published list adapted):

1. Vector retrieval hits (lowest priority — reinforcement, not source of truth)
2. Far-back ancestor summaries (more than 2 chapters behind)
3. Keyed bible entries with lowest priority + lowest mentionCount
4. Knowledge ledger entries beyond ~10 facts
5. Older recent-prose (oldest first, but always preserve last 1500 tokens)
6. Constant bible entries (only when nothing else fits — strong signal user has too many always-on entries)
7. **Never evict:** System, Project Memory, Style Guide, Scene Brief, Current Scene Anchor, Author's Note, Mode Instruction, Cursor/Selection, Pinned Spans.

The History inspector tab[`LOOM_DESIGN_LANGUAGE.md` §14.5.2] should display the eviction order and what got cut, per A2.7.

### A4. Honest unproven caveats

Direct from the academic agent's report:

1. **SCORE's headline numbers (23.6/89.7/41.8% improvements)** are from author-defined non-standard benchmarks. Architectural inspiration only.[A1.29]
2. **RAPTOR's QuALITY +20%** was reported with GPT-4. No published evidence the same gain holds for local 13B-class summarisers.[A1.30]
3. **HippoRAG +20%** is on multi-hop QA (MuSiQue, 2WikiMultiHopQA), not fiction continuation.[A1.27]
4. **GraphRAG community summaries scale poorly** under manuscript edits. LightRAG's incremental updates are the realistic version.[A1.26]
5. **MemGPT requires reliable function calling** — local 7-13B is patchy. Letta's recent migration to fine-tuned inference servers isn't trivially replicable.[A1.31]
6. **DOC's FUDGE controller is not transferable** — it was trained on a specific corpus with a specific objective. The outline-metadata insight transfers; the headline numbers do not.[A1.25]
7. **ConStory's mid-novel error cluster** finding depends on which models were tested. Worth replicating against a Loom fixture.[A1.22]
8. **Sudowrite's documented 2000-words + bible + chapter-summary prompt structure** comes from a third-party reviewer, not a vendor disclosure. Hypothesis to validate, not ground truth.[A1.32]
9. **No surveyed system has been published with results at 32k context running locally on author manuscripts.** Every paper either uses frontier APIs or QA-length inputs. Loom's architecture is *informed* by the literature, not *validated* by it.[A1.33]
10. The first concrete Loom milestone after Phase 1 should be a small evaluation harness (~20 hand-graded scene continuations) comparing {Tier A only}, {+ episodic retrieval}, {+ entity graph} on a real manuscript before committing to Phase 5 RAG.

### A5. Round 2 sources

Direct citations from the subagent reports. All accessed 2026-05-10.

**Sudowrite + Novelcrafter (Agent 1):**
- [A1.1] Sudowrite Docs — Chapter Continuity — `https://docs.sudowrite.com/using-sudowrite/1ow1qkGqof9rtcyGnrWUBS/chapter-continuity/4KL8gFeLZQ6GSBjDWtSbV6`
- [A1.2] Sudowrite Feedback — Better Narrative Consistency — `https://feedback.sudowrite.com/changelog/better-narrative-consistency-with-chapter-continuity`
- [A1.3] Sudowrite Docs — Style — `https://docs.sudowrite.com/using-sudowrite/1ow1qkGqof9rtcyGnrWUBS/style/4gqKgVVjdN6XTKo71HChqV`
- [A1.4] Sudowrite Docs — Plugins (Saliency) — `https://docs.sudowrite.com/using-sudowrite/1ow1qkGqof9rtcyGnrWUBS/how-do-i-build-plugins/a3iVxJb4UZLKfSxf8BG3mY`
- [A1.5] Novelcrafter Help — Anatomy of a Codex Entry — `https://www.novelcrafter.com/help/docs/codex/anatomy-codex-entry`
- [A1.6] Novelcrafter Docs — Prompt Functions (Custom Instruction Grammar) — `https://docs.novelcrafter.com/en/articles/8678119-prompt-functions-custom-instruction-grammar`
- [A1.7] Novelcrafter Help — Prompt functions reference — `https://www.novelcrafter.com/help/reference/prompts/prompt-functions`
- [A1.8] Novelcrafter Help — Update Scene Summaries FAQ — `https://www.novelcrafter.com/help/faq/plan/update-scene-summaries`
- [A1.9] Novelcrafter Docs — Crafting Beats — `https://docs.novelcrafter.com/en/articles/8675715-crafting-beats`
- Sudowrite user complaints — `https://feedback.sudowrite.com/p/chapter-memory-previous-chapter-summary-or-the-like`, `https://feedback.sudowrite.com/p/muse-ignores-outline-character-bible-and-logic`, `https://nerdynav.com/sudowrite-review/`, `https://ucstrategies.com/news/sudowrite-review-i-tested-the-22-month-ai-against-chatgpt-across-70000-words/`

**AI Dungeon / NovelAI / character.ai / ChatGPT+Claude (Agent 2):**
- [A1.10] AI Dungeon Help — Memory System — `https://help.aidungeon.com/faq/the-memory-system`
- [A1.11] AI Dungeon Help — What goes into the Context — `https://help.aidungeon.com/faq/what-goes-into-the-context-sent-to-the-ai`
- [A1.12] AI Dungeon Help — Author's Note — `https://help.aidungeon.com/faq/what-is-the-authors-note`
- [A1.13] NovelAI Docs — Lorebook — `https://docs.novelai.net/en/text/lorebook/`
- [A1.14] Tapwave Zodiac NovelAI Knowledgebase — Context — `https://tapwavezodiac.github.io/novelaiUKB/Context.html`
- [A1.15] Tapwave Zodiac — Lorebook (Ephemeral Context) — `https://tapwavezodiac.github.io/novelaiUKB/Lorebook.html`
- [A1.16] Anlatan/NovelAI Blog — Llama 3 Erato Release — `https://blog.novelai.net/inference-update-llama-3-erato-release-window-new-text-gen-samplers-and-goodbye-cfg-6b9e247e0a63`
- [A1.17] character.ai Help Center — Pinned Memories — `https://support.character.ai/hc/en-us/articles/24327914463003-New-Feature-Pinned-Memories`
- [A1.18] character.ai Blog — Helping Characters Remember What Matters Most — `https://blog.character.ai/helping-characters-remember-what-matters-most/`
- [A1.19] OpenAI Help — Memory FAQ — `https://help.openai.com/en/articles/8590148-memory-faq`; Simon Willison — ChatGPT memory — `https://simonwillison.net/2025/May/21/chatgpt-new-memory/`
- [A1.20] OpenAI Help — Projects — `https://help.openai.com/en/articles/10169521-using-projects-in-chatgpt`
- [A1.21] AI Q&A Hub — Claude Story Quality Degrades — `https://www.aiqnahub.com/claude-story-quality-degrades-long-conversation/`

**Academic + OSS (Agent 3):**
- [A1.22] Lost in Stories / ConStory-Bench — `https://arxiv.org/abs/2603.05890`; site `https://picrew.github.io/constory-bench.github.io/`
- [A1.23] StoryWriter — `https://arxiv.org/abs/2506.16445`
- [A1.24] NexusSum — `https://arxiv.org/abs/2505.24575`
- [A1.25] DOC — `https://aclanthology.org/2023.acl-long.190/`
- [A1.26] LightRAG — `https://arxiv.org/abs/2410.05779`; repo `https://github.com/hkuds/lightrag`
- [A1.27] HippoRAG — `https://arxiv.org/abs/2405.14831`; repo `https://github.com/osu-nlp-group/hipporag`
- [A1.28] LangChain MapReduceDocumentsChain — `https://api.python.langchain.com/en/latest/chains/langchain.chains.combine_documents.map_reduce.MapReduceDocumentsChain.html`
- [A1.29] SCORE — `https://arxiv.org/abs/2503.23512`
- [A1.30] RAPTOR — `https://arxiv.org/abs/2401.18059`
- [A1.31] Letta concepts/memgpt — `https://docs.letta.com/concepts/memgpt/`; MemGPT paper — `https://arxiv.org/abs/2310.08560`
- [A1.32] aitoolsdevpro Sudowrite Guide (third-party reverse engineering) — `https://aitoolsdevpro.com/ai-tools/sudowrite-guide/`
- [A1.33] Re3 — `https://arxiv.org/abs/2210.06774`; STORM — `https://arxiv.org/abs/2402.14207`
- DOC repo — `https://github.com/yangkevin2/doc-story-generation`
- GraphRAG site — `https://microsoft.github.io/graphrag/`; paper — `https://arxiv.org/html/2404.16130v2`
- LlamaIndex DocumentSummaryIndex — `https://www.llamaindex.ai/blog/a-new-document-summary-index-for-llm-powered-qa-systems-9a32ece2f9ec`

### A6. Methodology caveats from the subagents

The Round 2 agents flagged several issues worth carrying forward:

- All three agents had `WebFetch` blocked at one or more points; one was blocked entirely. WebSearch worked. So most citations are search-result excerpts (which themselves are extracts of source pages), not full WebFetch round-trips. Where a claim is from a single search snippet, it's marked `[1S]` in the original report and treated cautiously here.
- NovelAI's `Probability` and `Cooldown` field names couldn't be verified in current docs; they may be SillyTavern / Miku.gg features confused into the prompt.
- Reddit threads weren't deep-read in Round 2 either (same WebFetch barrier). Agent 2's character.ai user-complaint quotes come from Storychat/RoboRhythms aggregator pages, not the original threads.
- Sudowrite's exact prompt assembly (vs. the published feature descriptions) remains hypothetical — the company doesn't disclose. Agent 1 explicitly flags this.
- ConStory-Bench is recent (arXiv 2603) and not yet a community standard. Agent 3 explicitly flags this.

For Phase 1 implementation, none of these caveats block — they affect Phase 4+ design refinements and Phase 5 evaluation harness setup.

---

## B. Round 3 — verified refinements (2026-05-10 evening)

User-approved permission pass-through enabled deeper WebFetch on previously-uncertain claims. Findings here either **verify** earlier claims, **falsify** earlier flagged-uncertain ones, or surface **new patterns** the earlier rounds missed.

### B1. Falsified claims (correcting Round 1/2)

- **NovelAI Lorebook does NOT have `Probability`, `Cooldown`, or `Trigger` fields.**[B1] The Round 2 agent flagged this as uncertain; verified from the official docs. The actual entry fields are: Entry Title (org-only), Entry Text, Activation Keys (incl. `/regex/` and `&` AND-gating), Search Range (≤ 10000 chars), Key-Relative Insertion (newline offset, signed), Insertion Order (priority), Token Budget, Prefix/Suffix, Always On, Subcontext (per-category packing). **Loom should not invent these field names** — they may have been confused into Round-1 prompts from SillyTavern (where `groupWeight` exists, see B3) or Miku.gg.
- **KoboldCpp World Info does NOT have `Probability`, `Cooldown`, `Group Injection`, or `Selective Injection` mechanics.**[B2] KoboldCpp's wiki documents the simpler "key match → content inject" model. The richer mechanics belong to SillyTavern's WI implementation (which uses koboldcpp as a backend but adds its own mechanics on top). **Implication:** Loom's Phase 2 lorebook design should mirror SillyTavern's mechanics, not KoboldCpp's bare-bones version, even though the *backend* is KoboldCpp.

### B2. Verified concrete numbers

**SillyTavern Chat Vectorization defaults**[B3] (the production defaults — useful as Loom's Phase 5 starting point):

| Knob | Default | Notes |
|---|---|---|
| Chunk size | **400 characters** (not tokens) | Configurable via "Chunk size (chars)" |
| Chunk boundary | Paragraph break, line break, or word boundary | Shared with Data Bank |
| Query window | Last **2 messages** | Embed concatenation as the query |
| Relevance threshold | **25%** (0.25 cosine) | Configurable via "Score threshold" |
| Recency exclusion | Last **5 messages** | Configurable via "Retain#" |
| Top-K retrieval | **3 most relevant** | Configurable via "Insert#" |
| Insertion default | **Top of chat after Main Prompt** | Alternatives: before Main Prompt, in-chat at depth-2 |

**Loom adoption:** translate from messages to scenes. 400-char chunk size is too small for prose (paragraph average ≈ 400-800 chars); recommend **scene-summary as the indexed unit, scene prose as the payload** (per [`LOOM_MEMORY.md`](LOOM_MEMORY.md) §2.1 SillyTavern summary-driven retrieval pattern). Top-K=3, threshold 0.25-0.55 (model-dependent), recency-exclude last 4 scenes.

**Critical SillyTavern warning, verified from docs:**[B3]

> Chat Vectorization restructures the prompt prefix between the LLM calls, which can lead to frequent cache misses.

This is the empirical confirmation of the cache-boundary rule. SillyTavern itself tells users to **choose between vectorization and prompt caching**. **Loom resolves this by placing vector hits BELOW the cache boundary** — already in design ([`LOOM_MEMORY.md`](LOOM_MEMORY.md) §1.5, §4.1). Confirmed correct.

**KoboldCpp embedding endpoint, verified:**[B2]
- Flag: `--embeddingsmodel <path-to-gguf>`
- Endpoints: `/v1/embeddings` and `/api/extra/embeddings`
- `--embeddingsmaxctx` for max context
- `--embeddingsgpu` available but minimal speedup; keep on CPU
- Context Shifting on by default; `--noshift` to disable
- `--smartcache X` opt-in for KV snapshot caching

These are exactly the flags Loom's Phase 5 will need. RPClient's [`Sources/RPClientCore/Memory/RetrievalEngine.swift`](../../RPClient/Sources/RPClientCore/Memory/RetrievalEngine.swift) and [`VectorStore.swift`](../../RPClient/Sources/RPClientCore/Memory/VectorStore.swift) already wire this; direct reuse with minor adapters.

### B3. New pattern surfaced — sphiratrioth's lorebook-as-active-scenario

The single highest-value Round 3 finding. SillyTavern has a power-user idiom that converts lorebooks from a **passive lore retrieval system** into a **conditional behavior engine** — dice-roll outcomes, scenario state shifts, behavioral constraints, all driven by lorebook entry configurations.[B4]

Mechanics (verified from the Hugging Face writeup):

| Field | Setting | Purpose |
|---|---|---|
| **Group** | Same string across N entries | Entries roll from a shared probability pool |
| **Position** | `(System)` | Inserted as system message; **auto-deleted from context** after the model reads it (no permanent footprint) |
| **Depth** | 0 or 1 | 0 = elegant ordering without semantic effect on next gen |
| **Order** | 100 | Standard insertion order |
| **Trigger** | 100 | Standard trigger strength |
| **Prevent recursion** | ON | Entry doesn't activate other entries |
| **Group Weight** | `100 / N` per entry | Distributes probability equally; weights sum to 100 per group |
| **Sticky** | ≥ 4 messages | Keeps instruction active for N following messages |

**Activation modes:**

1. **Deterministic** (Weight=100): single specific trigger word always fires the entry. Used when guaranteed behavior is wanted.
2. **Probabilistic rolling** (Weight=100/N): N entries share a trigger word; one fires per match by weight. Example: a `combat` group with three entries (success / failure / critical) at weight 33.33 each — typing "attack" rolls one outcome.

**Phrasing template** (improves compliance across Mistral, LLaMA, Qwen, Gemma): `"{{char}} will instantly [ACTION]"` or `"[EVENT] will instantly [HAPPEN]"`. The "WILL INSTANTLY" framing is doing the load-bearing work.

**Use-case groups** the recipe demonstrates:

- Combat resolution (attack success/failure/critical)
- Social encounters (NPC reactions)
- Random events (weather, time-of-day, world state shifts)
- Exploration outcomes (dungeon hazards, navigation)
- Character behavior consistency (mood, personality enforcement)
- **Positive-bias countering** for NSFW: explicit "the sword swing will instantly miss" overrides default LLM cooperativeness

**For Loom — three implications:**

1. **The lorebook entry schema in [`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md) §3.6 should be extended** with `group: String?`, `groupWeight: Double?`, `stickyMessages: Int?`, and a `position == .system` mode that auto-evicts. This is not Phase 1 — Phase 4+ when generation modes expand.

2. **A new generation mode emerges from this — "Roll outcome."** When the user is at a decision point ("Mia raises the gun"), Loom can offer a pre-configured outcome group (success / partial / failure / critical) with weights the user sets. Side-call rolls; chosen entry's text becomes the constraint passed to the main generation. Genuinely novel for fiction tools — Plottr has plot beats; Sudowrite has Brainstorm; nobody has dice-roll-shaped outcome generation.

3. **Dynamic scenario state belongs in the lorebook layer, not the bible.** Weather, time-of-day, in-progress events ("the storm is escalating") are *not* timeless attributes (which is what bible Settings hold). They're transient state that should expire. NovelAI's Ephemeral Context (§A2.5) and sphiratrioth's group-weighted entries are two implementations of the same underlying concept. **Loom should support both authoring affordances:** scheduled injections (Ephemeral) and dice-rolled outcomes (groups). Phase 4+.

### B4. r/LocalLLaMA April 2026 model consensus

Verified consolidated list from the swyxio gist, dated April 2026 (last updated 2026-05-04):[B5]

| Tier | Model | Best for |
|---|---|---|
| Tiny (~2B active) | **Huihui Gemma 4 E2B Abliterated v2** | MoE; punches above weight class |
| 7B | **SultrySilicon V2** | Creative writing, roleplay |
| 9B | **Gemma-2-Ataraxy-9B** | Creative writing; strong EQ-Bench |
| 9B | **Huihui-GLM-4.6V-Flash** | Vision + bilingual |
| 13B | **MythoMax-L2-13B** | Roleplay; the OG, ~59k GGUF downloads |
| 24B | **Dan's PersonalityEngine V1.3.0** | Generalist roleplay + reasoning |
| 27B | **Gemma 3 27B Abliterated** | Instruction-following, multimodal |
| 31B | **Huihui Gemma 4 31B Abliterated** | Strongest dense Gemma 4 |
| 70B | **Midnight Rose 70B v2.0.3** | High EQ-Bench at low quants |
| 70B | **Midnight Miqu 70B v1.5** | Still community-favorite for prose |
| 671B (MoE 37B active) | DeepSeek V3 | Recommend hosted; not local |

**Notable shifts from earlier research [`LOOM_RESEARCH.md`](LOOM_RESEARCH.md) §I.1:**

- **Magnum / Lumimaid / Cydonia / EVA / Stheno** (the 2024-era Mistral Nemo finetunes I'd cited) are **not on the April 2026 list** as primary recommendations. Community has rotated toward Huihui Gemma 4 abliterations and Dan's PersonalityEngine.
- **Midnight Miqu 70B v1.5** is *still* on the list — sustained 2-year community favorite.
- **MythoMax-L2-13B** is *still* on the list — the OG at 13B.
- **Gemma 4 abliteration family** is the dominant new entrant.

**For Loom:** the design docs' "Mistral Nemo 12B" reference as the laptop sweet spot needs an asterisk — by 2026, Gemma 4 9B-31B abliteration variants are the more common community choice. The architecture is unchanged; the *recommended-defaults* hint in Settings should mention Gemma 4 abliteration (e.g., "Huihui Gemma 4 31B Abliterated for prose; Dan's PersonalityEngine 24B for roleplay-heavy scenes"). Phase 1 ships the architecture; Phase 6 polish ships the recommendations table.

### B5. Style transfer 2025-26 academic — honest state of the art

Verified from arXiv abstracts (search-result excerpts; not full paper reads):[B6][B7][B8]

- **GPT-4o captures surface-level style but not stylometric depth.**[B6] In-context learning improves alignment but doesn't reach signature-level imitation.
- **Few-shot still struggles with implicit writing styles of everyday authors.**[B7] Even with exemplar-based prompting, current LLMs underperform especially for informal / stylistically diverse domains.
- **TAIL** (Task-specific Adapters for Imitation Learning) — uses LoRA + Bottleneck Adapters for parameter-efficient fine-tuning; learns from limited demonstrations.[B8]
- **StyleTunedLM** — LoRA finetuning is **more effective** than prompt engineering or few-shot for capturing training-data style.[B8]
- **Hierarchical zero-shot frameworks** for long-text style transfer combine sentence-level adaptation; results are framework-specific, not yet community-consensus.

**Implication for Loom — honest framing:**

LoRA fine-tuning is the academically-validated path to serious style imitation but is **out of scope for a single-user macOS app at the local-model tier**. Local LoRA training requires:
- Training infrastructure (PyTorch + transformers); not in the koboldcpp single-binary world.
- Significant compute (hours-to-days of GPU time per LoRA).
- Per-LoRA size on disk (10s-100s MB) and per-LoRA model loading.

**Loom's Phase 5 plan stays at the few-shot frontier**, with explicit acknowledgment in the docs that few-shot is the lower bar:

- Distilled style descriptor (~300 tokens; tone descriptors, sentence-length profile, lexicon) — always-on.
- Few-shot retrieval of style-matched scenes from reference texts (RAG-for-style; SillyTavern Vector Storage pattern).
- Per-scene-type retrieval (action / dialogue / etc.) — Loom's distinctive engineering.

**A "Style fine-tuning workflow" mode is a Phase 7+ R&D direction, not a commitment.** When/if local LoRA training tooling becomes turn-key (e.g., Apple's MLX-based finetuning matures), revisit. Until then, document the gap honestly: "Loom does few-shot style imitation; the academic state of the art for full style imitation is LoRA, which Loom does not ship."

### B6. Verified deprecations — what NOT to inherit

- **Ooba's superbooga and `long_term_memory` extensions are no longer in active development.**[B9] Both date from 2023; superseded by direct embedding-API integration in newer tools (SillyTavern Vector Storage, KoboldCpp's native embeddings endpoint). Loom **does not** mimic these extensions; it goes direct to KoboldCpp's `/v1/embeddings` per [`LOOM_RESEARCH.md`](LOOM_RESEARCH.md) §M.4 and B2 above.
- **NovelAI AI Modules (style-tuning via prompt-tuning vectors)** — discontinued late 2024 (per Round 1 [`LOOM_RESEARCH.md`](LOOM_RESEARCH.md) §C.3). NovelAI now positions Lorebook + Memory as effective substitutes. Loom doesn't ship a moduling pipeline; few-shot + style descriptor is the path.

### B7. Round 3 sources

- [B1] NovelAI Documentation — Lorebook — `https://docs.novelai.net/en/text/lorebook/` (verified field list)
- [B2] KoboldCpp Wiki — FAQ and Knowledgebase — `https://github.com/LostRuins/koboldcpp/wiki/The-KoboldCpp-FAQ-and-Knowledgebase`
- [B3] SillyTavern Docs — Chat Vectorization — `https://docs.sillytavern.app/extensions/chat-vectorization/` (concrete defaults verified)
- [B4] sphiratrioth666 — Lorebooks as ACTIVE scenario and character guidance tool — `https://huggingface.co/sphiratrioth666/Lorebooks_as_ACTIVE_scenario_and_character_guidance_tool`
- [B5] swyxio gist — r/localLlama + r/localLLM + r/sillytavernAI preferred models list (April 2026) — `https://gist.github.com/swyxio/324fc884061bf20e97a2ecbe59bae34a`
- [B6] Beyond the surface: stylometric analysis of GPT-4o (Oxford DSH) — `https://academic.oup.com/dsh/article/40/2/587/8118784`
- [B7] LLMs Still Struggle to Imitate the Implicit Writing Styles of Everyday Authors (EMNLP Findings 2025) — `https://aclanthology.org/2025.findings-emnlp.532.pdf`
- [B8] StyleTunedLM — `https://arxiv.org/html/2509.14543v1`; TAIL — `https://arxiv.org/html/2409.04574v1`
- [B9] oobabooga/text-generation-webui-extensions; wawawario2 long_term_memory archive — `https://github.com/wawawario2/long_term_memory`

### B8. What's NOT yet verified (carry forward)

- **Sudowrite's actual prompt assembly.** Round 1 + 2 cited Sudowrite docs and reviews; Round 3 didn't try to reverse-engineer the wire format. Phase 5 evaluation harness can attempt this if a hypothesis-test is needed.
- **GraphRAG / RAPTOR / LightRAG production usage at <13B.** All papers were validated with frontier models. The empirical question for Loom is whether per-scene summary clustering is reliable at 12-13B local model. Phase 5 eval harness territory.
- **Reddit megathread quotes.** Round 3 didn't deep-read individual r/SillyTavernAI / r/LocalLLaMA threads beyond the swyxio aggregation gist. The community recipes (Marinara's LLM Hub, Sukino settings, Virt-io presets) are referenced by the search results but not deeply read. Worth a Phase 5 follow-up if a specific recipe needs validation.
- **sqlite-vec performance at fiction scale.** RPClient research §9.10 says "<50k vectors at 384-768d is sub-50ms on Apple Silicon." Verified by anecdote from the sqlite-vec maintainer; not by Loom's own benchmark. Phase 5 should benchmark.


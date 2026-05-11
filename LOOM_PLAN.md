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
| L4 | Generation-mode expansion (Rewrite sub-modes, Show-don't-tell, Brainstorm, Critique, Bridge, Roll-Outcome); per-mode prompt templates; knowledge-state-per-character extraction; NSFW polish (Continue-from-refusal, Sphiratrioth pack) | 🚧 in flight — see [`HANDOFF.md`](HANDOFF.md) §15. Landed: rewriteVoice prompt layer, Continue-from-refusal, Sphiratrioth pack | 4 | [`LOOM_GENERATION_MODES.md`](LOOM_GENERATION_MODES.md), [`LOOM_STORY_BIBLE.md`](LOOM_STORY_BIBLE.md), [`LOOM_NSFW.md`](LOOM_NSFW.md) |
| L5 | Style ingestion (RAG-for-style; chunk reference texts; embed via RPClient embeddings server; per-scene-type retrieval) | pending | 5 | TBD; cross-references [`LOOM_RESEARCH.md`](LOOM_RESEARCH.md) §O.4 |
| L5b | Canon-brief storage on Bible entities; user-paste fandom canon ingestion (re-uses L5 pipeline) | pending | 5.b | [`LOOM_FANFIC.md`](LOOM_FANFIC.md) §3.2 |
| L5c | Fanfic Mode — Project kind, ATTG header, Ship/AU/Trope schemas, bundled trope library, fandom templates, fanfic-specific generation modes | pending | 5.c | [`LOOM_FANFIC.md`](LOOM_FANFIC.md) §9 |
| L6 | Polish + export (Markdown / RTF / .docx / ePub; search; autosave + version history; AO3-conformant frontmatter export) | pending | 6 | TBD |

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

### Phase 5 — Style ingestion (RAG-for-style)
Chunk reference texts, embed via RPClient embeddings server (the existing per-role server architecture covers this), retrieve relevant style exemplars per generation. **Per-scene-type retrieval** (action / dialogue / interiority / description) is the differentiator vs SillyTavern's generic vectorised lorebook.

This is Loom's largest single phase. R&D risk is real (research §O.4: no widely-adopted stylistic embedding model exists). Plan for an empirical pass first; production after.

### Phase 6 — Polish + export
Markdown / RTF / .docx / ePub via Compile-style pipeline[J1]. Search across project. Find/replace. Autosave + version history.

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

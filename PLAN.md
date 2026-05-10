# Loom — plan for the plan

> **Status:** scaffolding only. This document is the meta-plan: what gets researched, what design docs exist, and what order things ship. The substantive plan documents (research synthesis, design language, data model, etc.) are produced in the next working session and should replace / extend the placeholders here.

## 0. What Loom is

A local-LLM-powered fiction-writing app for macOS, built on the same kobold-backed model setup as RPClient. Targets long-form work — essays, short stories, novellas, novels — with persistent characters, settings, events, and timeline; can ingest very-long reference texts (>>model context) and reuse their style. Heavily NSFW-friendly; the user's local uncensored model is responsible for content, the app is the tool.

**Metaphor:** Scrivener with AI grafted in. A long-form document editor as the primary surface, with an AI-assist sidebar / inline generation rather than a chat transcript.

**Single-user, no collab/cloud sync.** Voice (TTS) is deferred indefinitely.

## 1. Reference points

- **RPClient** lives at `/Volumes/SSD1/Code/RPClient` and is the gold-standard reference for: kobold client wiring, ServerProbe, KoboldClientRegistry, embeddings server use, the Settings UX shape, TestKit harness, DebugLog convention, build.sh / run.sh scripts, ad-hoc signing posture, V2_DESIGN_LANGUAGE.md.
- **V2_DESIGN_LANGUAGE.md** in RPClient — adopted whole as Loom's visual/UX foundation. May get its own copy with Loom-specific surfaces appended.
- **Sudowrite** (industry-leading AI fiction tool; "Story Bible" is the gold standard for the consistency engine), **Novelcrafter** (codex/world-bible focus), **NovelAI** (lorebook + memory; closest to local-model setup), **Scrivener** (no AI, but the standard for long-form structure UI), **KoboldAI Lite story mode**, **Backyard.ai**, **Risu**, **SillyTavern story mode** — research targets.

## 2. What's different from RPClient

| Axis | RPClient | Loom |
|---|---|---|
| Primary surface | Chat transcript (turns) | Long-form document editor |
| Data shape | Chat → Turn (linear, branching) | Project → Part → Chapter → Scene → Beat (hierarchical) |
| Generation paradigm | Reply to user message | Insert / expand / rewrite at cursor; multiple modes |
| Memory | Rolling summary + entities | Story bible (entity sheets, timeline, knowledge state per character) |
| Reference text | Character cards (~5KB) | Full reference works (200k+ words) chunked + retrieved |
| Multi-character | Cast + speaker selection (turn-by-turn) | POV character per scene (document-level) |
| Audio | TTS pipeline | Deferred indefinitely |
| Branching | Per-turn variant tree | Per-scene drafts (similar pattern, different unit) |

## 3. Tooling carry-over (from RPClient)

Same Swift Package layout, same Swift+AppKit posture, same:
- TestKit framework (homegrown, see [feedback_test_framework](RPClient: memory))
- `swift run LoomCoreTests` test runner
- `build.sh` (ad-hoc signed, generates `Loom.app`)
- `run.sh` (bypasses Local Network privacy re-prompts during dev)
- `DebugLog.shared.write(...)` with subsystem prefixes (e.g. `[editor]`, `[bible]`, `[rag]`)
- KoboldClient + ServerProbe + Settings shape
- Storage layer pattern (per-entity JSON in `~/Library/Application Support/Loom/`)
- TDD workflow: pure-data helpers get tests-first; UI/glue gets honest smoke tests

## 4. Plan documents (to produce in the next context)

In order of dependency. Each is its own .md in this repo root unless noted.

| # | Doc | Contains | Phase |
|---|---|---|---|
| 1 | `LOOM_RESEARCH.md` | Synthesised output of 3 parallel research agents (tools survey, engineering, NSFW-friendly local-model UIs). Source of truth for "what others do, what works, what doesn't." | Pre-design |
| 2 | `LOOM_PLAN.md` | Master plan, mirrors V2_PLAN.md shape. Phase list, scope, deferred items, references. Replaces this file as the long-lived plan. | Design |
| 3 | `LOOM_DESIGN_LANGUAGE.md` | Visual + interaction language, adapted from V2_DESIGN_LANGUAGE.md. Editor surface specifics added (cursor affordances, AI insertion grammar, sidebar pattern). | Design |
| 4 | `LOOM_DATA_MODEL.md` | Project / Part / Chapter / Scene / Beat shapes. Entity sheet shape (incl. knowledge-state-per-scene). Timeline event shape. Style sheet (extracted from reference texts). Codable + on-disk layout. | Design |
| 5 | `LOOM_GENERATION_MODES.md` | The prompt templates: Continue, Expand, Rewrite (voice/tense/POV/length), Show-don't-tell, Brainstorm, Critique, Bridge. Per-mode context-assembly strategy. | Design |
| 6 | `LOOM_STORY_BIBLE.md` | The consistency engine: how entities are stamped, how facts get pinned, how knowledge state evolves per scene, how it injects into prompts. Inherits RPClient's entity/memory ideas; extends to fiction. | Design |
| 7 | `LOOM_PHASE1_EDITOR_MVP.md` | First-shippable slice. Sub-step contracts. | Implementation kick-off |

## 5. Phasing (provisional — refined in `LOOM_PLAN.md`)

- **Phase 0** — Research + design docs (this folder fills with the .md files above). No code. End-state: all design questions answered well enough to start coding without churn.
- **Phase 1** — Editor MVP. Single-window app, NSTextView-based scene editor, kobold client wired, two generation modes (Continue / Expand), bare-bones project/scene model, save as Markdown. Goal: typing a scene sketch and getting prose back.
- **Phase 2** — Story bible v1. Character sheets, settings, basic timeline. Bible content gets injected into generation context.
- **Phase 3** — Hierarchical structure + navigation. Project tree (Chapters → Scenes), word counts, target lengths.
- **Phase 4** — Generation mode expansion. Rewrite, Show-don't-tell, Brainstorm, Critique, Bridge. Per-mode prompt templates.
- **Phase 5** — Style ingestion (RAG-for-style). Chunk reference texts, embed (reuse RPClient's embeddings server), retrieve relevant style exemplars per generation. Likely the largest single phase.
- **Phase 6** — Polish + export. Markdown / RTF / .docx / ePub. Search. Find/replace. Autosave + version history.

**Deferred indefinitely:** voice/TTS, multi-user collab, cloud sync, mobile companion.

## 6. The MVP definition (Phase 1 specifically)

User can:
1. Create a new project.
2. Add 1–3 character cards (name + a paragraph description). Hand-paste OK; full editor lands in Phase 2.
3. Type a scene sketch (a few hundred words) into the main editor.
4. Highlight the sketch, click **Expand** → AI generates 1500–2500 words of prose, replaces the selection.
5. Position cursor at end, click **Continue** → AI continues writing from there.
6. Edit freely (NSTextView gives undo/redo, find, etc. for free).
7. Save as a `.md` file with frontmatter for the project metadata.

That's it. Everything else is Phase 2+.

## 7. Open questions for the next context to settle

- Project on-disk format. Likely a directory: `MyNovel.loom/` containing `project.json` + `scenes/<id>.md` + `bible/<id>.json` + `references/<id>.md`. Single-file Markdown export at any time.
- Do scenes live as actual files (round-trippable) or only in `project.json`? Round-trippable is more useful but more complex.
- Generation context budget — how much of the bible / how many adjacent scenes / how much extracted style get into each prompt at a 16k-context model?
- Where does the AI insert vs append? Cursor-aware vs end-of-document vs replace-selection — the modes overlap; design needs to be explicit.
- Variant drafts at the scene level: how does the user navigate between alternative versions of the same scene without losing the "main" thread?

## 8. Tooling bootstrap (deferred until Phase 1)

Once research + design docs are done and Phase 1 starts:
1. Copy `Package.swift` skeleton from RPClient, rename modules (`LoomCore`, `Loom`, `LoomCoreTests`).
2. Copy `build.sh` + `run.sh`, sed `RPClient` → `Loom`.
3. Copy `Sources/RPClientCore/{KoboldClient,ServerProbe,KoboldClientRegistry,DebugLog,Storage,Settings stub}.swift` and adapt — these are 80%+ reusable.
4. New `AppDelegate` + `MainWindowController` for the document-shaped surface.
5. Brand-new `EditorViewController` with NSTextView-based long-form editor.

Don't carry over: ChatViewController, TurnView, FlowPillRow, anything chat-shaped — different paradigm.

---

This file gets replaced by `LOOM_PLAN.md` once research lands. Treat it as scaffolding.

# Loom reference-help system — plan (Phase A output)

> **Status:** awaiting sign-off. This document is the locked TOC + source mapping for the
> two reference deliverables. Kept until both books ship, then archived or deleted.

## What we're building

Two **in-app** reference books, rendered through a new help webview panel inside Loom.app
(mirrors the Bible Workspace AppKit + WKWebView pattern):

| Book | Audience | Tone |
|---|---|---|
| **User Help** | Fiction writers using Loom day-to-day | Getting-Started + Reference halves. Friendly to first-time users, dense for power-users |
| **Technical Reference** | You / future you / contributors reading the code | Concise, code-first, accurate to current state (not historical plan-doc intent) |

The webview will have a top-level book switcher (User Help / Technical Reference), each with its own left-rail TOC and content area.

## Hard rule on staleness

The existing `LOOM_*.md` docs are **plan-docs + session ledgers**, not reference docs. They go
stale (L5's status line was a week out of date when we checked yesterday; LOOM_DATA_MODEL
predates References / Templates / Scene Exemplars / Continuity Findings / Proposed Entities).

**Every section is written from current code, with plan-doc design intent cited only where
code agrees.** Source-mapping below distinguishes "design intent (may be stale)" from
"current authoritative source (code)."

---

## Book 1 — User Help

Two halves: **Getting Started** (linear, first-time-user friendly) and **Reference**
(non-linear, look-up-what-I-need).

### Getting Started

| § | Section | Source | Freshness |
|---|---|---|---|
| GS.1 | What Loom is + when to use it | LOOM_PLAN §0; LOOM_NSFW §1 framing | mostly current |
| GS.2 | Install + first launch | README, build.sh, run.sh | needs fresh write |
| GS.3 | Configure your model servers (Kobold + Ollama) | Code: AppSettings, ServerProbe, AutoProbe | needs fresh write — no existing user-facing doc |
| GS.4 | Your first project | Code: AppState.createProject, ProjectStorage | needs fresh write |
| GS.5 | Your first scene + first generation (Continue) | LOOM_PHASE1_EDITOR_MVP; LOOM_GENERATION_MODES §2 | engineering tone — rewrite for user |
| GS.6 | What to do when generation refuses or feels off | LOOM_NSFW §3.5; RefusalDetector code | rewrite for user |
| GS.7 | Where your work lives on disk | LOOM_DATA_MODEL §7 (on-disk layout) | partially stale — needs code cross-check (References/Templates/Snapshots added since) |

### Reference

| § | Section | Source | Freshness |
|---|---|---|---|
| R.1 | Editor surface (panes, sidebar, inspector, keybindings) | LOOM_DESIGN_LANGUAGE §14; LOOM_UI_RESEARCH; code: EditorViewController + menu defs | partial — needs current keybinding sweep from code |
| R.2 | Generation modes — full catalogue | LOOM_GENERATION_MODES (engineering tone); code: every per-mode generator | engineering tone — rewrite for user |
| R.3 | Author's Note, per-call instructions, writing direction | LOOM_NSFW §3; LOOM_MEMORY §4 (Author's Note layer); code: AuthorsNoteInjector, WritingDirectionPrompt | rewrite for user |
| R.4 | Story Bible — Characters, Settings, Objects, Factions | LOOM_STORY_BIBLE; LOOM_DATA_MODEL §3 | partial — has Lorebook + Dynamics added since |
| R.5 | Story Bible — Lorebook entries | LOOM_BIBLE_WORKSPACE; HANDOFF §15.x lorebook | partial — needs current code sweep |
| R.6 | Story Bible — Dynamics (relationship spec) | Code: DynamicSheet, DynamicSheetInjector, DynamicSheetPrompt | needs fresh write — no existing user doc |
| R.7 | Knowledge ledger (what each character knows) | LOOM_MEMORY; LOOM_LEDGER_SPIKE; LOOM_STORY_BIBLE | mostly current — needs L4 §15.x cross-check |
| R.8 | Entity discovery (accepting auto-found bible entries) | LOOM_ENTITY_DISCOVERY_SPIKE | partial — needs current state cross-check |
| R.9 | References (style ingestion) — adding, ingesting, what it does | LOOM_RAG_SPIKE §13; code: ReferenceStorage, ReferenceIngestPipeline | needs fresh write — only engineering docs exist |
| R.10 | Scene exemplars + templates | LOOM_SCENE_EXEMPLAR; LOOM_SCENE_TEMPLATE | partial — written as design proposals, need user-voice rewrite |
| R.11 | Continuity audit — running, understanding findings | LOOM_CONTINUITY_AUDIT §0–§9 (design) | **gated on L10 Phase C** — no user surface yet. Stub for now. |
| R.12 | Project structure — Parts, Chapters, Scenes, Corkboard | LOOM_DATA_MODEL §2; HANDOFF §13 (Phase 3) | mostly current |
| R.13 | Snapshots + version history | LOOM_DATA_MODEL §J (planned-list parking lot — was it built?) | **needs code check** — verify what's actually shipped |
| R.14 | NSFW / dark-fiction posture | LOOM_NSFW | mostly current — condense |
| R.15 | Settings — app-level + per-project | LOOM_PHASE1_EDITOR_MVP §4; code: AppSettings, ProjectSettings, SamplerParams | needs fresh write from code |
| R.16 | Anti-slop phrases | Code: AntiSlopDefaults, KoboldClient.bannedStrings | needs fresh write |
| R.17 | Sphiratrioth pack + power-user resources | LOOM_NSFW §7 | mostly current |
| R.18 | Troubleshooting | none existing; HANDOFF scattered debug-log conventions | needs entirely fresh write — collect debug-log signal table |

---

## Book 2 — Technical Reference

| § | Section | Source | Freshness |
|---|---|---|---|
| T.1 | Architecture overview + runtime services | LOOM_PLAN §0; LOOM_RESEARCH §M, §N; LOOM_TECH_STACK | needs synthesis + a diagram |
| T.2 | Repo layout + module breakdown | Package.swift; ls Sources/LoomCore/ | needs fresh write from code |
| T.3 | Data model — every Codable, every on-disk artifact | LOOM_DATA_MODEL (out of date); code: every Models/* + every Storage/* | **major rewrite from code** — LOOM_DATA_MODEL predates ~half the current model |
| T.4 | Generation pipeline — PromptBuilder, layers, eviction, per-mode assembly | LOOM_GENERATION_MODES; LOOM_MEMORY §4; code: PromptBuilder + every injector | partial — needs current code cross-check for layer priorities + new layers |
| T.5 | Style retrieval + [STYLE EXEMPLARS] layer | LOOM_RAG_SPIKE §13; HANDOFF §15.12–§15.13; code: RetrievalService, StyleExemplarsLayer, CoreMLEmbeddingClient | mostly current — L8 CoreML migration removed Python subprocess |
| T.6 | Extraction pipelines — knowledge ledger / entity discovery / continuity / scene-template beats | LOOM_LEDGER_SPIKE; LOOM_ENTITY_DISCOVERY_SPIKE; LOOM_CONTINUITY_AUDIT; LOOM_SCENE_TEMPLATE_SPIKE | partial — synthesise common patterns (JSON-schema vs GBNF, tolerant parse, retry-on-empty) |
| T.7 | Embeddings — Wegmann CoreML, bge-large, FuncwordZ | LOOM_SCENE_EXEMPLAR_RESEARCH; LOOM_SCENE_EXEMPLAR_SPIKE; LOOM_NARRATIVE_MODE_SPIKE; LOOM_MLX_PORT_SPIKE (dead end) | mostly current |
| T.8 | UI architecture — AppKit/WKWebView split, snapshot/intent pattern | LOOM_BIBLE_WORKSPACE; code: BibleWorkspaceBridge, BibleWorkspaceSnapshot, BibleWorkspaceIntent | mostly current |
| T.9 | Build / test / run | build.sh, run.sh, scripts/, TestKit.swift | needs fresh write |
| T.10 | Spike runners (Tools/*) | Each Tools/*/main.swift | needs index + usage table |
| T.11 | Configuration — settings.json, server profiles, sampler families | code: AppSettings, ProjectSettings, SamplerParams, ProjectMemoryPresets | needs fresh write |
| T.12 | Conventions + dead ends | LOOM_TECH_STACK §3 (already a registry); LOOM_CONTINUITY_AUDIT §25–§28; LOOM_MLX_PORT_SPIKE §12 | mostly current — extend with §28 |
| T.13 | Debug log subsystems + signal reference | scattered DebugLog.shared.write calls; HANDOFF | needs fresh write — grep-based |
| T.14 | How to add: a new generation mode | code: GenerationCoordinator, GenerationModeAvailability + per-mode files | needs fresh write |
| T.15 | How to add: a new Bible entity field | LOOM_BIBLE_WORKSPACE; code: SnapshotCharacter, CharacterPatch, EntityList.tsx | needs fresh write |
| T.16 | How to add: a new extraction pipeline | code: OllamaLedgerExtractor as exemplar | needs fresh write |

---

## Phase B — Help webview shell

Sketch (commitments locked when Phase A signs off):

- **AppKit side**: `HelpWindowController` + `HelpViewController` mirroring `BibleWorkspaceWindowController` / `BibleWorkspaceViewController`. Single window, opens via "Help → Loom Help" menu item.
- **Webview bundle**: `web/help/` mirroring `web/bible-workspace/`. Vite + React + TypeScript + Tailwind + shadcn/ui. `dist/` becomes a `Loom_LoomCore.bundle` resource via Package.swift declaration.
- **React surface**: top-level `<BookSwitcher>` (User Help / Technical Reference), left-rail `<TOC>`, main `<Content>` markdown renderer.
- **Bridge**: snapshot push = `HelpSnapshot { book, toc, sectionId, sectionMarkdown }`; intent = `HelpIntent { selectSection(sectionId) }`. The Swift side reads markdown from `Resources/help/{user,technical}/<sectionId>.md`.
- **Bundled content**: each markdown section is a separate `.md` file under `Sources/LoomCore/Resources/help/`. Lets us ship + iterate content without rebuilding the webview bundle.
- **TDD**: snapshot Codable round-trip, intent dispatch, TOC ordering, section loading. ~15–20 new tests.
- **Phase B exit**: shell renders with a single placeholder "Hello from Loom Help" page; menu item opens it; book switcher swaps TOC. No real content yet.

---

## Phase C — content writing order

In priority order (highest user value first):

1. **GS.1–GS.7** Getting Started (highest user value — first-time-user flow, ground-truth from code)
2. **R.2** Generation modes — most-used user feature, big gain from a user-voice rewrite
3. **R.4–R.8** Story Bible (Characters / Lorebook / Dynamics / Knowledge ledger / Entity discovery)
4. **R.9–R.10** References + Scene exemplars (recently shipped, no user-facing doc exists)
5. **R.18** Troubleshooting (fresh write, will iterate as user runs into issues)
6. **T.1–T.3** Technical: architecture, repo layout, data model (foundation for all other technical sections)
7. **T.4–T.7** Technical: generation pipeline, retrieval, extraction, embeddings (the meat)
8. **Remaining R + T sections** in any order, batched by area
9. **R.11 Continuity audit user-help** — written once L10 Phase C ships the review surface

Each section gets a draft → user review → iterate cycle. Aim for ~1 section per writing session; sometimes more if related sections share source material.

---

## Outstanding scoping decisions for sign-off

1. **Approve TOCs** — both books as listed above? Anything missing or to cut?
2. **Approve writing-order** — Phase C list as ordered above? Any reordering for higher-priority gaps?
3. **Approve Phase B sketch** — webview shell as described? Any architectural concerns (e.g. should section markdown be bundled-static, or hot-loaded from a separate dir for dev iteration)?

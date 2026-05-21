# Generation pipeline

How a generation request becomes a prompt and a prompt becomes accepted prose. The load-bearing site is `Generation/PromptBuilder.swift`; the orchestration around it is `Generation/GenerationCoordinator.swift`.

> Where this page and `LOOM_GENERATION_MODES.md` disagree, the code wins. That doc describes a "20-layer" model; the current `buildLayers` emits fewer discrete layers than the `ChicletKind` enum has cases (some fold into the system block; a couple are reserved-but-unbuilt). This page reflects what `PromptBuilder.build` actually produces.

## `PromptBuilder.build(_:) -> AssembledPrompt`

Pure, stateless, thread-safe. Six steps:

1. **Resolve the instruct template.** Explicit `ProjectSettings.instructTemplate` wins; `.auto` runs `InstructTemplates.detect(forModelName:)` against the probed model name. Returns the rendering adapter.
2. **Build candidate layers** in display order (`buildLayers`). Each `Layer` carries `kind` (`ChicletKind`), `content`, `tokens`, `aboveCache: Bool`, `evictionPriority: Int`, `mandatory: Bool`, and an optional `userBlockContent` override.
3. **Enforce budget** (`enforceBudget`). `usableContextBudget = contextBudgetTokens − replyBudgetTokens`. Evicts to fit (see below). Returns the list of evicted layer kinds.
4. **Prefill-aware Continue** (`.continueProse` only). If the manuscript ends mid-sentence, `PrefillSeed.extract` splits the trailing fragment out of the recent-prose layer and into the assistant-turn prefill — the model completes the sentence from inside its own turn, removing the fresh-turn seam a refusal can open at. Only fires when real context survives ahead of the fragment.
5. **Render** above-cache layers into the system block (joined `\n\n`), below-cache layers into the user block (using `userBlockContent ?? content`).
6. **Wrap** with the template adapter (`adapter.wrap(system:userBody:prefill:)`), emitting the final prompt + stop sequences.

Returns an `AssembledPrompt` carrying the full prompt, system/user/prefill blocks, per-layer `ContextChiclet`s (for the History tab), above/below-cache token counts, evicted layers, and the resolved template.

## Layers + the cache boundary

Each layer is flagged `aboveCache` or below. The instruct adapter glues above-cache layers into the **system block** (cacheable across turns — stable project state) and below-cache layers into the **user block** (turn-specific — recent prose, mode instruction).

The empirical NovelAI finding drives the ordering: **lower in the prompt = stronger steering.** So the mode instruction and the recent-prose tail land at the bottom of the user block; the Author's Note splices in near the very end.

### `ChicletKind` — `PromptBuilder.swift`

```
system  projectMemory  styleSheet  projectSummary  chapterSummary  sceneSummary
bibleConstant  bibleKeyed  lorebookEntry  knowledgeLedger  recentProse  sceneAnchor
authorsNote  perCallInstruction  modeInstruction  fewShotStyleExample
directionDirective  sceneFraming  dynamicSheet  intimateAnatomy
```

Not all 20 are emitted as discrete layers today:

- **`directionDirective`** and work-framing are **concatenated into the `.system` layer's content** (`systemPromptFor(mode:) + WritingDirectionPrompt.systemAddendum(direction) + WorkFramingPrompt.systemAddendum(workFraming)`), not built as standalone layers.
- **`authorsNote`** is spliced **into** the recent-prose content at `authorsNoteDepthLines` from the cursor (NovelAI A/N convention), then recorded as a chiclet with empty `userBlockContent` so the bracket doesn't appear twice.
- **`sceneAnchor`** is folded into the AN per the Phase 1 §A3 simplification.
- **`projectSummary`** / **`chapterSummary`** are **reserved — not built** (the recursive-summary feed isn't wired yet).

### What's actually built, in order

**Above cache (system block):**

| Layer | Source | Eviction priority |
|---|---|---|
| `system` | per-mode system prompt + WritingDirection addendum + WorkFraming addendum | `.max` (mandatory) |
| `projectMemory` | `ProjectSettings.memory` | `.max` (mandatory) |
| `styleSheet` | `StylePrompt.render(assignedStyles)` — Planned Project genre/register styles | `.max` |
| `bibleConstant` | Characters/Settings/Objects with `injectionMode == .constant` | `100` |

**Below cache (user block), roughly top-to-bottom:**

| Layer | Source | Notes |
|---|---|---|
| `sceneSummary` | adjacent-scene recaps | when present |
| `bibleKeyed` | entities whose name/alias hit the recent-prose window | `BibleInjector.activated` |
| `lorebookEntry` | activated lorebook entries (`LorebookActivator`) | constant + keyed + scene-gated |
| `knowledgeLedger` | POV character's KNOWS/DOES-NOT-KNOW (`LedgerKnowledge.compute`) | POV-character-specific |
| `fewShotStyleExample` | top-K retrieved reference chunks (`RetrievalService`) | lower eviction priority than bible/knowledge |
| `dynamicSheet` | activated `DynamicSheet`s (`DynamicSheetInjector`) | always-on or participant-keyed |
| `sceneFraming` | `Scene.framing` | per-scene scenario block |
| `intimateAnatomy` | per-character `intimateAnatomy`, gated by `AnatomyGate` | only when scene depicted + character undressed |
| `recentProse` | last-N window before cursor (`RecentProseWindow.extract`), with AN spliced in | shrinks rather than evicts |
| `perCallInstruction` | the tray instruction field | one-shot |
| `modeInstruction` | the actual ask (continue/expand/rewrite/…) | lands last = strongest steering |

## Eviction (`enforceBudget`)

Three steps, run until the total fits `usableContextBudget`:

1. **Drop non-mandatory below-cache layers**, lowest `evictionPriority` first. (Style exemplars go before bible/knowledge.)
2. **Shrink `recentProse`** by re-extracting with a halved char budget (`RecentProseWindow.extract`), down to a ~50-token floor. The prose tail is never fully evicted — it's the load-bearing input.
3. **Drop non-mandatory above-cache layers** if still over (rare — means the system + memory + constant bible already overflow).

Mandatory layers (`evictionPriority == .max`: system, projectMemory, styleSheet) are never dropped — losing them would break the instruct-template structure. Evicted kinds are returned and recorded on `AssembledPrompt.evictedLayers`, surfaced in the History tab ("this generation evicted: dynamicSheet, fewShotStyleExample").

## Prefill + the chat-shaped structure

Loom keeps a **chat-shaped** prompt — prose in the user message, not the assistant prefill. The Phase-0 NovelAI/SillyTavern story-mode pattern (prose in the assistant prefill, model continues) was tested live 2026-05-10 and **does not work for instruct-tuned chat models** (Qwen, Gemma): they treat the prefill as "my completed response" and emit the end-of-turn token immediately, producing 0 tokens. The anti-echo guarantee instead comes from system-prompt sharpening + the `modeInstruction` layer landing *after* the prose.

The prefill is used for two narrow things:

- **`<think>` suppression** — ChatML/Qwen models get a `<think>\n\n</think>\n\n` prefill so they skip the chain-of-thought scratchpad (`prefillFor`).
- **Prefill-aware Continue** (step 4 above) — the mid-sentence fragment.

## Instruct-template handling (`Generation/InstructTemplates.swift`)

Loom probes the server and matches the model name against known families:

| Template | Detection substrings |
|---|---|
| `mistralV7` | `mistral-small-3`, `Goetia` |
| `mistralV3` | `mistral-7b`, `mixtral` |
| `gemma4` | `gemma-4`, `gemma4` (checked before generic `gemma`) |
| `gemma3` | `gemma`, `gemma-3` |
| `chatml` | `qwen`, `chatml` |
| `llama3` | `llama-3`, `llama3` |
| `alpaca` | `alpaca` |
| `raw` | fallback |
| `auto` | runs the detection chain |

`adapter(for:)` returns the system/user/assistant tag emitter + the stop-sequence set. The assistant-turn prefill is empty by default so the model continues naturally.

## Per-mode system prompts (`systemPromptFor`)

Each `GenerationMode` has a static system prompt in `PromptBuilder.systemPromptFor`. Highlights:

- **`.continueProse`** — "continue ~N words; don't restate; output begins on the next character; end at a natural pause." N comes from `WritingDirectionPrompt.continueWordTarget`.
- **`.expand`** — "the selection is a draft outline; flesh it out preserving every beat."
- **`.rewrite`** + sub-modes — preserve beats + entities; a scope-discipline clause ("stay strictly inside the selection — don't extend past its bounds") closes the Gemma over-contextualisation failures from HANDOFF §15.9.
- **`.rewriteVoice`** — target voice rides on `perCallInstruction`; the system prompt only commits to "rewrite in a different voice, preserve everything else."
- **`.rewritePOV`** — `RewritePOVDescriptor.build` threads `LedgerKnowledge.compute` into a `[KNOWLEDGE-LEDGER]` slot so the rewrite respects the new POV's knowledge.
- **`.showDontTell`** — dramatise one telling sentence; ~120% length target baked in.

The five enum cases without a UI surface (`brainstorm`, `critique`, `bridge`, `describe`, `nameSuggest`) have prompt code but aren't reachable from the tray — see **Generation modes** in User Help.

## Output post-processing

Applied to the model's stream/response:

- **`<think>` stripping** — `StreamingThinkBlockStripper` (on-the-fly for streaming) + `ThinkBlockStripper` (non-streaming). Removes Qwen's reasoning scratchpad so the user sees only prose.
- **Refusal detection** — `RefusalDetector.looksLikeRefusal` matches canonical refusal prefixes in responses ≤600 chars (longer prose with the phrase is treated as in-character dialogue). Sets `GenerationResponse.refusalDetected`, which chips the History row + surfaces the "Push past refusal" affordance (`RefusalContinuation`).
- **Anti-slop** — `ProjectSettings.antiSlopPhrases` (seeded from `AntiSlopDefaults`) is sent to KoboldCpp as `banned_strings` (`GenerateRequest.bannedStrings`) — a phrase-level backtracking sampler enforced server-side, not a post-filter.
- **Beat sanitisation** — `BeatOutputSanitizer` strips per-beat meta-commentary; applies mainly to template-driven generation.

## Orchestration (`GenerationCoordinator`)

`GenerationCoordinator.start` is the async wrapper around `PromptBuilder.build`:

```
EditorViewController.handle{Continue,Expand,Rewrite,…} →
  GenerationCoordinator.start(mode:context:) →
    PromptBuilder.build →
    KoboldClient.streamingGenerate (callbacks on a background queue) →
    StreamingThinkBlockStripper (on each delta) →
    deltas bounced to main → editor inserts incrementally →
  on completion:
    RefusalDetector → GenerationResponse →
    GenerationLogStore.write (generation-log/<ts>.json) →
    AcceptanceMachine transitions to .awaiting →
  user: Accept ⏎ / Reject ⌫ / Keep & Redo ⌘⇧R
```

`AcceptanceMachine` (`Generation/AcceptanceMachine.swift`) is the post-generation state machine — pending → awaiting → accepted/rejected, with auto-accept on edit.

Template-driven generation uses a separate coordinator (`TemplateGenerationCoordinator`) with a per-beat assembly path (`BeatGeneration.buildBeatPrompt`); see **Extraction pipelines** + **Style retrieval** for the pieces it composes.

## Concurrency

`PromptBuilder` is pure — safe to call from any thread, no shared state, logging is the caller's concern. `GenerationCoordinator` runs the network call off-main and bounces deltas + completion to main before touching editor state. No `async/await` — callback completion + `DispatchQueue`.

## See also

- **Generation modes** (User Help) — the user-facing mode catalogue.
- **Style retrieval** — the `fewShotStyleExample` layer's retrieval path, next section.
- **Extraction pipelines** — the Ollama-side passes that feed the bible the generation reads from.
- [`LOOM_GENERATION_MODES.md`](LOOM_GENERATION_MODES.md) — design intent + history (the "20-layer" model). Cross-check against `PromptBuilder.swift`.
- [`LOOM_MEMORY.md`](LOOM_MEMORY.md) — the conceptual long-form-context architecture this implements.

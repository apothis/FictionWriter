# Loom Generation Modes

> **Last code cross-check:** 2026-05-21
> **Posture:** reference doc reflecting *current shipped* code. Phase 0 design lock (2026-05-10) covered Continue + Expand only; the catalogue has since grown to 13 modes, the prompt has 20 layers, and several Phase-0 assumptions about budget / eviction were superseded by actual implementation. Where this doc and code disagree, **the code wins**.
> **Memory-architecture supersession.** [`LOOM_MEMORY.md`](LOOM_MEMORY.md) carries the conceptual long-form-context architecture; this doc is the **implementation reference** for what actually ships. They should agree; if they don't, this doc reflects shipped behaviour.
> **Companion to** [`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md) §4.5 (`GenerationMode` enum) + §17 (`GenerationLogEntry` shape), [`LOOM_STORY_BIBLE.md`](LOOM_STORY_BIBLE.md) §8 (assembled injection order), [`LOOM_NSFW.md`](LOOM_NSFW.md) (writing-direction posture layer).

## 1. Generation modes — the 13-mode catalogue

`Sources/LoomCore/Models/Scene.swift` (the `GenerationMode` enum):

| Case | Phase | Trigger | What it does |
|---|---|---|---|
| `.continueProse` | 1 | cursor, no selection | Extends from the cursor for `continueWordTarget` words, in voice |
| `.expand` | 1 | cursor, no selection | Drafts a longer beat (~`expandWordTarget` words) from a 1-line direction |
| `.rewrite` | 4 | selection | Generic rewrite of the selected passage |
| `.rewriteVoice` | 4 | selection | Rewrite preserving content; shift voice / register |
| `.rewriteTense` | 4 | selection | Switch tense (past ↔ present) |
| `.rewritePOV` | 4 | selection | Switch POV across characters (uses the per-character knowledge ledger) |
| `.rewriteLength` | 4 | selection | Compress / expand the passage to a target word count |
| `.showDontTell` | 4 | selection | Dramatise a telling sentence into showing prose |
| `.brainstorm` | 4 | cursor, optional selection | Idea generation; off-prose output |
| `.critique` | 4 | selection (or scene) | Editorial critique of the prose, not a rewrite |
| `.bridge` | 4 | cursor between two written beats | Drafts a connecting passage |
| `.describe` | 4 | cursor, optional Bible-entity context | Describe a Setting / Object / Character entity in prose |
| `.nameSuggest` | 4 | cursor | Suggest names (character / place / object) given a brief description |

**Per-mode availability** — `Sources/LoomCore/Generation/GenerationModeAvailability.swift` decides which modes are enabled based on cursor + selection state. The UI greys disabled modes; menu items reflect availability.

**Not in the enum** — two adjacent generation paths use their own coordinators:

- **Roll-Outcome** (Bible menu) — rolls a weighted lorebook group entry into the per-call instruction tray for the *next* Continue. Lives at `AppDelegate.rollOutcomeClicked` + `LorebookRoller.swift`. Not a generation mode; it primes the next one.
- **Scene-Template Generation** (L7) — per-template per-beat draft via `TemplateGenerationCoordinator.swift`. Its own pipeline (Pass-A skeleton extracted at ingest time, Pass-B per-beat writing at generation time). Uses the same writer model + style retriever but a different prompt builder (`BeatGeneration.buildBeatPrompt`).

## 2. The assembled prompt — 20 layers

`Sources/LoomCore/Generation/PromptBuilder.swift` builds a list of `Layer { kind: ChicletKind, content, tokens, aboveCache, priority }` then orders, fits, and renders. The `ChicletKind` enum is the load-bearing list:

```swift
public enum ChicletKind: String, Codable {
    case system               // instruct-template-aware system block
    case projectMemory        // ProjectSettings.memory
    case styleSheet           // Style preset (writer-prompt voice/genre/period preset)
    case projectSummary       // (reserved; not yet built)
    case chapterSummary       // (reserved; not yet built)
    case sceneSummary         // Scene.summary on adjacent scenes
    case bibleConstant        // Always-on Character/Setting/Object summaries
    case bibleKeyed           // Keyed lorebook entries triggered by recent-prose
    case lorebookEntry        // explicit-pinned lorebook entries
    case knowledgeLedger      // KNOWS / DOES NOT KNOW / SUSPECTS / MISTAKEN
    case recentProse          // last N tokens before cursor
    case sceneAnchor          // scene framing (POV / location / conflict / outcome banner)
    case authorsNote          // ProjectSettings.authorsNote at depth-N from end
    case perCallInstruction   // per-generation instruction tray (one-shot steering)
    case modeInstruction      // the mode's system instruction
    case fewShotStyleExample  // L5 style-retrieval exemplars from References (top-3)
    case directionDirective   // WritingDirection system-prompt addendum
    case sceneFraming         // Scene.framing field (per-scene scenario block)
    case dynamicSheet         // DynamicSheet block for the active cast
    case intimateAnatomy      // per-character intimateAnatomy (NSFW; injected when scene undressed)
}
```

### 2.1 Layer ordering — above-cache vs below-cache

Each layer is flagged `aboveCache: Bool`. The instruct-template adapter glues the above-cache layers into the *system block* and the below-cache layers into the *user block*:

```
System block (above-cache, joined by \n\n)
├── system                 # per-mode system preamble
├── projectMemory          # always-true facts
├── directionDirective     # WritingDirection addendum
├── bibleConstant          # always-on entities
├── dynamicSheet           # active dynamics
├── styleSheet             # writer-prompt voice preset
└── (additional preset layers)

User block (below-cache, joined by \n\n)
├── chapterSummary / projectSummary  # (reserved)
├── sceneSummary           # adjacent-scene recaps
├── bibleKeyed             # keyed lorebook entries
├── lorebookEntry          # explicit-pinned entries
├── knowledgeLedger        # POV character's facts
├── fewShotStyleExample    # L5 style retrieval
├── sceneFraming           # per-scene scenario
├── intimateAnatomy        # NSFW context for present cast
├── sceneAnchor            # POV / location / conflict / outcome banner
├── recentProse            # the prose tail
├── authorsNote            # near-end depth-N
├── perCallInstruction     # one-shot steering
└── modeInstruction        # the actual ask: continue / expand / rewrite / …
```

Empirical NovelAI finding: **lower in the prompt = stronger steering**. That's why `modeInstruction` and the cursor's `recentProse` tail are at the bottom, with `authorsNote` near the very end (depth-N controls how far).

### 2.2 Prefill-aware Continue (mid-sentence)

When `.continueProse` fires and the manuscript ends mid-sentence, `PromptBuilder.build` extracts the trailing unfinished fragment out of `recentProse` and into the **assistant-turn prefill** via `PrefillSeed.extract`. The model then completes the sentence from inside its own turn — no fresh-turn seam where a refusal can open. Only active for Continue, only when real context survives ahead of the fragment. See `PromptBuilder.swift` step 3a + `PrefillSeed.swift`.

### 2.3 Why prose lives in the user block, not the prefill

Phase 0 imagined the NovelAI/SillyTavern story-mode pattern: prose in the assistant prefill, model continues. Live testing 2026-05-10 confirmed this **does not work** for instruct-tuned chat models like Qwen and Gemma — they treat the prefill as "my completed response" and emit `<|im_end|>` immediately, producing 0 tokens. Loom keeps a chat-shaped structure: prose in the user message, sharpened system prompt steers the model to continue. The "anti-echo guarantee" comes from system-prompt sharpening + an explicit `modeInstruction` layer landing AFTER the prose (lower = stronger steering).

The prefill pattern still works for base / story-tuned models (Erato, Goliath), but Loom's default writer model (Goetia, Mistral-Small-3 24B) is instruct-tuned. The prefill mechanic is reserved for `<think>` suppression on ChatML (Qwen) — see `PromptBuilder.prefillFor`.

## 3. Token budget + eviction

`Sources/LoomCore/Generation/ContextBudgetRecommendation.swift` + `Sources/LoomCore/Generation/TokenEstimator.swift` + `PromptBuilder.enforceBudget`.

### 3.1 Budget shape (actual, not Phase 0 aspiration)

- `ProjectSettings.contextBudgetTokens` — user-set context budget for the project. Defaults vary by model's `trueMaxContext` capability.
- `replyBudgetTokens` — reserved for model output; subtracted from `contextBudgetTokens` to give the *usable* prompt budget.
- `ContextBudgetRecommendation.defaultSafetyMargin = 256` tokens — wiggle room for the model's BOS / instruct-template overhead the estimator may under-count.
- `ContextBudgetRecommendation.minimumBudget = 1024` tokens — refuse to recommend a budget lower than this.

Recommendations land in the inspector "Recommended Context Budget" pill — a per-model suggestion based on the server-probed `trueMaxContext`.

### 3.2 Eviction order

When assembled layers exceed `usableContextBudget`, `enforceBudget` drops below-cache non-mandatory layers first (lowest priority first), then shrinks `recentProse` by re-extracting with a smaller budget rather than fully evicting it. Above-cache layers stay (they're cacheable across turns and dropping them would break instruct-template structure).

Evicted layer kinds land on `AssembledPrompt.evictedLayers` so the History inspector can show "this generation evicted: dynamicSheet, fewShotStyleExample, sceneSummary." Useful for budget tuning.

## 4. Instruct-template handling

`Sources/LoomCore/Generation/InstructTemplates.swift`

Loom does not unilaterally pick the template — it probes the server (`/api/v1/model`) and matches the model name against known families:

| Template | Models | Detection |
|---|---|---|
| `.mistralV7` | Goetia, Mistral-Small-3.x (2501/2503/2506), Mistral-Large-3 | `mistral-small-3`, `Goetia` |
| `.mistralV3` | older Mistral / Mixtral | `mistral-7b`, `mixtral` |
| `.gemma4` | Gemma-2/3/4 family + abliterated variants | `gemma`, `gemma-3`, `gemma-4` |
| `.chatml` | Qwen3.x family, many merges | `qwen`, `chatml` |
| `.llama3` | Llama 3.x family | `llama-3`, `llama3` |
| `.alpaca` | older finetune family | `alpaca` |
| `.raw` | uncertain / base models | fallback |
| `.auto` | the default | runs the detection chain |

`InstructTemplates.detect(forModelName:)` returns the matched template. `InstructTemplates.adapter(for:)` returns the rendering adapter (system / user / assistant tag emitter + stop-sequence set).

For story-mode use specifically, **the assistant-turn prefill is empty by default** so the model continues naturally rather than emitting an "assistant turn" framing. ChatML / Qwen models get a `<think>\n\n</think>\n\n` suppression prefill (Qwen tunes have a default chain-of-thought scratchpad we don't want for prose).

## 5. Per-mode prompt shapes

Each mode's full prompt builder lives in code. This section is an index — system-prompt skeleton and which file owns the per-mode logic.

### 5.1 `.continueProse` (Phase 1)

- **Code:** `PromptBuilder.swift` → `modeInstructionFor(.continueProse)`.
- **Trigger:** cursor, no selection. `⌘⇧E`.
- **System prompt:** *"You are a fiction writer continuing an existing manuscript. Maintain voice, tense, POV, and tone exactly as established. Continue the scene naturally — do not summarize, do not break narrative voice, do not introduce meta-commentary. Continue for approximately {N_WORDS} words…"*
- **Context strategy:** standard assembly. Recent-prose tail is the load-bearing input; `modeInstruction` is minimal — the cursor itself is the ask.
- **Output:** insert at cursor; Accept/Reject/Redo UI per [`LOOM_DESIGN_LANGUAGE.md`](LOOM_DESIGN_LANGUAGE.md) §14.6.

### 5.2 `.expand` (Phase 1)

- **Code:** `PromptBuilder.swift` → `modeInstructionFor(.expand)`.
- **Trigger:** cursor; user provides a 1-line direction in the per-call instruction tray.
- **System prompt:** *"…draft approximately {N_WORDS} words from this direction…"*
- **Output:** insert at cursor.

### 5.3 `.rewrite` and the four sub-modes (Phase 4)

`Sources/LoomCore/Generation/PromptBuilder.swift` carries the mode-instruction strings; the per-sub-mode steering is layered:

- **`.rewriteVoice`** — system prompt: *"Rewrite the selection preserving content; shift voice to {VOICE_DESCRIPTOR}."* Voice descriptor either freeform from the user or selected from `StyleLibrary` presets.
- **`.rewriteTense`** — currently shipped: past ↔ present. Selection-tense heuristic (`Phase4SelectionTenseHeuristic`) detects current tense to pick the right shift direction.
- **`.rewritePOV`** — *"Rewrite from {NEW_POV_CHARACTER}'s perspective."* Threads `LedgerKnowledge.compute(...)` through `RewritePOVDescriptor.build` to fill a `[KNOWLEDGE-LEDGER]` block specific to the new POV (so the rewrite respects what the new POV character knows / doesn't know — the load-bearing reason POV rewrites need the ledger).
- **`.rewriteLength`** — `LengthScenario` enum drives target word count: shorter / similar / longer / specific N. System prompt is *"Rewrite the selection to {TARGET_LENGTH}."*
- **`.rewrite`** (generic) — open-ended rewrite from a freeform per-call instruction.

Each sub-mode adds a scope-discipline clause to the system prompt closing the Gemma over-contextualisation failures surfaced in HANDOFF §15.9 live testing.

### 5.4 `.showDontTell` (Phase 4)

- **System prompt:** *"Dramatise the selected telling-sentence into showing prose. Preserve the same events; use sensory detail, action, and dialogue."* 
- **Code:** PromptBuilder + a structural-limit guard (one telling sentence → one showing paragraph; longer expansions produce purple prose).

### 5.5 `.brainstorm`, `.critique`, `.bridge`, `.describe`, `.nameSuggest` (Phase 4)

Each has a tailored system prompt and a different acceptance UX:

- **Brainstorm** outputs to a sheet (not inserted at cursor); user picks a candidate to copy.
- **Critique** outputs in the inspector History tab as an editorial note, not as inserted prose.
- **Bridge** inserts at cursor between two written beats; takes the surrounding context heavily.
- **Describe** uses the Bible entity (Setting / Object / Character) as the primary instruction source.
- **NameSuggest** outputs a list; user picks one.

## 6. Output post-processing

`Sources/LoomCore/Generation/ThinkBlockStripper.swift` + `StreamingThinkBlockStripper.swift` + `RefusalDetector.swift` + `RefusalContinuation.swift` + `BeatOutputSanitizer.swift`.

### 6.1 `<think>` block stripping

Qwen-family models emit a `<think>...</think>` scratchpad before their actual response. The streaming stripper removes it on-the-fly so the user sees only the prose; the non-streaming stripper handles non-streaming endpoints. Without this, Qwen output renders with a visible reasoning trace.

### 6.2 Refusal detection + continuation

`RefusalDetector` matches refusal patterns ("I cannot continue this content because…", "As an AI…", etc.). On match, `RefusalContinuation` constructs a continuation prompt that *unlocks* the refused beat by reframing — usually a clause appended to the original system prompt that asserts the work's literary stance + the requested explicitness. The user sees a one-click "Continue past refusal" button when a refusal is detected.

See [`LOOM_NSFW.md`](LOOM_NSFW.md) §3.5 for the design.

### 6.3 Beat output sanitisation

`BeatOutputSanitizer` (Phase 7 — Scene-Template Generation) strips per-beat meta-commentary the model occasionally emits ("*This beat shows…*"). Generic post-processing; mostly applies to template-driven generation, not freehand modes.

### 6.4 Anti-slop

Anti-slop phrases (`ProjectSettings.antiSlopPhrases`, seeded from `AntiSlopDefaults`) are sent to KoboldCpp as `banned_strings` (phrase-level backtracking sampler). Per `Sources/LoomCore/Networking/KoboldClient.swift` → `GenerateRequest.bannedStrings`. The model never emits these phrases; the sampler backtracks if it tries. Seeded list curated from common "AI-tells" — *"eyes glinted with mischief,"* *"a shiver ran down her spine,"* etc.

## 7. Per-call instruction (one-shot steering)

The editor's generation tray exposes a single-line **"Instruction"** input under the Continue/Expand buttons. Its content lands in `perCallInstruction` layer at generation time (just before `modeInstruction`) — one-shot steering for the next generation only. Cleared after the generation fires.

Typical use:

- *"Make this dialogue-heavy."*
- *"End on a cliffhanger."*
- *"Mention the lighthouse."*

Roll-Outcome (§1 above) populates this tray with a rolled lorebook entry's content; user can edit or accept-as-is before firing Continue.

## 8. Generation log + acceptance UX

### 8.1 `GenerationLogEntry`

`Sources/LoomCore/Models/GenerationLog.swift` — one file per generation event at `generation-log/<iso-ts>.json`. Carries the full prompt assembly, the response, sampler snapshot, refusal flag, elapsed ms. See [`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md) §17 for the shape.

The **History inspector tab** pages over these files. Each entry expands to show the per-chiclet content (every layer's full text + token count). Useful for budget tuning and "why did the model say that."

### 8.2 Acceptance UX

Generated spans get visual treatment per `LOOM_DESIGN_LANGUAGE.md` §14.6:
- 6pt accent rule on the left of generated prose during pending state.
- Accept / Reject / Redo buttons in a floating tray near the inserted text.
- **Auto-accept on edit** — if the user types into a generated span, it's accepted; the rule disappears.
- The span persists in `Scene.generatedSpans` as a record (with `accepted: true/false` and the `promptLogPath` back-pointer) — the visual badge fades but the history is permanent.

## 9. References

- [`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md) §4.4 (Scene/GeneratedSpan/Snapshot), §4.5 (GenerationMode enum), §17 (GenerationLog).
- [`LOOM_STORY_BIBLE.md`](LOOM_STORY_BIBLE.md) §8 (assembled injection order — high-level companion to §2 here).
- [`LOOM_MEMORY.md`](LOOM_MEMORY.md) — conceptual architecture; this doc is the implementation reference.
- [`LOOM_NSFW.md`](LOOM_NSFW.md) §3 (WritingDirection layer), §3.5 (refusal detection + continuation).
- [`LOOM_SCENE_TEMPLATE.md`](LOOM_SCENE_TEMPLATE.md) + [`LOOM_SCENE_EXEMPLAR.md`](LOOM_SCENE_EXEMPLAR.md) — the L7 / L8 Scene-Template Generation path.
- [`LOOM_TECH_STACK.md`](LOOM_TECH_STACK.md) "LLM transport & generation" + "Structured extraction" — solved-problem registry.
- `Sources/LoomCore/Generation/PromptBuilder.swift` — the canonical implementation.
- `Sources/LoomCore/Generation/GenerationCoordinator.swift` — the async orchestration around it.

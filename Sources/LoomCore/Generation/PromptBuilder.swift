import Foundation

/// Inputs to a single prompt assembly.
public struct PromptContext {
    public var mode: GenerationMode
    public var project: Project
    public var scenes: [UUID: Scene]
    public var currentSceneId: UUID?
    public var cursorOffset: Int                 // NSString-offset into current scene's prose
    public var selectionRange: NSRange?
    /// If supplied and the project's `instructTemplate` is `.auto`, the
    /// model name is used to detect the right template; otherwise the
    /// project's explicit setting is honoured.
    public var modelName: String?
    public var contextBudgetTokens: Int
    public var replyBudgetTokens: Int
    /// One-shot ad-hoc steering for this generation only ("make it
    /// more dramatic", "first-person POV", "shorter please"). Layered
    /// just above the mode instruction so it lands close to the
    /// cursor (recency wins) without overriding the mode framing.
    /// Empty or nil → no layer added.
    public var perCallInstruction: String?

    public init(
        mode: GenerationMode,
        project: Project,
        scenes: [UUID: Scene],
        currentSceneId: UUID?,
        cursorOffset: Int,
        selectionRange: NSRange?,
        modelName: String?,
        contextBudgetTokens: Int,
        replyBudgetTokens: Int,
        perCallInstruction: String? = nil
    ) {
        self.mode = mode
        self.project = project
        self.scenes = scenes
        self.currentSceneId = currentSceneId
        self.cursorOffset = cursorOffset
        self.selectionRange = selectionRange
        self.modelName = modelName
        self.contextBudgetTokens = contextBudgetTokens
        self.replyBudgetTokens = replyBudgetTokens
        self.perCallInstruction = perCallInstruction
    }
}

/// Result of assembly. Carries the wrapped prompt for KoboldClient,
/// the structural pieces (system / user / prefill) for History, the
/// per-layer chiclets for transparency, the cache-boundary token
/// counts, and an eviction list when budget pressure trims layers.
public struct AssembledPrompt {
    public var fullPrompt: String
    public var stopSequences: [String]
    public var systemBlock: String
    public var userBlock: String
    public var prefill: String
    public var chiclets: [ContextChiclet]
    public var aboveCacheTokens: Int
    public var belowCacheTokens: Int
    public var totalTokens: Int { aboveCacheTokens + belowCacheTokens }
    public var evictedLayers: [String]
    public var template: InstructTemplate
}

/// Chiclet — labelled, tokenised slice of the assembled prompt for the
/// History inspector and generation log. Lives here (rather than the
/// data model) because it's a build-time artifact.
public struct ContextChiclet: Codable, Equatable {
    public var label: String
    public var sourceKind: ChicletKind
    public var sourceId: UUID?
    public var contentExcerpt: String
    public var fullContent: String
    public var tokenCount: Int

    public init(
        label: String,
        sourceKind: ChicletKind,
        sourceId: UUID? = nil,
        contentExcerpt: String,
        fullContent: String,
        tokenCount: Int
    ) {
        self.label = label
        self.sourceKind = sourceKind
        self.sourceId = sourceId
        self.contentExcerpt = contentExcerpt
        self.fullContent = fullContent
        self.tokenCount = tokenCount
    }
}

public enum ChicletKind: String, Codable, Equatable, CaseIterable {
    case system
    case projectMemory
    case styleSheet
    case projectSummary
    case chapterSummary
    case sceneSummary
    case bibleConstant
    case bibleKeyed
    case lorebookEntry
    case knowledgeLedger
    case recentProse
    case sceneAnchor
    case authorsNote
    case perCallInstruction
    case modeInstruction
    case fewShotStyleExample
}

// MARK: - Builder

public enum PromptBuilder {
    /// Assemble a prompt for the given context. Stateless; safe to call
    /// from any thread. Diagnostic logging is the caller's concern (the
    /// generation coordinator emits `[gen]` lines around the call) so
    /// PromptBuilder stays pure for testability.
    public static func build(_ context: PromptContext) -> AssembledPrompt {
        // Resolve template: explicit setting wins; .auto looks at modelName.
        let resolvedTemplate = resolveTemplate(
            explicit: context.project.settings.instructTemplate,
            modelName: context.modelName
        )
        let adapter = InstructTemplates.adapter(for: resolvedTemplate)

        // 1) Build candidate layers in display order. Each carries its
        //    own kind, content, token count, eviction priority, and
        //    above/below-cache flag.
        var layers = buildLayers(context)

        // 2) Fit to context budget. Reserve replyBudget for the model.
        //    Eviction targets non-mandatory below-cache layers first;
        //    recent-prose shrinks via re-extraction with a smaller
        //    budget rather than full eviction.
        let usableContextBudget = max(0, context.contextBudgetTokens - context.replyBudgetTokens)
        let evictedLayers = enforceBudget(&layers, budget: usableContextBudget, context: context)

        // 3) Render layered content into above/below-cache strings.
        //    Phase 1 keeps a chat-shaped structure (prose in user
        //    message, not prefill) because Qwen / Gemma instruct
        //    models are tuned to respond to user turns — putting
        //    prose in the assistant prefill makes them treat it as
        //    "my completed response" and emit <|im_end|> immediately,
        //    producing 0 tokens. (Confirmed live 2026-05-10.) The
        //    NovelAI/SillyTavern story-mode prefill pattern works
        //    for base / story-tuned models like Erato, not for
        //    instruct-tuned chat models. The anti-echo guarantee
        //    comes from the sharpened system prompt + an explicit
        //    "continue from here" instruction layer landing AFTER
        //    the prose (lower = stronger steering).
        let above = layers.filter { $0.aboveCache }
        let below = layers.filter { !$0.aboveCache }
        let systemBlock = above.map(\.content).filter { !$0.isEmpty }.joined(separator: "\n\n")
        let userBlock = below.map { $0.userBlockContent ?? $0.content }.filter { !$0.isEmpty }.joined(separator: "\n\n")

        // 4) Compute prefill: template-specific suppression only
        //    (`<think>\n\n</think>\n\n` for Qwen ChatML); empty for
        //    other templates.
        let prefill = prefillFor(template: resolvedTemplate, mode: context.mode)

        // 5) Wrap with the instruct-template adapter.
        let fullPrompt = adapter.wrap(system: systemBlock, userBody: userBlock, prefill: prefill)

        // 6) Build chiclets in display order (above first, below second).
        let chiclets: [ContextChiclet] = layers.map { layer in
            ContextChiclet(
                label: layer.label,
                sourceKind: layer.kind,
                sourceId: layer.sourceId,
                contentExcerpt: String(layer.content.prefix(200)),
                fullContent: layer.content,
                tokenCount: layer.tokens
            )
        }

        let aboveTokens = above.map(\.tokens).reduce(0, +)
        let belowTokens = below.map(\.tokens).reduce(0, +)

        return AssembledPrompt(
            fullPrompt: fullPrompt,
            stopSequences: adapter.stopSequences,
            systemBlock: systemBlock,
            userBlock: userBlock,
            prefill: prefill,
            chiclets: chiclets,
            aboveCacheTokens: aboveTokens,
            belowCacheTokens: belowTokens,
            evictedLayers: evictedLayers,
            template: resolvedTemplate
        )
    }

    // MARK: - Layer construction

    /// Internal layer struct. Public surface is `ContextChiclet`; this
    /// stays internal so layer mechanics aren't part of the API.
    struct Layer {
        var kind: ChicletKind
        var label: String
        var content: String
        /// If non-nil, used instead of `content` when joining the
        /// user-message block. Use case: the Author's Note layer
        /// when spliced into the recent-prose layer — we still
        /// want a chiclet (so set `content` to the AN bracket) but
        /// we don't want the bracket appearing twice in the
        /// assembled prompt (so set `userBlockContent` to "").
        var userBlockContent: String? = nil
        var tokens: Int
        var aboveCache: Bool
        var sourceId: UUID?
        /// Lower priority is evicted first. Mandatory layers have
        /// priority Int.max and are never evicted.
        var evictionPriority: Int
        var mandatory: Bool { evictionPriority == .max }
    }

    private static func buildLayers(_ context: PromptContext) -> [Layer] {
        var layers: [Layer] = []

        // ABOVE CACHE: System (per-mode), Project Memory, Style guide
        // (Phase 5; empty), Bible-Constant.

        let systemContent = systemPromptFor(mode: context.mode)
        layers.append(Layer(
            kind: .system,
            label: "System",
            content: systemContent,
            tokens: TokenEstimator.estimate(systemContent),
            aboveCache: true,
            sourceId: nil,
            evictionPriority: .max
        ))

        let memory = context.project.settings.memory
        if !memory.isEmpty {
            let formatted = "Project Memory:\n\(memory)"
            layers.append(Layer(
                kind: .projectMemory,
                label: "Project Memory",
                content: formatted,
                tokens: TokenEstimator.estimate(formatted),
                aboveCache: true,
                sourceId: nil,
                evictionPriority: .max
            ))
        }

        // Style guide — Phase 5; not wired yet.

        // Phase 2 #7 — split Bible into Constant (above-cache, always-on)
        // and Keyed (below-cache, activates only when the entity's
        // name/alias appears in the recent-prose window). The keyed
        // layer is built later, after we know what the recent-prose
        // window is; constant uses the static project state and lands
        // above the cache.
        let constantBibleText = formatBibleEntries(
            characters: context.project.bible.characters.filter { $0.injectionMode == .constant },
            settings: context.project.bible.settings.filter { $0.injectionMode == .constant },
            objects: context.project.bible.objects.filter { $0.injectionMode == .constant }
        )
        if !constantBibleText.isEmpty {
            let constantCount = context.project.bible.characters.filter { $0.injectionMode == .constant }.count
            layers.append(Layer(
                kind: .bibleConstant,
                label: "Cast (\(constantCount))",
                content: constantBibleText,
                tokens: TokenEstimator.estimate(constantBibleText),
                aboveCache: true,
                sourceId: nil,
                evictionPriority: 100
            ))
        }

        // BELOW CACHE: Recent-prose, Author's Note, Mode-instruction,
        // Cursor/Selection. (Current-scene anchor folded into AN per
        // the §A3 simplification for Phase 1.)

        // Recent prose + Author's Note. The AN is spliced INTO the
        // recent-prose content at `authorsNoteDepthLines` lines back
        // from the cursor (NovelAI A/N convention — lower in prompt
        // = stronger steering). We still record an Author's Note
        // chiclet for transparency, but it carries empty userBlock
        // content so the bracket doesn't appear twice in the
        // assembled prompt.
        let an = context.project.settings.authorsNote
        let depthLines = context.project.settings.authorsNoteDepthLines
        var recentProse = buildRecentProseLayer(context)

        // Phase 2 #7 — Bible-Keyed layer. The keyed entities activate
        // against the recent-prose window the model is about to see;
        // use the same extracted text so user expectations and the
        // matcher agree. Placed just above the (still-empty) recent-
        // prose layer slot — it sits below the cache boundary but
        // above the prose so it reads as "context the model needs to
        // know before reading the most-recent text."
        let matchProse = recentProse?.content ?? ""
        let activated = BibleInjector.activated(in: context.project, recentProse: matchProse)
        let keyedCharacters = activated.characters.filter { $0.injectionMode == .keyed }
        let keyedSettings = activated.settings.filter { $0.injectionMode == .keyed }
        let keyedObjects = activated.objects.filter { $0.injectionMode == .keyed }
        let keyedText = formatBibleEntries(
            characters: keyedCharacters,
            settings: keyedSettings,
            objects: keyedObjects
        )
        if !keyedText.isEmpty {
            let total = keyedCharacters.count + keyedSettings.count + keyedObjects.count
            layers.append(Layer(
                kind: .bibleKeyed,
                label: "Keyed entries (\(total))",
                content: keyedText,
                tokens: TokenEstimator.estimate(keyedText),
                aboveCache: false,
                sourceId: nil,
                // Lowish below-cache priority — keyed entries are
                // valuable but evicting them is preferable to losing
                // the recent prose itself.
                evictionPriority: 50
            ))
        }

        // Phase 2 #8 — Lorebook layer. Constant entries always; keyed
        // entries when at least one primary key matches AND every
        // secondary key matches (AND-gating per LOOM_DATA_MODEL.md
        // §3.6). Vectorised mode is Phase 5; LorebookActivator skips
        // it. Constant entries route above the cache (cache-stable);
        // keyed entries route below (recency-derived). Even though
        // the activator returns a single list, this split-routing
        // keeps prompt-cache hit rates high in projects that mix
        // both kinds.
        let activatedLore = LorebookActivator.activated(in: context.project, recentProse: matchProse)
        let constantLore = activatedLore.filter { $0.activationMode == .constant }
        let keyedLore = activatedLore.filter { $0.activationMode == .keyed }
        if !constantLore.isEmpty {
            let text = formatLorebookEntries(constantLore)
            layers.append(Layer(
                kind: .lorebookEntry,
                label: "Lore (constant, \(constantLore.count))",
                content: text,
                tokens: TokenEstimator.estimate(text),
                aboveCache: true,
                sourceId: nil,
                evictionPriority: 90
            ))
        }
        if !keyedLore.isEmpty {
            let text = formatLorebookEntries(keyedLore)
            layers.append(Layer(
                kind: .lorebookEntry,
                label: "Lore (keyed, \(keyedLore.count))",
                content: text,
                tokens: TokenEstimator.estimate(text),
                aboveCache: false,
                sourceId: nil,
                evictionPriority: 40
            ))
        }

        // Phase 4 #7 sub-task 7 — [KNOWLEDGE-LEDGER] layer. Renders the
        // POV character's KNOWS / DOES NOT KNOW blocks derived from
        // per-scene exposure (LedgerKnowledge.compute). Below the cache
        // boundary because the ledger changes whenever extraction adds
        // a fact or the user accepts a suggestion; keeping it below
        // means cache hit rates stay high across scenes that share the
        // same constant-bible above-cache content.
        //
        // Only rendered when the current scene has a POV character AND
        // there's at least one fact in either bucket — an empty layer
        // would just waste tokens.
        if let currentSceneId = context.currentSceneId,
           let currentScene = context.scenes[currentSceneId],
           let povId = currentScene.pov,
           let povCharacter = context.project.bible.characters.first(where: { $0.id == povId }) {
            let knowledge = LedgerKnowledge.compute(
                characterId: povId,
                asOfSceneId: currentSceneId,
                in: context.project,
                scenes: context.scenes
            )
            if !knowledge.knows.isEmpty || !knowledge.unknowns.isEmpty {
                let text = formatKnowledgeLedger(
                    povName: povCharacter.name,
                    knows: knowledge.knows,
                    unknowns: knowledge.unknowns
                )
                layers.append(Layer(
                    kind: .knowledgeLedger,
                    label: "Knowledge ledger (\(povCharacter.name))",
                    content: text,
                    tokens: TokenEstimator.estimate(text),
                    aboveCache: false,
                    sourceId: povId,
                    // Higher than bible-keyed (50) — the ledger is the
                    // distinctive engineering and POV consistency depends
                    // on it. Lower than .max so heavy budget pressure can
                    // still drop it before the prose itself.
                    evictionPriority: 70
                ))
            }
        }

        let trimmedAN = an.trimmingCharacters(in: .whitespacesAndNewlines)
        let willInjectAN = !trimmedAN.isEmpty && recentProse != nil && depthLines > 0
        if willInjectAN, var proseLayer = recentProse {
            let spliced = AuthorsNoteInjector.inject(
                authorsNote: trimmedAN,
                into: proseLayer.content,
                depthLines: depthLines
            )
            proseLayer.content = spliced
            proseLayer.tokens = TokenEstimator.estimate(spliced)
            recentProse = proseLayer
        }
        if let layer = recentProse {
            layers.append(layer)
        }
        if !trimmedAN.isEmpty {
            let bracket = "[\(trimmedAN)]"
            if willInjectAN {
                // AN already inside the prose — chiclet-only layer.
                layers.append(Layer(
                    kind: .authorsNote,
                    label: "Author's Note (spliced)",
                    content: bracket,
                    userBlockContent: "",
                    tokens: 0,
                    aboveCache: false,
                    sourceId: nil,
                    evictionPriority: .max
                ))
            } else {
                // Fallback: no recent prose to splice into, or
                // depthLines == 0. Keep the legacy "AN as own layer"
                // path so the AN still reaches the model.
                layers.append(Layer(
                    kind: .authorsNote,
                    label: "Author's Note",
                    content: bracket,
                    tokens: TokenEstimator.estimate(bracket),
                    aboveCache: false,
                    sourceId: nil,
                    evictionPriority: .max
                ))
            }
        }

        // Per-call instruction — one-shot ad-hoc steering for this
        // generation only, e.g. "make it more dramatic" or
        // "first-person POV". Lands just above the mode instruction
        // so it sits in the recency-strong slot without overriding
        // the mode framing itself.
        let perCall = (context.perCallInstruction ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !perCall.isEmpty {
            let formatted = "Per-call instruction: \(perCall)"
            layers.append(Layer(
                kind: .perCallInstruction,
                label: "Per-call instruction",
                content: formatted,
                tokens: TokenEstimator.estimate(formatted),
                aboveCache: false,
                sourceId: nil,
                evictionPriority: .max
            ))
        }

        // Mode-instruction lands LAST in the user message so it's the
        // closest signal to the assistant generation marker — the
        // recency-bias rule ("lower in prompt = stronger") concentrates
        // the steering at the cursor. For Continue this is the
        // explicit anti-echo "continue from here" cue; for Expand it's
        // the "Sketch to expand:" framing.
        let modeInstr = modeInstructionFor(mode: context.mode, context: context)
        if !modeInstr.isEmpty {
            layers.append(Layer(
                kind: .modeInstruction,
                label: "Mode instruction",
                content: modeInstr,
                tokens: TokenEstimator.estimate(modeInstr),
                aboveCache: false,
                sourceId: nil,
                evictionPriority: .max
            ))
        }

        return layers
    }

    private static func buildRecentProseLayer(_ context: PromptContext) -> Layer? {
        guard let id = context.currentSceneId, let scene = context.scenes[id] else { return nil }
        let prose = scene.prose
        if prose.isEmpty { return nil }

        // Token budget for recent prose follows LOOM_GENERATION_MODES.md
        // §1.2 — the largest below-cache slot. The default is roughly
        // 50% of the context budget (3000/8192, 6000/16384). Convert to
        // a char budget via the inverse of TokenEstimator.
        let proseTokenBudget = max(200, context.contextBudgetTokens / 2)
        let proseCharBudget = proseTokenBudget * 4

        let extracted = RecentProseWindow.extract(
            from: prose,
            cursorOffset: context.cursorOffset,
            charBudget: proseCharBudget
        )
        if extracted.isEmpty { return nil }

        return Layer(
            kind: .recentProse,
            label: "Recent prose",
            content: extracted,
            tokens: TokenEstimator.estimate(extracted),
            aboveCache: false,
            sourceId: id,
            // Mandatory: the prose IS the continuation context. Without
            // it, Continue is meaningless. PromptBuilder shrinks the
            // window via re-extract under budget pressure (see
            // enforceBudget) but never evicts the layer entirely.
            evictionPriority: .max
        )
    }

    // MARK: - Budget enforcement

    /// Trim layers in place until total tokens fit `budget`. Strategy:
    /// 1. If we're already under budget, no-op.
    /// 2. Drop non-mandatory below-cache layers in lowest-priority order.
    /// 3. If still over, shrink recent-prose by re-extracting at a
    ///    smaller char budget.
    /// 4. Drop non-mandatory above-cache layers (Bible constants are
    ///    the only Phase 1 candidate).
    /// Returns the list of evicted layer kinds (as raw-value strings),
    /// for the History tab and `[gen] cache` log line.
    private static func enforceBudget(
        _ layers: inout [Layer],
        budget: Int,
        context: PromptContext
    ) -> [String] {
        var evicted: [String] = []

        func currentTotal() -> Int {
            layers.map(\.tokens).reduce(0, +)
        }

        // Step 1: drop non-mandatory below-cache layers.
        while currentTotal() > budget,
              let dropIdx = layers.indices
                .filter({ !layers[$0].aboveCache && !layers[$0].mandatory })
                .min(by: { layers[$0].evictionPriority < layers[$1].evictionPriority })
        {
            evicted.append(layers[dropIdx].kind.rawValue)
            layers.remove(at: dropIdx)
        }

        // Step 2: shrink recent-prose by re-extracting smaller windows.
        while currentTotal() > budget,
              let proseIdx = layers.firstIndex(where: { $0.kind == .recentProse })
        {
            let layer = layers[proseIdx]
            guard layer.tokens > 50 else { break }   // already minimal
            // Halve the char budget and re-extract.
            let newCharBudget = max(200, layer.content.count / 2)
            guard let id = context.currentSceneId, let scene = context.scenes[id] else { break }
            let extracted = RecentProseWindow.extract(
                from: scene.prose,
                cursorOffset: context.cursorOffset,
                charBudget: newCharBudget
            )
            if extracted == layer.content { break }
            layers[proseIdx].content = extracted
            layers[proseIdx].tokens = TokenEstimator.estimate(extracted)
            if !evicted.contains("recentProse") {
                evicted.append("recentProse")    // mark as shrunk
            }
        }

        // Step 3: drop non-mandatory above-cache layers if still over.
        while currentTotal() > budget,
              let dropIdx = layers.indices
                .filter({ layers[$0].aboveCache && !layers[$0].mandatory })
                .min(by: { layers[$0].evictionPriority < layers[$1].evictionPriority })
        {
            evicted.append(layers[dropIdx].kind.rawValue)
            layers.remove(at: dropIdx)
        }

        return evicted
    }

    // MARK: - Mode-specific content

    private static func systemPromptFor(mode: GenerationMode) -> String {
        switch mode {
        case .continueProse:
            return """
            You are a fiction writer continuing an existing manuscript. You will be given prose; pick up exactly where it ends and write the next ~500 words of the scene. Maintain voice, tense, POV, and tone exactly as established. Do NOT restate, paraphrase, or quote any of the preceding prose — your output begins on the very next character that follows it. Do not summarize, do not break narrative voice, do not introduce meta-commentary or chapter headings. End at a natural pause (paragraph break, scene beat, or sentence boundary).
            """
        case .expand:
            return """
            You are a fiction writer expanding a sketch into prose. The selection below is a draft outline — beats, fragments, or a sparse paragraph that the author wants fleshed out. Expand it into full prose that:
            - Preserves every beat in the sketch (do not skip, do not invent missing plot)
            - Matches the voice/tense/POV of the surrounding manuscript
            - Adds sensory detail, dialogue, and interiority appropriate to the scene
            - Does not include meta-commentary or markdown headers
            """
        case .rewrite:
            return """
            You are a fiction writer rewriting an existing passage. The selection below is finished prose that the author wants reshaped — same beats and same meaning, but stronger word choice, tighter rhythm, or sharper voice. Rewrite it as full prose that:
            - Preserves every beat and every named entity from the original (do not skip, do not invent)
            - Matches the voice/tense/POV of the surrounding manuscript
            - Roughly matches the original length (±25%); do not summarise or balloon
            - Does not include meta-commentary, prefaces ("here is the rewrite:"), or markdown headers
            """
        case .rewriteVoice:
            // Phase 4 §14.1 #1 / LOOM_GENERATION_MODES.md §4.1.
            // Target-voice descriptor is carried separately via the
            // per-call instruction layer; the system prompt only
            // commits to *what kind* of rewrite this is.
            return """
            You are a fiction writer rewriting an existing passage in a different voice. The selection below is finished prose. Rewrite it in the target voice supplied by the author, while preserving everything else about the passage. The rewrite must:
            - Preserve every plot beat, dialogue beat, and named entity from the original (do not skip, do not invent events)
            - Match the manuscript's tense and POV exactly
            - Stay roughly the same length as the original (±20%); do not summarise or balloon
            - Does not include meta-commentary, prefaces ("here is the rewrite:"), or markdown headers
            """
        case .rewriteTense:
            // Phase 4 §14.1 #6 / LOOM_GENERATION_MODES.md §4.2.
            // Target-tense descriptor ("past" / "present" / freeform)
            // rides on `perCallInstruction`; system prompt only commits
            // to what kind of rewrite this is.
            return """
            You are a fiction writer rewriting an existing passage in a different tense. The selection below is finished prose. Rewrite it in the target tense supplied by the author, while preserving everything else about the passage. The rewrite must:
            - Preserve every plot beat, dialogue beat, and named entity from the original (do not skip, do not invent events)
            - Match the manuscript's voice and POV exactly
            - Stay roughly the same length as the original (±20%); do not summarise or balloon
            - Keep dialogue verbatim where natural; only adjust speech tags + interiority for tense consistency
            - Does not include meta-commentary, prefaces ("here is the rewrite:"), or markdown headers
            """
        case .rewriteLength:
            // Phase 4 §14.1 #6 / LOOM_GENERATION_MODES.md §4.4.
            // Target-length descriptor ("50%" / "80%" / "120%" / "150%"
            // / freeform) rides on `perCallInstruction`.
            return """
            You are a fiction writer rewriting an existing passage at a different length. The selection below is finished prose. Rewrite it at the target length supplied by the author, preserving everything else about the passage. The rewrite must:
            - Preserve every plot beat, dialogue beat, and named entity from the original (do not skip, do not invent events)
            - Match the manuscript's voice, tense, and POV exactly
            - Adjust through expanded sensory detail and interiority (when growing) OR tightened phrasing and trimmed transitions (when shrinking) — never by changing what happens
            - Does not include meta-commentary, prefaces ("here is the rewrite:"), or markdown headers
            """
        case .rewritePOV:
            // Phase 4 §14.1 #8 / LOOM_GENERATION_MODES.md §4.3.
            // Target-POV descriptor is the structured hint string
            // produced by `RewritePOVDescriptor.build(...)` —
            // includes the target character's name + person + a
            // KNOWS / DOES NOT KNOW bullet list sourced from
            // `LedgerKnowledge.compute`. The system prompt commits
            // to the swap shape; the descriptor on
            // `perCallInstruction` constrains what the new POV
            // character has access to.
            return """
            You are a fiction writer rewriting an existing passage from a different POV (point of view). The selection below is finished prose. Rewrite it from the target POV supplied by the author. The rewrite must:
            - Preserve every plot beat, dialogue beat, and named entity from the original (do not skip, do not invent events)
            - Match the manuscript's voice and tense exactly; only the POV character changes
            - Stay roughly the same length as the original (±20%); do not summarise or balloon
            - Adjust interiority so the new POV character only registers what they could plausibly know, see, or feel — do not invent thoughts, knowledge, or perceptions the character has not been exposed to (the per-call instruction below lists what they know and don't know as of this scene)
            - Does not include meta-commentary, prefaces ("here is the rewrite:"), or markdown headers
            """
        default:
            // Phase 4+ modes; PromptBuilder still produces something
            // sensible if invoked early.
            return "You are a fiction writer assisting an author."
        }
    }

    private static func modeInstructionFor(mode: GenerationMode, context: PromptContext) -> String {
        switch mode {
        case .continueProse:
            // Explicit terminal instruction for chat-shaped instruct
            // models: lands AFTER the prose in the user message so
            // the recency-bias rule ("lower = stronger") concentrates
            // the steering at the cursor. Without this, Qwen 3.x
            // treats the prose as a passage to comment on / quote
            // back, and prefixes its continuation with a verbatim
            // echo of the opening sentence (confirmed live 2026-05-10).
            return "—— Continue from immediately after the last word above. Output only the next ~500 words of prose. Do not restate, paraphrase, or quote any of the passage above."
        case .expand:
            // Frame the selection as the sketch.
            guard let selection = selectionText(in: context) else { return "" }
            return "Sketch to expand:\n\(selection)"
        case .rewrite:
            // Frame the selection as the passage to reshape.
            guard let selection = selectionText(in: context) else { return "" }
            return "Passage to rewrite:\n\(selection)\n\n—— Output the rewritten passage only. No preface, no commentary, no quotation marks around it."
        case .rewriteVoice:
            // Phase 4 §14.1 #1. The descriptor (target voice) rides
            // on `perCallInstruction` and is emitted by its own layer
            // just above this one — see the existing per-call
            // instruction injector. So the mode instruction itself
            // just frames the task and the passage.
            guard let selection = selectionText(in: context) else { return "" }
            return "Passage to rewrite in a new voice:\n\(selection)\n\n—— Output the rewritten passage only, in the target voice. No preface, no commentary, no quotation marks around it."
        case .rewriteTense:
            // Phase 4 §14.1 #6. Target-tense descriptor rides on
            // `perCallInstruction`; mode instruction frames the task
            // and the passage.
            guard let selection = selectionText(in: context) else { return "" }
            return "Passage to rewrite in a new tense:\n\(selection)\n\n—— Output the rewritten passage only, in the target tense. No preface, no commentary, no quotation marks around it."
        case .rewriteLength:
            // Phase 4 §14.1 #6. Target-length descriptor rides on
            // `perCallInstruction`; mode instruction frames the task
            // and the passage.
            guard let selection = selectionText(in: context) else { return "" }
            return "Passage to rewrite at a new length:\n\(selection)\n\n—— Output the rewritten passage only, at the target length. No preface, no commentary, no quotation marks around it."
        case .rewritePOV:
            // Phase 4 §14.1 #8. Target-POV descriptor (target name,
            // person, KNOWS / DOES NOT KNOW buckets) rides on
            // `perCallInstruction`; mode instruction frames the task
            // and the passage.
            guard let selection = selectionText(in: context) else { return "" }
            return "Passage to rewrite from a new POV:\n\(selection)\n\n—— Output the rewritten passage only, from the target POV. No preface, no commentary, no quotation marks around it."
        default:
            return ""
        }
    }

    /// Pull the selected substring out of the current scene's prose
    /// using `context.selectionRange`. Returns nil if there's no
    /// selection or the active scene can't be located. Bounds-clamps
    /// the range so we never crash on stale offsets.
    private static func selectionText(in context: PromptContext) -> String? {
        guard let range = context.selectionRange,
              let id = context.currentSceneId,
              let scene = context.scenes[id]
        else { return nil }
        let nsProse = scene.prose as NSString
        let safeRange = NSRange(
            location: max(0, min(range.location, nsProse.length)),
            length: max(0, min(range.length, nsProse.length - max(0, min(range.location, nsProse.length))))
        )
        return nsProse.substring(with: safeRange)
    }

    /// Phase 2 #7 — formats the Bible slice (already filtered to either
    /// constant or activated-keyed entities) into a prose blob the
    /// model can read. Empty input → empty string (caller decides
    /// whether to emit a layer at all).
    private static func formatBibleEntries(
        characters: [Character],
        settings: [Setting],
        objects: [BibleObject]
    ) -> String {
        var blocks: [String] = []
        if !characters.isEmpty {
            var out = "Cast:"
            for character in characters {
                out += "\n\n— \(character.name)"
                if !character.role.rawValue.isEmpty {
                    out += " (\(character.role.rawValue))"
                }
                if !character.oneLine.isEmpty {
                    out += ": \(character.oneLine)"
                }
                if !character.description.isEmpty {
                    out += "\n\(character.description)"
                }
            }
            blocks.append(out)
        }
        if !settings.isEmpty {
            var out = "Places:"
            for setting in settings {
                out += "\n\n— \(setting.name)"
                if !setting.description.isEmpty {
                    out += "\n\(setting.description)"
                }
                if !setting.sensoryNotes.isEmpty {
                    out += "\n(\(setting.sensoryNotes))"
                }
            }
            blocks.append(out)
        }
        if !objects.isEmpty {
            var out = "Objects:"
            for object in objects {
                out += "\n\n— \(object.name)"
                if !object.description.isEmpty {
                    out += "\n\(object.description)"
                }
                if !object.significance.isEmpty {
                    out += "\n(significance: \(object.significance))"
                }
            }
            blocks.append(out)
        }
        return blocks.joined(separator: "\n\n")
    }

    /// Phase 2 #8 — formats activated lorebook entries into a prose
    /// blob. Entry name + content; name elided when content already
    /// reads as a complete thought.
    private static func formatLorebookEntries(_ entries: [LorebookEntry]) -> String {
        var out = "Lore:"
        for entry in entries {
            out += "\n\n— \(entry.name)"
            if !entry.content.isEmpty {
                out += "\n\(entry.content)"
            }
        }
        return out
    }

    /// Phase 4 #7 sub-task 7 — render the `[KNOWLEDGE-LEDGER]` block.
    /// Format per LOOM_GENERATION_MODES.md §11. Each sub-block (KNOWS,
    /// DOES NOT KNOW) is omitted when its bucket is empty so an
    /// empty bullet list never reaches the model.
    private static func formatKnowledgeLedger(
        povName: String,
        knows: [KnownFact],
        unknowns: [KnownFact]
    ) -> String {
        var out = "[KNOWLEDGE-LEDGER]"
        if !knows.isEmpty {
            out += "\n\(povName) knows the following as of this scene:"
            for fact in knows {
                out += "\n- \(fact.fact)"
            }
        }
        if !unknowns.isEmpty {
            if !knows.isEmpty { out += "\n" }
            out += "\n\(povName) does NOT know:"
            for fact in unknowns {
                out += "\n- \(fact.fact)"
            }
        }
        return out
    }

    // MARK: - Template resolution + prefill

    private static func resolveTemplate(
        explicit: InstructTemplate,
        modelName: String?
    ) -> InstructTemplate {
        if explicit != .auto { return explicit }
        if let name = modelName, let detected = InstructTemplates.detect(forModelName: name) {
            return detected
        }
        return .raw
    }

    /// ChatML-family models (notably Qwen 3.x) default to think-mode
    /// ON. For story-mode prose continuation we need to suppress the
    /// reasoning trace by prefilling the assistant turn with a closed
    /// `<think></think>` block. This is exactly the prefix that
    /// `enable_thinking=false` injects in Qwen's chat-template Jinja.
    private static func prefillFor(template: InstructTemplate, mode: GenerationMode) -> String {
        switch template {
        case .chatml:
            return "<think>\n\n</think>\n\n"
        default:
            return ""
        }
    }
}

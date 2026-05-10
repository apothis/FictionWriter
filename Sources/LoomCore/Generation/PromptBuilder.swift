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

    public init(
        mode: GenerationMode,
        project: Project,
        scenes: [UUID: Scene],
        currentSceneId: UUID?,
        cursorOffset: Int,
        selectionRange: NSRange?,
        modelName: String?,
        contextBudgetTokens: Int,
        replyBudgetTokens: Int
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
    case knowledgeLedger
    case recentProse
    case sceneAnchor
    case authorsNote
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
        let above = layers.filter { $0.aboveCache }
        let below = layers.filter { !$0.aboveCache }
        let systemBlock = above.map(\.content).filter { !$0.isEmpty }.joined(separator: "\n\n")
        let userBlock = below.map(\.content).filter { !$0.isEmpty }.joined(separator: "\n\n")

        // 4) Compute prefill (Qwen 3.x think-mode suppression for
        //    ChatML; empty everywhere else).
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

        let bibleConstant = formatBibleConstant(context.project.bible)
        if !bibleConstant.isEmpty {
            layers.append(Layer(
                kind: .bibleConstant,
                label: "Cast (\(context.project.bible.characters.count))",
                content: bibleConstant,
                tokens: TokenEstimator.estimate(bibleConstant),
                aboveCache: true,
                sourceId: nil,
                evictionPriority: 100
            ))
        }

        // BELOW CACHE: Recent-prose, Author's Note, Mode-instruction,
        // Cursor/Selection. (Current-scene anchor folded into AN per
        // the §A3 simplification for Phase 1.)

        let recentProse = buildRecentProseLayer(context)
        if let layer = recentProse {
            layers.append(layer)
        }

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

        let an = context.project.settings.authorsNote
        if !an.isEmpty {
            // Bracketed convention from AI Dungeon / web-fiction model
            // prior. For Phase 1 the current-scene anchor is folded
            // into the AN (per §A3 simplification).
            let formatted = "[\(an)]"
            layers.append(Layer(
                kind: .authorsNote,
                label: "Author's Note",
                content: formatted,
                tokens: TokenEstimator.estimate(formatted),
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
            You are a fiction writer continuing an existing manuscript. Maintain voice, tense, POV, and tone exactly as established in the preceding text. Continue the scene naturally — do not summarize, do not break narrative voice, do not introduce meta-commentary. End at a natural pause (paragraph break, scene beat, or sentence boundary).
            """
        case .expand:
            return """
            You are a fiction writer expanding a sketch into prose. The selection below is a draft outline — beats, fragments, or a sparse paragraph that the author wants fleshed out. Expand it into full prose that:
            - Preserves every beat in the sketch (do not skip, do not invent missing plot)
            - Matches the voice/tense/POV of the surrounding manuscript
            - Adds sensory detail, dialogue, and interiority appropriate to the scene
            - Does not include meta-commentary or markdown headers
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
            // For Continue, the cursor position itself is the
            // instruction — model continues from where the prose ends.
            // No separate mode instruction needed.
            return ""
        case .expand:
            // Frame the selection as the sketch.
            guard let range = context.selectionRange,
                  let id = context.currentSceneId,
                  let scene = context.scenes[id]
            else { return "" }
            let nsProse = scene.prose as NSString
            let safeRange = NSRange(
                location: max(0, min(range.location, nsProse.length)),
                length: max(0, min(range.length, nsProse.length - max(0, min(range.location, nsProse.length))))
            )
            let selection = nsProse.substring(with: safeRange)
            return "Sketch to expand:\n\(selection)"
        default:
            return ""
        }
    }

    private static func formatBibleConstant(_ bible: Bible) -> String {
        guard !bible.characters.isEmpty else { return "" }
        var out = "Cast:"
        for character in bible.characters {
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

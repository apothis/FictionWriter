import Foundation

/// Orchestrates a single Continue/Expand generation: assemble the prompt
/// via PromptBuilder, fire the kobold streaming request, marshal token
/// callbacks to main, and surface lifecycle events as notifications the
/// editor + history tab can subscribe to.
///
/// One coordinator per editor. Owns the kobold client and the active
/// generation's running insertion offset. Cancellation is best-effort:
/// the kobold client's `cancel()` aborts the URLSession task and POSTs
/// `/api/extra/abort` to the server.
public final class GenerationCoordinator {
    public let session: ProjectSession
    public let registry: KoboldClientRegistry

    /// Posted when a generation starts. Object is the coordinator.
    public static let didStartNotification = Notification.Name("LoomGenerationCoordinator.didStart")
    /// Posted on every streamed token. userInfo: `["token": String, "insertionOffset": Int]`.
    public static let didEmitTokenNotification = Notification.Name("LoomGenerationCoordinator.didEmitToken")
    /// Posted on finish (success, cancel, or error). userInfo:
    /// `["error": Error?, "insertedRange": NSRange, "elapsedMs": Int]`.
    public static let didFinishNotification = Notification.Name("LoomGenerationCoordinator.didFinish")

    public private(set) var isGenerating: Bool = false
    /// Where the next token should be inserted in the active scene's
    /// prose. Starts at the cursor offset; advances by token length on
    /// each emit.
    public private(set) var insertionOffset: Int = 0
    /// Text accumulated this generation (for the inserted-range
    /// reporting on finish).
    public private(set) var insertedText: String = ""
    private var generationStartedAt: Date = .distantPast
    private var generationStartOffset: Int = 0
    private var activeClient: KoboldClient?

    public init(session: ProjectSession, registry: KoboldClientRegistry) {
        self.session = session
        self.registry = registry
    }

    // MARK: - Lifecycle

    /// Start a generation. Cancels any in-flight generation first. Mode
    /// must be `.continueProse` or `.expand` in Phase 1; other modes
    /// are accepted but follow the Continue path until 1.j+ adds them.
    public func start(
        mode: GenerationMode,
        cursorOffset: Int,
        selectionRange: NSRange?
    ) {
        cancel()

        guard let sceneId = session.currentSceneId else {
            DebugLog.shared.write("[gen] start aborted: no current scene")
            return
        }

        // Build the prompt. PromptBuilder is pure; no network yet.
        let context = PromptContext(
            mode: mode,
            project: session.project,
            scenes: session.scenes,
            currentSceneId: sceneId,
            cursorOffset: cursorOffset,
            selectionRange: selectionRange,
            modelName: nil, // probed lazily later; explicit template wins
            contextBudgetTokens: session.project.settings.contextBudgetTokens,
            replyBudgetTokens: session.project.settings.generationDefaults.maxOutputTokens
        )
        let assembled = PromptBuilder.build(context)

        // Diagnostic logs from day 1 (LOOM_MEMORY.md §7.2).
        DebugLog.shared.write(
            "[gen] \(mode.rawValue): ctx=\(assembled.totalTokens) reply=\(context.replyBudgetTokens) above-cache=\(assembled.aboveCacheTokens) below-cache=\(assembled.belowCacheTokens) template=\(assembled.template.rawValue)"
        )
        if !assembled.evictedLayers.isEmpty {
            DebugLog.shared.write(
                "[gen] cache: above=\(assembled.aboveCacheTokens) below=\(assembled.belowCacheTokens) evicted=\(assembled.evictedLayers.joined(separator: ","))"
            )
        }
        DebugLog.shared.write(
            "[gen] recent-prose-window: chars=\(assembled.userBlock.count) tokens=\(assembled.belowCacheTokens) from-cursor=\(cursorOffset)"
        )

        // Wire sampler params from project's GenerationDefaults.
        let params = makeSamplerParams(from: session.project.settings.generationDefaults)
        let request = GenerateRequest(
            prompt: assembled.fullPrompt,
            stopSequences: assembled.stopSequences,
            params: params,
            maxContextLength: session.project.settings.contextBudgetTokens,
            maxLengthOverride: session.project.settings.generationDefaults.maxOutputTokens
        )

        // Resolve client + kick off the stream. KoboldClient's callbacks
        // arrive on a URLSession delegate queue; marshal to main here.
        let client = registry.client(forProfileId: session.project.settings.serverProfileId)
        activeClient = client

        isGenerating = true
        insertionOffset = cursorOffset
        generationStartOffset = cursorOffset
        insertedText = ""
        generationStartedAt = Date()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            NotificationCenter.default.post(name: Self.didStartNotification, object: self)
        }

        client.generateStream(
            request: request,
            onToken: { [weak self] token in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.handleToken(token)
                }
            },
            onFinish: { [weak self] error in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.handleFinish(error: error)
                }
            }
        )
    }

    public func cancel() {
        guard isGenerating else { return }
        activeClient?.cancel()
        // The cancel triggers onFinish via URLSession; isGenerating
        // stays true until handleFinish lands.
    }

    // MARK: - Internals

    private func handleToken(_ token: String) {
        guard isGenerating else { return }
        insertedText.append(token)
        let offsetForThisToken = insertionOffset
        insertionOffset += (token as NSString).length
        NotificationCenter.default.post(
            name: Self.didEmitTokenNotification,
            object: self,
            userInfo: ["token": token, "insertionOffset": offsetForThisToken]
        )
    }

    private func handleFinish(error: Error?) {
        guard isGenerating else { return }
        isGenerating = false
        let elapsedMs = Int(Date().timeIntervalSince(generationStartedAt) * 1000)
        let insertedRange = NSRange(
            location: generationStartOffset,
            length: (insertedText as NSString).length
        )
        if let error = error {
            DebugLog.shared.write("[gen] finish: error=\(error) elapsed=\(elapsedMs)ms inserted=\(insertedRange.length)")
        } else {
            DebugLog.shared.write("[gen] finish: ok elapsed=\(elapsedMs)ms inserted=\(insertedRange.length)")
        }
        var info: [AnyHashable: Any] = [
            "insertedRange": insertedRange,
            "elapsedMs": elapsedMs,
        ]
        if let error = error { info["error"] = error }
        NotificationCenter.default.post(
            name: Self.didFinishNotification,
            object: self,
            userInfo: info
        )
        activeClient = nil
    }

    /// Map Loom's user-facing GenerationDefaults to the kobold-API
    /// SamplerParams shape. Kept here (not on GenerationDefaults) so
    /// the model layer doesn't depend on the networking layer.
    private func makeSamplerParams(from defaults: GenerationDefaults) -> SamplerParams {
        SamplerParams(
            temperature: defaults.temperature,
            topP: 0.95,
            topK: defaults.topK,
            minP: defaults.minP,
            repPen: 1.07,
            repPenRange: 1024,
            maxLength: defaults.maxOutputTokens,
            samplerOrder: [6, 0, 1, 3, 4, 2, 5],
            dryMultiplier: defaults.dryMultiplier,
            dryBase: defaults.dryBase,
            dryAllowedLength: defaults.dryAllowedLength,
            xtcThreshold: defaults.xtcThreshold,
            xtcProbability: defaults.xtcProbability
        )
    }
}

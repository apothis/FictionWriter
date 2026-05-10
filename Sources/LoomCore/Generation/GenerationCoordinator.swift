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

    /// Posted after a generation-log entry has been persisted to disk.
    /// History inspector listens for this and reloads. userInfo:
    /// `["entry": GenerationLogEntry, "url": URL]`.
    public static let didWriteLogEntryNotification = Notification.Name("LoomGenerationCoordinator.didWriteLogEntry")

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
    /// Captured at start so the on-finish log write has the full
    /// assembled prompt + chiclets + cache bookkeeping (PromptBuilder
    /// is pure, but we don't call it twice; capture once).
    private var pendingAssembly: AssembledPrompt?
    private var pendingMode: GenerationMode = .continueProse
    private var pendingSceneId: UUID?
    private var pendingServerProfileId: UUID?
    private let logStore: GenerationLogStore

    public init(
        session: ProjectSession,
        registry: KoboldClientRegistry,
        logStore: GenerationLogStore = GenerationLogStore()
    ) {
        self.session = session
        self.registry = registry
        self.logStore = logStore
    }

    // MARK: - Lifecycle

    /// Start a generation. Cancels any in-flight generation first.
    /// Phase 1 supports `.continueProse` and `.expand`; Phase 1.5
    /// adds `.rewrite`. PromptBuilder is mode-aware; the coordinator
    /// itself is mode-agnostic.
    public func start(
        mode: GenerationMode,
        cursorOffset: Int,
        selectionRange: NSRange?,
        perCallInstruction: String? = nil
    ) {
        cancel()

        guard let sceneId = session.currentSceneId else {
            DebugLog.shared.write("[gen] start aborted: no current scene")
            return
        }

        // Build the prompt. PromptBuilder is pure; no network yet.
        // Pass the last-probed model name so `.auto` template detection
        // resolves against the live model (e.g. "Qwen3.6-..." → .chatml).
        let context = PromptContext(
            mode: mode,
            project: session.project,
            scenes: session.scenes,
            currentSceneId: sceneId,
            cursorOffset: cursorOffset,
            selectionRange: selectionRange,
            modelName: AppState.shared.lastProbedModelName,
            contextBudgetTokens: session.project.settings.contextBudgetTokens,
            replyBudgetTokens: session.project.settings.generationDefaults.maxOutputTokens,
            perCallInstruction: perCallInstruction
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

        // Resolve client + kick off the stream. The project's
        // serverProfileId overrides the global AppSettings default
        // (per-project servers are a Phase 2+ feature; Phase 1 just
        // wants "use whatever AppSettings says is default" when the
        // project doesn't override). KoboldClient's callbacks arrive
        // on a URLSession delegate queue; marshal to main here.
        let profileId = session.project.settings.serverProfileId
            ?? AppState.shared.settings.defaultServerId
        let client = registry.client(forProfileId: profileId)
        activeClient = client

        isGenerating = true
        insertionOffset = cursorOffset
        generationStartOffset = cursorOffset
        insertedText = ""
        generationStartedAt = Date()

        // Capture state needed at finish for the generation-log write.
        pendingAssembly = assembled
        pendingMode = mode
        pendingSceneId = sceneId
        pendingServerProfileId = session.project.settings.serverProfileId

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

        // Persist the generation-log entry. Skipped on error (no real
        // response) and on in-memory sessions (no URL to write to).
        if error == nil, let assembly = pendingAssembly,
           let sceneId = pendingSceneId,
           let projectURL = session.url
        {
            writeLogEntry(
                assembly: assembly,
                sceneId: sceneId,
                projectURL: projectURL,
                elapsedMs: elapsedMs
            )
        }

        pendingAssembly = nil
        pendingSceneId = nil
        pendingServerProfileId = nil
        activeClient = nil
    }

    private func writeLogEntry(
        assembly: AssembledPrompt,
        sceneId: UUID,
        projectURL: URL,
        elapsedMs: Int
    ) {
        let entry = GenerationLogEntry(
            sceneId: sceneId,
            mode: pendingMode,
            model: nil,    // model name probe is 1.m polish
            serverProfileId: pendingServerProfileId,
            promptAssembly: PromptAssembly(
                contextChiclets: assembly.chiclets,
                fullPrompt: assembly.fullPrompt,
                promptTokens: assembly.totalTokens,
                aboveCacheTokens: assembly.aboveCacheTokens,
                belowCacheTokens: assembly.belowCacheTokens,
                evictedLayers: assembly.evictedLayers,
                template: assembly.template
            ),
            response: GenerationResponse(
                rawText: insertedText,
                completionTokens: TokenEstimator.estimate(insertedText),
                stopReason: nil,
                refusalDetected: RefusalDetector.looksLikeRefusal(insertedText),
                elapsedMs: elapsedMs
            )
        )
        do {
            let url = try logStore.write(entry, in: projectURL)
            NotificationCenter.default.post(
                name: Self.didWriteLogEntryNotification,
                object: self,
                userInfo: ["entry": entry, "url": url]
            )
        } catch {
            DebugLog.shared.write("[gen] log-write failed: \(error)")
        }
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

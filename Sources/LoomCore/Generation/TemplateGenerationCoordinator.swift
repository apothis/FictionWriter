import Foundation

/// Phase 7.b.4 — orchestrator for `.generateFromTemplate`-mode scenes.
///
/// Per-beat loop: loads the template scene's stored skeleton from
/// `<project>/templates/<id>.beats.json`, then fires M sequential
/// writer calls (one per beat) via the injected `KoboldGenerating`,
/// accumulating the generated prose into a rolling buffer. Each
/// beat's prose is emitted as a single `didEmitToken` event so the
/// existing editor token-inserter handles insertion verbatim — no
/// new wiring needed.
///
/// Distinct from `GenerationCoordinator`: this coordinator owns
/// per-beat state (currentBeatIndex, rolling prose buffer, cancel
/// flag) rather than single-prompt assembly state. Both coordinators
/// can run in parallel against the same session if needed — they
/// post under different notification names + scoped to their own
/// `object` identities.
///
/// Pinned in [`LOOM_SCENE_TEMPLATE.md`](../../../LOOM_SCENE_TEMPLATE.md)
/// §7.2 + §9 (7.b.4).
public final class TemplateGenerationCoordinator {
    public let session: ProjectSession
    public let writerResolver: (UUID?) -> KoboldGenerating
    /// Resolves the app-level default writer profile id, consulted
    /// when `session.project.settings.serverProfileId` is nil
    /// (typical for newly-created projects). Mirrors
    /// `GenerationCoordinator`'s `?? AppState.shared.settings.
    /// defaultServerId` chain — without this, the registry returned
    /// its localhost sentinel and beat 0 failed with `Could not
    /// connect to the server`.
    ///
    /// Default `{ nil }` so existing test call sites don't have to
    /// pass it (they preserve the previous "no fallback" behaviour).
    public let appDefaultProfileIdProvider: () -> UUID?
    /// Phase 8.b.4 — per-beat style retriever closure. Called once per
    /// beat with the query produced by `BeatRetrievalQuery.build`; the
    /// returned exemplars feed into `BeatGeneration.buildBeatPrompt`'s
    /// `styleExemplars:` parameter. nil → no retrieval (Phase 7
    /// behaviour preserved). Wired by AppState at project-open to a
    /// closure over the project's `RetrievalService` (the same shape
    /// as `GenerationCoordinator.styleRetriever`).
    public let styleRetriever: ((_ query: String) -> [StyleExemplar])?
    private let logStore: GenerationLogStore

    /// Posted when a template generation starts. Object is `self`.
    public static let didStartNotification = Notification.Name("LoomTemplateGenerationCoordinator.didStart")
    /// Posted once per beat. `userInfo: ["token": String, "insertionOffset": Int, "beatIndex": Int]`.
    /// Reuses the `GenerationCoordinator.didEmitToken` userInfo shape
    /// so the editor's existing token-inserter logic is verbatim-
    /// reusable on this notification too.
    public static let didEmitTokenNotification = Notification.Name("LoomTemplateGenerationCoordinator.didEmitToken")
    /// Posted on finish (success, cancel, or error). `userInfo:
    /// ["insertedRange": NSRange, "elapsedMs": Int, "beatCount": Int,
    /// "cancelled": Bool, "error": Error?]`.
    public static let didFinishNotification = Notification.Name("LoomTemplateGenerationCoordinator.didFinish")
    /// Phase 7.b followup — posted after a `GenerationLogEntry` is
    /// persisted to `<project>/generation-log/`. `userInfo:
    /// ["entry": GenerationLogEntry, "url": URL]`. The History
    /// inspector listens for this same shape from `GenerationCoordinator`;
    /// adding it here gives template gens parity with Continue.
    public static let didWriteLogEntryNotification = Notification.Name("LoomTemplateGenerationCoordinator.didWriteLogEntry")

    public private(set) var isGenerating: Bool = false
    public private(set) var currentBeatIndex: Int = 0
    public private(set) var totalBeatCount: Int = 0
    public private(set) var insertionOffset: Int = 0
    public private(set) var insertedText: String = ""
    /// Most recent stop-sequence set passed to the writer — exposed
    /// for test assertion of punchlist item 2 (no bare `[` prefix).
    public private(set) var lastStopSequences: [String] = []

    private var generationStartedAt: Date = .distantPast
    private var generationStartOffset: Int = 0
    private var cancelled: Bool = false
    private var pendingSceneId: UUID?
    private var pendingTemplateId: UUID?
    private var pendingSkeleton: ExtractedSceneSkeleton?
    private var pendingCastMapping: String = ""
    private var pendingPacing: PacingStats = .zero
    private var pendingTemplateBody: String = ""
    private var pendingTemplateName: String = ""
    /// Phase 8.b.8 — per-invocation D4 soft toggle. Default-off
    /// preserves Phase 7 strict-prompt behaviour. Flipped on by the
    /// Write-From-Template menu's "imitate content" affordance.
    private var pendingImitateContent: Bool = false
    /// Captured per-beat for the generation-log entry. Each entry is
    /// the full prompt sent for that beat — so the History tab can
    /// show "what was sent" for each per-beat call, not just the
    /// final one.
    private var pendingBeatPrompts: [String] = []

    public init(
        session: ProjectSession,
        writerResolver: @escaping (UUID?) -> KoboldGenerating,
        appDefaultProfileIdProvider: @escaping () -> UUID? = { nil },
        logStore: GenerationLogStore = GenerationLogStore(),
        styleRetriever: ((_ query: String) -> [StyleExemplar])? = nil
    ) {
        self.session = session
        self.writerResolver = writerResolver
        self.appDefaultProfileIdProvider = appDefaultProfileIdProvider
        self.logStore = logStore
        self.styleRetriever = styleRetriever
    }

    // MARK: - Lifecycle

    /// Start a per-beat template generation. No-ops on stale template
    /// id, missing skeleton sidecar, or in-memory session with no
    /// current scene.
    public func start(
        templateId: UUID,
        castMapping: String,
        cursorOffset: Int,
        imitateContent: Bool = false
    ) {
        cancel()
        cancelled = false

        guard let projectURL = session.url else {
            DebugLog.shared.write("[template-gen] start aborted: in-memory session")
            return
        }
        guard let sceneId = session.currentSceneId else {
            DebugLog.shared.write("[template-gen] start aborted: no current scene")
            return
        }
        let template: TemplateScene
        do {
            template = try TemplateSceneStorage.loadTemplate(id: templateId, in: projectURL)
        } catch {
            DebugLog.shared.write("[template-gen] start aborted: template load failed id=\(templateId) error=\(error)")
            return
        }
        guard let skeleton = TemplateSceneStorage.loadSkeleton(for: templateId, in: projectURL) else {
            DebugLog.shared.write("[template-gen] start aborted: skeleton sidecar missing id=\(templateId) (was Extract run?)")
            return
        }
        guard !skeleton.beats.isEmpty else {
            DebugLog.shared.write("[template-gen] start aborted: skeleton has 0 beats id=\(templateId)")
            return
        }

        isGenerating = true
        currentBeatIndex = 0
        totalBeatCount = skeleton.beats.count
        insertionOffset = cursorOffset
        generationStartOffset = cursorOffset
        insertedText = ""
        generationStartedAt = Date()

        pendingSceneId = sceneId
        pendingTemplateId = templateId
        pendingSkeleton = skeleton
        pendingCastMapping = castMapping
        pendingTemplateBody = template.body
        pendingTemplateName = template.name
        pendingPacing = PacingStats.compute(text: template.body)
        pendingBeatPrompts = []
        pendingImitateContent = imitateContent

        DebugLog.shared.write("[template-gen] start id=\(templateId) beats=\(skeleton.beats.count) cursor=\(cursorOffset)")

        NotificationCenter.default.post(
            name: Self.didStartNotification,
            object: self,
            userInfo: [
                "templateId": templateId,
                "beatCount": skeleton.beats.count,
            ]
        )

        fireBeat(index: 0, retryAttemptsRemaining: 1)
    }

    public func cancel() {
        guard isGenerating else { return }
        cancelled = true
        // The in-flight beat's URLSession task can't be aborted
        // through KoboldGenerating (no cancel on the protocol). We
        // accept the last in-flight beat completing; the cancel
        // flag prevents the next beat from firing.
    }

    // MARK: - Per-beat loop

    private func fireBeat(index: Int, retryAttemptsRemaining: Int) {
        guard isGenerating, !cancelled else {
            finishGeneration(error: nil)
            return
        }
        guard let skeleton = pendingSkeleton else {
            finishGeneration(error: NSError(domain: "TemplateGen", code: -1, userInfo: [NSLocalizedDescriptionKey: "skeleton missing mid-generation"]))
            return
        }
        guard index < skeleton.beats.count else {
            finishGeneration(error: nil)
            return
        }

        currentBeatIndex = index
        let beat = skeleton.beats[index]
        // Phase 8.b.4 — per-beat retrieval. Build the query, ask the
        // retriever (if wired), pass the result into buildBeatPrompt.
        // nil retriever → empty exemplars → no [STYLE EXEMPLARS] block.
        let styleExemplars: [StyleExemplar]
        if let retrieve = styleRetriever {
            let query = BeatRetrievalQuery.build(
                beat: beat,
                castMapping: pendingCastMapping,
                priorBeatsProse: insertedText
            )
            styleExemplars = retrieve(query)
        } else {
            styleExemplars = []
        }
        let prompt = BeatGeneration.buildBeatPrompt(
            templateBody: pendingTemplateBody,
            skeleton: skeleton,
            castMapping: pendingCastMapping,
            currentBeatIndex: index,
            priorBeatsProse: insertedText,
            groundTruthPacing: pendingPacing,
            styleExemplars: styleExemplars,
            imitateContent: pendingImitateContent
        )
        // Capture per-beat prompt for the generation-log entry. Append
        // on the FIRST attempt of each beat (retries reuse the slot
        // rather than create duplicate entries).
        if retryAttemptsRemaining == 1 {
            pendingBeatPrompts.append(prompt)
        } else if let lastIdx = pendingBeatPrompts.indices.last {
            pendingBeatPrompts[lastIdx] = prompt
        }
        // Punchlist item 2 (§7.a.2): NO bare `[` in the stop list — the
        // model opens beats with `[silence]` / `[the protagonist…]`
        // patterns and a bare `[` triggered immediate empty completion.
        // The longer markers below catch genuine prompt-structure
        // echoes without false-positives on prose openings.
        // `[END` catches hallucinated end-markers like
        // `[END BEAT 7 PROSE]` the writer emits at the final beat
        // (mimicking the prompt's structural label shape). Narrower
        // than a bare `[` so prose bracketed openings still stream.
        let stops = ["=== END", "[BEAT SKELETON", "[INSTRUCTION", "[SYSTEM]", "[NEW CAST]", "[NEXT-BEAT HINT", "[END"]
        self.lastStopSequences = stops

        let params = SamplerParams(
            maxLength: max(64, beat.targetWords * 2)
        )

        let profileId = session.project.settings.serverProfileId
            ?? appDefaultProfileIdProvider()
        let writer = writerResolver(profileId)
        DebugLog.shared.write("[template-gen] beat \(index)/\(skeleton.beats.count - 1) (\(beat.modality.rawValue), \(beat.function.rawValue), target \(beat.targetWords)w)")

        writer.generate(
            prompt: prompt,
            stopSequences: stops,
            params: params,
            maxContextLength: session.project.settings.contextBudgetTokens,
            // KoboldClient's streaming overload marshals onToken +
            // completion to main itself, so we don't double-hop here.
            // Test stubs deliver synchronously on whatever queue
            // their `flush()` is called from.
            onToken: { [weak self] token in
                self?.handleStreamedToken(token, beatIndex: index)
            },
            completion: { [weak self] result in
                self?.handleBeatResult(
                    result: result,
                    beatIndex: index,
                    retryAttemptsRemaining: retryAttemptsRemaining
                )
            }
        )
    }

    /// Append a token to the rolling buffer + post didEmitToken with
    /// the offset where this token will land. Mirrors
    /// `GenerationCoordinator.handleToken`'s shape so the editor's
    /// insertion logic is identical for both coordinators.
    private func emitToken(_ token: String, beatIndex: Int) {
        guard isGenerating, !cancelled, !token.isEmpty else { return }
        let offset = insertionOffset
        insertedText += token
        insertionOffset += (token as NSString).length
        NotificationCenter.default.post(
            name: Self.didEmitTokenNotification,
            object: self,
            userInfo: [
                "token": token,
                "insertionOffset": offset,
                "beatIndex": beatIndex,
            ]
        )
    }

    private func handleStreamedToken(_ token: String, beatIndex: Int) {
        emitToken(token, beatIndex: beatIndex)
    }

    private func handleBeatResult(
        result: Result<String, Error>,
        beatIndex: Int,
        retryAttemptsRemaining: Int
    ) {
        guard isGenerating else { return }
        if cancelled {
            finishGeneration(error: nil)
            return
        }
        switch result {
        case .success(let raw):
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            // Punchlist item 3: empty output retries once. Streaming
            // means we can only retry safely when NO tokens were
            // emitted for this beat — `***`-only output would have
            // already landed in the editor as streamed tokens, and we
            // can't unwind that without a delete instruction (out of
            // scope). Empty-output retry stays.
            if trimmed.isEmpty, retryAttemptsRemaining > 0 {
                DebugLog.shared.write("[template-gen] beat \(beatIndex) returned empty output; retrying")
                fireBeat(index: beatIndex, retryAttemptsRemaining: retryAttemptsRemaining - 1)
                return
            }
            // Tokens were already emitted via the streaming onToken
            // callback. Advance to the next beat — first emit the
            // inter-beat paragraph break so the next beat's tokens
            // land cleanly. Emitting here (after success, not on
            // retry) avoids double-separator-on-retry.
            if beatIndex + 1 < totalBeatCount {
                emitToken("\n\n", beatIndex: beatIndex)
            }
            // Advance to next beat (fresh retry budget per beat).
            fireBeat(index: beatIndex + 1, retryAttemptsRemaining: 1)
        case .failure(let err):
            DebugLog.shared.write("[template-gen] beat \(beatIndex) failed: \(err)")
            finishGeneration(error: err)
        }
    }

    private func finishGeneration(error: Error?) {
        guard isGenerating else { return }
        isGenerating = false
        let elapsedMs = Int(Date().timeIntervalSince(generationStartedAt) * 1000)
        let insertedRange = NSRange(
            location: generationStartOffset,
            length: (insertedText as NSString).length
        )
        var info: [AnyHashable: Any] = [
            "insertedRange": insertedRange,
            "elapsedMs": elapsedMs,
            "beatCount": totalBeatCount,
            "cancelled": cancelled,
        ]
        if let error = error { info["error"] = error }
        DebugLog.shared.write("[template-gen] finish: elapsed=\(elapsedMs)ms inserted=\(insertedRange.length) cancelled=\(cancelled) error=\(error.map(String.init(describing:)) ?? "nil")")
        NotificationCenter.default.post(
            name: Self.didFinishNotification,
            object: self,
            userInfo: info
        )

        // Phase 7.b followup — persist a GenerationLogEntry to
        // `<project>/generation-log/` so template gens appear in the
        // History tab with the same shape as Continue. Skip when:
        // - error (no real response)
        // - in-memory session (no URL to write to)
        // - zero prose accumulated (cancelled before any beat completed)
        if error == nil,
           !insertedText.isEmpty,
           let projectURL = session.url,
           let sceneId = pendingSceneId,
           let templateId = pendingTemplateId,
           let skeleton = pendingSkeleton
        {
            writeLogEntry(
                projectURL: projectURL,
                sceneId: sceneId,
                templateId: templateId,
                skeleton: skeleton,
                elapsedMs: elapsedMs
            )
        }

        pendingSkeleton = nil
        pendingSceneId = nil
        pendingTemplateId = nil
        pendingBeatPrompts = []
    }

    private func writeLogEntry(
        projectURL: URL,
        sceneId: UUID,
        templateId: UUID,
        skeleton: ExtractedSceneSkeleton,
        elapsedMs: Int
    ) {
        // Synthesise a PromptAssembly that captures the per-beat
        // prompts concatenated with `=== BEAT N ===` separators. The
        // History tab can scroll through to see what was sent for
        // each beat. Token counts are estimates from the assembled
        // text.
        let fullPrompt = pendingBeatPrompts.enumerated().map { (i, p) in
            "=== BEAT \(i) ===\n\(p)"
        }.joined(separator: "\n\n")
        let promptTokens = TokenEstimator.estimate(fullPrompt)
        let assembly = PromptAssembly(
            contextChiclets: [],
            fullPrompt: fullPrompt,
            promptTokens: promptTokens,
            aboveCacheTokens: 0,
            belowCacheTokens: promptTokens,
            evictedLayers: [],
            template: .raw
        )
        let response = GenerationResponse(
            rawText: insertedText,
            completionTokens: TokenEstimator.estimate(insertedText),
            stopReason: cancelled ? "cancelled" : nil,
            refusalDetected: RefusalDetector.looksLikeRefusal(insertedText),
            elapsedMs: elapsedMs
        )
        let info = TemplateGenerationInfo(
            templateId: templateId,
            templateName: pendingTemplateName,
            castMapping: pendingCastMapping,
            beatCount: skeleton.beats.count,
            beatModalitySequence: skeleton.beats.map(\.modality.rawValue),
            voiceDescriptor: skeleton.voiceDescriptor
        )
        let entry = GenerationLogEntry(
            sceneId: sceneId,
            mode: .continueProse, // pragmatic stand-in; templateGenerationInfo is the authoritative discriminator
            promptAssembly: assembly,
            response: response,
            templateGenerationInfo: info
        )
        do {
            let url = try logStore.write(entry, in: projectURL)
            NotificationCenter.default.post(
                name: Self.didWriteLogEntryNotification,
                object: self,
                userInfo: ["entry": entry, "url": url]
            )
        } catch {
            DebugLog.shared.write("[template-gen] log-write failed: \(error)")
        }
    }
}

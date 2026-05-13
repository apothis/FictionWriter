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

    public init(
        session: ProjectSession,
        writerResolver: @escaping (UUID?) -> KoboldGenerating,
        logStore: GenerationLogStore = GenerationLogStore()
    ) {
        self.session = session
        self.writerResolver = writerResolver
        self.logStore = logStore
    }

    // MARK: - Lifecycle

    /// Start a per-beat template generation. No-ops on stale template
    /// id, missing skeleton sidecar, or in-memory session with no
    /// current scene.
    public func start(templateId: UUID, castMapping: String, cursorOffset: Int) {
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
        pendingPacing = PacingStats.compute(text: template.body)

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
        let prompt = BeatGeneration.buildBeatPrompt(
            templateBody: pendingTemplateBody,
            skeleton: skeleton,
            castMapping: pendingCastMapping,
            currentBeatIndex: index,
            priorBeatsProse: insertedText,
            groundTruthPacing: pendingPacing
        )
        // Punchlist item 2 (§7.a.2): NO bare `[` in the stop list — the
        // model opens beats with `[silence]` / `[the protagonist…]`
        // patterns and a bare `[` triggered immediate empty completion.
        // The longer markers below catch genuine prompt-structure
        // echoes without false-positives on prose openings.
        let stops = ["=== END", "[BEAT SKELETON", "[INSTRUCTION", "[SYSTEM]", "[NEW CAST]", "[NEXT-BEAT HINT"]
        self.lastStopSequences = stops

        let params = SamplerParams(
            maxLength: max(64, beat.targetWords * 2)
        )

        let writer = writerResolver(session.project.settings.serverProfileId)
        DebugLog.shared.write("[template-gen] beat \(index)/\(skeleton.beats.count - 1) (\(beat.modality.rawValue), \(beat.function.rawValue), target \(beat.targetWords)w)")

        writer.generate(
            prompt: prompt,
            stopSequences: stops,
            params: params,
            maxContextLength: session.project.settings.contextBudgetTokens
        ) { [weak self] result in
            // Marshal completion handling to main so notification +
            // state mutation are deterministic. Tests verify state
            // post-flush so this main-hop is fine for them too.
            self?.handleBeatResult(
                result: result,
                beatIndex: index,
                retryAttemptsRemaining: retryAttemptsRemaining
            )
        }
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
            // Punchlist item 3: empty output and `***`-only output
            // both count as "the model didn't commit"; retry once
            // before accepting whatever the model gave.
            let isDegenerate = trimmed.isEmpty || trimmed == "***" || trimmed == "* * *"
            if isDegenerate, retryAttemptsRemaining > 0 {
                DebugLog.shared.write("[template-gen] beat \(beatIndex) returned degenerate output (\(trimmed.isEmpty ? "empty" : "scene-break")); retrying")
                fireBeat(index: beatIndex, retryAttemptsRemaining: retryAttemptsRemaining - 1)
                return
            }
            // Append the beat's prose to the rolling buffer + emit
            // as a token event. Add a paragraph break between beats
            // so the editor's inserted prose has structure.
            let toEmit = beatIndex == 0 ? trimmed : "\n\n" + trimmed
            let offsetForThisBeat = insertionOffset
            insertedText += toEmit
            insertionOffset += (toEmit as NSString).length
            NotificationCenter.default.post(
                name: Self.didEmitTokenNotification,
                object: self,
                userInfo: [
                    "token": toEmit,
                    "insertionOffset": offsetForThisBeat,
                    "beatIndex": beatIndex,
                ]
            )
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
        pendingSkeleton = nil
        pendingSceneId = nil
        pendingTemplateId = nil
    }
}

import Foundation

/// Planned Project mode — Phase 5.2: the outline-driven scene drafter.
///
/// Drafts one outline scene end-to-end against the writer model:
///
/// 1. **Plan** — one LLM pass (`SceneBeatPlanner`) over the scene's
///    `summary` produces an ordered beat list with a per-beat word
///    budget.
/// 2. **Draft** — one writer call per beat (`SceneDraftPrompt`),
///    sequential, the prose accumulated into a rolling buffer with
///    the project's assigned styles threaded into every prompt.
/// 3. **Commit** — the accumulated prose is written to the scene and
///    its status advanced `todo → draft`.
///
/// Background generation: unlike `GenerationCoordinator` /
/// `TemplateGenerationCoordinator` the drafter does not stream tokens
/// into the editor — the scene being drafted need not be open. The
/// `didFinish` notification lets the UI refresh once the prose lands.
///
/// All I/O routes through one injected `OllamaCallProvider` (the
/// writer model — `KoboldCallProvider` instruct-wraps it), so the
/// orchestration is tested without HTTP, the same shape as
/// `OutlineGenerator`.
public final class OutlineDraftCoordinator {
    private let session: ProjectSession
    private let provider: OllamaCallProvider

    /// Supplies the app style library used to resolve the project's
    /// assigned styles. Defaults to `styles.json`; overridable for tests.
    public var styleLibraryProvider: () -> [Style] = { StyleLibraryStore().load() }

    /// Posted when a scene draft starts. `userInfo: ["sceneId": UUID]`.
    public static let didStartNotification = Notification.Name("LoomOutlineDraftCoordinator.didStart")
    /// Posted on finish (success, cancel, or error). `userInfo:
    /// ["sceneId": UUID, "beatCount": Int, "cancelled": Bool,
    /// "error": Error?]`.
    public static let didFinishNotification = Notification.Name("LoomOutlineDraftCoordinator.didFinish")

    public private(set) var isGenerating = false

    /// Fallback when a scene carries no `targetWordCount` — a typical
    /// single scene length (LOOM_PLANNED_PROJECT §3.3: ~1,500 words).
    private static let defaultTargetWords = 1_500

    private var cancelled = false

    public init(session: ProjectSession, provider: OllamaCallProvider) {
        self.session = session
        self.provider = provider
    }

    // MARK: - Lifecycle

    /// Draft the outline scene `sceneId`. No-ops if a draft is already
    /// running or the scene id is stale.
    public func start(sceneId: UUID) {
        guard !isGenerating else {
            DebugLog.shared.write("[outline-draft] start ignored — already generating")
            return
        }
        guard let scene = session.scenes[sceneId] else {
            DebugLog.shared.write("[outline-draft] start aborted — stale sceneId=\(sceneId)")
            return
        }

        isGenerating = true
        cancelled = false
        let styles = resolvedStyles()
        let targetWords = scene.targetWordCount ?? Self.defaultTargetWords
        let summary = scene.summary

        DebugLog.shared.write("[outline-draft] start sceneId=\(sceneId) target=\(targetWords)w")
        NotificationCenter.default.post(
            name: Self.didStartNotification, object: self,
            userInfo: ["sceneId": sceneId]
        )

        SceneBeatPlanner(provider: provider).planBeats(
            sceneSummary: summary, targetWordCount: targetWords
        ) { [weak self] result in
            guard let self = self else { return }
            self.onMain {
                switch result {
                case .failure(let error):
                    self.finish(sceneId: sceneId, prose: "", beatCount: 0, error: error)
                case .success(let beats):
                    self.draftBeat(
                        index: 0, beats: beats, sceneId: sceneId,
                        sceneSummary: summary, styles: styles, accumulated: ""
                    )
                }
            }
        }
    }

    /// Run `work` on the main thread. The provider's completion fires
    /// on whatever queue the HTTP client uses (off-main for the real
    /// `KoboldCallProvider`); the coordinator mutates `ProjectSession`
    /// and schedules its debounced auto-save Timer, both of which must
    /// happen on the main runloop. When already on main (the
    /// synchronous test stubs), `work` runs inline so the per-beat
    /// recursion stays deterministic for tests.
    private func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    /// Request cancellation. The in-flight beat completes; no further
    /// beats fire. Prose drafted so far is still committed.
    public func cancel() {
        guard isGenerating else { return }
        cancelled = true
    }

    // MARK: - Per-beat loop

    private func draftBeat(
        index: Int,
        beats: [SceneBeatPlanning.PlannedBeat],
        sceneId: UUID,
        sceneSummary: String,
        styles: [Style],
        accumulated: String
    ) {
        if cancelled || index >= beats.count {
            finish(sceneId: sceneId, prose: accumulated, beatCount: beats.count, error: nil)
            return
        }
        let beat = beats[index]
        // Cross-path NSFW consistency — the planned-beat draft carries
        // the same WritingDirection posture + anti-slop as the editor
        // path, with the target scene's explicitness override applied.
        let direction = WritingDirectionPrompt.effective(
            session.project.settings.writingDirection,
            sceneExplicitness: session.scenes[sceneId]?.explicitnessLevel
        )
        let prompt = SceneDraftPrompt.buildBeatPrompt(
            sceneSummary: sceneSummary,
            beats: beats,
            currentBeatIndex: index,
            priorProse: accumulated,
            styles: styles
        ) + WritingDirectionPrompt.systemAddendum(direction)
        // Output budget: 4× the beat's word target with a 256-token
        // floor, mirroring TemplateGenerationCoordinator — room to end
        // on a clean sentence without the framing losing length
        // discipline.
        let options = OllamaChatOptions(
            numPredict: max(256, beat.targetWords * 4),
            bannedStrings: session.project.settings.antiSlopPhrases
        )
        provider.call(prompt: prompt, schema: [:], options: options) { [weak self] result in
            guard let self = self else { return }
            self.onMain {
                switch result {
                case .failure(let error):
                    self.finish(
                        sceneId: sceneId, prose: accumulated,
                        beatCount: beats.count, error: error
                    )
                case .success(let raw):
                    let beatProse = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    let next = accumulated.isEmpty
                        ? beatProse
                        : accumulated + "\n\n" + beatProse
                    self.draftBeat(
                        index: index + 1, beats: beats, sceneId: sceneId,
                        sceneSummary: sceneSummary, styles: styles, accumulated: next
                    )
                }
            }
        }
    }

    // MARK: - Commit

    private func finish(sceneId: UUID, prose: String, beatCount: Int, error: Error?) {
        guard isGenerating else { return }
        isGenerating = false

        // Commit whatever prose was drafted: a clean success, or a
        // partial draft from a cancel. A hard error commits nothing.
        if error == nil, !prose.isEmpty {
            session.updateProse(id: sceneId, prose: prose)
            session.setSceneStatus(id: sceneId, to: .draft)
        }
        DebugLog.shared.write(
            "[outline-draft] finish sceneId=\(sceneId) beats=\(beatCount) " +
            "cancelled=\(cancelled) error=\(error.map(String.init(describing:)) ?? "nil")"
        )
        NotificationCenter.default.post(
            name: Self.didFinishNotification, object: self,
            userInfo: [
                "sceneId": sceneId,
                "beatCount": beatCount,
                "cancelled": cancelled,
                "error": error as Any,
            ]
        )
    }

    private func resolvedStyles() -> [Style] {
        let ids = session.project.plannedConfig?.assignedStyleIds ?? []
        guard !ids.isEmpty else { return [] }
        return StyleLibrary.resolve(ids, in: styleLibraryProvider())
    }
}

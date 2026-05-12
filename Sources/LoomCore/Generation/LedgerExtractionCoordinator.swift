import Foundation

/// The post-scene side-call extractor abstraction. The Phase 4 #7
/// production adapter is `OllamaLedgerExtractor`; tests inject a stub
/// that records calls + returns canned results.
public protocol LedgerExtractor {
    func extract(
        scenePose: String,
        characters: [LedgerExtraction.CharacterRef],
        completion: @escaping (Result<[LedgerExtraction.ExtractedFact], Error>) -> Void
    )
}

/// Debounce scheduler abstraction. Production uses `TimerScheduler`
/// (Timer.scheduledTimer); tests inject `ManualScheduler` that lets
/// them step through pending actions deterministically.
public protocol LedgerExtractionScheduler: AnyObject {
    /// Schedule `action` to run after `delay` seconds. Cancels any
    /// previously-scheduled action; this is the load-bearing semantics
    /// for the debounce — repeated `evaluate` calls during a typing
    /// burst collapse into one extraction at the end.
    func schedule(after delay: TimeInterval, action: @escaping () -> Void)
    /// Cancel without firing.
    func cancel()
}

/// Production scheduler backed by `Timer.scheduledTimer`. Fires on
/// the main run loop. Under TestKit (where the run loop isn't pumped)
/// timers never fire; tests must use `ManualScheduler`.
public final class TimerScheduler: LedgerExtractionScheduler {
    private var timer: Timer?

    public init() {}

    public func schedule(after delay: TimeInterval, action: @escaping () -> Void) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            action()
        }
    }

    public func cancel() {
        timer?.invalidate()
        timer = nil
    }
}

/// Phase 4 #7 sub-task 2 — the post-scene side-call coordinator.
/// Wires the trigger evaluator + debounced extractor dispatch.
///
/// Flow:
/// 1. App observes scene-prose changes (via `didChangeDirtyStateNotification`
///    or a per-mutation hook) and calls `evaluate(sceneId:currentWordCount:)`.
/// 2. The coordinator checks the trigger against the per-scene baseline.
///    Below threshold → no-op. Above → schedule a debounced fire.
/// 3. Subsequent `evaluate` calls during the debounce window cancel +
///    reschedule (typing-burst collapse).
/// 4. When the timer fires, the coordinator pulls the latest prose +
///    bible characters via `sceneProvider`, dispatches to
///    `extractor.extract`, and on success: updates the baseline, fires
///    `onExtractionComplete`.
/// 5. On failure: baseline stays nil — next prose update can re-trigger.
///
/// The diff-against-existing-ledger + Suggestions UI (Phase 4 #7
/// sub-tasks 3 / 4) consume the `onExtractionComplete` callback. This
/// coordinator does NOT persist anything onto the bible itself.
public final class LedgerExtractionCoordinator {
    public var threshold: Int = LedgerExtractionTrigger.defaultThreshold
    public var debounceSeconds: TimeInterval = 2.0

    public typealias ExtractionResultHandler = (UUID, Result<[LedgerExtraction.ExtractedFact], Error>) -> Void

    /// Fires on the main thread after a successful or failed extraction.
    /// Sub-task 3 wires this into the diff-and-propose path.
    public var onExtractionComplete: ExtractionResultHandler?

    private let extractorProvider: () -> LedgerExtractor?
    private let scheduler: LedgerExtractionScheduler
    private let sceneProvider: (UUID) -> (prose: String, characters: [LedgerExtraction.CharacterRef])?

    private var baselines: [UUID: Int] = [:]
    private var pendingSceneId: UUID?
    /// Per-scene in-flight guard (2026-05-13 live-test fix). The 2s
    /// debounce collapses keystroke bursts BEFORE fire, but once the
    /// URLSession is off (production extractions take 50–100s), more
    /// keystrokes inside that window otherwise spawn a concurrent
    /// fire on the same scene. The user saw this as two identical
    /// fact sets in the queue on the same scene. Guard is per-scene
    /// (a different scene in a different state is independent
    /// content + can extract in parallel without conflict).
    private var inFlightSceneIds: Set<UUID> = []

    public init(
        extractorProvider: @escaping () -> LedgerExtractor?,
        scheduler: LedgerExtractionScheduler,
        sceneProvider: @escaping (UUID) -> (prose: String, characters: [LedgerExtraction.CharacterRef])?
    ) {
        self.extractorProvider = extractorProvider
        self.scheduler = scheduler
        self.sceneProvider = sceneProvider
    }

    public func evaluate(sceneId: UUID, currentWordCount: Int) {
        let baseline = baselines[sceneId]
        guard LedgerExtractionTrigger.shouldFire(
            currentWordCount: currentWordCount,
            baselineWordCount: baseline,
            threshold: threshold
        ) else { return }
        // Cancel any pending fire and reschedule — debounce reset.
        // Only cancel when there's an actual pending action; otherwise
        // the first-evaluate path needlessly thrashes the scheduler.
        if pendingSceneId != nil {
            scheduler.cancel()
        }
        pendingSceneId = sceneId
        scheduler.schedule(after: debounceSeconds) { [weak self] in
            self?.fire()
        }
    }

    /// Manually set the baseline for a scene without running the
    /// extractor. Used at session bootstrap (preload baselines from
    /// the last persisted ledger) and in tests.
    public func setBaseline(sceneId: UUID, wordCount: Int) {
        baselines[sceneId] = wordCount
    }

    /// Public for tests. The production app reads it via the
    /// session-lifecycle paths only.
    public func baseline(for sceneId: UUID) -> Int? {
        baselines[sceneId]
    }

    private func fire() {
        guard let sceneId = pendingSceneId else { return }
        pendingSceneId = nil
        if inFlightSceneIds.contains(sceneId) {
            // A previous extraction on this scene is still resolving.
            // Suppress concurrent fires — the user's typing-burst will
            // re-trip the threshold after completion (provided the
            // delta accumulated past the new baseline), and the next
            // evaluate-flush cycle will fire a fresh extraction
            // against the latest prose state then.
            DebugLog.shared.write("[ledger] skipping side-call: extraction already in flight for scene=\(sceneId)")
            return
        }
        guard let extractor = extractorProvider() else {
            DebugLog.shared.write("[ledger] skipping side-call: no extractor profile configured")
            return
        }
        guard let snapshot = sceneProvider(sceneId) else {
            DebugLog.shared.write("[ledger] skipping side-call: scene \(sceneId) not found")
            return
        }
        let scenePose = snapshot.prose
        let postWordCount = WordCount.count(scenePose)
        inFlightSceneIds.insert(sceneId)
        DebugLog.shared.write("[ledger] firing side-call: scene=\(sceneId) words=\(postWordCount) characters=\(snapshot.characters.count)")
        extractor.extract(scenePose: scenePose, characters: snapshot.characters) { [weak self] result in
            guard let self = self else { return }
            self.inFlightSceneIds.remove(sceneId)
            switch result {
            case .success(let facts):
                self.baselines[sceneId] = postWordCount
                DebugLog.shared.write("[ledger] extraction ok: scene=\(sceneId) facts=\(facts.count)")
            case .failure(let err):
                DebugLog.shared.write("[ledger] extraction failed: scene=\(sceneId) err=\(err)")
            }
            self.onExtractionComplete?(sceneId, result)
        }
    }
}

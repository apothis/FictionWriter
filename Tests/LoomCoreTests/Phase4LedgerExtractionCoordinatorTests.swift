import Foundation
@testable import LoomCore

/// Phase 4 #7 sub-task 2 — the post-scene side-call coordinator.
/// Owns per-scene baselines + the debounce timer + the extractor
/// dispatch. Designed for full pure-data tests: the extractor +
/// scheduler are protocols injected at construction; the
/// production wiring (OllamaLedgerExtractor + TimerScheduler) is
/// honest-smoke.
func phase4LedgerExtractionCoordinatorTests() -> TestSuite {
    let s = TestSuite("Phase4LedgerExtractionCoordinator")

    // MARK: - Test doubles

    final class StubExtractor: LedgerExtractor {
        var calls: [(prose: String, characters: [LedgerExtraction.CharacterRef])] = []
        var nextResult: Result<[LedgerExtraction.ExtractedFact], Error> = .success([])
        func extract(
            scenePose: String,
            characters: [LedgerExtraction.CharacterRef],
            completion: @escaping (Result<[LedgerExtraction.ExtractedFact], Error>) -> Void
        ) {
            calls.append((scenePose, characters))
            completion(nextResult)
        }
    }

    final class ManualScheduler: LedgerExtractionScheduler {
        var pendingAction: (() -> Void)?
        var lastDelay: TimeInterval?
        var cancellations: Int = 0
        func schedule(after delay: TimeInterval, action: @escaping () -> Void) {
            lastDelay = delay
            pendingAction = action
        }
        func cancel() {
            pendingAction = nil
            cancellations += 1
        }
        /// Test-only — synchronously fire the pending action (the
        /// production scheduler dispatches on the run loop).
        func flush() {
            let action = pendingAction
            pendingAction = nil
            action?()
        }
    }

    let sampleProse = "Mia opened the door. The wind blew through. Anders stood there, holding a bouquet."
    let sampleCharacters = [
        LedgerExtraction.CharacterRef(name: "Mia", aliases: []),
        LedgerExtraction.CharacterRef(name: "Anders", aliases: []),
    ]
    let sampleFact = LedgerExtraction.ExtractedFact(
        characterId: "Mia", fact: "Mia opened the door.",
        certainty: .asserted, evidenceQuote: "Mia opened the door."
    )

    func makeCoordinator(
        extractor: LedgerExtractor?,
        scheduler: LedgerExtractionScheduler,
        sceneProse: String = "",
        characters: [LedgerExtraction.CharacterRef] = []
    ) -> LedgerExtractionCoordinator {
        return LedgerExtractionCoordinator(
            extractorProvider: { extractor },
            scheduler: scheduler,
            sceneProvider: { _ in (prose: sceneProse, characters: characters) }
        )
    }

    s.test("evaluate below threshold from nil baseline does not schedule the extractor") {
        let extractor = StubExtractor()
        let sched = ManualScheduler()
        let coord = makeCoordinator(extractor: extractor, scheduler: sched)
        let sceneId = UUID()
        coord.evaluate(sceneId: sceneId, currentWordCount: 100)
        try expectNil(sched.pendingAction)
        try expectEqual(extractor.calls.count, 0)
    }

    s.test("evaluate above threshold schedules a debounced fire (no synchronous extract)") {
        let extractor = StubExtractor()
        let sched = ManualScheduler()
        let coord = makeCoordinator(extractor: extractor, scheduler: sched)
        let sceneId = UUID()
        coord.evaluate(sceneId: sceneId, currentWordCount: 250)
        _ = try expectNotNil(sched.pendingAction)
        try expectEqual(extractor.calls.count, 0, "extractor must not fire until debounce expires")
        try expectEqual(sched.lastDelay, coord.debounceSeconds)
    }

    s.test("flushing the scheduler after evaluate triggers the extractor with scene prose + characters") {
        let extractor = StubExtractor()
        let sched = ManualScheduler()
        let coord = makeCoordinator(
            extractor: extractor, scheduler: sched,
            sceneProse: sampleProse, characters: sampleCharacters
        )
        coord.evaluate(sceneId: UUID(), currentWordCount: 250)
        sched.flush()
        try expectEqual(extractor.calls.count, 1)
        try expectEqual(extractor.calls[0].prose, sampleProse)
        try expectEqual(extractor.calls[0].characters, sampleCharacters)
    }

    s.test("successful extraction posts didCompleteExtraction with the facts") {
        let extractor = StubExtractor()
        extractor.nextResult = .success([sampleFact])
        let sched = ManualScheduler()
        let coord = makeCoordinator(
            extractor: extractor, scheduler: sched,
            sceneProse: sampleProse, characters: sampleCharacters
        )
        let sceneId = UUID()

        var captured: (UUID, Result<[LedgerExtraction.ExtractedFact], Error>)?
        coord.onExtractionComplete = { id, result in captured = (id, result) }

        coord.evaluate(sceneId: sceneId, currentWordCount: 250)
        sched.flush()

        let (capturedId, capturedResult) = try expectNotNil(captured)
        try expectEqual(capturedId, sceneId)
        switch capturedResult {
        case .success(let facts): try expectEqual(facts, [sampleFact])
        case .failure(let e): try expectTrue(false, "expected success, got \(e)")
        }
    }

    s.test("successful extraction updates the per-scene baseline") {
        let extractor = StubExtractor()
        extractor.nextResult = .success([])
        let sched = ManualScheduler()
        let coord = makeCoordinator(
            extractor: extractor, scheduler: sched,
            sceneProse: sampleProse, characters: sampleCharacters
        )
        let sceneId = UUID()
        let postWordCount = WordCount.count(sampleProse)

        coord.evaluate(sceneId: sceneId, currentWordCount: 250)
        sched.flush()

        // After success the baseline should equal the prose's actual
        // word count. Subsequent evaluate at that count won't re-fire.
        try expectEqual(coord.baseline(for: sceneId), postWordCount)
        coord.evaluate(sceneId: sceneId, currentWordCount: postWordCount)
        try expectNil(sched.pendingAction)  // baseline at current count → no re-fire
    }

    s.test("failed extraction does NOT update the baseline — next evaluate can re-trigger") {
        let extractor = StubExtractor()
        extractor.nextResult = .failure(NSError(domain: "stub", code: 1))
        let sched = ManualScheduler()
        let coord = makeCoordinator(
            extractor: extractor, scheduler: sched,
            sceneProse: sampleProse, characters: sampleCharacters
        )
        let sceneId = UUID()

        coord.evaluate(sceneId: sceneId, currentWordCount: 250)
        sched.flush()
        try expectNil(coord.baseline(for: sceneId))  // baseline must remain nil after failure

        coord.evaluate(sceneId: sceneId, currentWordCount: 250)
        _ = try expectNotNil(sched.pendingAction)  // post-failure evaluate must be able to re-schedule
    }

    s.test("evaluate while a fire is pending cancels and reschedules (debounce reset)") {
        let extractor = StubExtractor()
        let sched = ManualScheduler()
        let coord = makeCoordinator(extractor: extractor, scheduler: sched)
        let sceneId = UUID()

        coord.evaluate(sceneId: sceneId, currentWordCount: 250)
        try expectEqual(sched.cancellations, 0)
        coord.evaluate(sceneId: sceneId, currentWordCount: 300)
        try expectEqual(sched.cancellations, 1, "re-evaluating should cancel the prior schedule first")
        _ = try expectNotNil(sched.pendingAction)  // and replace it with a fresh one
    }

    s.test("missing extractor profile silently skips the side-call when the timer fires") {
        let sched = ManualScheduler()
        let coord = LedgerExtractionCoordinator(
            extractorProvider: { nil },  // no profile configured
            scheduler: sched,
            sceneProvider: { _ in (prose: "x", characters: []) }
        )
        let sceneId = UUID()

        coord.evaluate(sceneId: sceneId, currentWordCount: 250)
        sched.flush()

        // No extractor → no callback fires, no baseline update, no crash.
        try expectNil(coord.baseline(for: sceneId))
    }

    s.test("setBaseline(sceneId:wordCount:) records the baseline without running the extractor") {
        let extractor = StubExtractor()
        let sched = ManualScheduler()
        let coord = makeCoordinator(extractor: extractor, scheduler: sched)
        let sceneId = UUID()
        coord.setBaseline(sceneId: sceneId, wordCount: 1500)
        try expectEqual(coord.baseline(for: sceneId), 1500)
        try expectEqual(extractor.calls.count, 0)
    }

    // MARK: - In-flight guard (Phase 4 #7 2026-05-13 live-test fix)

    // Deferred stub for testing the in-flight window. Production
    // extracts take 50–100 seconds; the existing StubExtractor
    // completes synchronously inside `extract(...)` and so doesn't
    // exercise the window where the URLSession is pending. This stub
    // stores completions for explicit `flush(_:at:)` resolution per
    // the `feedback_tdd_async_callbacks` memory.
    final class DeferredStubExtractor: LedgerExtractor {
        var calls: [(prose: String, characters: [LedgerExtraction.CharacterRef])] = []
        var pending: [(Result<[LedgerExtraction.ExtractedFact], Error>) -> Void] = []
        func extract(
            scenePose: String,
            characters: [LedgerExtraction.CharacterRef],
            completion: @escaping (Result<[LedgerExtraction.ExtractedFact], Error>) -> Void
        ) {
            calls.append((scenePose, characters))
            pending.append(completion)
        }
        func flushAll(_ result: Result<[LedgerExtraction.ExtractedFact], Error>) {
            let snapshot = pending
            pending = []
            for c in snapshot { c(result) }
        }
    }

    s.test("evaluate during an in-flight extraction does NOT fire a second extract on the same scene") {
        let extractor = DeferredStubExtractor()
        let sched = ManualScheduler()
        let coord = makeCoordinator(
            extractor: extractor, scheduler: sched,
            sceneProse: sampleProse, characters: sampleCharacters
        )
        let sceneId = UUID()
        // First trip the threshold + flush — extract is now in flight
        // (completion held by the deferred stub).
        coord.evaluate(sceneId: sceneId, currentWordCount: 250)
        sched.flush()
        try expectEqual(extractor.calls.count, 1)
        try expectEqual(extractor.pending.count, 1)
        // While the first extraction is still pending, more typing
        // re-trips the threshold. The debounced timer fires again —
        // but the coordinator must NOT start a second concurrent
        // extract on the same scene.
        coord.evaluate(sceneId: sceneId, currentWordCount: 500)
        sched.flush()
        try expectEqual(extractor.calls.count, 1,
            "second concurrent extract on the same scene must be suppressed while one is in flight")
        try expectEqual(extractor.pending.count, 1)
    }

    s.test("after the in-flight extraction completes, a subsequent evaluate CAN re-fire") {
        let extractor = DeferredStubExtractor()
        let sched = ManualScheduler()
        let coord = makeCoordinator(
            extractor: extractor, scheduler: sched,
            sceneProse: sampleProse, characters: sampleCharacters
        )
        let sceneId = UUID()
        coord.evaluate(sceneId: sceneId, currentWordCount: 250)
        sched.flush()
        try expectEqual(extractor.calls.count, 1)
        // Complete the first extraction. The in-flight flag should
        // clear so the next evaluate can fire normally.
        extractor.flushAll(.success([]))
        // Need to overcome the new baseline (which equals the prose's
        // word count post-success). Trip the threshold from there.
        let postWordCount = WordCount.count(sampleProse)
        coord.evaluate(sceneId: sceneId, currentWordCount: postWordCount + 250)
        sched.flush()
        try expectEqual(extractor.calls.count, 2)
    }

    s.test("different scene can fire concurrently with another scene's in-flight extraction") {
        let extractor = DeferredStubExtractor()
        let sched = ManualScheduler()
        let coord = makeCoordinator(
            extractor: extractor, scheduler: sched,
            sceneProse: sampleProse, characters: sampleCharacters
        )
        let sceneA = UUID()
        let sceneB = UUID()
        coord.evaluate(sceneId: sceneA, currentWordCount: 250)
        sched.flush()
        try expectEqual(extractor.calls.count, 1)
        // Scene B is independent — the in-flight guard is per-scene,
        // not global. User can edit a different scene while another's
        // extraction is still resolving.
        coord.evaluate(sceneId: sceneB, currentWordCount: 250)
        sched.flush()
        try expectEqual(extractor.calls.count, 2,
            "in-flight extraction on scene A must not block extraction on scene B")
    }

    s.test("in-flight failure clears the guard so the next evaluate can re-fire") {
        let extractor = DeferredStubExtractor()
        let sched = ManualScheduler()
        let coord = makeCoordinator(
            extractor: extractor, scheduler: sched,
            sceneProse: sampleProse, characters: sampleCharacters
        )
        let sceneId = UUID()
        coord.evaluate(sceneId: sceneId, currentWordCount: 250)
        sched.flush()
        try expectEqual(extractor.calls.count, 1)
        // Fail the in-flight call. Baseline is NOT updated, but the
        // in-flight guard MUST clear — otherwise a transient failure
        // permanently wedges the scene.
        extractor.flushAll(.failure(NSError(domain: "stub", code: 1)))
        coord.evaluate(sceneId: sceneId, currentWordCount: 250)
        sched.flush()
        try expectEqual(extractor.calls.count, 2)
    }

    return s
}

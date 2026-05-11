import Foundation
@testable import LoomCore

/// Phase 4 #7 sub-task 8 — honest smoke that AppState routes the
/// post-diff suggestions through `LedgerFilterPipeline` and commits
/// the filtered result onto the suggestions queue. The pipeline +
/// individual filters are pinned in `Phase4LedgerFilterPipelineTests`
/// and `Phase4LedgerFiltersTests`; this suite verifies the AppState
/// glue between them.
///
/// The embedder injection here is a `DeferredStubEmbedder` per the
/// `feedback_tdd_async_callbacks` memory: completions are flushed
/// explicitly by the test, never invoked synchronously inside the
/// stub. The AppState commit hops to main via `DispatchQueue.main.async`,
/// so the test spins the run loop via the `Expectation.wait` helper
/// from `Phase4LedgerDiffWiringTests`.
func phase4LedgerFiltersWiringTests() -> TestSuite {
    let s = TestSuite("Phase4LedgerFiltersWiring")

    func makeAppState(with embedder: DeferredStubEmbedder) -> AppState {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("loom-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let store = AppSettingsStore(fileManager: .default, rootDir: tmp)
        return AppState(settingsStore: store, embedderProvider: { embedder })
    }

    s.test("embedder is consulted when a matched suggestion would be queued") {
        let embedder = DeferredStubEmbedder()
        let appState = makeAppState(with: embedder)
        _ = appState.currentSession.addCharacter(name: "Mia")
        let sceneId = appState.currentSession.currentSceneId!

        appState.ledgerCoordinator.onExtractionComplete?(sceneId, .success([
            LedgerExtraction.ExtractedFact(
                characterId: "Mia",
                fact: "Mia drank wine.",
                certainty: .asserted,
                evidenceQuote: "Mia drank her wine."
            )
        ]))

        // The pipeline fires the embed call synchronously from the
        // post-diff branch; the test stub has captured the request.
        try expectNotNil(embedder.stored)
    }

    s.test("successful filter pass queues the surviving suggestion + posts notification") {
        let embedder = DeferredStubEmbedder()
        let appState = makeAppState(with: embedder)
        let mia = appState.currentSession.addCharacter(name: "Mia")
        let sceneId = appState.currentSession.currentSceneId!

        let didFire = expectation(named: "ledgerSuggestionsDidChange")
        let token = NotificationCenter.default.addObserver(
            forName: AppState.ledgerSuggestionsDidChangeNotification,
            object: appState,
            queue: nil
        ) { _ in didFire.fulfill() }
        defer { NotificationCenter.default.removeObserver(token) }

        appState.ledgerCoordinator.onExtractionComplete?(sceneId, .success([
            LedgerExtraction.ExtractedFact(
                characterId: "Mia",
                fact: "Mia drank wine.",
                certainty: .asserted,
                evidenceQuote: ""
            )
        ]))

        // Flush the stubbed embed call with orthogonal vectors so
        // nothing matches → all filters pass through.
        let texts = embedder.stored!.texts
        var vectors: [[Float]] = []
        for t in texts {
            switch t {
            case "Mia drank wine.":
                vectors.append([1.0, 0.0])
            default:
                vectors.append([0.0, 1.0])
            }
        }
        embedder.flush(.success(vectors))

        try didFire.wait(timeout: 1.0)
        try expectEqual(appState.ledgerSuggestionsQueue.totalCount, 1)
        let forMia = appState.ledgerSuggestionsQueue.suggestions(forCharacter: mia.id)
        try expectEqual(forMia.count, 1)
    }

    s.test("filter chain drops the only candidate → no queue add, no notification") {
        let embedder = DeferredStubEmbedder()
        let appState = makeAppState(with: embedder)
        let mia = appState.currentSession.addCharacter(name: "Mia")
        // Pre-populate Mia's ledger with the existing-fact text the
        // dedup filter will use as the paraphrase target.
        var miaWithFact = mia
        miaWithFact.knownFactsBySceneId[UUID()] = [
            KnownFact(fact: "Mia was drinking wine.", certainty: .asserted)
        ]
        appState.currentSession.updateCharacter(miaWithFact)
        let sceneId = appState.currentSession.currentSceneId!

        var notificationFired = false
        let token = NotificationCenter.default.addObserver(
            forName: AppState.ledgerSuggestionsDidChangeNotification,
            object: appState,
            queue: nil
        ) { _ in notificationFired = true }
        defer { NotificationCenter.default.removeObserver(token) }

        appState.ledgerCoordinator.onExtractionComplete?(sceneId, .success([
            LedgerExtraction.ExtractedFact(
                characterId: "Mia",
                fact: "Mia drank wine.",
                certainty: .asserted,
                evidenceQuote: ""
            )
        ]))

        let texts = embedder.stored!.texts
        let vNew: [Float] = [1.0, 0.0]
        let vClose: [Float] = [0.95, 0.3122]  // cos 0.95 with vNew
        var vectors: [[Float]] = []
        for t in texts {
            switch t {
            case "Mia drank wine.":
                vectors.append(vNew)
            case "Mia was drinking wine.":
                vectors.append(vClose)
            default:
                vectors.append([0.0, 1.0])
            }
        }
        embedder.flush(.success(vectors))

        // Drain any pending main-queue dispatch.
        let deadline = Date().addingTimeInterval(0.3)
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }

        try expectEqual(appState.ledgerSuggestionsQueue.totalCount, 0)
        try expectFalse(notificationFired)
    }

    s.test("embed failure → fail-soft: candidate still queued unfiltered") {
        let embedder = DeferredStubEmbedder()
        let appState = makeAppState(with: embedder)
        _ = appState.currentSession.addCharacter(name: "Mia")
        let sceneId = appState.currentSession.currentSceneId!

        let didFire = expectation(named: "ledgerSuggestionsDidChange (fail-soft)")
        let token = NotificationCenter.default.addObserver(
            forName: AppState.ledgerSuggestionsDidChangeNotification,
            object: appState,
            queue: nil
        ) { _ in didFire.fulfill() }
        defer { NotificationCenter.default.removeObserver(token) }

        appState.ledgerCoordinator.onExtractionComplete?(sceneId, .success([
            LedgerExtraction.ExtractedFact(
                characterId: "Mia",
                fact: "Mia drank wine.",
                certainty: .asserted,
                evidenceQuote: ""
            )
        ]))

        embedder.flush(.failure(NSError(domain: "test", code: 1)))

        try didFire.wait(timeout: 1.0)
        try expectEqual(appState.ledgerSuggestionsQueue.totalCount, 1)
    }

    return s
}

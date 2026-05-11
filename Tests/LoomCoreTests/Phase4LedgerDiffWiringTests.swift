import Foundation
@testable import LoomCore

/// Phase 4 #7 sub-task 3 — honest smoke that AppState wires the
/// coordinator's `onExtractionComplete` callback into the diff +
/// suggestions queue + notification, end-to-end. The diff itself
/// is pinned in Phase4LedgerDiffTests; the queue in
/// Phase4LedgerSuggestionsQueueTests; this suite verifies the
/// production glue between them.
func phase4LedgerDiffWiringTests() -> TestSuite {
    let s = TestSuite("Phase4LedgerDiffWiring")

    func freshAppState() -> AppState {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("loom-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let store = AppSettingsStore(fileManager: .default, rootDir: tmp)
        return AppState(settingsStore: store)
    }

    s.test("AppState constructs an empty ledgerSuggestionsQueue at init") {
        let appState = freshAppState()
        try expectEqual(appState.ledgerSuggestionsQueue.totalCount, 0)
    }

    s.test("successful extraction with matching bible character queues a suggestion") {
        let appState = freshAppState()
        // Seed the bible with a character matching the upcoming extraction.
        let mia = appState.currentSession.addCharacter(name: "Mia")
        let sceneId = appState.currentSession.currentSceneId!

        // Drive the coordinator's onExtractionComplete callback directly.
        // (The full network round-trip path is honest smoke; the
        // production extractor is OllamaLedgerExtractor wired in
        // sub-task 2.)
        let extracted = [
            LedgerExtraction.ExtractedFact(
                characterId: "Mia",
                fact: "Mia opened the door.",
                certainty: .asserted,
                evidenceQuote: "Mia opened the door."
            )
        ]
        let didFire = expectation(named: "ledgerSuggestionsDidChange notification")
        let token = NotificationCenter.default.addObserver(
            forName: AppState.ledgerSuggestionsDidChangeNotification,
            object: appState,
            queue: nil
        ) { _ in didFire.fulfill() }
        defer { NotificationCenter.default.removeObserver(token) }

        appState.ledgerCoordinator.onExtractionComplete?(sceneId, .success(extracted))

        try expectEqual(appState.ledgerSuggestionsQueue.totalCount, 1)
        let forMia = appState.ledgerSuggestionsQueue.suggestions(forCharacter: mia.id)
        try expectEqual(forMia.count, 1)
        try expectEqual(forMia[0].fact.fact, "Mia opened the door.")
        try expectEqual(forMia[0].fact.sourceSceneId, sceneId)
        try didFire.wait(timeout: 0.5)
    }

    s.test("extraction with zero net-new suggestions (all already on ledger) does NOT post notification") {
        let appState = freshAppState()
        let mia = appState.currentSession.addCharacter(name: "Mia")
        let sceneId = appState.currentSession.currentSceneId!

        // Pre-populate Mia's ledger with the fact the model will extract.
        var miaWithFact = mia
        let priorSceneId = UUID()
        miaWithFact.knownFactsBySceneId[priorSceneId] = [
            KnownFact(fact: "Mia opened the door.", certainty: .asserted)
        ]
        appState.currentSession.updateCharacter(miaWithFact)

        var notificationFired = false
        let token = NotificationCenter.default.addObserver(
            forName: AppState.ledgerSuggestionsDidChangeNotification,
            object: appState,
            queue: nil
        ) { _ in notificationFired = true }
        defer { NotificationCenter.default.removeObserver(token) }

        let extracted = [
            LedgerExtraction.ExtractedFact(
                characterId: "Mia",
                fact: "Mia opened the door.",  // dup
                certainty: .asserted,
                evidenceQuote: ""
            )
        ]
        appState.ledgerCoordinator.onExtractionComplete?(sceneId, .success(extracted))

        try expectEqual(appState.ledgerSuggestionsQueue.totalCount, 0)
        try expectFalse(notificationFired)
    }

    s.test("failed extraction does not crash, does not enqueue, does not notify") {
        let appState = freshAppState()
        let sceneId = appState.currentSession.currentSceneId!

        var notificationFired = false
        let token = NotificationCenter.default.addObserver(
            forName: AppState.ledgerSuggestionsDidChangeNotification,
            object: appState,
            queue: nil
        ) { _ in notificationFired = true }
        defer { NotificationCenter.default.removeObserver(token) }

        let err = NSError(domain: "test", code: 1)
        appState.ledgerCoordinator.onExtractionComplete?(sceneId, .failure(err))

        try expectEqual(appState.ledgerSuggestionsQueue.totalCount, 0)
        try expectFalse(notificationFired)
    }

    return s
}

// MARK: - Tiny expectation helper

/// TestKit doesn't carry XCTest's `XCTestExpectation`; provide a
/// drop-dead-simple Bool-fulfilled version sufficient for the
/// sub-task 3 wiring assertions.
final class Expectation {
    let name: String
    private(set) var isFulfilled = false
    init(name: String) { self.name = name }
    func fulfill() { isFulfilled = true }
    func wait(timeout: TimeInterval) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !isFulfilled, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        try expectTrue(isFulfilled, "expectation '\(name)' was not fulfilled within \(timeout)s")
    }
}

func expectation(named name: String) -> Expectation { Expectation(name: name) }

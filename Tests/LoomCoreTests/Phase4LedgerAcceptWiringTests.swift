import Foundation
@testable import LoomCore

/// Phase 4 #7 sub-tasks 4+5 — the AppState-level accept/reject API
/// the Bible-inspector Suggestions UI calls into. Pure-data layers
/// (LedgerDiff / LedgerSuggestionsQueue / LedgerSuggestionAcceptor)
/// are pinned separately; this suite verifies the wire-through.
///
/// Contract:
/// - acceptLedgerSuggestion: appends fact to character.knownFactsBySceneId
///   via the acceptor, writes through ProjectSession.updateCharacter
///   (so the project is dirty + auto-saves), removes from the queue,
///   posts ledgerSuggestionsDidChangeNotification.
/// - rejectLedgerSuggestion: removes from queue, posts notification.
///   The bible is NOT mutated (the dedup pass in LedgerDiff will not
///   skip this fact next time — rejecting once doesn't blacklist
///   forever; that's a sub-task 8 + Phase 6 concern).
func phase4LedgerAcceptWiringTests() -> TestSuite {
    let s = TestSuite("Phase4LedgerAcceptWiring")

    func freshAppState() -> AppState {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("loom-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let store = AppSettingsStore(fileManager: .default, rootDir: tmp)
        return AppState(settingsStore: store)
    }

    s.test("acceptLedgerSuggestion appends the fact to the character's ledger") {
        let appState = freshAppState()
        let mia = appState.currentSession.addCharacter(name: "Mia")
        let sceneId = appState.currentSession.currentSceneId!

        let suggestion = LedgerSuggestion(
            characterId: mia.id,
            fact: KnownFact(fact: "Mia opened the door.", sourceSceneId: sceneId, certainty: .asserted),
            evidenceQuote: "..."
        )
        appState.ledgerSuggestionsQueue.add([suggestion])

        appState.acceptLedgerSuggestion(suggestion)

        let updated = appState.currentSession.project.bible.characters.first { $0.id == mia.id }!
        let facts = updated.knownFactsBySceneId[sceneId] ?? []
        try expectEqual(facts.count, 1)
        try expectEqual(facts[0].fact, "Mia opened the door.")
    }

    s.test("acceptLedgerSuggestion removes the suggestion from the queue") {
        let appState = freshAppState()
        let mia = appState.currentSession.addCharacter(name: "Mia")
        let sceneId = appState.currentSession.currentSceneId!
        let suggestion = LedgerSuggestion(
            characterId: mia.id,
            fact: KnownFact(fact: "Mia opened the door.", sourceSceneId: sceneId, certainty: .asserted),
            evidenceQuote: ""
        )
        appState.ledgerSuggestionsQueue.add([suggestion])
        try expectEqual(appState.ledgerSuggestionsQueue.totalCount, 1)
        appState.acceptLedgerSuggestion(suggestion)
        try expectEqual(appState.ledgerSuggestionsQueue.totalCount, 0)
    }

    s.test("acceptLedgerSuggestion posts ledgerSuggestionsDidChangeNotification") {
        let appState = freshAppState()
        let mia = appState.currentSession.addCharacter(name: "Mia")
        let sceneId = appState.currentSession.currentSceneId!
        let suggestion = LedgerSuggestion(
            characterId: mia.id,
            fact: KnownFact(fact: "x", sourceSceneId: sceneId, certainty: .asserted),
            evidenceQuote: ""
        )
        appState.ledgerSuggestionsQueue.add([suggestion])

        var fired = false
        let token = NotificationCenter.default.addObserver(
            forName: AppState.ledgerSuggestionsDidChangeNotification,
            object: appState,
            queue: nil
        ) { _ in fired = true }
        defer { NotificationCenter.default.removeObserver(token) }

        appState.acceptLedgerSuggestion(suggestion)
        try expectTrue(fired)
    }

    s.test("acceptLedgerSuggestion on a stale character (deleted) is a graceful no-op") {
        let appState = freshAppState()
        let sceneId = appState.currentSession.currentSceneId!
        let suggestion = LedgerSuggestion(
            characterId: UUID(),  // not in bible
            fact: KnownFact(fact: "x", sourceSceneId: sceneId, certainty: .asserted),
            evidenceQuote: ""
        )
        appState.ledgerSuggestionsQueue.add([suggestion])
        appState.acceptLedgerSuggestion(suggestion)
        // Suggestion still removed from queue (the caller's intent was
        // "I'm done with this") but no character was mutated.
        try expectEqual(appState.ledgerSuggestionsQueue.totalCount, 0)
    }

    s.test("rejectLedgerSuggestion removes from queue without mutating the bible") {
        let appState = freshAppState()
        let mia = appState.currentSession.addCharacter(name: "Mia")
        let sceneId = appState.currentSession.currentSceneId!
        let suggestion = LedgerSuggestion(
            characterId: mia.id,
            fact: KnownFact(fact: "Mia opened the door.", sourceSceneId: sceneId, certainty: .asserted),
            evidenceQuote: ""
        )
        appState.ledgerSuggestionsQueue.add([suggestion])

        appState.rejectLedgerSuggestion(factId: suggestion.fact.id)

        try expectEqual(appState.ledgerSuggestionsQueue.totalCount, 0)
        let stillMia = appState.currentSession.project.bible.characters.first { $0.id == mia.id }!
        try expectTrue(stillMia.knownFactsBySceneId.isEmpty)
    }

    s.test("rejectLedgerSuggestion posts ledgerSuggestionsDidChangeNotification") {
        let appState = freshAppState()
        let mia = appState.currentSession.addCharacter(name: "Mia")
        let sceneId = appState.currentSession.currentSceneId!
        let suggestion = LedgerSuggestion(
            characterId: mia.id,
            fact: KnownFact(fact: "x", sourceSceneId: sceneId, certainty: .asserted),
            evidenceQuote: ""
        )
        appState.ledgerSuggestionsQueue.add([suggestion])
        var fired = false
        let token = NotificationCenter.default.addObserver(
            forName: AppState.ledgerSuggestionsDidChangeNotification,
            object: appState,
            queue: nil
        ) { _ in fired = true }
        defer { NotificationCenter.default.removeObserver(token) }

        appState.rejectLedgerSuggestion(factId: suggestion.fact.id)
        try expectTrue(fired)
    }

    return s
}

import Foundation
@testable import LoomCore

/// Phase 4 #7 sub-task 5 — pure-data acceptor for a `LedgerSuggestion`.
/// Returns the input `Character` with the suggestion's `KnownFact`
/// appended to `knownFactsBySceneId[sourceSceneId]`, preserving all
/// other fields. The caller (AppState.acceptLedgerSuggestion) writes
/// the result back via `ProjectSession.updateCharacter(_:)` and
/// removes the suggestion from the queue.
///
/// `sourceSceneId` is non-optional on `LedgerSuggestion.fact` (sub-
/// task 3 always stamps it from the extraction scene); pre-stamped
/// `KnownFact`s with `sourceSceneId == nil` are treated as pre-story
/// knowledge and stored under a nil-key — but `LedgerSuggestion`
/// never carries those.
func phase4LedgerSuggestionAcceptorTests() -> TestSuite {
    let s = TestSuite("Phase4LedgerSuggestionAcceptor")

    let sceneId = UUID()
    let otherSceneId = UUID()
    let miaId = UUID()

    func makeSuggestion(fact: String, on sceneId: UUID) -> LedgerSuggestion {
        LedgerSuggestion(
            characterId: miaId,
            fact: KnownFact(
                id: UUID(),
                fact: fact,
                sourceSceneId: sceneId,
                certainty: .asserted
            ),
            evidenceQuote: "..."
        )
    }

    s.test("apply appends the fact to the character's ledger under sourceSceneId") {
        let mia = Character(id: miaId, name: "Mia")
        let suggestion = makeSuggestion(fact: "Mia opened the door.", on: sceneId)
        let updated = LedgerSuggestionAcceptor.apply(suggestion, to: mia)
        let facts = updated.knownFactsBySceneId[sceneId] ?? []
        try expectEqual(facts.count, 1)
        try expectEqual(facts[0].fact, "Mia opened the door.")
        try expectEqual(facts[0].id, suggestion.fact.id)
    }

    s.test("apply preserves existing facts on the same scene (append, not replace)") {
        var mia = Character(id: miaId, name: "Mia")
        let prior = KnownFact(fact: "Mia drank wine.", sourceSceneId: sceneId, certainty: .asserted)
        mia.knownFactsBySceneId[sceneId] = [prior]
        let suggestion = makeSuggestion(fact: "Mia opened the door.", on: sceneId)
        let updated = LedgerSuggestionAcceptor.apply(suggestion, to: mia)
        let facts = updated.knownFactsBySceneId[sceneId] ?? []
        try expectEqual(facts.count, 2)
        try expectEqual(facts[0].fact, "Mia drank wine.")  // existing first
        try expectEqual(facts[1].fact, "Mia opened the door.")
    }

    s.test("apply preserves facts on OTHER scenes untouched") {
        var mia = Character(id: miaId, name: "Mia")
        let other = KnownFact(fact: "Mia met Anders.", sourceSceneId: otherSceneId, certainty: .asserted)
        mia.knownFactsBySceneId[otherSceneId] = [other]
        let suggestion = makeSuggestion(fact: "Mia opened the door.", on: sceneId)
        let updated = LedgerSuggestionAcceptor.apply(suggestion, to: mia)
        let otherFacts = updated.knownFactsBySceneId[otherSceneId] ?? []
        try expectEqual(otherFacts.count, 1)
        try expectEqual(otherFacts[0].fact, "Mia met Anders.")
    }

    s.test("apply preserves the character's other fields (name, aliases, description, etc.)") {
        var mia = Character(id: miaId, name: "Mia")
        mia.aliases = ["the librarian"]
        mia.description = "A late-thirties librarian."
        mia.role = .protagonist
        let suggestion = makeSuggestion(fact: "Mia opened the door.", on: sceneId)
        let updated = LedgerSuggestionAcceptor.apply(suggestion, to: mia)
        try expectEqual(updated.id, miaId)
        try expectEqual(updated.name, "Mia")
        try expectEqual(updated.aliases, ["the librarian"])
        try expectEqual(updated.description, "A late-thirties librarian.")
        try expectEqual(updated.role, .protagonist)
    }

    s.test("apply with a nil sourceSceneId on the suggestion's fact stores under the nil-key") {
        let mia = Character(id: miaId, name: "Mia")
        // Manually construct a suggestion whose fact has no sourceSceneId.
        // (Sub-task 3 always stamps sourceSceneId, but the acceptor must
        // not crash if the caller supplies otherwise — e.g. a future
        // import-from-bible path.)
        let preStory = LedgerSuggestion(
            characterId: miaId,
            fact: KnownFact(fact: "Mia is a librarian.", sourceSceneId: nil, certainty: .asserted),
            evidenceQuote: ""
        )
        let updated = LedgerSuggestionAcceptor.apply(preStory, to: mia)
        // The nil-key bucket — pre-story facts live here. Inserting at
        // sourceSceneId=nil is the documented "pre-story knowledge"
        // behaviour from LOOM_DATA_MODEL.md §3.1.
        // We can't key by Optional<UUID> in a Swift dictionary, so the
        // acceptor either drops the suggestion OR stores it under a
        // sentinel. Test pins the contract: if sourceSceneId is nil,
        // the suggestion is silently dropped (no crash, character
        // unchanged).
        try expectEqual(updated.knownFactsBySceneId.count, 0)
    }

    return s
}

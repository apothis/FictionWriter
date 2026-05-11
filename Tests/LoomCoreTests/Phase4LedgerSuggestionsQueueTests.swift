import Foundation
@testable import LoomCore

/// Phase 4 #7 sub-task 3 — in-memory queue of pending
/// `LedgerSuggestion`s, keyed by character. The Bible inspector chip
/// (sub-task 4) reads `suggestions(forCharacter:)`; the accept/reject
/// handlers (sub-task 4) call `remove(_:)`. Persistence into the
/// bible is sub-task 5 — the queue itself is ephemeral and rebuilt
/// across app launches if extractions re-fire.
func phase4LedgerSuggestionsQueueTests() -> TestSuite {
    let s = TestSuite("Phase4LedgerSuggestionsQueue")

    let miaId = UUID()
    let andersId = UUID()
    let sceneId = UUID()

    func makeSuggestion(characterId: UUID, fact: String) -> LedgerSuggestion {
        LedgerSuggestion(
            characterId: characterId,
            fact: KnownFact(fact: fact, sourceSceneId: sceneId, certainty: .asserted),
            evidenceQuote: "..."
        )
    }

    s.test("new queue is empty for any character") {
        let q = LedgerSuggestionsQueue()
        try expectEqual(q.suggestions(forCharacter: miaId), [])
        try expectEqual(q.totalCount, 0)
    }

    s.test("add appends suggestions and groups them by character") {
        let q = LedgerSuggestionsQueue()
        q.add([
            makeSuggestion(characterId: miaId, fact: "a"),
            makeSuggestion(characterId: andersId, fact: "b"),
            makeSuggestion(characterId: miaId, fact: "c"),
        ])
        try expectEqual(q.suggestions(forCharacter: miaId).count, 2)
        try expectEqual(q.suggestions(forCharacter: andersId).count, 1)
        try expectEqual(q.totalCount, 3)
    }

    s.test("add preserves insertion order within a character") {
        let q = LedgerSuggestionsQueue()
        let s1 = makeSuggestion(characterId: miaId, fact: "first")
        let s2 = makeSuggestion(characterId: miaId, fact: "second")
        let s3 = makeSuggestion(characterId: miaId, fact: "third")
        q.add([s1, s2, s3])
        let got = q.suggestions(forCharacter: miaId)
        try expectEqual(got.map { $0.fact.fact }, ["first", "second", "third"])
    }

    s.test("remove drops a specific suggestion by fact id") {
        let q = LedgerSuggestionsQueue()
        let s1 = makeSuggestion(characterId: miaId, fact: "a")
        let s2 = makeSuggestion(characterId: miaId, fact: "b")
        q.add([s1, s2])
        q.remove(factId: s1.fact.id)
        let remaining = q.suggestions(forCharacter: miaId)
        try expectEqual(remaining.count, 1)
        try expectEqual(remaining[0].fact.fact, "b")
    }

    s.test("remove on a non-existent fact id is a no-op") {
        let q = LedgerSuggestionsQueue()
        let s1 = makeSuggestion(characterId: miaId, fact: "a")
        q.add([s1])
        q.remove(factId: UUID())
        try expectEqual(q.suggestions(forCharacter: miaId).count, 1)
    }

    s.test("clear(characterId:) empties just that character's queue") {
        let q = LedgerSuggestionsQueue()
        q.add([
            makeSuggestion(characterId: miaId, fact: "a"),
            makeSuggestion(characterId: miaId, fact: "b"),
            makeSuggestion(characterId: andersId, fact: "c"),
        ])
        q.clear(characterId: miaId)
        try expectEqual(q.suggestions(forCharacter: miaId), [])
        try expectEqual(q.suggestions(forCharacter: andersId).count, 1)
    }

    s.test("clearAll empties every character's queue") {
        let q = LedgerSuggestionsQueue()
        q.add([
            makeSuggestion(characterId: miaId, fact: "a"),
            makeSuggestion(characterId: andersId, fact: "b"),
        ])
        q.clearAll()
        try expectEqual(q.totalCount, 0)
    }

    s.test("add deduplicates by fact id if the same suggestion is added twice") {
        let q = LedgerSuggestionsQueue()
        let s1 = makeSuggestion(characterId: miaId, fact: "a")
        q.add([s1])
        q.add([s1])  // duplicate id
        try expectEqual(q.suggestions(forCharacter: miaId).count, 1)
    }

    return s
}

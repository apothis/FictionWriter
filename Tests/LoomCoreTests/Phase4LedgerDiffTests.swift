import Foundation
@testable import LoomCore

/// Phase 4 #7 sub-task 3 — diff extracted facts against the existing
/// per-character ledger and produce a `LedgerSuggestion` list for the
/// Bible-inspector Suggestions chip (sub-task 4). Pure-data.
///
/// Responsibilities pinned here:
/// - Resolve `extracted.characterId` (a name OR alias string) against
///   the bible's characters; drop facts whose character can't be
///   resolved (e.g. the model invented a new name).
/// - Drop facts whose `fact` text already appears (case-insensitive,
///   trimmed) anywhere on that character's existing ledger. The
///   §10.5 embedding-based dedup (cosine ≥ 0.85 paraphrases) is
///   sub-task 8 — this sub-task only catches verbatim duplicates.
/// - Stamp surviving facts with `sourceSceneId` + `addedAt` + a fresh
///   UUID so they're ready to persist on accept (sub-task 5).
/// - Preserve certainty + evidence_quote from the extraction.
func phase4LedgerDiffTests() -> TestSuite {
    let s = TestSuite("Phase4LedgerDiff")

    let mia = Character(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        name: "Mia",
        aliases: ["Miss Vance", "the librarian"]
    )
    let anders = Character(
        id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        name: "Anders",
        aliases: []
    )
    let sceneId = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    let now = Date(timeIntervalSince1970: 1_730_000_000)

    func emptyBible(_ characters: [Character]) -> Bible {
        var b = Bible()
        b.characters = characters
        return b
    }

    s.test("an extracted fact whose character_id doesn't resolve is dropped") {
        let extracted = [
            LedgerExtraction.ExtractedFact(
                characterId: "Ghost",
                fact: "Ghost did a thing.",
                certainty: .asserted,
                evidenceQuote: "Ghost did a thing."
            )
        ]
        let out = LedgerDiff.diff(
            extracted: extracted,
            bible: emptyBible([mia, anders]),
            sourceSceneId: sceneId,
            now: now
        )
        try expectEqual(out.count, 0)
    }

    s.test("an extracted fact with a known character_id produces one suggestion") {
        let extracted = [
            LedgerExtraction.ExtractedFact(
                characterId: "Mia",
                fact: "Mia opened the door.",
                certainty: .asserted,
                evidenceQuote: "Mia opened the door."
            )
        ]
        let out = LedgerDiff.diff(
            extracted: extracted,
            bible: emptyBible([mia, anders]),
            sourceSceneId: sceneId,
            now: now
        )
        try expectEqual(out.count, 1)
        try expectEqual(out[0].characterId, mia.id)
        try expectEqual(out[0].fact.fact, "Mia opened the door.")
        try expectEqual(out[0].fact.certainty, .asserted)
        try expectEqual(out[0].fact.sourceSceneId, sceneId)
        try expectEqual(out[0].fact.addedAt, now)
        try expectEqual(out[0].evidenceQuote, "Mia opened the door.")
    }

    s.test("alias resolution is case-insensitive and matches any alias") {
        let extracted = [
            LedgerExtraction.ExtractedFact(
                characterId: "the LIBRARIAN",  // alias, weird case
                fact: "She drank wine alone.",
                certainty: .asserted,
                evidenceQuote: "wine alone"
            ),
            LedgerExtraction.ExtractedFact(
                characterId: "miss vance",      // alias, lowercase
                fact: "She locked the door.",
                certainty: .asserted,
                evidenceQuote: "locked"
            ),
        ]
        let out = LedgerDiff.diff(
            extracted: extracted,
            bible: emptyBible([mia, anders]),
            sourceSceneId: sceneId,
            now: now
        )
        try expectEqual(out.count, 2)
        try expectEqual(out[0].characterId, mia.id)
        try expectEqual(out[1].characterId, mia.id)
    }

    s.test("a fact whose text exactly matches an existing ledger entry on the same character is dropped") {
        var miaWithFact = mia
        let existing = KnownFact(
            id: UUID(),
            fact: "Mia opened the door.",
            sourceSceneId: UUID(),  // from some prior scene
            certainty: .asserted,
            addedAt: Date(timeIntervalSince1970: 1_000_000_000)
        )
        miaWithFact.knownFactsBySceneId[existing.sourceSceneId!] = [existing]

        let extracted = [
            LedgerExtraction.ExtractedFact(
                characterId: "Mia",
                fact: "Mia opened the door.",  // same text
                certainty: .asserted,
                evidenceQuote: "..."
            )
        ]
        let out = LedgerDiff.diff(
            extracted: extracted,
            bible: emptyBible([miaWithFact, anders]),
            sourceSceneId: sceneId,
            now: now
        )
        try expectEqual(out.count, 0)
    }

    s.test("existing-fact text match is case-insensitive and ignores leading/trailing whitespace") {
        var miaWithFact = mia
        let existing = KnownFact(
            id: UUID(),
            fact: "  MIA opened the door.  ",
            sourceSceneId: UUID(),
            certainty: .asserted
        )
        miaWithFact.knownFactsBySceneId[existing.sourceSceneId!] = [existing]

        let extracted = [
            LedgerExtraction.ExtractedFact(
                characterId: "Mia",
                fact: "mia OPENED the door.",
                certainty: .asserted,
                evidenceQuote: "..."
            )
        ]
        let out = LedgerDiff.diff(
            extracted: extracted,
            bible: emptyBible([miaWithFact, anders]),
            sourceSceneId: sceneId,
            now: now
        )
        try expectEqual(out.count, 0)
    }

    s.test("existing fact on a DIFFERENT character doesn't block a new fact on this character") {
        var andersWithFact = anders
        andersWithFact.knownFactsBySceneId[UUID()] = [
            KnownFact(fact: "Mia opened the door.", certainty: .asserted)
        ]
        let extracted = [
            LedgerExtraction.ExtractedFact(
                characterId: "Mia",
                fact: "Mia opened the door.",
                certainty: .asserted,
                evidenceQuote: "..."
            )
        ]
        let out = LedgerDiff.diff(
            extracted: extracted,
            bible: emptyBible([mia, andersWithFact]),
            sourceSceneId: sceneId,
            now: now
        )
        try expectEqual(out.count, 1)
        try expectEqual(out[0].characterId, mia.id)
    }

    s.test("multiple extracted facts produce multiple ordered suggestions") {
        let extracted = [
            LedgerExtraction.ExtractedFact(
                characterId: "Mia",
                fact: "Mia opened the door.",
                certainty: .asserted,
                evidenceQuote: "a"
            ),
            LedgerExtraction.ExtractedFact(
                characterId: "Anders",
                fact: "Anders stood in the rain.",
                certainty: .asserted,
                evidenceQuote: "b"
            ),
            LedgerExtraction.ExtractedFact(
                characterId: "Mia",
                fact: "Mia spoke softly.",
                certainty: .asserted,
                evidenceQuote: "c"
            ),
        ]
        let out = LedgerDiff.diff(
            extracted: extracted,
            bible: emptyBible([mia, anders]),
            sourceSceneId: sceneId,
            now: now
        )
        try expectEqual(out.count, 3)
        try expectEqual(out[0].fact.fact, "Mia opened the door.")
        try expectEqual(out[1].fact.fact, "Anders stood in the rain.")
        try expectEqual(out[2].fact.fact, "Mia spoke softly.")
    }

    s.test("each suggestion's KnownFact gets a fresh UUID (collision-free)") {
        let extracted = [
            LedgerExtraction.ExtractedFact(characterId: "Mia", fact: "a", certainty: .asserted, evidenceQuote: ""),
            LedgerExtraction.ExtractedFact(characterId: "Mia", fact: "b", certainty: .asserted, evidenceQuote: ""),
            LedgerExtraction.ExtractedFact(characterId: "Mia", fact: "c", certainty: .asserted, evidenceQuote: ""),
        ]
        let out = LedgerDiff.diff(
            extracted: extracted,
            bible: emptyBible([mia]),
            sourceSceneId: sceneId,
            now: now
        )
        let ids = Set(out.map { $0.fact.id })
        try expectEqual(ids.count, out.count)
    }

    return s
}

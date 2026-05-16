import Foundation
@testable import LoomCore

/// Phase 5 — GLiNER as the discovery detection step. Pure-data checks
/// for the GLiNER-entity → discovery-candidate conversion.
func glinerCandidateDetectorTests() -> TestSuite {
    let s = TestSuite("GLiNERCandidateDetector")

    func scalars(_ text: String) -> [UnicodeScalar] { Array(text.unicodeScalars) }

    s.test("enclosingSentence returns the single sentence around a span") {
        let text = "Marek drew the dagger in the cathedral."
        // "dagger" is scalars 15..<21.
        let quote = GLiNERCandidateDetector.enclosingSentence(
            scalars: scalars(text), start: 15, end: 21
        )
        try expectEqual(quote, "Marek drew the dagger in the cathedral.")
    }

    s.test("enclosingSentence isolates the span's own sentence in multi-sentence prose") {
        let text = "She ran for the door. Marek fought the guard. Night fell."
        // "Marek" begins at scalar 22.
        let quote = GLiNERCandidateDetector.enclosingSentence(
            scalars: scalars(text), start: 22, end: 27
        )
        try expectEqual(quote, "Marek fought the guard.")
    }

    s.test("candidates maps GLiNER entities to Candidate values by kind") {
        let text = "Marek drew the dagger in the cathedral."
        let entities = [
            GLiNEREntity(start: 0, end: 5, text: "Marek", label: "character", score: 0.9),
            GLiNEREntity(start: 15, end: 21, text: "dagger", label: "object", score: 0.65),
            GLiNEREntity(start: 29, end: 38, text: "cathedral", label: "place", score: 0.9),
        ]
        let candidates = GLiNERCandidateDetector.candidates(from: entities, sourceText: text)
        try expectEqual(candidates.map(\.surface), ["Marek", "dagger", "cathedral"])
        try expectEqual(candidates.map(\.kind), [.character, .object, .place])
        try expectEqual(candidates[0].firstSeenQuote, "Marek drew the dagger in the cathedral.")
    }

    s.test("candidates drops entities whose label is not a known Kind") {
        let entities = [
            GLiNEREntity(start: 0, end: 5, text: "Marek", label: "character", score: 0.9),
            GLiNEREntity(start: 6, end: 11, text: "today", label: "date", score: 0.9),
        ]
        let candidates = GLiNERCandidateDetector.candidates(
            from: entities, sourceText: "Marek today"
        )
        try expectEqual(candidates.map(\.surface), ["Marek"])
    }

    return s
}

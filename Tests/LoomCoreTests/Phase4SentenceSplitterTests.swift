import Foundation
@testable import LoomCore

/// Phase 4 #7 sub-task 8 — sentence splitter used by the evidence-
/// quote validation filter. Conservative heuristics; tested against
/// the kinds of prose Loom actually feeds it.
func phase4SentenceSplitterTests() -> TestSuite {
    let s = TestSuite("Phase4SentenceSplitter")

    s.test("splits on terminator followed by whitespace") {
        let prose = "Mia drank wine. She watched the rain. Anders waited."
        try expectEqual(SentenceSplitter.split(prose), [
            "Mia drank wine.",
            "She watched the rain.",
            "Anders waited.",
        ])
    }

    s.test("preserves quoted-question intact (no split on ? inside quotes)") {
        let prose = "Mia asked, \"Who is it?\" She held her breath."
        try expectEqual(SentenceSplitter.split(prose), [
            "Mia asked, \"Who is it?\"",
            "She held her breath.",
        ])
    }

    s.test("splits on paragraph breaks even without terminator") {
        let prose = "Mia drank wine\n\nAnders waited"
        try expectEqual(SentenceSplitter.split(prose), [
            "Mia drank wine",
            "Anders waited",
        ])
    }

    s.test("collapses multiple adjacent terminators into one sentence") {
        let prose = "Anders shouted!? Mia stayed quiet."
        try expectEqual(SentenceSplitter.split(prose), [
            "Anders shouted!?",
            "Mia stayed quiet.",
        ])
    }

    s.test("empty prose returns empty list") {
        try expectEqual(SentenceSplitter.split(""), [])
    }

    s.test("prose without terminators returns single tail sentence") {
        try expectEqual(SentenceSplitter.split("Mia drank wine"), ["Mia drank wine"])
    }

    return s
}

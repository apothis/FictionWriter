import Foundation
@testable import LoomCore

/// Sub-step 1.f — pure word-count helper. Per the contract: "handles
/// markdown headers, blockquotes, italics correctly." The algorithm
/// treats markdown markers (`# > _ * ~ ``) and em-dashes as word
/// separators; hyphens and apostrophes are preserved (so "well-known"
/// is one word and "don't" is one word). Any token containing at least
/// one non-separator character counts.
func phase1EditorWordCountTests() -> TestSuite {
    let s = TestSuite("Phase1EditorWordCount")

    s.test("plain prose words counted by whitespace") {
        try expectEqual(WordCount.count("the wind had been picking up"), 6)
    }

    s.test("markdown header strips leading hash markers") {
        try expectEqual(WordCount.count("# Chapter Twelve"), 2)
        try expectEqual(WordCount.count("## Section title here"), 3)
    }

    s.test("blockquote strips leading angle marker") {
        try expectEqual(WordCount.count("> She thought quietly."), 3)
    }

    s.test("italic and bold markers count contained words once") {
        try expectEqual(WordCount.count("_italics_ and **bold**"), 3)
    }

    s.test("em-dash separates adjoining words") {
        try expectEqual(WordCount.count("well—she said"), 3)
    }

    s.test("hyphenated compound counts as one word") {
        try expectEqual(WordCount.count("well-known fact"), 2)
    }

    s.test("apostrophe in contraction counts as one word") {
        try expectEqual(WordCount.count("don't go"), 2)
    }

    s.test("multi-paragraph prose spans newlines") {
        let prose = "First paragraph here.\n\nSecond paragraph follows."
        try expectEqual(WordCount.count(prose), 6)
    }

    s.test("empty string yields zero") {
        try expectEqual(WordCount.count(""), 0)
    }

    s.test("whitespace-only yields zero") {
        try expectEqual(WordCount.count("   \n\t  "), 0)
    }

    s.test("punctuation alone yields zero") {
        try expectEqual(WordCount.count("...!? — "), 0)
    }

    return s
}

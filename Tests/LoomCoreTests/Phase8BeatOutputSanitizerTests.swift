import Foundation
@testable import LoomCore

// Phase 8.b.x — sanitize writer-emitted text before it lands in the
// rolling per-beat prose buffer. Two failures we're guarding against,
// both directly observable in `<project>/generation-log/*.json` from
// the 2026-05-15 live smoke:
//
// 1. Meta-block leakage. The writer LLM (gemma-4-31B-Deckard-Heretic-
//    Thinking) hallucinates prompt-shaped self-validation blocks like
//    `[VALIDATE BEAT]` + `Length check: ...` + `Pacing: ...` or
//    `[BEAT CHECK]` + `Length: ...` after a beat completes. The
//    pattern propagates: once it lands in `insertedText`, every
//    subsequent beat sees it in `[BEATS BEFORE THIS]` and learns to
//    repeat it.
// 2. Trailing whitespace runs. The writer emits multi-blank-line
//    padding before meta-blocks. The `\n\n` inter-beat separator
//    in TemplateGenerationCoordinator compounds them into 6+ blank
//    lines between adjacent beats.
//
// The sanitizer is the post-stream-pre-insert filter that fixes both.
// Stop sequences (extended in the same commit) are a preventive
// upstream layer; this is the defense-in-depth pass.

func phase8BeatOutputSanitizerTests() -> TestSuite {
    let s = TestSuite("Phase8BeatOutputSanitizer")

    s.test("clean prose passes through unchanged") {
        let input = "She walked the road. The road was long.\n\n\"Where are you going?\" he asked."
        try expectEqual(BeatOutputSanitizer.strip(input), input)
    }

    s.test("strips trailing [VALIDATE BEAT] block (exact leak observed in 2026-05-15 smoke)") {
        let input = """
            Maya bites Emily's shoulder. "I want you right now," she whimpers. Emily shoves her back, pinning Maya against the brick. She drops down to pull Maya's pants away. Fingers find damp folds, hot and slippery. She tongues one swelling nipple while shoving two fingers deep inside.



            [VALIDATE BEAT]
            Length check: 54 words (Within range?). Yes.
            Pacing: Sentences = [1, 6, 7,
            """
        let cleaned = BeatOutputSanitizer.strip(input)
        try expectFalse(cleaned.contains("[VALIDATE BEAT]"))
        try expectFalse(cleaned.contains("Length check"))
        try expectFalse(cleaned.contains("Pacing: Sentences"))
        // Prose is preserved.
        try expectTrue(cleaned.contains("Maya bites Emily's shoulder"))
        try expectTrue(cleaned.contains("two fingers deep inside."))
    }

    s.test("strips trailing [BEAT CHECK] block (second leak shape)") {
        let input = """
            Emily presses a lingering kiss into her earlobe and murmurs a dirty promise about tonight. She lets her go with a wink.



            [BEAT CHECK]
            Length: 54 words
            Dialogue ratio: 0%
            Sentence length distribution: 8, 12, 20, 6, 7
            """
        let cleaned = BeatOutputSanitizer.strip(input)
        try expectFalse(cleaned.contains("[BEAT CHECK]"))
        try expectFalse(cleaned.contains("Length:"))
        try expectFalse(cleaned.contains("Dialogue ratio"))
        try expectTrue(cleaned.contains("lingering kiss"))
    }

    s.test("strips standalone Length-check / Pacing meta lines even without bracket header") {
        // Model variants emit the body without the `[X BEAT]` wrapper.
        let input = """
            She turned and walked into the dark.

            Length check: 50 words (Within range?). Yes.
            Pacing: Sentences = [8, 12, 4].
            """
        let cleaned = BeatOutputSanitizer.strip(input)
        try expectFalse(cleaned.contains("Length check"))
        try expectFalse(cleaned.contains("Pacing: Sentences"))
        try expectTrue(cleaned.contains("walked into the dark"))
    }

    s.test("collapses runs of 3+ newlines down to 2 (cleans inter-beat whitespace pileup)") {
        let input = "First paragraph.\n\n\n\n\n\nSecond paragraph after six newlines."
        let cleaned = BeatOutputSanitizer.strip(input)
        try expectEqual(cleaned, "First paragraph.\n\nSecond paragraph after six newlines.")
    }

    s.test("trims trailing whitespace") {
        let input = "Final line of prose.   \n\n\n  "
        let cleaned = BeatOutputSanitizer.strip(input)
        try expectEqual(cleaned, "Final line of prose.")
    }

    s.test("preserves intentional paragraph breaks (\\n\\n stays \\n\\n)") {
        let input = "Paragraph one.\n\nParagraph two.\n\nParagraph three."
        let cleaned = BeatOutputSanitizer.strip(input)
        try expectEqual(cleaned, input)
    }

    s.test("does not eat prose that legitimately contains the word 'Length' or 'Pacing'") {
        // Guard against over-aggressive matching. "Length" as part of
        // a real sentence (not a meta-line shape) must survive.
        let input = "The length of her hair surprised him. The pacing of the music quickened."
        try expectEqual(BeatOutputSanitizer.strip(input), input)
    }

    s.test("end-to-end: full beat output with leakage + trailing blanks") {
        // Reproduces the actual pattern seen in 2026-05-15 gen-log:
        // beat prose, six blank lines, [VALIDATE BEAT] block.
        let input = """
            Maya wraps her arms around Emily. "You missed me," she purrs.

            "Very much."






            [VALIDATE BEAT]
            Length check: 54 words. Yes.
            Pacing: Sentences = [4, 2,
            """
        let cleaned = BeatOutputSanitizer.strip(input)
        try expectFalse(cleaned.contains("[VALIDATE BEAT]"))
        try expectFalse(cleaned.contains("Length check"))
        try expectFalse(cleaned.contains("\n\n\n"),
                       "no run of 3+ newlines should remain:\n\(cleaned)")
        try expectTrue(cleaned.contains("\"Very much.\""))
        try expectTrue(cleaned.hasSuffix("\"Very much.\""))
    }

    return s
}

import Foundation
@testable import LoomCore

/// Phase 4 §15.9 follow-on — streaming-aware companion to
/// `ThinkBlockStripper`. The post-finish stripper still runs as
/// defence-in-depth at generation finish, but with Gemma 4 31B as
/// the writer (which always emits a `<|channel>thought\n...\n
/// <channel|>` wrapper on every generation), the user sees the
/// thinking tags + their content on every streaming Continue /
/// rewrite for ~60–120 seconds before they get stripped. This
/// stripper threads the token stream and swallows tokens that fall
/// inside a thinking block, so the user never sees them in the
/// editor.
///
/// Contract:
/// - Stateful: each generation gets its own `StreamingThinkBlockStripper`
///   instance, reset on `didStart`.
/// - `consume(token)` returns the **clean text to insert** for that
///   token (may be `""` while inside a thinking block, may be longer
///   than `token` if a buffered prefix flushes through).
/// - `flush()` at end-of-stream returns any safely-bufferable
///   residue. Unclosed thinking blocks are preserved (mirrors the
///   post-finish stripper's "don't swallow unclosed" rule).
/// - Handles both Qwen `<think>...</think>` and Gemma 4
///   `<|channel>thought\n...\n<channel|>` formats.
/// - Handles token boundaries that split tags ("<thi" + "nk>",
///   "<|cha" + "nnel>thought", "</thi" + "nk>").
/// - Stray `<` or `<word>` that doesn't form an opening tag flushes
///   through as ordinary text (the editor's prose can contain angle
///   brackets — preserves them).
func phase4StreamingThinkBlockStripperTests() -> TestSuite {
    let s = TestSuite("Phase4StreamingThinkBlockStripper")

    // MARK: - Plain text passthrough

    s.test("plain text without any tags flushes through verbatim") {
        var stripper = StreamingThinkBlockStripper()
        var output = ""
        for token in ["Hello, ", "world!", " The cat sat ", "on the mat."] {
            output += stripper.consume(token)
        }
        output += stripper.flush()
        try expectEqual(output, "Hello, world! The cat sat on the mat.")
    }

    s.test("single empty consume returns empty") {
        var stripper = StreamingThinkBlockStripper()
        try expectEqual(stripper.consume(""), "")
        try expectEqual(stripper.flush(), "")
    }

    // MARK: - Qwen <think>...</think>

    s.test("Qwen single-token think block strips the block, keeps trailing prose") {
        var stripper = StreamingThinkBlockStripper()
        let out = stripper.consume("<think>internal reasoning here</think>actual prose")
        try expectEqual(out + stripper.flush(), "actual prose")
    }

    s.test("Qwen think block split across many tiny tokens still strips cleanly") {
        var stripper = StreamingThinkBlockStripper()
        let tokens = ["<", "thi", "nk", ">", "I should ", "consider...", "</", "thi", "nk", ">", "\n\n", "She walked away."]
        var out = ""
        for t in tokens { out += stripper.consume(t) }
        out += stripper.flush()
        try expectEqual(out, "She walked away.")
    }

    s.test("Qwen think block with prose before it preserves the preceding prose") {
        var stripper = StreamingThinkBlockStripper()
        let tokens = ["Some intro text. ", "<think>", "thinking...", "</think>", "And then the rest."]
        var out = ""
        for t in tokens { out += stripper.consume(t) }
        out += stripper.flush()
        try expectEqual(out, "Some intro text. And then the rest.")
    }

    s.test("Qwen unclosed think block preserves the partial leak at flush (don't swallow forever)") {
        var stripper = StreamingThinkBlockStripper()
        let tokens = ["<think>", "the model truncated mid-thought"]
        var out = ""
        for t in tokens { out += stripper.consume(t) }
        out += stripper.flush()
        try expectEqual(out, "<think>the model truncated mid-thought")
    }

    // MARK: - Gemma 4 <|channel>thought\n...\n<channel|>

    s.test("Gemma 4 single-token thought block strips cleanly") {
        var stripper = StreamingThinkBlockStripper()
        let out = stripper.consume("<|channel>thought\nreasoning body<channel|>actual prose")
        try expectEqual(out + stripper.flush(), "actual prose")
    }

    s.test("Gemma 4 empty thought block (thinking disabled but tags still emitted) strips cleanly") {
        var stripper = StreamingThinkBlockStripper()
        let out = stripper.consume("<|channel>thought<channel|>She turned the key.")
        try expectEqual(out + stripper.flush(), "She turned the key.")
    }

    s.test("Gemma 4 thought block split across many tiny tokens still strips cleanly") {
        var stripper = StreamingThinkBlockStripper()
        let tokens = ["<|", "channel>", "thought", "\n", "reasoning ", "here", "<", "channel", "|>", "\n\n", "She walked away."]
        var out = ""
        for t in tokens { out += stripper.consume(t) }
        out += stripper.flush()
        try expectEqual(out, "She walked away.")
    }

    s.test("Gemma 4 unclosed thought block preserves partial leak at flush") {
        var stripper = StreamingThinkBlockStripper()
        let tokens = ["<|channel>thought\n", "I should weigh the options"]
        var out = ""
        for t in tokens { out += stripper.consume(t) }
        out += stripper.flush()
        try expectEqual(out, "<|channel>thought\nI should weigh the options")
    }

    // MARK: - Angle-bracket false-positives

    s.test("stray angle bracket in prose (not part of any tag) flushes through") {
        var stripper = StreamingThinkBlockStripper()
        let tokens = ["She wore a <", "blue> ", "dress that night."]
        var out = ""
        for t in tokens { out += stripper.consume(t) }
        out += stripper.flush()
        try expectEqual(out, "She wore a <blue> dress that night.")
    }

    s.test("text containing '<th' but not '<think>' flushes through") {
        var stripper = StreamingThinkBlockStripper()
        let tokens = ["The <th", "eatre> was empty."]
        var out = ""
        for t in tokens { out += stripper.consume(t) }
        out += stripper.flush()
        try expectEqual(out, "The <theatre> was empty.")
    }

    s.test("text containing '<|c' but not '<|channel>thought' flushes through") {
        var stripper = StreamingThinkBlockStripper()
        let tokens = ["The pipe glyph <|c", "ode|> ", "appeared in the diff."]
        var out = ""
        for t in tokens { out += stripper.consume(t) }
        out += stripper.flush()
        try expectEqual(out, "The pipe glyph <|code|> appeared in the diff.")
    }

    s.test("text ending mid-possible-tag at flush keeps the partial as-is") {
        // "<thin" at flush could have become <think> but didn't —
        // preserve it rather than swallow.
        var stripper = StreamingThinkBlockStripper()
        let out = stripper.consume("She wrote <thin")
        try expectEqual(out + stripper.flush(), "She wrote <thin")
    }

    // MARK: - Mixed / sequence

    s.test("multiple Qwen think blocks in a single stream all get stripped") {
        var stripper = StreamingThinkBlockStripper()
        let tokens = ["<think>first</think>", "Visible part one. ", "<think>second</think>", "Visible part two."]
        var out = ""
        for t in tokens { out += stripper.consume(t) }
        out += stripper.flush()
        try expectEqual(out, "Visible part one. Visible part two.")
    }

    s.test("Gemma 4 thought + Qwen think in the same stream both get stripped") {
        var stripper = StreamingThinkBlockStripper()
        let tokens = ["<|channel>thought\nfirst reasoning<channel|>", "Visible. ", "<think>second</think>", "More visible."]
        var out = ""
        for t in tokens { out += stripper.consume(t) }
        out += stripper.flush()
        try expectEqual(out, "Visible. More visible.")
    }

    return s
}

import Foundation
@testable import LoomCore

/// Sub-step: post-finish safety net that strips Qwen-style
/// `<think>...</think>` blocks from generated prose. The ChatML
/// prefill suppresses thinking in most cases; this catches what
/// leaks through.
func phase1ThinkBlockStripperTests() -> TestSuite {
    let s = TestSuite("Phase1ThinkBlockStripper")

    s.test("plain prose passes through unchanged") {
        let input = "She walked into the room and looked around."
        try expectEqual(ThinkBlockStripper.strip(input), input)
    }

    s.test("single think block at start is removed along with trailing whitespace") {
        let input = "<think>I should write something dramatic.</think>\n\nShe walked into the room."
        try expectEqual(ThinkBlockStripper.strip(input), "She walked into the room.")
    }

    s.test("think block spanning multiple lines is removed") {
        let input = "<think>\nFirst, set the scene.\nThen, introduce conflict.\n</think>\n\nThe wind howled."
        try expectEqual(ThinkBlockStripper.strip(input), "The wind howled.")
    }

    s.test("multiple think blocks are all removed") {
        let input = "<think>thought one</think>\n\nFirst sentence. <think>thought two</think>\n\nSecond sentence."
        let output = ThinkBlockStripper.strip(input)
        try expectFalse(output.contains("<think>"))
        try expectFalse(output.contains("thought"))
        try expectTrue(output.contains("First sentence."))
        try expectTrue(output.contains("Second sentence."))
    }

    s.test("unclosed <think> tag is left intact — partial-leak signal preserved") {
        // Defensive: a bare opening tag without a close shouldn't
        // swallow the rest of the prose. (The runtime should rarely
        // hit this — the model either emits a full block or none.)
        let input = "<think>unclosed musing, then prose"
        let output = ThinkBlockStripper.strip(input)
        try expectEqual(output, input)
    }

    s.test("empty input is empty output") {
        try expectEqual(ThinkBlockStripper.strip(""), "")
    }

    s.test("input that is entirely a think block strips to empty") {
        let input = "<think>just thinking, no prose</think>"
        try expectEqual(ThinkBlockStripper.strip(input), "")
    }

    // MARK: - Gemma 4 reasoning format (added 2026-05-13)
    //
    // Per https://ai.google.dev/gemma/docs/capabilities/thinking
    // Gemma 4 uses `<|channel>thought\n[reasoning]<channel|>` for
    // its CoT output, NOT the `<think>...</think>` Qwen format.
    // Even when thinking is disabled, the model still emits the
    // tags with an empty thought block: `<|channel>thought\n
    // <channel|>[answer]`. Both forms must be stripped.

    s.test("Gemma 4 empty-thought wrapper at start is stripped") {
        let input = "<|channel>thought\n<channel|>But he speaks anyway, his voice ragged."
        try expectEqual(ThinkBlockStripper.strip(input), "But he speaks anyway, his voice ragged.")
    }

    s.test("Gemma 4 filled-thought wrapper at start is stripped") {
        let input = "<|channel>thought\nThe scene is intimate; I should match the prior voice.\n<channel|>She turned to face him."
        try expectEqual(ThinkBlockStripper.strip(input), "She turned to face him.")
    }

    s.test("Gemma 4 thought wrapper spanning multiple lines is stripped") {
        let input = "<|channel>thought\nFirst, set tone.\nThen, advance plot.\n<channel|>\n\nThe rain began."
        try expectEqual(ThinkBlockStripper.strip(input), "The rain began.")
    }

    s.test("Gemma 4 unclosed <|channel> tag is left intact — partial-leak signal preserved") {
        let input = "<|channel>thought\nunclosed reasoning, then prose"
        let output = ThinkBlockStripper.strip(input)
        try expectEqual(output, input)
    }

    s.test("Gemma 4 entire-thought-only input strips to empty") {
        let input = "<|channel>thought\n<channel|>"
        try expectEqual(ThinkBlockStripper.strip(input), "")
    }

    s.test("mixed Qwen + Gemma tags in the same input both get stripped") {
        // Unlikely in production (writer model is one family at a
        // time), but the stripper should be defensive enough to
        // handle either or both.
        let input = "<think>qwen thought</think>\n\n<|channel>thought\n<channel|>The actual prose."
        try expectEqual(ThinkBlockStripper.strip(input), "The actual prose.")
    }

    return s
}

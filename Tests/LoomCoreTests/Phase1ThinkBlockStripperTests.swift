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

    return s
}

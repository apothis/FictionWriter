import Foundation
@testable import LoomCore

/// Sub-step 1.m — pure refusal-detection regex. Used by
/// GenerationCoordinator to set GenerationLogEntry.response.refusal-
/// Detected = true so the History tab can chip the row yellow.
///
/// Per LOOM_RESEARCH.md / RPClient feedback_quirk_detectors: refusal
/// is a *signal*, never a *block*. Loom never refuses to insert; it
/// surfaces the signal so the user can spot mode-failure.
func phase1RefusalDetectionTests() -> TestSuite {
    let s = TestSuite("Phase1RefusalDetection")

    s.test("detects 'I cannot' refusal") {
        try expectTrue(RefusalDetector.looksLikeRefusal(
            "I cannot help with that request."
        ))
    }

    s.test("detects 'I'm sorry, but' refusal") {
        try expectTrue(RefusalDetector.looksLikeRefusal(
            "I'm sorry, but I can't continue this story."
        ))
    }

    s.test("detects 'as an AI' meta-comment refusal") {
        try expectTrue(RefusalDetector.looksLikeRefusal(
            "As an AI language model, I'm not able to write that scene."
        ))
    }

    s.test("detects 'I won't' refusal") {
        try expectTrue(RefusalDetector.looksLikeRefusal(
            "I won't generate explicit content."
        ))
    }

    s.test("normal narrative prose is NOT detected as refusal") {
        try expectFalse(RefusalDetector.looksLikeRefusal(
            "She walked into the room, glancing back over her shoulder."
        ))
    }

    s.test("dialogue containing 'I cannot' (in-character) is NOT a false positive on length") {
        // Heuristic: if the suspicious phrase appears within a long
        // chunk of clearly-narrative prose, it's probably dialogue.
        // The detector only fires when the response itself is short
        // (typical refusals are 1-3 sentences). For Phase 1 we
        // require the response to be SHORT for refusal detection.
        let longProse = String(repeating: "She walked the long road. ", count: 30)
        + #"He said, "I cannot leave her behind." "# +
        String(repeating: "The wind picked up. ", count: 30)
        try expectFalse(RefusalDetector.looksLikeRefusal(longProse))
    }

    s.test("empty string is not a refusal") {
        try expectFalse(RefusalDetector.looksLikeRefusal(""))
    }

    return s
}

import Foundation
@testable import LoomCore

/// Pure-data heuristic classifier — Phase 5 scope-lock #5 baseline
/// per [LOOM_NARRATIVE_MODE_SPIKE](LOOM_NARRATIVE_MODE_SPIKE.md) §3.2(a).
/// Quote-density gate for dialogue (research expects near-perfect
/// precision there); verb/cognition/sensory ratios for the rest;
/// temporal-compression markers for summary; `mixed` fallback.
func phase5NarrativeModeHeuristicTests() -> TestSuite {
    let s = TestSuite("Phase5NarrativeModeHeuristic")

    // MARK: - Dialogue gate (the easy one)

    s.test("dialogue-heavy text classifies as dialogue") {
        let text = "\"Come here,\" she said. \"I want to talk.\""
        try expectEqual(NarrativeModeHeuristic.classify(text), .dialogue)
    }

    s.test("short pure-dialogue (single line) classifies as dialogue") {
        try expectEqual(NarrativeModeHeuristic.classify("\"Stop,\" she said."), .dialogue)
    }

    s.test("dialogue with attribution beats still classifies as dialogue") {
        let text = "\"It is nothing,\" she said.\n\n\"It is not nothing.\"\n\n\"It is.\""
        try expectEqual(NarrativeModeHeuristic.classify(text), .dialogue)
    }

    s.test("text with no quotes never classifies as dialogue") {
        let text = "He walked across the room. He sat down. He waited."
        try expectFalse(NarrativeModeHeuristic.classify(text) == .dialogue)
    }

    // MARK: - Summary (compressed-time markers)

    s.test("temporal-compression markers classify as summary") {
        let text = "For three weeks she avoided him. By the time she stopped, she had forgotten why she had started."
        try expectEqual(NarrativeModeHeuristic.classify(text), .summary)
    }

    s.test("had-been -ing past-perfect-progressive marks summary") {
        let text = "They had been seeing each other for six months when she found the photograph."
        try expectEqual(NarrativeModeHeuristic.classify(text), .summary)
    }

    // MARK: - Interiority (cognition verbs / free-indirect)

    s.test("cognition-verb-heavy text classifies as interiority") {
        let text = "She thought, I should go. She thought, but I will not. She wondered if she had ever known the difference."
        try expectEqual(NarrativeModeHeuristic.classify(text), .interiority)
    }

    s.test("free-indirect markers (would/might/could without subject attribution) classify as interiority") {
        let text = "She felt the slow grief which had attended them both these last hours. The room would be cold by morning, she knew. She might never come back."
        try expectEqual(NarrativeModeHeuristic.classify(text), .interiority)
    }

    // MARK: - Description (sensory / suspended-time / low verb density)

    s.test("static-description text classifies as description") {
        let text = "The kitchen was painted yellow. There was a calendar on the wall from two years ago. The refrigerator hummed. Sun came in over the back of the chair."
        try expectEqual(NarrativeModeHeuristic.classify(text), .description)
    }

    s.test("sensory-environment text classifies as description") {
        let text = "The room smelled of old smoke and lavender. A radiator ticked. The bedspread was wool, dark green, frayed at the corner."
        try expectEqual(NarrativeModeHeuristic.classify(text), .description)
    }

    // MARK: - Action (concrete verbs, scene-time progression)

    s.test("active-verb-heavy text classifies as action") {
        let text = "He kicked the door. The lock held. He kicked it again. On the third kick the frame splintered and the door swung in."
        try expectEqual(NarrativeModeHeuristic.classify(text), .action)
    }

    s.test("clipped-prose action sequence classifies as action") {
        let text = "She locked the door. He sat on the bed. The light was bad. She did not switch it on."
        try expectEqual(NarrativeModeHeuristic.classify(text), .action)
    }

    // MARK: - Fallback

    s.test("text with no strong signal falls back to mixed") {
        let text = "And."
        try expectEqual(NarrativeModeHeuristic.classify(text), .mixed)
    }

    s.test("empty text falls back to mixed") {
        try expectEqual(NarrativeModeHeuristic.classify(""), .mixed)
    }

    return s
}

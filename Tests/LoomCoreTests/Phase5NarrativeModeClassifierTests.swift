import Foundation
@testable import LoomCore

/// Two-pass narrative-mode classifier — Phase 5 scope-lock #5
/// closing surface. Per [LOOM_NARRATIVE_MODE_SPIKE](LOOM_NARRATIVE_MODE_SPIKE.md)
/// §8 empirical results, the heuristic dialogue-gate (87% recall, 100%
/// precision) significantly outperforms gemma-31B-zero-shot on
/// dialogue (37% recall); the LLM in turn beats the heuristic on the
/// other five categories. Composition: heuristic first, fall through
/// to LLM when heuristic doesn't say dialogue.
func phase5NarrativeModeClassifierTests() -> TestSuite {
    let s = TestSuite("Phase5NarrativeModeClassifier")

    s.test("heuristic dialogue verdict short-circuits the LLM call") {
        var llmCalled = false
        let pred = NarrativeModeClassifier.classify("\"Hello,\" she said.") { _ in
            llmCalled = true
            return .action // would be wrong if used
        }
        try expectEqual(pred, .dialogue)
        try expectFalse(llmCalled, "LLM should not be called when heuristic catches dialogue")
    }

    s.test("non-dialogue chunk delegates to the LLM") {
        var llmCalled = false
        var receivedText: String?
        let pred = NarrativeModeClassifier.classify("She walked across the room and sat down.") { text in
            llmCalled = true
            receivedText = text
            return .action
        }
        try expectTrue(llmCalled, "LLM should be called for non-dialogue chunks")
        try expectEqual(receivedText, "She walked across the room and sat down.")
        try expectEqual(pred, .action)
    }

    s.test("LLM returning nil falls back to the heuristic verdict") {
        // Network error etc. The heuristic verdict is at least a
        // defensible mode; better than refusing to classify the chunk
        // (which would leave modality=nil in the index sidecar).
        let pred = NarrativeModeClassifier.classify(
            "She thought, I should leave. She thought, but I won't. She wondered why."
        ) { _ in nil }
        try expectEqual(pred, .interiority)
    }

    s.test("LLM returning .mixed is respected (not overridden by heuristic)") {
        // The LLM expressing low confidence via `mixed` is meaningful
        // signal — don't second-guess it from the heuristic.
        let pred = NarrativeModeClassifier.classify(
            "She walked across the room.",
            via: { _ in .mixed }
        )
        try expectEqual(pred, .mixed)
    }

    s.test("heuristic non-dialogue verdict is NOT used as the final answer (LLM wins)") {
        // The heuristic's only high-confidence category is dialogue.
        // For everything else the LLM beats it on the spike's gold.
        // This pins that we don't accidentally short-circuit to a
        // heuristic verdict for action/description/summary/interiority.
        let pred = NarrativeModeClassifier.classify(
            "She walked across the room.",
            via: { _ in .description }
        )
        try expectEqual(pred, .description)
    }

    return s
}

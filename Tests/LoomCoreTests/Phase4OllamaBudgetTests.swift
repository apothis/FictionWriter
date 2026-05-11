import Foundation
@testable import LoomCore

/// Phase 4 #7 follow-on (2026-05-12) — scene-aware `num_predict`
/// auto-budget so long scenes don't silently empty out under
/// Ollama's JSON-Schema mode. The model emits ~1 fact per ~14
/// scene-words at our extraction prompt's "be thorough" framing,
/// and each JSON-envelope-wrapped fact is ~70 tokens — so the
/// per-call budget needs to scale with scene length. The hard cap
/// (8192) keeps the call from open-endedly hogging the extractor
/// when a runaway scene gets pasted in; the floor (2048) covers
/// short scenes without dropping below the live-tested safe
/// minimum from 2026-05-12.
func phase4OllamaBudgetTests() -> TestSuite {
    let s = TestSuite("Phase4OllamaBudget")

    s.test("budgetForSceneWords floors at 2048 for short scenes") {
        try expectEqual(OllamaLedgerExtractor.budgetForSceneWords(0), 2048)
        try expectEqual(OllamaLedgerExtractor.budgetForSceneWords(100), 2048)
        try expectEqual(OllamaLedgerExtractor.budgetForSceneWords(256), 2048)
    }

    s.test("budgetForSceneWords scales linearly past the floor") {
        // 312 words → 2496 (live-verified safe budget for the 25-fact
        // test scene from 2026-05-12).
        try expectEqual(OllamaLedgerExtractor.budgetForSceneWords(312), 2496)
        // 500 words → 4000.
        try expectEqual(OllamaLedgerExtractor.budgetForSceneWords(500), 4000)
        // 1000 words → 8000 (just under the cap).
        try expectEqual(OllamaLedgerExtractor.budgetForSceneWords(1000), 8000)
    }

    s.test("budgetForSceneWords caps at 8192 for runaway scenes") {
        try expectEqual(OllamaLedgerExtractor.budgetForSceneWords(1024), 8192)
        try expectEqual(OllamaLedgerExtractor.budgetForSceneWords(5000), 8192)
        try expectEqual(OllamaLedgerExtractor.budgetForSceneWords(50_000), 8192)
    }

    return s
}

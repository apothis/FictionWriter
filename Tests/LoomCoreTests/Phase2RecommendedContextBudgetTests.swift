import Foundation
@testable import LoomCore

/// Phase 2 polish: derive a recommended `contextBudgetTokens` from
/// the server's probed `trueMaxContext`. The current
/// `contextBudgetTokens` default (8192) is a conservative Phase 1
/// fallback — on a server that reports 16384, the user is leaving
/// ~7000 tokens of recent-prose context unused.
///
/// The recommendation = trueMax - replyBudget - safetyMargin, clamped
/// to a usable floor. Pure arithmetic, easy to test.
func phase2RecommendedContextBudgetTests() -> TestSuite {
    let s = TestSuite("Phase2RecommendedContextBudget")

    s.test("normal case: subtracts reply budget + safety margin") {
        let result = ContextBudgetRecommendation.recommend(
            trueMaxContext: 16384,
            replyBudgetTokens: 1024,
            safetyMargin: 256
        )
        try expectEqual(result, 16384 - 1024 - 256)
    }

    s.test("uses default safety margin of 256 when omitted") {
        let result = ContextBudgetRecommendation.recommend(
            trueMaxContext: 16384,
            replyBudgetTokens: 1024
        )
        try expectEqual(result, 16384 - 1024 - 256)
    }

    s.test("clamps to a minimum of 1024 even when arithmetic would go below") {
        // Tiny server / oversized reply budget → still return something
        // usable rather than 0 or negative.
        let result = try expectNotNil(ContextBudgetRecommendation.recommend(
            trueMaxContext: 1500,
            replyBudgetTokens: 1024,
            safetyMargin: 256
        ))
        try expectTrue(result >= 1024, "should clamp to >= 1024, got \(result)")
    }

    s.test("returns nil when trueMaxContext is 0 or negative — no server probe data yet") {
        try expectNil(ContextBudgetRecommendation.recommend(
            trueMaxContext: 0,
            replyBudgetTokens: 1024
        ))
        try expectNil(ContextBudgetRecommendation.recommend(
            trueMaxContext: -1,
            replyBudgetTokens: 1024
        ))
    }

    s.test("a typical 8k local model with default reply budget recommends ~6900") {
        // Sanity check against a common configuration.
        let result = ContextBudgetRecommendation.recommend(
            trueMaxContext: 8192,
            replyBudgetTokens: 1024
        )
        try expectEqual(result, 8192 - 1024 - 256) // 6912
    }

    return s
}

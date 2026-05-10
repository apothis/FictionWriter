import Foundation

/// Derive a project `contextBudgetTokens` recommendation from the
/// server's probed `trueMaxContext`. The Phase 1 default of 8192 is
/// conservative — on a 16k-context server, the user is leaving ~7k
/// tokens of recent-prose context unused.
///
/// Formula: `trueMax - replyBudget - safetyMargin`, clamped to a
/// minimum of 1024 so a degenerate config still produces a working
/// (if cramped) generation. Returns nil when no probe data is
/// available (trueMax <= 0).
public enum ContextBudgetRecommendation {
    public static let defaultSafetyMargin = 256
    public static let minimumBudget = 1024

    public static func recommend(
        trueMaxContext: Int,
        replyBudgetTokens: Int,
        safetyMargin: Int = defaultSafetyMargin
    ) -> Int? {
        guard trueMaxContext > 0 else { return nil }
        let raw = trueMaxContext - replyBudgetTokens - safetyMargin
        return max(raw, minimumBudget)
    }
}

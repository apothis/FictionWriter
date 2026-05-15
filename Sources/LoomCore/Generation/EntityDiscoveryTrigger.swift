import Foundation

/// Phase 9 entity-discovery — pure-data threshold evaluator. Mirrors
/// `LedgerExtractionTrigger` shape but with a higher default threshold
/// (500 vs ledger's 200) because the discovery pipeline is ~30s vs
/// ledger's ~20s — re-firing too often costs the user real wall-clock
/// time and rarely surfaces new entities after the first pass.
///
/// Baseline nil is treated as 0 — a brand-new scene fires once it
/// crosses the threshold for the first time. Absolute-delta posture
/// matches the ledger trigger: heavy deletion (user trims a long
/// passage) is also a re-discovery signal because the bible's stored
/// entities may no longer be supported by the prose.
public enum EntityDiscoveryTrigger {
    public static let defaultThreshold: Int = 500

    public static func shouldFire(
        currentWordCount: Int,
        baselineWordCount: Int?,
        threshold: Int = defaultThreshold
    ) -> Bool {
        let baseline = baselineWordCount ?? 0
        return abs(currentWordCount - baseline) >= threshold
    }
}

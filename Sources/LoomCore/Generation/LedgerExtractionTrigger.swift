import Foundation

/// Pure-data threshold evaluator for the Phase 4 #7 post-scene
/// side-call. LOOM_STORY_BIBLE §3.2 specifies a >200-word change as
/// the trigger; this helper takes the current word count and a
/// per-scene baseline (the word count at the last successful
/// extraction, or nil if the scene has never been extracted) and
/// returns whether the side-call should fire.
///
/// Baseline nil is treated as 0 — a brand-new scene fires once it
/// crosses the threshold for the first time. The comparison uses
/// absolute delta so heavy deletion (user trims a long passage) is
/// also a re-extraction signal: the bible content has materially
/// changed and the existing facts may no longer be supported by the
/// prose.
public enum LedgerExtractionTrigger {
    public static let defaultThreshold: Int = 200

    public static func shouldFire(
        currentWordCount: Int,
        baselineWordCount: Int?,
        threshold: Int = defaultThreshold
    ) -> Bool {
        let baseline = baselineWordCount ?? 0
        return abs(currentWordCount - baseline) >= threshold
    }
}

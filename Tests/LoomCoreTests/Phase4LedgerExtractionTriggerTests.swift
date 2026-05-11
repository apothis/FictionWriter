import Foundation
@testable import LoomCore

/// Phase 4 #7 sub-task 2 — pure-data threshold evaluator for the
/// post-scene side-call. LOOM_STORY_BIBLE §3.2 specifies a ">200-word
/// change" trigger; the helper takes a current word count and a
/// per-scene baseline (the word count at the last successful
/// extraction) and returns whether the side-call should fire.
///
/// Baseline nil is treated as 0 (a brand-new scene fires once it
/// crosses the threshold). Negative deltas (user deletes prose) also
/// count toward the threshold via absolute value — heavy deletion
/// is a re-extraction signal too.
func phase4LedgerExtractionTriggerTests() -> TestSuite {
    let s = TestSuite("Phase4LedgerExtractionTrigger")

    s.test("default threshold is 200 words per LOOM_STORY_BIBLE §3.2") {
        try expectEqual(LedgerExtractionTrigger.defaultThreshold, 200)
    }

    s.test("shouldFire returns false when current word count is below threshold from nil baseline") {
        try expectFalse(LedgerExtractionTrigger.shouldFire(
            currentWordCount: 199,
            baselineWordCount: nil
        ))
    }

    s.test("shouldFire returns true when current word count meets threshold from nil baseline") {
        try expectTrue(LedgerExtractionTrigger.shouldFire(
            currentWordCount: 200,
            baselineWordCount: nil
        ))
    }

    s.test("shouldFire returns true when growth from baseline meets threshold") {
        try expectTrue(LedgerExtractionTrigger.shouldFire(
            currentWordCount: 800,
            baselineWordCount: 600  // delta 200
        ))
    }

    s.test("shouldFire returns false when growth from baseline is below threshold") {
        try expectFalse(LedgerExtractionTrigger.shouldFire(
            currentWordCount: 799,
            baselineWordCount: 600  // delta 199
        ))
    }

    s.test("shouldFire returns true on heavy deletion (delta is absolute)") {
        try expectTrue(LedgerExtractionTrigger.shouldFire(
            currentWordCount: 400,
            baselineWordCount: 700  // delta -300 → abs 300 ≥ 200
        ))
    }

    s.test("shouldFire honours a custom threshold") {
        try expectTrue(LedgerExtractionTrigger.shouldFire(
            currentWordCount: 100,
            baselineWordCount: nil,
            threshold: 50
        ))
        try expectFalse(LedgerExtractionTrigger.shouldFire(
            currentWordCount: 49,
            baselineWordCount: nil,
            threshold: 50
        ))
    }

    return s
}

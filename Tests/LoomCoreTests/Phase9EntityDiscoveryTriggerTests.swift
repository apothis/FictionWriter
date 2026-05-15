import Foundation
@testable import LoomCore

/// Phase 9 entity-discovery — pure-data trigger evaluator.
/// LOOM_ENTITY_DISCOVERY_SPIKE §9.5 productionisation: instead of
/// the "first time per session" Set<UUID> memo, track a per-scene
/// word-count baseline and re-fire discovery when the user has
/// substantially rewritten the scene since the last successful
/// pass. Higher threshold (500 vs ledger's 200) because discovery
/// is ~30s vs ledger's ~20s — don't spam.
///
/// Pure-data; mirrors LedgerExtractionTrigger.
func phase9EntityDiscoveryTriggerTests() -> TestSuite {
    let s = TestSuite("Phase9EntityDiscoveryTrigger")

    s.test("default threshold is 500 words") {
        try expectEqual(EntityDiscoveryTrigger.defaultThreshold, 500)
    }

    s.test("nil baseline + short scene → no fire") {
        try expectFalse(EntityDiscoveryTrigger.shouldFire(
            currentWordCount: 100,
            baselineWordCount: nil
        ))
    }

    s.test("nil baseline + long scene → fire (first-time discovery)") {
        try expectTrue(EntityDiscoveryTrigger.shouldFire(
            currentWordCount: 500,
            baselineWordCount: nil
        ))
        try expectTrue(EntityDiscoveryTrigger.shouldFire(
            currentWordCount: 700,
            baselineWordCount: nil
        ))
    }

    s.test("baseline X + tiny edit → no fire (typing burst)") {
        try expectFalse(EntityDiscoveryTrigger.shouldFire(
            currentWordCount: 510,
            baselineWordCount: 500
        ))
    }

    s.test("baseline X + ≥500-word rewrite → fire (re-discovery)") {
        try expectTrue(EntityDiscoveryTrigger.shouldFire(
            currentWordCount: 1000,
            baselineWordCount: 500
        ))
        try expectTrue(EntityDiscoveryTrigger.shouldFire(
            currentWordCount: 1500,
            baselineWordCount: 1000
        ))
    }

    s.test("heavy deletion also fires (absolute delta)") {
        // User trims a long scene by 500+ words — the bible may
        // contain stale entities; re-discovery is the right call.
        try expectTrue(EntityDiscoveryTrigger.shouldFire(
            currentWordCount: 500,
            baselineWordCount: 1100
        ))
    }

    s.test("custom threshold overrides default") {
        try expectTrue(EntityDiscoveryTrigger.shouldFire(
            currentWordCount: 200,
            baselineWordCount: nil,
            threshold: 150
        ))
        try expectFalse(EntityDiscoveryTrigger.shouldFire(
            currentWordCount: 200,
            baselineWordCount: nil,
            threshold: 250
        ))
    }

    return s
}

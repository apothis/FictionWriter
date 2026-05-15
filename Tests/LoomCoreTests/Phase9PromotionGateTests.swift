import Foundation
@testable import LoomCore

/// Phase 9 entity-discovery spike — Stage B promotion gate.
/// Pure-data filter, applied after candidate generation, before
/// dedup. v1 (per LOOM_ENTITY_DISCOVERY_SPIKE §4.3): proper-noun
/// proposals only — definite-NP entities ("the cook", "the woman
/// in red") are deferred to v2 once cross-scene coreference exists
/// to gate them on recurrence. Anatomy descriptors are blocked
/// first (§4.6) so NSFW false-positive traps never reach the LLM
/// normalisation stage.
func phase9PromotionGateTests() -> TestSuite {
    let s = TestSuite("Phase9PromotionGate")

    s.test("proper-noun single token → promote") {
        try expectEqual(EntityPromotionGate.evaluate(canonicalName: "Anders"), .promote)
        try expectEqual(EntityPromotionGate.evaluate(canonicalName: "Velka"), .promote)
        try expectEqual(EntityPromotionGate.evaluate(canonicalName: "Penelope"), .promote)
    }

    s.test("proper-noun multi-token → promote") {
        try expectEqual(EntityPromotionGate.evaluate(canonicalName: "Marius Thorn"), .promote)
        try expectEqual(EntityPromotionGate.evaluate(canonicalName: "Mia Vance"), .promote)
    }

    s.test("proper-noun with title prefix → promote") {
        try expectEqual(EntityPromotionGate.evaluate(canonicalName: "Dr Thorn"), .promote)
        try expectEqual(EntityPromotionGate.evaluate(canonicalName: "Mr Halloran"), .promote)
    }

    s.test("proper-noun place with definite article → promote") {
        // "The Quay" — the leading "The" is part of the name, not a
        // generic determiner. Strip-leading-determiner heuristic
        // still leaves "Quay" as a capitalized proper noun token.
        try expectEqual(EntityPromotionGate.evaluate(canonicalName: "The Quay"), .promote)
        try expectEqual(EntityPromotionGate.evaluate(canonicalName: "The Iron Bell"), .promote)
    }

    s.test("proper-noun-by-surname-plural ('the Bergmans') → promote (gate doesn't recurrence-check)") {
        // v1 gate doesn't gate on recurrence — that's the job of
        // candidate-generation count tracking. "the Bergmans" is a
        // proper-noun surname and passes the gate; downstream
        // recurrence/dedup/LLM stages can reject if it's a one-off
        // mention with no on-page presence.
        try expectEqual(EntityPromotionGate.evaluate(canonicalName: "the Bergmans"), .promote)
    }

    s.test("anatomy-only descriptor → reject (block-list)") {
        try expectEqual(EntityPromotionGate.evaluate(canonicalName: "the redhead"), .rejectAnatomyOnly)
        try expectEqual(EntityPromotionGate.evaluate(canonicalName: "the brunette woman"), .rejectAnatomyOnly)
        try expectEqual(EntityPromotionGate.evaluate(canonicalName: "a blonde woman"), .rejectAnatomyOnly)
        try expectEqual(EntityPromotionGate.evaluate(canonicalName: "the blonde"), .rejectAnatomyOnly)
    }

    s.test("definite-NP without proper noun → reject (v1 out of scope)") {
        // §4.3: deferred to v2. v1 rejects these so the user
        // doesn't get drowned in low-confidence proposals.
        try expectEqual(EntityPromotionGate.evaluate(canonicalName: "the cook"), .rejectNoProperNoun)
        try expectEqual(EntityPromotionGate.evaluate(canonicalName: "the stranger"), .rejectNoProperNoun)
        try expectEqual(EntityPromotionGate.evaluate(canonicalName: "the man on the landing"), .rejectNoProperNoun)
        try expectEqual(EntityPromotionGate.evaluate(canonicalName: "the woman in red"), .rejectNoProperNoun)
        try expectEqual(EntityPromotionGate.evaluate(canonicalName: "my boss"), .rejectNoProperNoun)
        try expectEqual(EntityPromotionGate.evaluate(canonicalName: "the agency"), .rejectNoProperNoun)
    }

    s.test("generic place reference → reject") {
        try expectEqual(EntityPromotionGate.evaluate(canonicalName: "the cafe"), .rejectNoProperNoun)
        try expectEqual(EntityPromotionGate.evaluate(canonicalName: "the bedroom"), .rejectNoProperNoun)
        try expectEqual(EntityPromotionGate.evaluate(canonicalName: "the gallery"), .rejectNoProperNoun)
        try expectEqual(EntityPromotionGate.evaluate(canonicalName: "the hotel"), .rejectNoProperNoun)
    }

    s.test("all-lowercase proper-noun-ish input → reject (signals model failure)") {
        // If the LLM emits "marius" without capitalisation, the
        // pipeline can't trust the casing — better to reject and
        // let the normalisation stage re-emit. Strict here means
        // no false promotion on miscased outputs.
        try expectEqual(EntityPromotionGate.evaluate(canonicalName: "marius"), .rejectNoProperNoun)
        try expectEqual(EntityPromotionGate.evaluate(canonicalName: "the bergmans"), .rejectNoProperNoun)
    }

    s.test("empty / whitespace / determiner-only → reject empty") {
        try expectEqual(EntityPromotionGate.evaluate(canonicalName: ""), .rejectEmpty)
        try expectEqual(EntityPromotionGate.evaluate(canonicalName: "   "), .rejectEmpty)
        try expectEqual(EntityPromotionGate.evaluate(canonicalName: "the"), .rejectEmpty)
        try expectEqual(EntityPromotionGate.evaluate(canonicalName: "a"), .rejectEmpty)
    }

    s.test("anatomy gate wins over proper-noun gate on collision") {
        // If a candidate happens to be both anatomy AND have an
        // uppercase token (unlikely but possible: "the Redhead" as
        // a stage name), anatomy block-list still rejects. v1
        // posture is conservative — false-negative on the rare
        // intentional-stage-name beats false-positive on every
        // anatomy descriptor.
        try expectEqual(EntityPromotionGate.evaluate(canonicalName: "the Redhead"), .rejectAnatomyOnly)
    }

    return s
}

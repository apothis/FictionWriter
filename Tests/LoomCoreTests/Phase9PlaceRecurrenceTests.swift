import Foundation
@testable import LoomCore

/// Phase 9 entity-discovery — place-recurrence filter.
/// LOOM_ENTITY_DISCOVERY_SPIKE §6.4 first-run finding: gemma4_2b
/// promotes real-world cities mentioned once in passing (Brussels,
/// Edinburgh) as bible-worthy places. Promotion gate alone (proper-
/// noun) is too permissive for places — research §8.4 says fiction
/// systems gate places on either definite-article-as-name OR
/// recurrence-across-scenes. Within-scene-mention-count is the
/// cheapest principled signal we have.
///
/// Rule: a place candidate passes iff
///   (a) canonical name starts with "The " (definite article is
///       part of the proper name — "The Quay", "The Iron Bell"), OR
///   (b) the surface appears ≥ 2 times in the scene prose.
///
/// Characters bypass this filter — they have separate gate logic.
func phase9PlaceRecurrenceTests() -> TestSuite {
    let s = TestSuite("Phase9PlaceRecurrence")

    s.test("place with 'The' prefix → passes regardless of mention count") {
        let prose = "The Quay was a pub. She went there once."
        try expectTrue(EntityDiscovery.passesPlaceRecurrence(
            surface: "The Quay", kind: .place, scenePose: prose
        ))
    }

    s.test("place with recurring mention (≥2) → passes") {
        let prose = "She arrived in Brussels. Brussels was raining."
        try expectTrue(EntityDiscovery.passesPlaceRecurrence(
            surface: "Brussels", kind: .place, scenePose: prose
        ))
    }

    s.test("place with single passing mention + no 'The' → rejected") {
        // §6.4 first-run failure mode: Brussels / Edinburgh single-
        // mention in scene eds-07 — should be rejected.
        let prose = "Penelope was at a conference in Brussels."
        try expectFalse(EntityDiscovery.passesPlaceRecurrence(
            surface: "Brussels", kind: .place, scenePose: prose
        ))
    }

    s.test("place mention count is case-insensitive") {
        let prose = "Brussels was hot. BRUSSELS in summer was always hot."
        try expectTrue(EntityDiscovery.passesPlaceRecurrence(
            surface: "Brussels", kind: .place, scenePose: prose
        ))
    }

    s.test("substring-of-larger-word does NOT count as mention") {
        // "Brusselsprouts" should not count as a Brussels mention.
        let prose = "She bought brusselsprouts. Brussels was elsewhere."
        // Only one real mention.
        try expectFalse(EntityDiscovery.passesPlaceRecurrence(
            surface: "Brussels", kind: .place, scenePose: prose
        ))
    }

    s.test("character kind bypasses the filter entirely") {
        // Characters use the regular gate; this filter is place-only.
        let prose = "Anders said hello."
        try expectTrue(EntityDiscovery.passesPlaceRecurrence(
            surface: "Anders", kind: .character, scenePose: prose
        ))
    }

    s.test("possessive-of-named-character ('Velka's flat') → rejected without recurrence") {
        // Single mention, no "The" prefix — distractor per fixture.
        let prose = "She lived at Velka's flat above the chemist's."
        try expectFalse(EntityDiscovery.passesPlaceRecurrence(
            surface: "Velka's flat", kind: .place, scenePose: prose
        ))
    }

    return s
}

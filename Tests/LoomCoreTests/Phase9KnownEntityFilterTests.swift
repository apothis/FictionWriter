import Foundation
@testable import LoomCore

/// Phase 9 entity-discovery — pre-gate known-entity filter.
/// LOOM_ENTITY_DISCOVERY_SPIKE §6.4 findings (post-first-run):
/// gemma4_2b ignores the prompt's "do not emit known entities"
/// instruction. Adding a Swift-side exact-name post-filter on
/// Stage A2 output is the structural-enforcement fix
/// (cf. feedback_prompt_blacklist_evasion memory entry — prompt
/// blacklists get evaded; structural enforcement does not).
///
/// Cheap and deterministic: case-insensitive normalised-string
/// set intersection. The harder "same entity under different
/// surface form" case is the dedup stage's job (cosine
/// similarity).
func phase9KnownEntityFilterTests() -> TestSuite {
    let s = TestSuite("Phase9KnownEntityFilter")

    s.test("exact match on canonical name → known") {
        try expectTrue(EntityDiscovery.isKnownSurface("Mia", knownNames: ["Mia"]))
        try expectTrue(EntityDiscovery.isKnownSurface("Anders", knownNames: ["Mia", "Anders"]))
    }

    s.test("case-insensitive match → known") {
        try expectTrue(EntityDiscovery.isKnownSurface("MIA", knownNames: ["mia"]))
        try expectTrue(EntityDiscovery.isKnownSurface("anders", knownNames: ["Anders"]))
    }

    s.test("whitespace-tolerant match → known") {
        try expectTrue(EntityDiscovery.isKnownSurface("  Mia  ", knownNames: ["Mia"]))
        try expectTrue(EntityDiscovery.isKnownSurface("Mia", knownNames: ["  Mia  "]))
    }

    s.test("non-match → unknown") {
        try expectFalse(EntityDiscovery.isKnownSurface("Karim", knownNames: ["Mia", "Anders"]))
        try expectFalse(EntityDiscovery.isKnownSurface("Marius", knownNames: ["Mia", "Anders"]))
    }

    s.test("empty known list → never known") {
        try expectFalse(EntityDiscovery.isKnownSurface("Mia", knownNames: []))
    }

    s.test("partial-match does NOT mark as known (Vance vs Karim Vance)") {
        // §6.4 first-run finding: gemma4_2b split "Karim Vance" into
        // two candidates (Karim, Vance). "Vance" alone is NOT in the
        // known-names list — exact-match filter shouldn't reject it.
        // The dedup stage (cosine) is the right place for that
        // partial-overlap case.
        try expectFalse(EntityDiscovery.isKnownSurface("Vance", knownNames: ["Karim Vance", "Karim"]))
        try expectFalse(EntityDiscovery.isKnownSurface("Karim", knownNames: ["Karim Vance"]))
    }

    s.test("filter candidates drops known + keeps unknown, preserves order") {
        let candidates = [
            EntityDiscovery.Candidate(surface: "Mia", kind: .character, firstSeenQuote: "x"),
            EntityDiscovery.Candidate(surface: "Anders", kind: .character, firstSeenQuote: "x"),
            EntityDiscovery.Candidate(surface: "Karim", kind: .character, firstSeenQuote: "x"),
        ]
        let kept = EntityDiscovery.filterKnown(candidates, knownNames: ["Mia", "Anders"])
        try expectEqual(kept.count, 1)
        try expectEqual(kept[0].surface, "Karim")
    }

    return s
}

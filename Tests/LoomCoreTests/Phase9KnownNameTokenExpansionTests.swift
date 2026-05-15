import Foundation
@testable import LoomCore

/// Phase 9 entity-discovery — known-name token expansion.
/// LOOM_ENTITY_DISCOVERY_SPIKE §6.4 second-run finding: gemma4_2b
/// emitted "Vance" alone (split from "Karim Vance") in eds-03.
/// The known-list contained "Karim Vance" + "Mia Vance" + "Karim"
/// + "Mia" — but not the bare token "Vance" — so the exact-name
/// pre-gate filter let it through.
///
/// Fix: auto-expand the known-names list with proper-noun tokens
/// from multi-word names. "Karim Vance" → adds "Karim" + "Vance".
/// Constrained to tokens that (a) start with uppercase, (b) have
/// length ≥ 3 — drops noise like determiners ("the") and short
/// titles ("Mr", "Dr") which would over-match.
func phase9KnownNameTokenExpansionTests() -> TestSuite {
    let s = TestSuite("Phase9KnownNameTokenExpansion")

    s.test("single-token name → no expansion (already a token)") {
        let out = EntityDiscovery.expandKnownNamesWithTokens(["Mia"])
        try expectEqual(Set(out), Set(["Mia"]))
    }

    s.test("two-token proper-noun name → adds both tokens") {
        let out = EntityDiscovery.expandKnownNamesWithTokens(["Karim Vance"])
        try expectEqual(Set(out), Set(["Karim Vance", "Karim", "Vance"]))
    }

    s.test("short tokens (length < 3) are dropped to avoid title noise") {
        // "Dr Thorn" → adds Thorn but NOT "Dr" (too short, would
        // over-match in unrelated contexts).
        let out = EntityDiscovery.expandKnownNamesWithTokens(["Dr Thorn"])
        try expectTrue(Set(out).contains("Thorn"))
        try expectFalse(Set(out).contains("Dr"))
    }

    s.test("lowercase tokens are dropped (non-proper-noun)") {
        // "the stranger" has no proper-noun tokens.
        let out = EntityDiscovery.expandKnownNamesWithTokens(["the stranger"])
        try expectEqual(Set(out), Set(["the stranger"]))
    }

    s.test("deduplicates across multiple inputs sharing a token") {
        // Mia Vance + Karim Vance both contribute Vance — should
        // appear once in the output.
        let out = EntityDiscovery.expandKnownNamesWithTokens([
            "Mia Vance", "Karim Vance"
        ])
        let s = Set(out)
        try expectTrue(s.contains("Mia Vance"))
        try expectTrue(s.contains("Karim Vance"))
        try expectTrue(s.contains("Vance"))
        try expectTrue(s.contains("Mia"))
        try expectTrue(s.contains("Karim"))
        // Expect exactly 5 unique entries.
        try expectEqual(s.count, 5)
    }

    s.test("realistic eds-03 starting bible → Vance gets covered") {
        // The eds-03 starting bible: Mia + aliases [Mia Vance, Miss
        // Vance], Anders + [Anders Voll, the stranger], Karim +
        // [Karim Vance]. After expansion, "Vance" is in the list.
        let input = [
            "Mia", "Mia Vance", "Miss Vance",
            "Anders", "Anders Voll", "the stranger",
            "Karim", "Karim Vance",
        ]
        let out = Set(EntityDiscovery.expandKnownNamesWithTokens(input))
        try expectTrue(out.contains("Vance"))
        try expectTrue(out.contains("Voll"))
        try expectTrue(out.contains("Miss"))
    }

    return s
}

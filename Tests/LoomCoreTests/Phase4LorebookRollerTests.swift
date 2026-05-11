import Foundation
@testable import LoomCore

/// Phase 4 §14.1 #8 / LOOM_NSFW.md §3.5 / LOOM_MEMORY.md §B3 —
/// weighted picker over a Sphiratrioth-style outcome group.
///
/// **Design intent:** Roll-Outcome is NOT a new generation mode. It's
/// a Bible action that rolls one weighted entry from a labelled group
/// and pre-seeds the next Continue via the existing per-call
/// instruction field. The History audit trail naturally records the
/// rolled content (because the instruction field is part of the
/// prompt assembly).
///
/// Pure-data layer tested here. Menu wiring + tray-field plumbing is
/// honest-smoke glue.
func phase4LorebookRollerTests() -> TestSuite {
    let s = TestSuite("Phase4LorebookRoller")

    // MARK: - availableGroups

    s.test("availableGroups returns sorted unique non-nil group labels") {
        let entries: [LorebookEntry] = [
            makeEntry(name: "a", group: "alpha", weight: 10),
            makeEntry(name: "b", group: "alpha", weight: 10),
            makeEntry(name: "c", group: "beta", weight: 10),
            makeEntry(name: "d", group: nil)
        ]
        let groups = LorebookRoller.availableGroups(in: entries)
        try expectEqual(groups, ["alpha", "beta"])
    }

    s.test("availableGroups omits groups whose only entries are disabled") {
        let entries: [LorebookEntry] = [
            makeEntry(name: "a", group: "alpha", weight: 10, enabled: false),
            makeEntry(name: "b", group: "alpha", weight: 10, enabled: false),
            makeEntry(name: "c", group: "beta", weight: 10, enabled: true)
        ]
        try expectEqual(LorebookRoller.availableGroups(in: entries), ["beta"])
    }

    s.test("availableGroups omits groups whose entries have only zero / nil weight") {
        let entries: [LorebookEntry] = [
            makeEntry(name: "a", group: "alpha", weight: 0),
            makeEntry(name: "b", group: "alpha", weight: nil),
            makeEntry(name: "c", group: "beta", weight: 1)
        ]
        try expectEqual(LorebookRoller.availableGroups(in: entries), ["beta"])
    }

    // MARK: - pick

    s.test("pick from a single-entry group always returns that entry") {
        var rng = SeededRNG(seed: 42)
        let entries = [makeEntry(name: "only", group: "g", weight: 10)]
        let picked = LorebookRoller.pick(group: "g", from: entries, using: &rng)
        let unwrapped = try expectNotNil(picked)
        try expectEqual(unwrapped.name, "only")
    }

    s.test("pick returns nil for an empty / nonexistent group") {
        var rng = SeededRNG(seed: 1)
        let entries = [makeEntry(name: "a", group: "g", weight: 10)]
        try expectTrue(LorebookRoller.pick(group: "missing", from: entries, using: &rng) == nil)
    }

    s.test("pick skips disabled entries even when they have weight") {
        var rng = SeededRNG(seed: 1)
        let entries = [
            makeEntry(name: "off", group: "g", weight: 99, enabled: false),
            makeEntry(name: "on", group: "g", weight: 1)
        ]
        let picked = LorebookRoller.pick(group: "g", from: entries, using: &rng)
        try expectEqual(picked?.name, "on")
    }

    s.test("pick skips zero/nil-weight entries") {
        var rng = SeededRNG(seed: 1)
        let entries = [
            makeEntry(name: "zero", group: "g", weight: 0),
            makeEntry(name: "nil", group: "g", weight: nil),
            makeEntry(name: "real", group: "g", weight: 5)
        ]
        let picked = LorebookRoller.pick(group: "g", from: entries, using: &rng)
        try expectEqual(picked?.name, "real")
    }

    s.test("pick distribution is weighted across many seeds") {
        // With 1:4 weights, ~1000 rolls should land roughly 200:800.
        // Tolerance generous; the goal is "weight bias exists," not
        // a statistical certificate.
        let entries = [
            makeEntry(name: "rare", group: "g", weight: 1),
            makeEntry(name: "common", group: "g", weight: 4)
        ]
        var rare = 0, common = 0
        for seed in 1...1000 {
            var rng = SeededRNG(seed: UInt64(seed))
            switch LorebookRoller.pick(group: "g", from: entries, using: &rng)?.name {
            case "rare": rare += 1
            case "common": common += 1
            default: break
            }
        }
        try expectTrue(rare + common == 1000)
        try expectTrue(common > rare, "weight-4 entry should win more often than weight-1 (got rare=\(rare), common=\(common))")
        // Loose sanity: rare should land 5-30% of the time at this scale.
        try expectTrue(rare >= 50 && rare <= 350, "rare ratio out of expected band: \(rare)/1000")
    }

    return s
}

// MARK: - Helpers

private func makeEntry(name: String, group: String? = nil, weight: Int? = nil, enabled: Bool = true) -> LorebookEntry {
    return LorebookEntry(
        name: name,
        content: "content of \(name)",
        activationMode: .keyed,
        keys: [],
        enabled: enabled,
        group: group,
        weight: weight
    )
}

/// Reproducible RNG so the weighted-distribution test is deterministic.
private struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 0xdead_beef : seed }
    mutating func next() -> UInt64 {
        // SplitMix64
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

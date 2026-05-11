import Foundation

/// Phase 4 §14.1 #8 / LOOM_NSFW.md §3.5 / LOOM_MEMORY.md §B3.
///
/// Weighted picker over a Sphiratrioth-style outcome group. Used by
/// the Roll-Outcome action: at a decision point in the manuscript, the
/// user picks a labelled group (e.g. `action_outcome`) and Loom rolls
/// one entry from it. The rolled entry's content seeds the next
/// generation via the existing per-call instruction layer — no new
/// generation mode required.
///
/// Eligibility rules for being rolled:
///   - entry is `enabled`
///   - entry's `group` matches the requested label
///   - entry's `weight` is non-nil and > 0
///
/// Distribution is weighted-random: an entry with weight 4 is rolled
/// roughly 4× as often as a sibling with weight 1.
public enum LorebookRoller {

    /// All groups in the lorebook that have at least one eligible
    /// entry, sorted for stable UI presentation.
    public static func availableGroups(in entries: [LorebookEntry]) -> [String] {
        var seen = Set<String>()
        for entry in entries where isEligible(entry) {
            if let g = entry.group { seen.insert(g) }
        }
        return seen.sorted()
    }

    /// Roll one entry from the named group. Returns nil if no eligible
    /// entries exist (group missing, all disabled, all zero-weight).
    public static func pick<R: RandomNumberGenerator>(
        group: String,
        from entries: [LorebookEntry],
        using rng: inout R
    ) -> LorebookEntry? {
        let eligible = entries.filter { isEligible($0) && $0.group == group }
        guard !eligible.isEmpty else { return nil }
        let totalWeight = eligible.reduce(0) { $0 + ($1.weight ?? 0) }
        guard totalWeight > 0 else { return nil }
        // Roll an integer in [0, totalWeight) using the supplied RNG.
        let roll = Int(rng.next() % UInt64(totalWeight))
        var cursor = 0
        for candidate in eligible {
            cursor += candidate.weight ?? 0
            if roll < cursor { return candidate }
        }
        // Shouldn't reach here given the math, but return last for
        // safety on rounding edges.
        return eligible.last
    }

    /// Convenience overload that uses the system RNG. The main entry
    /// point for UI code; tests use the `using:` variant with a
    /// seeded RNG.
    public static func pick(group: String, from entries: [LorebookEntry]) -> LorebookEntry? {
        var rng = SystemRandomNumberGenerator()
        return pick(group: group, from: entries, using: &rng)
    }

    private static func isEligible(_ entry: LorebookEntry) -> Bool {
        return entry.enabled && (entry.weight ?? 0) > 0
    }
}

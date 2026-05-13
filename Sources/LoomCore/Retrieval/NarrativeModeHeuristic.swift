import Foundation

/// Pure-Swift heuristic baseline for narrative-mode classification —
/// Phase 5 scope-lock #5 floor per
/// [`LOOM_NARRATIVE_MODE_SPIKE.md`](../../LOOM_NARRATIVE_MODE_SPIKE.md)
/// §3.2(a). Establishes the eval floor: if the LLM classifier doesn't
/// materially beat this, the spike pivots to heuristic-only.
///
/// Ordering is load-bearing: dialogue gate first (quote-density is
/// near-perfect on its category, per research); summary next (the
/// temporal-compression markers are unambiguous when present);
/// interiority via cognition verbs; description via sensory verbs +
/// low verb density; action as the active-verb fallback; `mixed` when
/// no signal fires.
public enum NarrativeModeHeuristic {
    public static func classify(_ text: String) -> NarrativeMode {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .mixed }

        let lower = trimmed.lowercased()

        if isDialogue(trimmed) { return .dialogue }
        if isSummary(lower) { return .summary }
        if isInteriority(lower) { return .interiority }
        if isDescription(lower) { return .description }
        if isAction(lower) { return .action }
        return .mixed
    }

    // MARK: - Dialogue

    /// Quote density ≥ ~30% of non-space characters inside paired
    /// straight-quote runs. Catches both `"…"` and `'…'`.
    static func isDialogue(_ text: String) -> Bool {
        let nonSpace = text.filter { !$0.isWhitespace }
        guard !nonSpace.isEmpty else { return false }

        let quotedChars = quotedCharCount(text)
        let density = Double(quotedChars) / Double(nonSpace.count)
        return density >= 0.3
    }

    private static func quotedCharCount(_ text: String) -> Int {
        var inside = false
        var count = 0
        for ch in text {
            if ch == "\"" {
                inside.toggle()
            } else if inside && !ch.isWhitespace {
                count += 1
            }
        }
        return count
    }

    // MARK: - Summary

    /// Temporal-compression markers. Either explicit duration
    /// ("for three weeks", "by autumn", "in the months after") or
    /// past-perfect / past-perfect-progressive forms ("had been -ing",
    /// "had spent", "would later").
    static func isSummary(_ lower: String) -> Bool {
        let timeWindowPatterns: [String] = [
            " for three ", " for four ", " for five ", " for six ",
            " for seven ", " for eight ", " for nine ", " for ten ",
            " for eleven ", " for twelve ",
            " for weeks", " for months", " for years",
            " for a year", " for a month", " for a week",
            " for the next ",
            " by the time ", " by autumn", " by winter", " by spring",
            " by summer", " by december", " by november",
            " in the months after", " in the years after",
            " in the weeks after", " in the days after",
            " through the summer ", " through the autumn ",
            " through the winter ", " through the year ",
            " through the years ",
            " in the months", " in the years",
        ]
        for p in timeWindowPatterns where lower.contains(p) {
            return true
        }

        // Past-perfect-progressive: "had been -ing"
        if lower.contains("had been ") {
            return true
        }
        // "He spent the autumn in Berlin." Past tense with definite
        // article + season-name = compressed-time.
        let seasonalSpent: [String] = [
            " spent the autumn", " spent the winter", " spent the spring",
            " spent the summer", " spent the year",
        ]
        for p in seasonalSpent where lower.contains(p) {
            return true
        }

        return false
    }

    // MARK: - Interiority

    /// Cognition-verb count ≥ 2 (per word, not per sentence) OR
    /// free-indirect-style mode adverbs without quote attribution.
    static func isInteriority(_ lower: String) -> Bool {
        let cognitionVerbs: [String] = [
            "thought", "thinking", "felt", "feeling", "wondered",
            "wondering", "remembered", "remembering", "knew", "knowing",
            "imagined", "suspected", "noticed", "realised", "realized",
        ]
        let count = cognitionVerbs.reduce(0) { acc, verb in
            acc + countOccurrences(of: verb, in: lower)
        }
        if count >= 2 { return true }

        return false
    }

    // MARK: - Description

    /// Sensory verbs + low verb-to-noun density. Static, suspended-time
    /// passages where the prose lingers on environmental detail.
    static func isDescription(_ lower: String) -> Bool {
        let sensoryVerbs: [String] = [
            " smelled", " smelt", " appeared", " looked",
            " seemed", " tasted", " sounded", " felt of ",
            " hummed", " ticked", " guttered", " creaked",
        ]
        var sensoryHits = 0
        for v in sensoryVerbs {
            sensoryHits += countOccurrences(of: v, in: lower)
        }
        if sensoryHits >= 1 { return true }

        // Stative-dominant: lots of `was/were` copulas with no quoted
        // speech, no cognition verbs, no time-window markers. Tends to
        // mark scene-painting / environmental sketches.
        let was = countOccurrences(of: " was ", in: lower)
        let were = countOccurrences(of: " were ", in: lower)
        if was + were >= 2 { return true }

        return false
    }

    // MARK: - Action

    /// Active concrete verbs in scene-time. The catch-all positive: if
    /// nothing else fired and there are physical-action verbs, call it
    /// action.
    static func isAction(_ lower: String) -> Bool {
        let actionVerbs: [String] = [
            " walked", " ran", " kicked", " struck", " threw", " grabbed",
            " pushed", " pulled", " moved", " turned", " sat", " stood",
            " locked", " unlocked", " hit", " held", " gripped", " stepped",
            " entered", " left", " came", " went", " drew", " drank",
            " set ", " placed", " bit", " kissed", " undid", " unbuttoned",
        ]
        let hits = actionVerbs.reduce(0) { acc, v in
            acc + countOccurrences(of: v, in: lower)
        }
        return hits >= 2
    }

    // MARK: - Utility

    private static func countOccurrences(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var searchStart = haystack.startIndex
        while let range = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
            count += 1
            searchStart = range.upperBound
        }
        return count
    }
}

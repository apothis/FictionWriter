import Foundation

/// Pure helper: extract the prose immediately before the cursor that
/// fits within a character budget, preferring paragraph-boundary
/// truncation over mid-sentence cuts. The Phase 1 minimum recent-prose
/// layer per LOOM_GENERATION_MODES.md §1.2 — last N tokens before the
/// cursor.
///
/// Char budget is used (not token budget) since this is a content-
/// shape decision, not a budget-eviction one. The budget caller is
/// PromptBuilder, which converts a token allowance to a char allowance
/// via the inverse of TokenEstimator (4 chars/token).
public enum RecentProseWindow {
    /// Extract the last `charBudget` characters of `prose` before
    /// `cursorOffset`, snapped to a paragraph boundary (`\n\n`) when
    /// one exists within the visible suffix. Out-of-range cursor is
    /// clamped to the prose length.
    public static func extract(from prose: String, cursorOffset: Int, charBudget: Int) -> String {
        guard !prose.isEmpty, charBudget > 0 else { return "" }
        let clamped = max(0, min(cursorOffset, prose.count))
        guard clamped > 0 else { return "" }

        // Take the entire prose-up-to-cursor.
        let proseUpToCursor = String(prose.prefix(clamped))
        if proseUpToCursor.count <= charBudget {
            return proseUpToCursor
        }

        // Over budget: trim to last `charBudget` chars, then snap to a
        // paragraph boundary if one is reachable. The paragraph
        // separator is `\n\n` (markdown / iA Writer / Obsidian
        // convention); if no paragraph break exists in the trimmed
        // suffix, fall back to the raw suffix.
        let suffixStart = proseUpToCursor.index(proseUpToCursor.endIndex, offsetBy: -charBudget)
        let trimmed = String(proseUpToCursor[suffixStart...])

        if let separatorRange = trimmed.range(of: "\n\n") {
            // Start at the character after the paragraph separator so
            // the result begins at the first character of the next
            // paragraph.
            let after = trimmed.index(separatorRange.upperBound, offsetBy: 0)
            let snapped = String(trimmed[after...])
            // Don't snap if it would leave us with nothing meaningful.
            // 32 chars is an arbitrary "still useful" threshold.
            if snapped.count >= 32 { return snapped }
        }
        return trimmed
    }
}

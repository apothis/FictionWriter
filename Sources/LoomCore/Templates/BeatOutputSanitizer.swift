import Foundation

// Phase 8.b.x — defense-in-depth filter on writer-LLM beat output
// before it lands in `TemplateGenerationCoordinator.insertedText`.
//
// Two failure modes, both observed empirically in the 2026-05-15
// live smoke and confirmed via the gen-log JSON:
//
// 1. Hallucinated prompt-shaped meta-blocks. The writer (gemma-4-31B
//    Deckard-Heretic-Thinking) mimics the structural shape of our
//    `[BEAT SKELETON]` / `[VOICE TARGET]` / `[INSTRUCTION]` blocks
//    and emits its own apocryphal self-validation rubbish like:
//
//        [VALIDATE BEAT]
//        Length check: 54 words (Within range?). Yes.
//        Pacing: Sentences = [1, 6, 7,
//
//    The leakage cascades — once it lands in `insertedText`, every
//    subsequent beat sees it in `[BEATS BEFORE THIS]` and learns to
//    repeat the pattern.
//
// 2. Trailing-whitespace pileups. The writer emits multi-blank-line
//    padding before the meta-blocks; the `\n\n` inter-beat separator
//    in TemplateGenerationCoordinator compounds them into 6+ blank
//    lines between adjacent beats.
//
// This sanitizer:
//   (a) Truncates the output at the first hallucinated meta-block
//       header (`[VALIDATE BEAT]`, `[BEAT CHECK]`, or any all-caps
//       bracket header that smells like ours).
//   (b) Also strips header-less meta-lines (`Length check: ...`,
//       `Pacing: Sentences = ...`, `Dialogue ratio: ...`).
//   (c) Collapses runs of 3+ newlines down to 2 so paragraph spacing
//       stays uniform.
//   (d) Trims trailing whitespace.
//
// Pure-data. Stop sequences are the preventive upstream layer; the
// sanitizer is the post-stream guardrail.

public enum BeatOutputSanitizer {
    /// Hallucinated bracket-header patterns the model emits at the
    /// end of a beat. The full list is informed by the actual leakage
    /// seen in 2026-05-15's gen-log; add more here as new patterns
    /// surface in smoke. Each is matched as a line-start anchor.
    private static let bracketHeaderPatterns: [String] = [
        "[VALIDATE BEAT]",
        "[VALIDATE BEAT ]",
        "[BEAT CHECK]",
        "[BEAT CHECK ]",
        "[BEAT VALIDATION]",
        "[LENGTH CHECK]",
        "[PACING CHECK]",
        "[CHECK]",
    ]

    /// Header-less meta-line patterns the model emits when it skips
    /// the bracket wrapper. Anchored to line-start; case-sensitive
    /// matches the literal forms observed in gen-log.
    private static let metaLinePatterns: [String] = [
        "Length check:",
        "Length:",
        "Pacing: Sentences",
        "Pacing:",
        "Dialogue ratio:",
        "Sentence length distribution:",
        "Sentence count:",
        "Word count:",
    ]

    public static func strip(_ raw: String) -> String {
        var text = raw

        // (a) Truncate at the first bracket-shaped meta-header.
        text = truncateAtFirstMatch(text, candidates: bracketHeaderPatterns)

        // (b) Truncate at the first header-less meta-line if it
        //     appears at the start of a line. Same rule: cut to
        //     end of string — nothing useful follows.
        text = truncateAtFirstLineStartMatch(text, candidates: metaLinePatterns)

        // (c) Collapse runs of 3+ newlines down to 2.
        text = collapseExcessNewlines(text)

        // (d) Trim trailing whitespace.
        while let last = text.last, last.isWhitespace || last.isNewline {
            text.removeLast()
        }
        return text
    }

    /// Find the earliest occurrence of any candidate string anywhere
    /// in `text`; return everything up to (but not including) that
    /// occurrence. Original string if no match.
    private static func truncateAtFirstMatch(_ text: String, candidates: [String]) -> String {
        var earliest: String.Index?
        for needle in candidates {
            if let range = text.range(of: needle) {
                if earliest == nil || range.lowerBound < earliest! {
                    earliest = range.lowerBound
                }
            }
        }
        guard let cut = earliest else { return text }
        return String(text[..<cut])
    }

    /// Truncate at the first occurrence of any candidate that lands
    /// at line-start. Same semantics as `truncateAtFirstMatch` but
    /// only fires when the match is preceded by a newline (or is at
    /// position 0). Stops the over-aggressive case where the literal
    /// substring appears inside legitimate prose (e.g. "The length of
    /// her hair…" must NOT trigger).
    private static func truncateAtFirstLineStartMatch(_ text: String, candidates: [String]) -> String {
        var earliest: String.Index?
        for needle in candidates {
            var searchStart = text.startIndex
            while let range = text.range(of: needle, range: searchStart..<text.endIndex) {
                let atLineStart: Bool
                if range.lowerBound == text.startIndex {
                    atLineStart = true
                } else {
                    let prev = text.index(before: range.lowerBound)
                    atLineStart = (text[prev] == "\n")
                }
                if atLineStart {
                    if earliest == nil || range.lowerBound < earliest! {
                        earliest = range.lowerBound
                    }
                    break
                }
                searchStart = range.upperBound
            }
        }
        guard let cut = earliest else { return text }
        return String(text[..<cut])
    }

    private static func collapseExcessNewlines(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        var newlineRun = 0
        for ch in text {
            if ch == "\n" {
                newlineRun += 1
                if newlineRun <= 2 {
                    out.append(ch)
                }
            } else {
                newlineRun = 0
                out.append(ch)
            }
        }
        return out
    }
}

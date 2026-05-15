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
    /// Meta-vocabulary words that, when they appear as the first
    /// token inside a `[...]` line-start header, signal a
    /// hallucinated self-validation block. The 2026-05-15 smoke
    /// surfaced `[VALIDATE BEAT]`, `[BEAT CHECK]`, and `[CHECK BEAT]`
    /// (word-order reversed) — but the model improvises new label
    /// shapes each generation. The vocabulary-anchored regex
    /// covers any combination starting with one of these.
    ///
    /// Conservative on purpose: prose-shaped brackets like
    /// `[OUTSIDE THE OFFICE]`, `[LATER]`, `[NIGHT]`, `[CHAPTER 2]`,
    /// `[FLASHBACK]` do NOT match — none of their first words are
    /// in this vocab, so stage-direction-style fiction is safe.
    private static let metaVocabulary: [String] = [
        "BEAT", "CHECK", "VALIDATE", "LENGTH", "PACING", "VOICE",
        "DIALOGUE", "SCENE", "PROSE", "OUTPUT", "NOTE", "META",
        "SELF", "VERIFY",
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

        // (a) Truncate at the first vocabulary-anchored bracket
        //     header. Catches any `[META_WORD ...]` shape at line-
        //     start including word-order variations the model
        //     improvises across generations.
        text = truncateAtFirstMetaBracketHeader(text)

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

    /// Truncate at the first `[META_WORD ...]` style header at
    /// line-start. Matches `[VALIDATE BEAT]`, `[BEAT CHECK]`,
    /// `[CHECK BEAT]`, `[VERIFY OUTPUT]`, etc. — any open-bracket
    /// followed by one of the meta-vocabulary words. Skips brackets
    /// whose first word is NOT in the vocab (e.g. `[OUTSIDE THE
    /// OFFICE]` in fiction prose).
    private static func truncateAtFirstMetaBracketHeader(_ text: String) -> String {
        var searchStart = text.startIndex
        while let bracket = text.range(of: "[", range: searchStart..<text.endIndex) {
            let atLineStart: Bool
            if bracket.lowerBound == text.startIndex {
                atLineStart = true
            } else {
                let prev = text.index(before: bracket.lowerBound)
                atLineStart = (text[prev] == "\n")
            }
            if atLineStart {
                let afterOpen = bracket.upperBound
                // Read the first word's characters until a space or
                // closing bracket. If it's in the vocab, cut here.
                var wordEnd = afterOpen
                while wordEnd < text.endIndex {
                    let c = text[wordEnd]
                    if c == " " || c == "]" { break }
                    wordEnd = text.index(after: wordEnd)
                }
                let firstWord = String(text[afterOpen..<wordEnd])
                if metaVocabulary.contains(firstWord) {
                    return String(text[..<bracket.lowerBound])
                }
            }
            searchStart = bracket.upperBound
        }
        return text
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

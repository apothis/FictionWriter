import Foundation

/// Minimal sentence splitter for the §10.5 evidence-quote validation
/// filter — splits scene prose into sentence-sized chunks for
/// embedding comparison. Uses paragraph (`\n\n`) and
/// sentence-terminator (`.`, `!`, `?`) heuristics; sentence
/// terminators inside quotes don't split (so `"Who is it?"` stays
/// intact). Designed for embedding-similarity work, not editorial
/// display — punctuation handling is conservative and good-enough.
///
/// `Swift.Character` is used throughout to disambiguate from
/// LoomCore's bible `Character` model (the shadow surfaces as
/// confusing "expected Character, got Character" diagnostics
/// otherwise).
public enum SentenceSplitter {
    private static let terminators: Set<Swift.Character> = [".", "!", "?"]
    private static let quoteChars: Set<Swift.Character> = ["\"", "\u{201C}", "\u{201D}"]
    private static let newline: Swift.Character = "\n"

    public static func split(_ prose: String) -> [String] {
        var sentences: [String] = []
        var buffer = ""
        var insideQuotes = false
        // Set when we see a terminator inside quotes; consumed on
        // the matching close-quote so `Mia asked, "Who is it?" She
        // ...` splits AFTER the closing quote.
        var pendingSplit = false

        func flush() {
            let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { sentences.append(trimmed) }
            buffer = ""
        }

        let chars: [Swift.Character] = Array(prose)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            buffer.append(ch)

            if quoteChars.contains(ch) {
                if insideQuotes {
                    insideQuotes = false
                    let nextIsBoundary = (i + 1 >= chars.count) || chars[i + 1].isWhitespace
                    if pendingSplit && nextIsBoundary {
                        flush()
                        pendingSplit = false
                    }
                } else {
                    insideQuotes = true
                }
            } else if terminators.contains(ch) {
                if insideQuotes {
                    pendingSplit = true
                } else {
                    // Greedy: consume runs of terminators ("?!", "...").
                    while i + 1 < chars.count, terminators.contains(chars[i + 1]) {
                        i += 1
                        buffer.append(chars[i])
                    }
                    let nextIsBoundary = (i + 1 >= chars.count) || chars[i + 1].isWhitespace
                    if nextIsBoundary {
                        flush()
                        pendingSplit = false
                    }
                }
            } else if ch == newline {
                flush()
                pendingSplit = false
            }
            i += 1
        }
        flush()
        return sentences
    }
}

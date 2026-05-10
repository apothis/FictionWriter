import Foundation

/// Pure word-count helper for the status strip + editor's
/// `wordCountChanged` event. Treats markdown markers and em-dashes as
/// separators, preserves hyphens and apostrophes as in-word characters,
/// and rejects pure-punctuation tokens (so a line of `...!?` counts
/// zero words).
public enum WordCount {
    /// Set of separator characters: any of these splits the surrounding
    /// text into two tokens. Whitespace is also a separator (handled by
    /// `Swift.Character.isWhitespace`).
    private static let separators: Set<Swift.Character> = [
        "—",     // em-dash
        "#",     // markdown header
        "*",     // bold/italic
        "_",     // italic
        ">",     // blockquote
        "~",     // strikethrough
        "`",     // inline code
    ]

    public static func count(_ s: String) -> Int {
        var tokens: [String] = []
        var current = ""
        for ch in s {
            if ch.isWhitespace || separators.contains(ch) {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        // A token must contain at least one letter or number to count.
        // Filters out trailing punctuation like "..." or "!?".
        return tokens.filter { token in
            token.contains(where: { $0.isLetter || $0.isNumber })
        }.count
    }
}

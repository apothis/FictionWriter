import Foundation

/// Splits recent prose into a `head` (context) and a trailing `seed`
/// (an unfinished sentence at the cursor).
///
/// When an author stops mid-sentence and fires Continue, routing that
/// trailing fragment into the assistant-turn *prefill* — rather than
/// leaving it in the user-context — makes the model *complete the
/// sentence* from inside its own turn. There is no fresh-turn seam for
/// a refusal to open with; the community's strongest anti-refusal
/// lever, and it also produces a cleaner continuation.
///
/// `seed` is empty when the prose ends on a clean sentence boundary —
/// in that case Continue behaves exactly as before. `head + seed`
/// reconstructs the input exactly (the separating whitespace stays in
/// `head`).
public enum PrefillSeed {
    private static let terminators: Set<Swift.Character> = [".", "!", "?"]
    private static let quoteChars: Set<Swift.Character> = ["\"", "\u{201C}", "\u{201D}"]

    public static func extract(from prose: String) -> (head: String, seed: String) {
        let chars: [Swift.Character] = Array(prose)
        // Exclusive end-index of the last completed sentence.
        var lastBoundary = 0
        var insideQuotes = false
        var pendingSplit = false

        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if quoteChars.contains(ch) {
                if insideQuotes {
                    insideQuotes = false
                    let nextIsBoundary = (i + 1 >= chars.count) || chars[i + 1].isWhitespace
                    if pendingSplit && nextIsBoundary {
                        lastBoundary = i + 1
                        pendingSplit = false
                    }
                } else {
                    insideQuotes = true
                }
            } else if terminators.contains(ch) {
                if insideQuotes {
                    pendingSplit = true
                } else {
                    while i + 1 < chars.count, terminators.contains(chars[i + 1]) {
                        i += 1
                    }
                    let nextIsBoundary = (i + 1 >= chars.count) || chars[i + 1].isWhitespace
                    if nextIsBoundary {
                        lastBoundary = i + 1
                        pendingSplit = false
                    }
                }
            } else if ch == "\n" {
                lastBoundary = i + 1
                pendingSplit = false
            }
            i += 1
        }

        // Push the separating whitespace into `head` so `seed` starts
        // at its first real character.
        var seedStart = lastBoundary
        while seedStart < chars.count, chars[seedStart].isWhitespace {
            seedStart += 1
        }
        let head = String(chars[0..<seedStart])
        let seed = String(chars[seedStart...])
        return (head, seed)
    }
}

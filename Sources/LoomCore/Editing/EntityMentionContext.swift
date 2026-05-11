import Foundation

/// Phase 2 #10 — detects whether a cursor in a prose body sits in an
/// `@xxx` mention context. The editor's completion popover trigger
/// uses this to decide whether to show suggestions.
///
/// Detection rules:
///   - The `@` sigil must be preceded by whitespace, a newline, or
///     the beginning of the body. An `@` in the middle of a token
///     (e.g. `foo@bar`) is an email-like fragment, NOT a mention.
///   - The partial query is the run of non-whitespace characters
///     immediately following the `@` and ending at the cursor.
///   - A whitespace character between the `@` and the cursor ends
///     the context (the user finished or abandoned the mention).
public struct EntityMentionContext: Equatable {
    /// The substring after the `@`, up to the cursor. May be empty
    /// (cursor sits immediately after the `@`).
    public let partialQuery: String
    /// The range of the entire `@xxx` substring in the prose,
    /// including the `@`. Replacing this range with the entity
    /// markdown is the apply-completion step.
    public let replacementRange: NSRange

    public init(partialQuery: String, replacementRange: NSRange) {
        self.partialQuery = partialQuery
        self.replacementRange = replacementRange
    }

    public static func detect(in prose: String, cursorOffset: Int) -> EntityMentionContext? {
        let nsProse = prose as NSString
        let cursor = max(0, min(cursorOffset, nsProse.length))

        // Walk backwards from the cursor looking for `@`. Stop on
        // whitespace (mention ended) or the start of the prose.
        var i = cursor
        while i > 0 {
            let prevIndex = i - 1
            let scalar = nsProse.character(at: prevIndex)
            let ch = Unicode.Scalar(scalar)!
            if ch == "@" {
                // Verify the `@` is at BOL or preceded by whitespace.
                if prevIndex == 0 {
                    let query = nsProse.substring(with: NSRange(location: i, length: cursor - i))
                    return EntityMentionContext(
                        partialQuery: query,
                        replacementRange: NSRange(location: prevIndex, length: cursor - prevIndex)
                    )
                }
                let before = nsProse.character(at: prevIndex - 1)
                let beforeScalar = Unicode.Scalar(before)!
                if CharacterSet.whitespacesAndNewlines.contains(beforeScalar) {
                    let query = nsProse.substring(with: NSRange(location: i, length: cursor - i))
                    return EntityMentionContext(
                        partialQuery: query,
                        replacementRange: NSRange(location: prevIndex, length: cursor - prevIndex)
                    )
                }
                // `@` in the middle of a token — not a mention.
                return nil
            }
            if CharacterSet.whitespacesAndNewlines.contains(ch) {
                // Hit whitespace before any `@` — not in a mention.
                return nil
            }
            i = prevIndex
        }
        return nil
    }

    /// Result of applying a completion: new prose body + the cursor
    /// position the editor should move to.
    public struct Replacement: Equatable {
        public let prose: String
        public let cursorOffset: Int
    }

    /// Replaces the `@xxx` substring in `prose` with the entity's
    /// markdown link and returns the new prose + cursor offset
    /// (which lands at the end of the inserted markdown).
    public func applyReplacement(
        in prose: String,
        with match: EntityAutocompleteMatch
    ) -> Replacement {
        let nsProse = prose as NSString
        let ref = EntityReference(
            category: match.ref.category,
            id: match.ref.id,
            displayName: match.displayName
        )
        let replacement = ref.markdown
        let newProse = nsProse.replacingCharacters(in: replacementRange, with: replacement)
        let newCursor = replacementRange.location + (replacement as NSString).length
        return Replacement(prose: newProse, cursorOffset: newCursor)
    }
}

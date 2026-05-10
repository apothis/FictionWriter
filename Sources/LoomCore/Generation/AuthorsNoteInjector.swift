import Foundation

/// Splices the Author's Note into the recent-prose layer N lines back
/// from the cursor end — NovelAI's A/N convention. Lower in the prompt
/// means stronger steering ("recency wins"), so placing the AN inside
/// the prefill close to the cursor (rather than as a separate layer
/// somewhere above the prose) materially sharpens its effect on the
/// next-token distribution.
///
/// Pure string operation. Tested in isolation; PromptBuilder calls it
/// when assembling the recent-prose layer.
public enum AuthorsNoteInjector {
    /// Splice `[authorsNote]` into `prose` so the AN sits `depthLines`
    /// linebreaks back from the end of `prose`.
    ///
    /// - `depthLines == 0` → AN appended at the end (closest to cursor).
    /// - `depthLines >= line count` → AN prepended at the start.
    /// - Empty AN → returns prose unchanged.
    public static func inject(authorsNote: String, into prose: String, depthLines: Int) -> String {
        let trimmedNote = authorsNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNote.isEmpty, !prose.isEmpty else { return prose }

        // Bracketed convention from AI Dungeon / NovelAI — the model
        // is trained on long-form fiction where `[...]` brackets read
        // as out-of-band directorial notes, not in-story content.
        let bracket = "[\(trimmedNote)]"

        // Splitting on \n preserves blank lines as empty segments,
        // which is what we want — paragraph breaks count as two
        // line breaks. depthLines is measured in line breaks, so
        // we anchor the splice at the (count - depthLines)-th line
        // boundary from the start of `prose`.
        let lines = prose.components(separatedBy: "\n")
        let totalLines = lines.count
        let safeDepth = max(0, depthLines)
        let splitIndex = max(0, totalLines - safeDepth)

        if splitIndex == 0 {
            // AN at very top of the prose window.
            return bracket + "\n\n" + prose
        }
        if splitIndex >= totalLines {
            // AN at very bottom — depthLines = 0 path.
            return prose + "\n\n" + bracket
        }

        let head = lines[0..<splitIndex].joined(separator: "\n")
        let tail = lines[splitIndex..<totalLines].joined(separator: "\n")
        return head + "\n\n" + bracket + "\n\n" + tail
    }
}

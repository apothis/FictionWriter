import Foundation

/// Extracts the query text for style-RAG retrieval from a PromptContext.
/// Called by the generation coordinator immediately before
/// `PromptBuilder.build` to feed `RetrievalService.retrieve(query:)`.
///
/// Per-mode shape:
///
/// - `.continueProse` → last `lastWords` words of the current scene's
///   prose before the cursor. The model is about to continue from
///   here; retrieving against the most-recent text gets the freshest
///   voice signal.
/// - `.expand` / `.rewrite` / `.rewriteVoice` / `.rewriteTense` /
///   `.rewritePOV` / `.rewriteLength` / `.showDontTell` → the
///   selected substring. The model is operating on this text; that's
///   the voice we want exemplars to match.
/// - `.brainstorm` / `.critique` / `.bridge` / `.describe` /
///   `.nameSuggest` → nil. These modes don't generate prose that
///   imitates a style (they produce summaries, notes, name lists, or
///   stub markers); style retrieval doesn't apply.
public enum RetrievalQueryBuilder {
    public static func queryText(
        for context: PromptContext,
        lastWords: Int = 100
    ) -> String? {
        guard let sceneId = context.currentSceneId,
              let scene = context.scenes[sceneId]
        else { return nil }

        switch context.mode {
        case .continueProse:
            return lastWordsBeforeCursor(
                prose: scene.prose,
                cursorOffset: context.cursorOffset,
                words: lastWords
            )

        case .expand, .rewrite, .rewriteVoice, .rewriteTense,
             .rewritePOV, .rewriteLength, .showDontTell:
            return selectedSubstring(prose: scene.prose, range: context.selectionRange)

        case .brainstorm, .critique, .bridge, .describe, .nameSuggest:
            return nil
        }
    }

    // MARK: - Helpers

    private static func lastWordsBeforeCursor(
        prose: String,
        cursorOffset: Int,
        words: Int
    ) -> String? {
        let ns = prose as NSString
        let clamped = max(0, min(cursorOffset, ns.length))
        guard clamped > 0 else { return nil }
        let prefix = ns.substring(to: clamped)
        let tokens = prefix.split(whereSeparator: { $0.isWhitespace })
        guard !tokens.isEmpty else { return nil }
        let tail = tokens.suffix(words)
        return tail.joined(separator: " ")
    }

    private static func selectedSubstring(prose: String, range: NSRange?) -> String? {
        guard let range, range.length > 0 else { return nil }
        let ns = prose as NSString
        guard range.location >= 0,
              range.location + range.length <= ns.length
        else { return nil }
        return ns.substring(with: range)
    }
}

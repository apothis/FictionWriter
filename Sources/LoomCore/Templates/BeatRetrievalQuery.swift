import Foundation

// Phase 8.b.4 — per-beat retrieval query construction.
//
// Each beat in the per-beat writer-call loop optionally consults a
// style retriever. The query string this builder produces is what
// the embedder turns into a vector — its job is to surface chunks
// whose style + modality + content register match what we want this
// beat to read like. Tested at the pure-data level so the rendered
// query is reproducible from inputs.
//
// Components, in order:
//
//   - the beat's modality + function (lets the retriever lean toward
//     same-modality chunks once beat-aware filtering lands in §8.b.5)
//   - the beat's summary (already STRAP-stripped — role tokens, not
//     source-character names)
//   - the cast mapping (free-form v1; the substituted names give the
//     retriever a topical hook)
//   - the last sentence of priorBeatsProse as a recency anchor (only
//     when there IS prior prose — opening beats omit it)
//
// Each component lives on its own line. Compact: keeps the
// embedder's 512-token context budget intact even on long beats.

public enum BeatRetrievalQuery {
    public static func build(
        beat: SceneBeat,
        castMapping: String,
        priorBeatsProse: String
    ) -> String {
        var lines: [String] = []
        lines.append("Beat modality: \(beat.modality.rawValue). Function: \(beat.function.rawValue).")
        lines.append("Beat summary: \(beat.summary)")
        let trimmedCast = castMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCast.isEmpty {
            lines.append("Cast: \(trimmedCast)")
        }
        if let anchor = lastSentence(of: priorBeatsProse), !anchor.isEmpty {
            lines.append(anchor)
        }
        return lines.joined(separator: "\n")
    }

    /// Walk `text` backward from the end to the last sentence-ending
    /// punctuation (`.`, `!`, `?`), returning everything after it as a
    /// trimmed string. Returns nil for empty / whitespace-only input.
    /// Tracks the last full sentence even when the text ends without
    /// punctuation (mid-sentence prior prose).
    private static func lastSentence(of text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        func isEnder(_ c: Swift.Character) -> Bool { c == "." || c == "!" || c == "?" }
        // Drop any trailing whitespace/quote chars, then find the
        // preceding terminator (which marks the START of the last
        // sentence, after the terminator + space).
        let endIdx = trimmed.endIndex
        // If text ends with a terminator, look for the SECOND-to-last
        // (to grab the full last sentence). Otherwise look for the
        // last (the trailing fragment IS the last sentence).
        let endsWithTerminator = trimmed.last.map(isEnder) ?? false
        var searchEnd = endIdx
        if endsWithTerminator {
            searchEnd = trimmed.index(before: endIdx)
        }
        // Scan backward for a terminator before `searchEnd`.
        var cursor = searchEnd
        while cursor > trimmed.startIndex {
            cursor = trimmed.index(before: cursor)
            if isEnder(trimmed[cursor]) {
                let start = trimmed.index(after: cursor)
                let candidate = String(trimmed[start..<endIdx])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return candidate.isEmpty ? nil : candidate
            }
        }
        // No interior terminator — the whole thing is one sentence.
        return trimmed
    }
}

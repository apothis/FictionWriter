import Foundation

/// Pure-data scaffolding for the Phase 5 RAG-for-style spike
/// (LOOM_RAG_SPIKE.md). Holds the embedding vector type, cosine
/// similarity, and the word-window chunker. No networking — the spike
/// runner in `Tools/RagSpike` calls Kobold + Ollama and converts their
/// responses into `EmbeddingVector` values for ranking.

public struct EmbeddingVector: Equatable {
    public let values: [Float]
    public var dim: Int { values.count }

    public init(values: [Float]) {
        self.values = values
    }

    /// Cosine similarity in [-1, 1]. Returns 0 for the degenerate
    /// cases (zero magnitude either side, dim mismatch) so callers
    /// don't need to special-case NaN.
    public static func cosine(_ a: EmbeddingVector, _ b: EmbeddingVector) -> Float {
        guard a.dim == b.dim, a.dim > 0 else { return 0 }
        var dot: Float = 0
        var na: Float = 0
        var nb: Float = 0
        for i in 0..<a.dim {
            let x = a.values[i]
            let y = b.values[i]
            dot += x * y
            na += x * x
            nb += y * y
        }
        guard na > 0, nb > 0 else { return 0 }
        return dot / (sqrt(na) * sqrt(nb))
    }
}

public struct RagChunk: Equatable {
    public let text: String
    public let wordRange: Range<Int>

    public init(text: String, wordRange: Range<Int>) {
        self.text = text
        self.wordRange = wordRange
    }
}

public enum RagChunker {
    /// Word-window chunker. `size` is the window width in whitespace-
    /// separated tokens; `overlap` is the count of trailing tokens
    /// repeated at the start of the next window. The final window is
    /// kept even if it's shorter than `size` (tail prose still
    /// embeds; truncating it would lose corpus content).
    ///
    /// Invalid inputs (size <= 0, overlap >= size, overlap < 0) return
    /// an empty array. The spike's eval runner trusts the chunker, so
    /// the defensive empty path keeps the runner from looping on
    /// caller error.
    public static func chunk(_ text: String, size: Int, overlap: Int) -> [RagChunk] {
        guard size > 0, overlap >= 0, overlap < size else { return [] }
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return [] }

        let step = size - overlap
        var chunks: [RagChunk] = []
        var start = 0
        while start < words.count {
            let end = min(start + size, words.count)
            let slice = words[start..<end]
            chunks.append(RagChunk(
                text: slice.joined(separator: " "),
                wordRange: start..<end
            ))
            if end == words.count { break }
            start += step
        }
        return chunks
    }
}

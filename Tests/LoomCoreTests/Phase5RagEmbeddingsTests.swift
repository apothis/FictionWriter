import Foundation
@testable import LoomCore

/// Pure-data scaffolding for the Phase 5 RAG-for-style spike
/// (LOOM_RAG_SPIKE.md §6 S1). Covers `EmbeddingVector` + cosine
/// similarity + the word-window chunker. No networking — those land
/// when the spike runner (Tools/RagSpike) is wired in S3.
func phase5RagEmbeddingsTests() -> TestSuite {
    let s = TestSuite("Phase5RagEmbeddings")

    s.test("EmbeddingVector exposes dim from its values count") {
        let v = EmbeddingVector(values: [0.1, 0.2, 0.3])
        try expectEqual(v.dim, 3)
    }

    s.test("cosine of a vector with itself is 1.0") {
        let v = EmbeddingVector(values: [1.0, 2.0, 3.0])
        let c = EmbeddingVector.cosine(v, v)
        try expectTrue(abs(c - 1.0) < 1e-6, "cosine(v,v) = \(c), expected ~1.0")
    }

    s.test("cosine of orthogonal vectors is 0.0") {
        let a = EmbeddingVector(values: [1.0, 0.0])
        let b = EmbeddingVector(values: [0.0, 1.0])
        let c = EmbeddingVector.cosine(a, b)
        try expectTrue(abs(c) < 1e-6, "cosine(orthogonal) = \(c)")
    }

    s.test("cosine of opposite vectors is -1.0") {
        let a = EmbeddingVector(values: [1.0, 2.0, 3.0])
        let b = EmbeddingVector(values: [-1.0, -2.0, -3.0])
        let c = EmbeddingVector.cosine(a, b)
        try expectTrue(abs(c + 1.0) < 1e-6, "cosine(opposite) = \(c)")
    }

    s.test("cosine is symmetric") {
        let a = EmbeddingVector(values: [1.0, 2.0, 3.0, 4.0])
        let b = EmbeddingVector(values: [2.0, 1.0, 0.5, 3.0])
        let ab = EmbeddingVector.cosine(a, b)
        let ba = EmbeddingVector.cosine(b, a)
        try expectTrue(abs(ab - ba) < 1e-6, "cosine asymmetric: \(ab) vs \(ba)")
    }

    s.test("cosine of zero vector is 0 (degenerate, no NaN)") {
        let a = EmbeddingVector(values: [0.0, 0.0, 0.0])
        let b = EmbeddingVector(values: [1.0, 2.0, 3.0])
        let c = EmbeddingVector.cosine(a, b)
        try expectEqual(c, 0.0)
    }

    s.test("cosine of mismatched dims is 0 (defensive — guards against caller error)") {
        // Production never hits this — different embedder paths have
        // different dims, callers must group by path. The defensive
        // zero return prevents a silent crash if the grouping breaks.
        let a = EmbeddingVector(values: [1.0, 2.0, 3.0])
        let b = EmbeddingVector(values: [1.0, 2.0])
        try expectEqual(EmbeddingVector.cosine(a, b), 0.0)
    }

    // MARK: - Chunker

    s.test("chunkText on empty input returns empty array") {
        let chunks = RagChunker.chunk("", size: 10, overlap: 2)
        try expectEqual(chunks.count, 0)
    }

    s.test("chunkText with fewer words than chunk size returns a single chunk") {
        let chunks = RagChunker.chunk("one two three four five", size: 10, overlap: 2)
        try expectEqual(chunks.count, 1)
        try expectEqual(chunks[0].text, "one two three four five")
        try expectEqual(chunks[0].wordRange.lowerBound, 0)
        try expectEqual(chunks[0].wordRange.upperBound, 5)
    }

    s.test("chunkText splits at the word window with the right number of windows") {
        // 12 words, size=5, overlap=1 → step=4
        // window 0: words [0..5)   ← "w0 w1 w2 w3 w4"
        // window 1: words [4..9)   ← "w4 w5 w6 w7 w8"
        // window 2: words [8..12)  ← "w8 w9 w10 w11"  (short tail, kept)
        let text = (0..<12).map { "w\($0)" }.joined(separator: " ")
        let chunks = RagChunker.chunk(text, size: 5, overlap: 1)
        try expectEqual(chunks.count, 3)
        try expectEqual(chunks[0].text, "w0 w1 w2 w3 w4")
        try expectEqual(chunks[1].text, "w4 w5 w6 w7 w8")
        try expectEqual(chunks[2].text, "w8 w9 w10 w11")
    }

    s.test("chunkText carries word ranges so callers can locate chunks in the source") {
        let text = (0..<12).map { "w\($0)" }.joined(separator: " ")
        let chunks = RagChunker.chunk(text, size: 5, overlap: 1)
        try expectEqual(chunks[0].wordRange.lowerBound, 0)
        try expectEqual(chunks[0].wordRange.upperBound, 5)
        try expectEqual(chunks[1].wordRange.lowerBound, 4)
        try expectEqual(chunks[1].wordRange.upperBound, 9)
        try expectEqual(chunks[2].wordRange.lowerBound, 8)
        try expectEqual(chunks[2].wordRange.upperBound, 12)
    }

    s.test("chunkText with overlap=0 produces non-overlapping windows") {
        let text = (0..<10).map { "w\($0)" }.joined(separator: " ")
        let chunks = RagChunker.chunk(text, size: 4, overlap: 0)
        // step=4: [0..4), [4..8), [8..10)
        try expectEqual(chunks.count, 3)
        try expectEqual(chunks[0].text, "w0 w1 w2 w3")
        try expectEqual(chunks[1].text, "w4 w5 w6 w7")
        try expectEqual(chunks[2].text, "w8 w9")
    }

    s.test("chunkText normalises internal whitespace to single spaces") {
        // Source prose often has newlines and double spaces; the
        // chunker re-joins word tokens with single spaces so embedders
        // see a stable normalised input.
        let chunks = RagChunker.chunk("alpha   beta\n\ngamma\tdelta", size: 10, overlap: 0)
        try expectEqual(chunks.count, 1)
        try expectEqual(chunks[0].text, "alpha beta gamma delta")
    }

    s.test("chunkText rejects invalid params by returning empty (defensive)") {
        // size <= 0 or overlap >= size is caller error; return empty
        // rather than divide-by-zero or infinite-loop.
        try expectEqual(RagChunker.chunk("a b c d e", size: 0, overlap: 0).count, 0)
        try expectEqual(RagChunker.chunk("a b c d e", size: 3, overlap: 3).count, 0)
        try expectEqual(RagChunker.chunk("a b c d e", size: 3, overlap: 5).count, 0)
    }

    return s
}

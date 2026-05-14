import Foundation

// Phase 8.a §6.1 — cosine matrix + axis-separation scoring for the
// embedder discrimination spike. Given a set of fixtures, each with an
// axis label (register for NSFW, style_axis for SFW), and a vector per
// fixture from some candidate embedder, the spike asks:
//
//   "Does this embedder pull same-axis pairs closer together than
//    cross-axis pairs?"
//
// The headline metric is `sameAxisMean - crossAxisMean`. Larger is
// better. Negative means the embedder is doing the *opposite* of what
// we need (anti-clustering on the axis we care about).
//
// Pure-data: zero networking, zero I/O. The spike runner (`Tools/
// SceneExemplarSpike`) wraps the embedders and feeds vectors in.

public struct CosineMatrix: Equatable {
    /// Row/column labels in matrix order (typically fixture ids).
    public let labels: [String]
    /// `values[i][j]` is `cosine(vec_i, vec_j)`. The matrix is symmetric
    /// (`values[i][j] == values[j][i]`) with 1.0 on the diagonal for
    /// non-degenerate vectors.
    public let values: [[Float]]

    public init(labels: [String], values: [[Float]]) {
        self.labels = labels
        self.values = values
    }

    /// Lookup by label. Returns nil if either label is not in the matrix.
    public func cosine(_ a: String, _ b: String) -> Float? {
        guard let i = labels.firstIndex(of: a),
              let j = labels.firstIndex(of: b) else { return nil }
        return values[i][j]
    }
}

public struct SeparationScore: Equatable {
    /// Mean cosine across unordered off-diagonal pairs whose labels share an axis.
    public let sameAxisMean: Float
    /// Mean cosine across unordered off-diagonal pairs whose labels are on different axes.
    public let crossAxisMean: Float
    public let sameAxisCount: Int
    public let crossAxisCount: Int

    /// Headline metric. Larger = better discrimination on the axis-of-interest.
    public var separation: Float { sameAxisMean - crossAxisMean }
}

public enum CosineMatrixAnalysis {
    /// Build a symmetric N×N cosine matrix from a vector-per-label list.
    /// Uses `EmbeddingVector.cosine`, which returns 0 for degenerate
    /// (zero-magnitude / dim-mismatched) inputs — the matrix may then
    /// carry 0.0 on the diagonal, which the separation score's
    /// off-diagonal-only walk ignores.
    public static func build(
        vectors: [(label: String, vector: EmbeddingVector)]
    ) -> CosineMatrix {
        let labels = vectors.map(\.label)
        let n = vectors.count
        var rows: [[Float]] = Array(repeating: Array(repeating: 0, count: n), count: n)
        for i in 0..<n {
            for j in i..<n {
                let c = EmbeddingVector.cosine(vectors[i].vector, vectors[j].vector)
                rows[i][j] = c
                rows[j][i] = c
            }
        }
        return CosineMatrix(labels: labels, values: rows)
    }

    /// Compute axis-separation: split unordered off-diagonal pairs into
    /// same-axis vs. cross-axis buckets using the caller-supplied
    /// `axisOf` map, then compare bucket means. Each unordered pair is
    /// counted once.
    public static func separationScore(
        matrix: CosineMatrix,
        axisOf: (String) -> String
    ) -> SeparationScore {
        var sameSum: Float = 0
        var sameCount = 0
        var crossSum: Float = 0
        var crossCount = 0
        let labels = matrix.labels
        let n = labels.count
        for i in 0..<n {
            for j in (i + 1)..<n {
                let c = matrix.values[i][j]
                if axisOf(labels[i]) == axisOf(labels[j]) {
                    sameSum += c
                    sameCount += 1
                } else {
                    crossSum += c
                    crossCount += 1
                }
            }
        }
        let sameMean = sameCount > 0 ? sameSum / Float(sameCount) : 0
        let crossMean = crossCount > 0 ? crossSum / Float(crossCount) : 0
        return SeparationScore(
            sameAxisMean: sameMean,
            crossAxisMean: crossMean,
            sameAxisCount: sameCount,
            crossAxisCount: crossCount
        )
    }
}

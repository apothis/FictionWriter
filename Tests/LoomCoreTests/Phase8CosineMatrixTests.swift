import Foundation
@testable import LoomCore

// Phase 8.a §6.1 — pure-data cosine matrix + same-axis/cross-axis
// separation score. The §6.1 spike's headline metric is
// `mean(same-axis cosine) - mean(cross-axis cosine)` per embedder: a
// style embedder that discriminates the register axes well produces a
// positive separation; one that conflates all explicit prose into a
// single cluster produces ~0 or negative.

private func vec(_ values: [Float]) -> EmbeddingVector {
    return EmbeddingVector(values: values)
}

func phase8CosineMatrixTests() -> TestSuite {
    let s = TestSuite("Phase8CosineMatrix")

    s.test("build produces a symmetric matrix with 1.0 on the diagonal") {
        let m = CosineMatrixAnalysis.build(vectors: [
            (label: "a", vector: vec([1, 0, 0])),
            (label: "b", vector: vec([0, 1, 0])),
            (label: "c", vector: vec([1, 1, 0])),
        ])
        try expectEqual(m.labels, ["a", "b", "c"])
        try expectEqual(m.values.count, 3)
        try expectEqual(m.values[0].count, 3)
        // Diagonal == 1.0 (within float epsilon)
        for i in 0..<3 {
            try expectTrue(abs(m.values[i][i] - 1.0) < 1e-5,
                           "diagonal[\(i)] = \(m.values[i][i])")
        }
        // Symmetric
        for i in 0..<3 {
            for j in 0..<3 {
                try expectTrue(abs(m.values[i][j] - m.values[j][i]) < 1e-6)
            }
        }
        // (a, b) orthogonal → cosine 0
        try expectTrue(abs(m.values[0][1]) < 1e-6)
        // (a, c) = 1/sqrt(2)
        try expectTrue(abs(m.values[0][2] - 1.0 / sqrt(2.0)) < 1e-5)
    }

    s.test("cosine(by label) returns the matrix entry") {
        let m = CosineMatrixAnalysis.build(vectors: [
            (label: "alpha", vector: vec([1, 0])),
            (label: "beta",  vector: vec([0, 1])),
        ])
        let c = try expectNotNil(m.cosine("alpha", "beta"))
        try expectTrue(abs(c) < 1e-6)
        try expectNil(m.cosine("alpha", "gamma"))
    }

    s.test("separation score: perfect axis-clustering produces ~1.0 separation") {
        // 4 vectors, 2 axes (axisA, axisB). Vectors within an axis are
        // identical; across axes they're orthogonal. Expect:
        //   same-axis mean = 1.0, cross-axis mean = 0.0, separation = 1.0.
        let m = CosineMatrixAnalysis.build(vectors: [
            (label: "a1", vector: vec([1, 0])),
            (label: "a2", vector: vec([1, 0])),
            (label: "b1", vector: vec([0, 1])),
            (label: "b2", vector: vec([0, 1])),
        ])
        let axisOf: (String) -> String = { id in
            id.hasPrefix("a") ? "A" : "B"
        }
        let score = CosineMatrixAnalysis.separationScore(matrix: m, axisOf: axisOf)
        try expectTrue(abs(score.sameAxisMean - 1.0) < 1e-5,
                       "sameAxisMean=\(score.sameAxisMean)")
        try expectTrue(abs(score.crossAxisMean) < 1e-5,
                       "crossAxisMean=\(score.crossAxisMean)")
        try expectTrue(abs(score.separation - 1.0) < 1e-5)
    }

    s.test("separation score: random-direction vectors produce ~0 separation") {
        // All four vectors orthogonal: same-axis cosine = 0,
        // cross-axis cosine = 0, separation = 0.
        let m = CosineMatrixAnalysis.build(vectors: [
            (label: "a1", vector: vec([1, 0, 0, 0])),
            (label: "a2", vector: vec([0, 1, 0, 0])),
            (label: "b1", vector: vec([0, 0, 1, 0])),
            (label: "b2", vector: vec([0, 0, 0, 1])),
        ])
        let axisOf: (String) -> String = { id in
            id.hasPrefix("a") ? "A" : "B"
        }
        let score = CosineMatrixAnalysis.separationScore(matrix: m, axisOf: axisOf)
        try expectTrue(abs(score.sameAxisMean) < 1e-5)
        try expectTrue(abs(score.crossAxisMean) < 1e-5)
        try expectTrue(abs(score.separation) < 1e-5)
    }

    s.test("separation score: anti-clustering produces NEGATIVE separation") {
        // Vectors within an axis are orthogonal, vectors across axes
        // are identical — the embedder is doing the wrong job. Expect
        // negative separation.
        let m = CosineMatrixAnalysis.build(vectors: [
            (label: "a1", vector: vec([1, 0])),
            (label: "b1", vector: vec([1, 0])),
            (label: "a2", vector: vec([0, 1])),
            (label: "b2", vector: vec([0, 1])),
        ])
        let axisOf: (String) -> String = { id in
            id.hasPrefix("a") ? "A" : "B"
        }
        let score = CosineMatrixAnalysis.separationScore(matrix: m, axisOf: axisOf)
        try expectLessThan(score.separation, 0)
    }

    s.test("separation score: diagonal is excluded from both means") {
        // 2 vectors, same axis. Without diagonal exclusion, same-axis
        // mean would include the two 1.0 self-similarities and skew
        // toward 1.0. With exclusion, it's just the single (a1, a2)
        // pair.
        let m = CosineMatrixAnalysis.build(vectors: [
            (label: "a1", vector: vec([1, 0])),
            (label: "a2", vector: vec([1, 1])),
        ])
        let axisOf: (String) -> String = { _ in "A" }
        let score = CosineMatrixAnalysis.separationScore(matrix: m, axisOf: axisOf)
        try expectEqual(score.sameAxisCount, 1) // one off-diagonal pair (a1,a2)
        try expectEqual(score.crossAxisCount, 0)
        // cosine((1,0), (1,1)) = 1/sqrt(2)
        try expectTrue(abs(score.sameAxisMean - 1.0 / sqrt(2.0)) < 1e-5)
    }

    s.test("separation score: pair counts symmetric (each unordered pair counted once)") {
        // 4 vectors, 2 per axis. Off-diagonal entries: 4*3 = 12 (ordered)
        // → 6 unordered. 2 same-axis (a1,a2 and b1,b2) + 4 cross-axis
        // (a1,b1) (a1,b2) (a2,b1) (a2,b2).
        let m = CosineMatrixAnalysis.build(vectors: [
            (label: "a1", vector: vec([1, 0])),
            (label: "a2", vector: vec([1, 0])),
            (label: "b1", vector: vec([0, 1])),
            (label: "b2", vector: vec([0, 1])),
        ])
        let axisOf: (String) -> String = { id in
            id.hasPrefix("a") ? "A" : "B"
        }
        let score = CosineMatrixAnalysis.separationScore(matrix: m, axisOf: axisOf)
        try expectEqual(score.sameAxisCount, 2)
        try expectEqual(score.crossAxisCount, 4)
    }

    return s
}

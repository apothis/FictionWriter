import Foundation
@testable import LoomCore

// Phase 8.a §6.1 — Markdown report formatter for the embedder
// discrimination spike. Each candidate embedder's run produces a
// section in LOOM_SCENE_EXEMPLAR_SPIKE.md: the headline separation
// score, the per-axis breakdown, and the full cosine matrix as a
// Markdown table.

func phase8EmbedderReportFormatterTests() -> TestSuite {
    let s = TestSuite("Phase8EmbedderReportFormatter")

    let m = CosineMatrixAnalysis.build(vectors: [
        (label: "a1", vector: EmbeddingVector(values: [1, 0])),
        (label: "a2", vector: EmbeddingVector(values: [1, 0])),
        (label: "b1", vector: EmbeddingVector(values: [0, 1])),
    ])
    let registerScore = CosineMatrixAnalysis.separationScore(matrix: m) { id in
        id.hasPrefix("a") ? "A" : "B"
    }

    s.test("formatMatrix renders a Markdown table with N+1 header columns") {
        let table = EmbedderReportFormatter.formatMatrix(m)
        let lines = table.split(separator: "\n", omittingEmptySubsequences: false)
        // Header row + separator row + N data rows = N+2
        try expectEqual(lines.count, m.labels.count + 2)
        // Header includes each label
        for label in m.labels {
            try expectTrue(table.contains(label),
                           "label \(label) missing from table")
        }
    }

    s.test("formatMatrix uses 3-decimal precision") {
        let table = EmbedderReportFormatter.formatMatrix(m)
        // (a1, a2) cosine is exactly 1.0 → "1.000"
        try expectTrue(table.contains("1.000"),
                       "expected 3-decimal '1.000' in table:\n\(table)")
        // (a1, b1) cosine is 0.0 → "0.000"
        try expectTrue(table.contains("0.000"))
    }

    s.test("formatScore prints same-mean, cross-mean, separation with 3 decimals") {
        let line = EmbedderReportFormatter.formatScore(registerScore, label: "register")
        try expectTrue(line.contains("register"))
        try expectTrue(line.contains("Same"))
        try expectTrue(line.contains("Cross"))
        try expectTrue(line.contains("Separation"))
        // Same-axis mean: (a1,a2) cosine = 1.0
        try expectTrue(line.contains("1.000"))
        // Cross-axis mean: avg of (a1,b1)=0, (a2,b1)=0 → 0.000
        try expectTrue(line.contains("0.000"))
    }

    s.test("formatScore signs separation with leading + or -") {
        let positive = EmbedderReportFormatter.formatScore(registerScore, label: "register")
        try expectTrue(positive.contains("+1.000") || positive.contains("+ 1.000"),
                       "expected +-prefixed separation in:\n\(positive)")

        let anti = SeparationScore(
            sameAxisMean: 0.2,
            crossAxisMean: 0.8,
            sameAxisCount: 1,
            crossAxisCount: 1
        )
        let neg = EmbedderReportFormatter.formatScore(anti, label: "register")
        try expectTrue(neg.contains("-0.600") || neg.contains("- 0.600"),
                       "expected negative separation in:\n\(neg)")
    }

    s.test("formatReport includes embedder id, headline scores, and full matrix") {
        let report = EmbedderReportFormatter.formatReport(
            embedderId: "StyleDistance/styledistance",
            embedderRole: "incumbent (style)",
            matrix: m,
            registerScore: registerScore,
            styleAxisScore: registerScore
        )
        try expectTrue(report.contains("StyleDistance/styledistance"))
        try expectTrue(report.contains("incumbent (style)"))
        try expectTrue(report.contains("register"))
        try expectTrue(report.contains("style_axis"))
        // Cosine matrix entry survives
        try expectTrue(report.contains("1.000"))
        // Table header for the matrix
        for label in m.labels {
            try expectTrue(report.contains(label))
        }
    }

    return s
}

import Foundation

// Phase 8.a §6.1 — Markdown report formatter for the embedder
// discrimination spike. Each candidate embedder's run produces one
// section: a header (id + role), the headline separation scores, and
// the full cosine matrix as a Markdown table. Sections concatenate into
// LOOM_SCENE_EXEMPLAR_SPIKE.md.
//
// Pure-data: takes a `CosineMatrix` + `SeparationScore`s, returns a
// String. Zero I/O.

public enum EmbedderReportFormatter {
    /// Render the matrix as a Markdown table with N+1 columns: a label
    /// column followed by one column per label. Values formatted to
    /// 3 decimals.
    public static func formatMatrix(_ matrix: CosineMatrix) -> String {
        var lines: [String] = []
        let header = ([""] + matrix.labels).joined(separator: " | ")
        lines.append("| " + header + " |")
        let sep = ([String](repeating: "---", count: matrix.labels.count + 1))
            .joined(separator: " | ")
        lines.append("| " + sep + " |")
        for (i, rowLabel) in matrix.labels.enumerated() {
            let cells = ([rowLabel] + matrix.values[i].map { formatCosine($0) })
                .joined(separator: " | ")
            lines.append("| " + cells + " |")
        }
        return lines.joined(separator: "\n")
    }

    /// One-line summary of a separation score.
    /// Example: `**register** — Same: 0.834 | Cross: 0.612 | Separation: +0.222 (n=10 / 90)`
    public static func formatScore(_ score: SeparationScore, label: String) -> String {
        let sep = formatSigned(score.separation)
        let same = formatCosine(score.sameAxisMean)
        let cross = formatCosine(score.crossAxisMean)
        return "**\(label)** — Same: \(same) | Cross: \(cross) | Separation: \(sep) " +
               "(n=\(score.sameAxisCount) same / \(score.crossAxisCount) cross)"
    }

    /// Full report section for one embedder.
    public static func formatReport(
        embedderId: String,
        embedderRole: String,
        matrix: CosineMatrix,
        registerScore: SeparationScore,
        styleAxisScore: SeparationScore
    ) -> String {
        var out: [String] = []
        out.append("### `\(embedderId)` — \(embedderRole)")
        out.append("")
        out.append(formatScore(registerScore, label: "register"))
        out.append("")
        out.append(formatScore(styleAxisScore, label: "style_axis"))
        out.append("")
        out.append("<details><summary>Full \(matrix.labels.count)×\(matrix.labels.count) cosine matrix</summary>")
        out.append("")
        out.append(formatMatrix(matrix))
        out.append("")
        out.append("</details>")
        return out.joined(separator: "\n")
    }

    // MARK: - Helpers

    private static func formatCosine(_ value: Float) -> String {
        return String(format: "%.3f", value)
    }

    private static func formatSigned(_ value: Float) -> String {
        let abs = String(format: "%.3f", Swift.abs(value))
        return value >= 0 ? "+\(abs)" : "-\(abs)"
    }
}

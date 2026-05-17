import Foundation

/// Planned Project mode — Phase 3: render a project's assigned styles
/// into a prompt block.
///
/// Genre and register go in separate, separately-labelled sections
/// with the register section last and framed as hard constraints —
/// research found that putting the two signals on distinct channels,
/// register last and most concrete, stops a vivid genre exemplar from
/// drowning the register (LOOM_PLANNED_PROJECT.md §3.2, §6).
///
/// When both a genre and a register are assigned the two can pull
/// apart (an atmospheric genre vs. a spare register). The leads then
/// carry an explicit precedence rule — genre owns mood and content,
/// register owns sentence construction and wins the overlap — so the
/// genre doesn't quietly override the register.
public enum StylePrompt {

    /// Render assigned styles into a prompt block. Returns an empty
    /// string when no styles are assigned, so the caller can omit the
    /// layer entirely.
    public static func render(_ styles: [Style]) -> String {
        let genres = styles.filter { $0.type == .genre }
        let registers = styles.filter { $0.type == .register }
        let bothPresent = !genres.isEmpty && !registers.isEmpty
        var sections: [String] = []
        if !genres.isEmpty {
            sections.append(section(
                header: "GENRE",
                lead: bothPresent
                    ? "Write in the following genre. The genre sets mood, atmosphere, content, and subject matter — it does not govern how a sentence is built. Where the genre and the prose register below pull apart, the register wins:"
                    : "Write in the following genre:",
                styles: genres
            ))
        }
        if !registers.isEmpty {
            sections.append(section(
                header: "PROSE REGISTER",
                lead: bothPresent
                    ? "Apply the following prose register. The register governs sentence-level construction — sentence length, rhythm, diction, and image density. Wherever it pulls against the genre above, the register decides how the sentence is built. Treat these as hard constraints on every sentence:"
                    : "Apply the following prose register — treat these as hard constraints on every sentence:",
                styles: registers
            ))
        }
        return sections.joined(separator: "\n\n")
    }

    private static func section(
        header: String, lead: String, styles: [Style]
    ) -> String {
        var lines = ["[STYLE — \(header)]", lead]
        for style in styles {
            lines.append("")
            lines.append("\(style.name) — \(style.descriptor)")
            for constraint in style.constraints {
                lines.append("- \(constraint)")
            }
            for (i, exemplar) in style.exemplars.enumerated() {
                lines.append("Example passage \(i + 1): \(exemplar)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

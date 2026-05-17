import Foundation

/// Planned Project mode — Phase 3: render a project's assigned styles
/// into a prompt block.
///
/// Genre and register go in separate, separately-labelled sections
/// with the register section last and framed as hard constraints —
/// research found that putting the two signals on distinct channels,
/// register last and most concrete, stops a vivid genre exemplar from
/// drowning the register (LOOM_PLANNED_PROJECT.md §3.2, §6).
public enum StylePrompt {

    /// Render assigned styles into a prompt block. Returns an empty
    /// string when no styles are assigned, so the caller can omit the
    /// layer entirely.
    public static func render(_ styles: [Style]) -> String {
        let genres = styles.filter { $0.type == .genre }
        let registers = styles.filter { $0.type == .register }
        var sections: [String] = []
        if !genres.isEmpty {
            sections.append(section(
                header: "GENRE",
                lead: "Write in the following genre:",
                styles: genres
            ))
        }
        if !registers.isEmpty {
            sections.append(section(
                header: "PROSE REGISTER",
                lead: "Apply the following prose register — treat these as hard constraints on every sentence:",
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

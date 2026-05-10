import Foundation

/// Pure manuscript → Markdown serialiser. The output is a single .md
/// file with a YAML frontmatter (title / author / exportedAt) at the
/// top, followed by each scene rendered as a `## <title>` section.
///
/// Phase 1 ships a flat scene list; Phase 3+ Parts/Chapters can extend
/// this with `# <chapter>` separators above the per-scene `##` blocks
/// without breaking the round-trip property of the existing per-scene
/// .md files.
public enum MarkdownExporter {
    public static func export(
        project: Project,
        scenes: [UUID: Scene],
        exportedAt: Date = Date()
    ) -> String {
        var out = ""

        // Frontmatter.
        out += "---\n"
        out += "title: \(quote(project.title))\n"
        if let author = project.author, !author.isEmpty {
            out += "author: \(quote(author))\n"
        }
        out += "exportedAt: \(quote(timestampString(exportedAt)))\n"
        out += "---\n\n"

        // Scenes in manuscript order.
        for sceneId in project.manuscript.orphanedSceneIds {
            guard let scene = scenes[sceneId] else { continue }
            out += "## \(scene.title)\n\n"
            out += scene.prose
            // Guarantee a blank-line separator before the next scene
            // (or at the file's end). Add one or two newlines depending
            // on what the prose already ends with.
            if !scene.prose.hasSuffix("\n") { out += "\n" }
            out += "\n"
        }
        return out
    }

    private static func quote(_ s: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(s.count + 2)
        escaped.append("\"")
        for ch in s {
            switch ch {
            case "\\": escaped.append("\\\\")
            case "\"": escaped.append("\\\"")
            case "\n": escaped.append("\\n")
            case "\r": escaped.append("\\r")
            case "\t": escaped.append("\\t")
            default: escaped.append(ch)
            }
        }
        escaped.append("\"")
        return escaped
    }

    private static func timestampString(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return f.string(from: date)
    }
}

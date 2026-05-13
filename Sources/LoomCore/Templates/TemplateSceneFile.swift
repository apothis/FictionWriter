import Foundation

/// On-disk format for `templates/<id>.md`: YAML-ish frontmatter
/// followed by prose body. Mirrors `ReferenceFile` exactly —
/// double-quoted scalar values, unknown keys preserved via
/// `extraFrontmatter`. Format:
///
///     ---
///     id: "..."
///     name: "..."
///     nsfw: false
///     createdAt: "2026-05-13T12:34:56.789Z"
///     ---
///
///     [prose body]
public enum TemplateSceneFile {
    public static func encode(_ scene: TemplateScene) -> String {
        var lines: [String] = ["---"]
        lines.append("id: \(quote(scene.id.uuidString))")
        lines.append("name: \(quote(scene.name))")
        lines.append("nsfw: \(scene.nsfw ? "true" : "false")")
        lines.append("createdAt: \(quote(LoomISO8601.fractionalFormatter.string(from: scene.createdAt)))")
        for key in scene.extraFrontmatter.keys.sorted() {
            let value = scene.extraFrontmatter[key]!
            lines.append("\(key): \(quote(value))")
        }
        lines.append("---")
        lines.append("")
        lines.append(scene.body)
        return lines.joined(separator: "\n")
    }

    public static func decode(_ text: String) throws -> TemplateScene {
        let split = try splitFrontmatterAndBody(text)
        let fm = parseFrontmatter(split.frontmatter)

        guard let idStr = fm["id"], let id = UUID(uuidString: idStr) else {
            throw TemplateSceneFileError.missingOrInvalidID
        }
        let name = fm["name"] ?? ""
        let nsfw = fm["nsfw"] == "true"
        let createdAt: Date
        if let dateStr = fm["createdAt"],
           let parsed = LoomISO8601.fractionalFormatter.date(from: dateStr)
            ?? LoomISO8601.plainFormatter.date(from: dateStr) {
            createdAt = parsed
        } else {
            createdAt = Date()
        }

        let owned: Set<String> = ["id", "name", "nsfw", "createdAt"]
        var extra: [String: String] = [:]
        for (key, value) in fm where !owned.contains(key) {
            extra[key] = value
        }

        return TemplateScene(
            id: id,
            name: name,
            nsfw: nsfw,
            createdAt: createdAt,
            extraFrontmatter: extra,
            body: split.body
        )
    }

    // MARK: - Frontmatter helpers (1:1 with ReferenceFile)

    private static func splitFrontmatterAndBody(_ text: String) throws -> (frontmatter: String, body: String) {
        let lines = text.components(separatedBy: "\n")
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else {
            throw TemplateSceneFileError.missingFrontmatter
        }
        var closingIndex: Int? = nil
        for i in 1..<lines.count where lines[i].trimmingCharacters(in: .whitespaces) == "---" {
            closingIndex = i
            break
        }
        guard let closing = closingIndex else {
            throw TemplateSceneFileError.unterminatedFrontmatter
        }
        let frontmatter = lines[1..<closing].joined(separator: "\n")
        var bodyStart = closing + 1
        if bodyStart < lines.count && lines[bodyStart].isEmpty {
            bodyStart += 1
        }
        let body = bodyStart < lines.count
            ? lines[bodyStart..<lines.count].joined(separator: "\n")
            : ""
        return (frontmatter, body)
    }

    private static func parseFrontmatter(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            guard let colonIdx = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colonIdx]).trimmingCharacters(in: .whitespaces)
            let valueRaw = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
            out[key] = unquote(valueRaw)
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

    private static func unquote(_ s: String) -> String {
        guard s.hasPrefix("\"") && s.hasSuffix("\"") && s.count >= 2 else { return s }
        let inner = String(s.dropFirst().dropLast())
        var out = ""
        out.reserveCapacity(inner.count)
        var iter = inner.makeIterator()
        while let ch = iter.next() {
            if ch != "\\" {
                out.append(ch)
                continue
            }
            guard let escaped = iter.next() else { break }
            switch escaped {
            case "\\": out.append("\\")
            case "\"": out.append("\"")
            case "n": out.append("\n")
            case "r": out.append("\r")
            case "t": out.append("\t")
            default:
                out.append("\\")
                out.append(escaped)
            }
        }
        return out
    }
}

public enum TemplateSceneFileError: Error, Equatable {
    case missingFrontmatter
    case unterminatedFrontmatter
    case missingOrInvalidID
}

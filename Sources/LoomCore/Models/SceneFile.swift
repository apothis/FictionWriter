import Foundation

/// On-disk representation for `scenes/<id>.md`: a YAML frontmatter block
/// followed by prose body. The frontmatter is restricted to scalar
/// key:value lines — no nesting, no multiline values, no lists. Strings
/// are double-quoted; bools/ints/UUIDs are bare. The forward-compat
/// promise is that any unrecognised key is preserved on `extraFrontmatter`
/// and re-emitted on save, so an external editor can add metadata without
/// fear of Loom dropping it.
///
/// Format (verbatim per LOOM_DATA_MODEL.md §7.1):
///
///     ---
///     id: "..."
///     title: "..."
///     status: "draft"
///     summaryDirty: false
///     ---
///
///     The wind had been picking up...
public enum SceneFile {
    /// Encode a scene to its on-disk text representation.
    public static func encode(_ scene: Scene) -> String {
        var lines: [String] = ["---"]

        lines.append("id: \(quote(scene.id.uuidString))")
        lines.append("title: \(quote(scene.title))")
        if let pov = scene.pov {
            lines.append("pov: \(quote(pov.uuidString))")
        }
        if let location = scene.location {
            lines.append("location: \(quote(location.uuidString))")
        }
        lines.append("status: \(quote(scene.status.rawValue))")
        if let target = scene.targetWordCount {
            lines.append("targetWordCount: \(target)")
        }
        if !scene.conflict.isEmpty {
            lines.append("conflict: \(quote(scene.conflict))")
        }
        if !scene.outcome.isEmpty {
            lines.append("outcome: \(quote(scene.outcome))")
        }
        if !scene.summary.isEmpty {
            lines.append("summary: \(quote(scene.summary))")
        }
        if !scene.framing.isEmpty {
            lines.append("framing: \(quote(scene.framing))")
        }
        if let level = scene.explicitnessLevel {
            lines.append("explicitnessLevel: \(quote(level.rawValue))")
        }
        lines.append("summaryDirty: \(scene.summaryDirty ? "true" : "false")")

        // Forward-compat: emit any extra keys not owned by Loom in
        // alphabetical order. Strings are quoted; non-string source values
        // already arrived as strings via the parser, so we keep them as
        // strings on round-trip.
        for key in scene.extraFrontmatter.keys.sorted() {
            let value = scene.extraFrontmatter[key]!
            lines.append("\(key): \(quote(value))")
        }

        lines.append("---")
        lines.append("")
        lines.append(scene.prose)

        return lines.joined(separator: "\n")
    }

    /// Decode a scene from on-disk text. The contentPath is supplied
    /// rather than derived because the caller knows where they read from
    /// (and stale `contentPath` values in old files shouldn't override
    /// the truth).
    public static func decode(_ text: String, contentPath: String) throws -> Scene {
        let split = try splitFrontmatterAndBody(text)
        let frontmatter = parseFrontmatter(split.frontmatter)

        guard let idStr = frontmatter["id"], let id = UUID(uuidString: idStr) else {
            throw SceneFileError.missingOrInvalidID
        }
        let title = frontmatter["title"] ?? ""

        let pov = frontmatter["pov"].flatMap { UUID(uuidString: $0) }
        let location = frontmatter["location"].flatMap { UUID(uuidString: $0) }
        let status = (frontmatter["status"].flatMap { SceneStatus(rawValue: $0) }) ?? .draft
        let summaryDirty = frontmatter["summaryDirty"] == "true"
        let targetWordCount: Int? = frontmatter["targetWordCount"].flatMap { Int($0) }
        let conflict = frontmatter["conflict"] ?? ""
        let outcome = frontmatter["outcome"] ?? ""
        let summary = frontmatter["summary"] ?? ""
        let framing = frontmatter["framing"] ?? ""
        let explicitnessLevel = frontmatter["explicitnessLevel"]
            .flatMap { ExplicitnessLevel(rawValue: $0) }

        // Extra: every key not in the Loom-owned set lands here. The set
        // must mirror the encode side exactly.
        let owned: Set<String> = [
            "id", "title", "pov", "location", "status",
            "targetWordCount", "conflict", "outcome", "summary", "framing",
            "explicitnessLevel", "summaryDirty",
        ]
        var extra: [String: String] = [:]
        for (key, value) in frontmatter where !owned.contains(key) {
            extra[key] = value
        }

        return Scene(
            id: id,
            title: title,
            pov: pov,
            location: location,
            status: status,
            conflict: conflict,
            outcome: outcome,
            summary: summary,
            summaryDirty: summaryDirty,
            targetWordCount: targetWordCount,
            contentPath: contentPath,
            framing: framing,
            explicitnessLevel: explicitnessLevel,
            extraFrontmatter: extra,
            prose: split.body
        )
    }

    // MARK: - Frontmatter parsing

    private static func splitFrontmatterAndBody(_ text: String) throws -> (frontmatter: String, body: String) {
        // Per LOOM_DATA_MODEL.md §7.1 the file MUST open with `---` (alone
        // on its first line); the second `---` delimits the frontmatter.
        // Anything after that line is prose body. Internal `---` in prose
        // are horizontal rules and untouched.
        let lines = text.components(separatedBy: "\n")
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else {
            throw SceneFileError.missingFrontmatter
        }
        // Find next `---` line.
        var closingIndex: Int? = nil
        for i in 1..<lines.count where lines[i].trimmingCharacters(in: .whitespaces) == "---" {
            closingIndex = i
            break
        }
        guard let closing = closingIndex else {
            throw SceneFileError.unterminatedFrontmatter
        }

        let frontmatter = lines[1..<closing].joined(separator: "\n")
        // Body starts after the closing `---` line. Convention: skip exactly
        // one blank line between frontmatter and prose so the round-trip is
        // stable. If the line after closing is blank, drop it; otherwise
        // include it.
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

    // MARK: - Quote/unquote

    /// Always emit values as JSON-style double-quoted strings: keeps the
    /// emitter trivial, sidesteps YAML ambiguity (`yes`/`no`/`null` etc),
    /// and round-trips cleanly through external editors that respect
    /// the surrounding quotes.
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
        guard s.hasPrefix("\"") && s.hasSuffix("\"") && s.count >= 2 else {
            return s
        }
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

public enum SceneFileError: Error, Equatable {
    case missingFrontmatter
    case unterminatedFrontmatter
    case missingOrInvalidID
}

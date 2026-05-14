import Foundation

// Phase 8.a §6.1 — scene-exemplar fixture model + YAML-frontmatter
// parser for the embedder-discrimination spike. The 20 fixtures at
// `Tools/SceneExemplarSpike/fixtures/` extend the Phase 7
// SceneTemplateSpike frontmatter pattern with three new fields:
// `nsfw` (bool), `register` (axis label or "n/a"), `style_axis`
// (matching style label). See LOOM_SCENE_EXEMPLAR.md §8.a.1.

public struct SceneExemplarFixture: Equatable {
    /// The `fixture_id` frontmatter field — also the file's stem, used
    /// as the matrix row/column label.
    public let id: String
    public let title: String
    public let nsfw: Bool
    /// Register axis (for NSFW fixtures: clinical / euphemistic /
    /// explicit-direct / explicit-poetic / explicit-mundane). SFW
    /// fixtures carry `"n/a"`.
    public let register: String
    /// Style axis — for SFW fixtures the canonical label
    /// (clipped-Hemingway / lyrical-McCarthy / clinical-procedural /
    /// baroque-Victorian / mundane-workmanlike); for NSFW the same
    /// value as `register`.
    public let styleAxis: String
    /// The prose body, with the closing `---` line stripped and any
    /// leading blank lines removed but trailing whitespace preserved.
    public let body: String

    public init(
        id: String,
        title: String,
        nsfw: Bool,
        register: String,
        styleAxis: String,
        body: String
    ) {
        self.id = id
        self.title = title
        self.nsfw = nsfw
        self.register = register
        self.styleAxis = styleAxis
        self.body = body
    }
}

public enum SceneExemplarFixtureParseError: Error, Equatable {
    case noFrontmatter
    case missingRequiredField(String)
    case invalidBool(field: String, value: String)
}

public enum SceneExemplarFixtureParser {
    /// Parse a markdown string with `---`-delimited YAML-style
    /// frontmatter. Supports flat `key: value` pairs and YAML block
    /// scalars introduced by `key: |` (indented continuation lines are
    /// consumed but discarded — the spike does not surface `notes`).
    public static func parse(_ markdown: String) throws -> SceneExemplarFixture {
        guard markdown.hasPrefix("---\n") else {
            throw SceneExemplarFixtureParseError.noFrontmatter
        }
        let afterFirst = markdown.dropFirst(4)
        guard let closeRange = afterFirst.range(of: "\n---\n") ?? afterFirst.range(of: "\n---") else {
            throw SceneExemplarFixtureParseError.noFrontmatter
        }
        let fmBlock = String(afterFirst[..<closeRange.lowerBound])
        let bodyRaw = String(afterFirst[closeRange.upperBound...])

        // Strip a leading newline (the one immediately after the
        // closing `---`) and any further blank lines so the body starts
        // at the first prose line.
        let body = stripLeadingBlankLines(bodyRaw)

        // Two-state line scanner. In `flat` we parse `key: value` pairs.
        // In `blockScalar` we consume indented continuation lines
        // (started by a prior `key: |`) until the indentation drops
        // back to zero — at which point we re-enter `flat`.
        var fields: [String: String] = [:]
        enum State { case flat, blockScalar }
        var state: State = .flat
        for line in fmBlock.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            switch state {
            case .flat:
                if s.trimmingCharacters(in: .whitespaces).isEmpty { continue }
                guard let colon = s.firstIndex(of: ":") else { continue }
                let key = String(s[..<colon]).trimmingCharacters(in: .whitespaces)
                var value = String(s[s.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                if value == "|" {
                    // Block scalar: consume indented lines until indent drops.
                    state = .blockScalar
                    continue
                }
                fields[key] = value
            case .blockScalar:
                if s.isEmpty { continue }
                if s.first == " " || s.first == "\t" {
                    // Still inside the block scalar — discard.
                    continue
                }
                // Indentation dropped — re-parse this line as a flat
                // entry. Recursion is bounded (one line), so just
                // inline it.
                state = .flat
                guard let colon = s.firstIndex(of: ":") else { continue }
                let key = String(s[..<colon]).trimmingCharacters(in: .whitespaces)
                let value = String(s[s.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                if value == "|" { state = .blockScalar; continue }
                fields[key] = value
            }
        }

        guard let id = fields["fixture_id"] else {
            throw SceneExemplarFixtureParseError.missingRequiredField("fixture_id")
        }
        guard let title = fields["title"] else {
            throw SceneExemplarFixtureParseError.missingRequiredField("title")
        }
        guard let nsfwRaw = fields["nsfw"] else {
            throw SceneExemplarFixtureParseError.missingRequiredField("nsfw")
        }
        let nsfw: Bool
        switch nsfwRaw {
        case "true": nsfw = true
        case "false": nsfw = false
        default:
            throw SceneExemplarFixtureParseError.invalidBool(field: "nsfw", value: nsfwRaw)
        }
        guard let register = fields["register"] else {
            throw SceneExemplarFixtureParseError.missingRequiredField("register")
        }
        guard let styleAxis = fields["style_axis"] else {
            throw SceneExemplarFixtureParseError.missingRequiredField("style_axis")
        }

        return SceneExemplarFixture(
            id: id,
            title: title,
            nsfw: nsfw,
            register: register,
            styleAxis: styleAxis,
            body: body
        )
    }

    private static func stripLeadingBlankLines(_ s: String) -> String {
        var lines = s.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeFirst()
        }
        return lines.joined(separator: "\n")
    }
}

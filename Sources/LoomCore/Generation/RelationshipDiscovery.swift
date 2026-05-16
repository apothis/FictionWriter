import Foundation

/// Phase 10 — Character Relationships. Step 2: the prompt, JSON
/// schema and parser for relationship discovery.
///
/// Relationship discovery is the sibling of Phase 9 entity
/// discovery: where entity discovery finds *who* is in a scene,
/// relationship discovery finds *how they relate*. It runs against
/// the bible's known characters and proposes directed edges
/// (from → to) with a kind and a temporal status the LLM infers
/// from prose cues ("ex-boyfriend" → past; "her new girlfriend" →
/// current).
///
/// The transition logic — demoting a prior `.current` partner when
/// a new one is accepted — lives in the accept flow, not here; this
/// namespace only turns a scene + character list into proposals.
public enum RelationshipDiscovery {
    /// A directed relationship edge proposed from a scene. Works in
    /// character *names* — the accept flow resolves names to bible
    /// UUIDs.
    public struct ProposedRelationship: Equatable {
        public let fromName: String
        public let toName: String
        public let kind: String
        public let status: RelationshipStatus
        public let evidenceQuote: String

        public init(
            fromName: String,
            toName: String,
            kind: String,
            status: RelationshipStatus,
            evidenceQuote: String
        ) {
            self.fromName = fromName
            self.toName = toName
            self.kind = kind
            self.status = status
            self.evidenceQuote = evidenceQuote
        }
    }

    /// A relationship proposal persisted to the sidecar — a
    /// `ProposedRelationship` with an identity and a scene anchor.
    /// Still name-based: the accept flow resolves names to bible
    /// character UUIDs at materialise time.
    public struct Proposal: Codable, Equatable {
        public let id: UUID
        public let fromName: String
        public let toName: String
        public let kind: String
        public let status: RelationshipStatus
        public let evidenceQuote: String
        public let sourceSceneId: UUID

        public init(
            id: UUID = UUID(),
            fromName: String,
            toName: String,
            kind: String,
            status: RelationshipStatus,
            evidenceQuote: String,
            sourceSceneId: UUID
        ) {
            self.id = id
            self.fromName = fromName
            self.toName = toName
            self.kind = kind
            self.status = status
            self.evidenceQuote = evidenceQuote
            self.sourceSceneId = sourceSceneId
        }

        /// Lift a name-based discovery result into a persistable
        /// proposal by attaching a fresh id and the source scene.
        public init(discovered: ProposedRelationship, sourceSceneId: UUID) {
            self.init(
                fromName: discovered.fromName,
                toName: discovered.toName,
                kind: discovered.kind,
                status: discovered.status,
                evidenceQuote: discovered.evidenceQuote,
                sourceSceneId: sourceSceneId
            )
        }
    }

    public static let promptInstruction =
        "Identify the relationships between the characters listed below as they are shown in the scene. For each ordered pair of listed characters with a relationship evident in the scene, emit one entry: \"from\" and \"to\" naming the two characters, \"kind\" describing the relationship from \"from\"'s perspective (e.g. \"girlfriend\", \"ex-boyfriend\", \"father\", \"rival\", \"close friend\", \"coworker\"), \"status\" being \"current\" if the relationship is live as of this scene or \"past\" if the scene shows it has ended (an ex-partner, a former mentor), and \"evidence_quote\" being a verbatim span from the scene that supports it. Only emit relationships where both characters appear in the list below."

    public static func buildDiscoveryPrompt(
        scenePose: String,
        characterNames: [String]
    ) -> String {
        let namesJSON: String = {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = (try? encoder.encode(characterNames)) ?? Data()
            return String(data: data, encoding: .utf8) ?? "[]"
        }()
        return """
        \(promptInstruction)

        Characters:
        \(namesJSON)

        Respond with ONLY a JSON array. Example:
        [{"from": "Jane", "to": "Mark", "kind": "sister", "status": "current", "evidence_quote": "Jane hugged her brother Mark."}]

        Scene:
        \(scenePose)

        Emit the JSON array.
        """
    }

    /// Discovery prompt asking for a **line list** rather than a JSON
    /// array. A small model emits a delimited line list far more
    /// reliably than nested JSON; parsed by `parseRelationshipLines`.
    public static func buildDiscoveryListPrompt(
        scenePose: String,
        characterNames: [String]
    ) -> String {
        let namesJSON: String = {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = (try? encoder.encode(characterNames)) ?? Data()
            return String(data: data, encoding: .utf8) ?? "[]"
        }()
        return """
        You are an indexing tool that catalogues the relationships between characters in a manuscript. You do not summarise or comment on the text — you only list relationships.

        Identify the relationships between the characters listed below as they are shown in the scene. For each ordered pair of listed characters with a relationship evident in the scene, emit one line.

        Output one relationship per line, and nothing else — no preamble, no JSON, no commentary. Each line must have exactly five fields separated by " | ":
        from | to | kind | status | quote
        where from and to are two of the characters named below; kind describes the relationship from "from"'s point of view (e.g. girlfriend, ex-boyfriend, father, rival, close friend); status is "current" if the relationship is live as of this scene or "past" if the scene shows it has ended; and quote is a short verbatim phrase from the scene that supports it. Only use characters from this list:
        \(namesJSON)

        Scene:
        \(scenePose)

        Begin the list now.
        """
    }

    public static func discoveryJSONSchema() -> [String: Any] {
        return [
            "type": "array",
            "items": [
                "type": "object",
                "properties": [
                    "from": ["type": "string"],
                    "to": ["type": "string"],
                    "kind": ["type": "string"],
                    "status": ["type": "string", "enum": ["current", "past"]],
                    "evidence_quote": ["type": "string"],
                ],
                "required": ["from", "to", "kind", "status", "evidence_quote"],
            ],
        ]
    }

    /// Parser tolerant of preamble / postamble and mid-array
    /// truncation — mirrors `EntityDiscovery.parseCandidates`.
    public static func parseRelationships(_ raw: String) throws -> [ProposedRelationship] {
        guard let first = raw.firstIndex(of: "[") else {
            throw EntityDiscovery.ParseError.noJSONArrayFound
        }
        if let last = raw.lastIndex(of: "]"), last > first {
            let slice = String(raw[first...last])
            if let data = slice.data(using: .utf8),
               let items = try? JSONDecoder().decode([RawRelationship].self, from: data)
            {
                return items.compactMap { relationshipFromRaw($0) }
            }
        }
        return recoverPerObject(raw[first...])
    }

    /// Parse the line-based discovery output: one relationship per
    /// line, `from | to | kind | status | quote`. Tolerant — skips
    /// blank lines, header noise, lines without the five pipe-
    /// delimited fields, and (per `parseRelationships`) defaults an
    /// unrecognised status to `.current`. Never throws.
    public static func parseRelationshipLines(_ raw: String) -> [ProposedRelationship] {
        var out: [ProposedRelationship] = []
        for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.drop(while: { lineLeadingNoiseCharacters.contains($0) })
            // maxSplits 4 so a pipe inside the quote stays intact.
            let parts = line.split(separator: "|", maxSplits: 4, omittingEmptySubsequences: false)
            guard parts.count == 5 else { continue }
            let from = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let to = String(parts[1]).trimmingCharacters(in: .whitespaces)
            let kind = String(parts[2]).trimmingCharacters(in: .whitespaces)
            let statusStr = String(parts[3]).trimmingCharacters(in: .whitespaces).lowercased()
            let quote = String(parts[4]).trimmingCharacters(in: .whitespaces)
            guard !from.isEmpty, !to.isEmpty, !kind.isEmpty else { continue }
            let status = RelationshipStatus(rawValue: statusStr) ?? .current
            out.append(ProposedRelationship(
                fromName: from, toName: to, kind: kind,
                status: status, evidenceQuote: quote
            ))
        }
        return out
    }

    private struct RawRelationship: Decodable {
        let from: String?
        let to: String?
        let kind: String?
        let status: String?
        let evidence_quote: String?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: DynamicCodingKey.self)
            // Unconstrained generation (no `format` schema) means the
            // model picks its own key names — accept the common
            // synonyms so edges aren't silently dropped.
            func str(_ keys: [String]) -> String? {
                for k in keys {
                    if let key = DynamicCodingKey(stringValue: k),
                       let v = try? c.decodeIfPresent(String.self, forKey: key) {
                        return v
                    }
                }
                return nil
            }
            from = str(["from", "from_character", "from_name", "fromName"])
            to = str(["to", "to_character", "to_name", "toName"])
            kind = str(["kind", "relationship", "type"])
            status = str(["status"])
            evidence_quote = str(["evidence_quote", "evidence", "quote"])
        }
    }

    private static func relationshipFromRaw(_ r: RawRelationship) -> ProposedRelationship? {
        guard let from = r.from, !from.isEmpty,
              let to = r.to, !to.isEmpty,
              let kind = r.kind, !kind.isEmpty,
              let quote = r.evidence_quote
        else { return nil }
        // An unrecognised / missing status defaults to .current —
        // an observed relationship is live unless the model says
        // otherwise.
        let status = RelationshipStatus(rawValue: r.status ?? "") ?? .current
        return ProposedRelationship(
            fromName: from,
            toName: to,
            kind: kind,
            status: status,
            evidenceQuote: quote
        )
    }

    /// Collapse duplicate edges sharing a direction + kind (case-
    /// insensitive, trimmed) down to their first occurrence. Like
    /// Phase 9's candidate dedup: gemma4_2b emits one edge per
    /// mention, so a scene where two characters interact repeatedly
    /// yields the same relationship many times. Status is part of
    /// the identity check is deliberately *not* — a contradictory
    /// current/past pair for the same edge keeps the first.
    public static func dedupRelationships(_ relationships: [ProposedRelationship]) -> [ProposedRelationship] {
        struct Key: Hashable {
            let from: String
            let to: String
            let kind: String
        }
        var seen: Set<Key> = []
        var out: [ProposedRelationship] = []
        for r in relationships {
            let key = Key(
                from: r.fromName.lowercased().trimmingCharacters(in: .whitespaces),
                to: r.toName.lowercased().trimmingCharacters(in: .whitespaces),
                kind: r.kind.lowercased().trimmingCharacters(in: .whitespaces)
            )
            if seen.insert(key).inserted {
                out.append(r)
            }
        }
        return out
    }

    private static func recoverPerObject(_ slice: Substring) -> [ProposedRelationship] {
        var out: [ProposedRelationship] = []
        var depth = 0
        var start: String.Index?
        for i in slice.indices {
            let c = slice[i]
            if c == "{" {
                if depth == 0 { start = i }
                depth += 1
            } else if c == "}" {
                depth -= 1
                if depth == 0, let s = start {
                    let objStr = String(slice[s...i])
                    if let data = objStr.data(using: .utf8),
                       let r = try? JSONDecoder().decode(RawRelationship.self, from: data),
                       let rel = relationshipFromRaw(r)
                    {
                        out.append(rel)
                    }
                    start = nil
                }
            }
        }
        return out
    }
}

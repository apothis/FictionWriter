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

        Scene:
        \(scenePose)

        Emit the JSON array.
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

    private struct RawRelationship: Decodable {
        let from: String?
        let to: String?
        let kind: String?
        let status: String?
        let evidence_quote: String?
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

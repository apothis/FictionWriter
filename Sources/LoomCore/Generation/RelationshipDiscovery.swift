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

    /// Drop edges whose endpoints aren't both in the known-character
    /// list. The discovery prompt says "only use characters from this
    /// list", but the model invents names anyway — e.g. "Narrator" for
    /// a first-person narrator who is in the list under their proper
    /// name. A hallucinated endpoint can't resolve to a bible
    /// character, so the edge is unusable. Case-insensitive, trimmed.
    public static func filterToKnownCharacters(
        _ relationships: [ProposedRelationship],
        characterNames: [String]
    ) -> [ProposedRelationship] {
        let known = Set(characterNames.map {
            $0.lowercased().trimmingCharacters(in: .whitespaces)
        })
        return relationships.filter { r in
            let from = r.fromName.lowercased().trimmingCharacters(in: .whitespaces)
            let to = r.toName.lowercased().trimmingCharacters(in: .whitespaces)
            return known.contains(from) && known.contains(to)
        }
    }

    // MARK: - Two-stage pairwise classification

    /// Stage 1 of pairwise relationship discovery: enumerate the
    /// unordered character pairs worth asking about — both names must
    /// actually occur in the scene. Asking the model one bounded
    /// "what is A to B?" question per pair beats one open "list every
    /// relationship" generation, which a small model hallucinates and
    /// under-reports (verified: GLiREL spike + gemma live-testing).
    public static func candidatePairs(
        characterNames: [String],
        scenePose: String
    ) -> [[String]] {
        let haystack = scenePose.lowercased()
        var seen = Set<String>()
        var present: [String] = []
        for name in characterNames {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            let key = trimmed.lowercased()
            guard !key.isEmpty, !seen.contains(key), haystack.contains(key) else { continue }
            seen.insert(key)
            present.append(trimmed)
        }
        var pairs: [[String]] = []
        for i in 0..<present.count {
            for j in (i + 1)..<present.count {
                pairs.append([present[i], present[j]])
            }
        }
        return pairs
    }

    /// Stage 2 prompt: a single bounded question about one character
    /// pair. The model either names the one relationship or answers
    /// "none" — far more reliable on a small model than open-ended
    /// list generation. Parsed by `parsePairClassification`.
    public static func buildPairClassificationPrompt(
        characterA: String,
        characterB: String,
        scenePose: String
    ) -> String {
        return """
        You are an indexing tool that catalogues character relationships in a manuscript. You do not summarise or judge the text — you answer one question.

        Decide whether the scene below shows a relationship between these two characters:
        \(characterA)
        \(characterB)

        If it does, reply with ONE line and nothing else — four fields separated by " | ":
        the first two fields are the two character names (\(characterA) and \(characterB), in whichever order makes the relationship read correctly); the third is a short relationship word describing the first name's relationship to the second (e.g. mother, daughter, sister, brother, lover, husband, wife, friend, rival, mentor); the fourth is "current" if the relationship is live as of this scene or "past" if the scene shows it has ended.
        For example, if \(characterA) is \(characterB)'s mentor, reply exactly:
        \(characterA) | \(characterB) | mentor | current
        If the scene shows NO relationship between \(characterA) and \(characterB), reply with exactly one word: none

        Scene:
        \(scenePose)
        """
    }

    /// Parse the Stage 2 per-pair answer: either `none` or one
    /// `from | to | kind | status` line. Tolerant of preamble and
    /// bullet noise; drops any line whose endpoints aren't the two
    /// characters that were asked about. Never throws.
    public static func parsePairClassification(
        _ raw: String,
        characterA: String,
        characterB: String
    ) -> [ProposedRelationship] {
        let allowed = Set([characterA, characterB].map {
            $0.lowercased().trimmingCharacters(in: .whitespaces)
        })
        var out: [ProposedRelationship] = []
        for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.drop(while: { lineLeadingNoiseCharacters.contains($0) })
            let parts = line.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false)
            guard parts.count == 4 else { continue }
            let from = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let to = String(parts[1]).trimmingCharacters(in: .whitespaces)
            let kind = String(parts[2]).trimmingCharacters(in: .whitespaces)
            let statusStr = String(parts[3]).trimmingCharacters(in: .whitespaces).lowercased()
            guard !kind.isEmpty,
                  allowed.contains(from.lowercased()),
                  allowed.contains(to.lowercased()),
                  from.lowercased() != to.lowercased()
            else { continue }
            out.append(ProposedRelationship(
                fromName: from, toName: to, kind: kind,
                status: RelationshipStatus(rawValue: statusStr) ?? .current,
                evidenceQuote: ""
            ))
        }
        return out
    }
}

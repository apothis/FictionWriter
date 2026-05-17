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

    // MARK: - Binary evidence gate (precision pre-filter)

    /// Stage 1.5 prompt: a conservative binary "do these two characters
    /// have a relationship?" gate, asked *before* the typed
    /// classification. A `yes` must cite a sentence copied verbatim
    /// from the scene; `parseGateResponse` then verifies that the
    /// quote is genuinely in the scene. The framing — "appearing in
    /// the same scene is NOT a relationship" — is a positive
    /// structural definition, not a negative blacklist.
    public static func buildRelationshipGatePrompt(
        characterA: String,
        characterB: String,
        scenePose: String
    ) -> String {
        return """
        You are an indexing tool that checks a manuscript for character relationships. You do not summarise or judge the text — you answer one question.

        Question: does the scene below show that these two characters have a relationship with each other — family, romantic, or social?
        \(characterA)
        \(characterB)

        A relationship means the text states or clearly implies how the two are connected — for example "her mother", "his wife", "the two friends had met at university". Two characters simply being present in the same scene, or interacting in passing, is NOT a relationship.

        Reply in exactly this form and nothing else:
        RELATED: yes
        EVIDENCE: <one sentence copied word for word from the scene that shows the relationship>
        Or, if the scene shows no relationship between \(characterA) and \(characterB), reply with exactly:
        RELATED: no

        Scene:
        \(scenePose)
        """
    }

    /// Parse the Stage 1.5 gate answer. Returns the verified evidence
    /// quote when the pair passes — a `yes` whose `EVIDENCE` sentence
    /// genuinely occurs in the scene (whitespace- and case-insensitive,
    /// and long enough to ground a claim). A `no`, a missing evidence
    /// line, or an ungrounded/fabricated quote all return nil: the
    /// pair is gated out and never reaches typed classification.
    public static func parseGateResponse(
        _ raw: String,
        scenePose: String
    ) -> String? {
        var related = false
        var evidence: String?
        for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.drop(while: { lineLeadingNoiseCharacters.contains($0) })
            let lower = line.lowercased()
            if lower.hasPrefix("related:") {
                related = line
                    .dropFirst("related:".count)
                    .lowercased()
                    .contains("yes")
            } else if lower.hasPrefix("evidence:") {
                evidence = String(line.dropFirst("evidence:".count))
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        guard related, let quote = evidence else { return nil }

        func normalised(_ s: String) -> String {
            s.lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
        let quoteNorm = normalised(quote)
        guard quoteNorm.count >= 12,
              normalised(scenePose).contains(quoteNorm)
        else { return nil }
        return quote.trimmingCharacters(in: .whitespaces)
    }

    /// Self-consistency vote over K independent classifications of one
    /// character pair. Each element is one run's parsed (deduped)
    /// result; an empty array is that run's "none" vote.
    ///
    /// Returns the edge only if a *strict majority* of runs found any
    /// relationship — gemma over-eagerly invents edges for unrelated
    /// pairs but does so unstably run-to-run, so a minority vote is
    /// almost always a hallucination. Among the runs that did find an
    /// edge, the most frequent `(from, to, kind, status)` wins; ties
    /// break toward the earliest run. K=1 degrades to "keep any edge".
    public static func voteOnPair(
        _ runs: [[ProposedRelationship]]
    ) -> [ProposedRelationship] {
        let votes = runs.compactMap { $0.first }
        guard votes.count * 2 > runs.count else { return [] }

        struct Key: Hashable {
            let from: String
            let to: String
            let kind: String
            let status: RelationshipStatus
        }
        func key(_ r: ProposedRelationship) -> Key {
            Key(
                from: r.fromName.lowercased().trimmingCharacters(in: .whitespaces),
                to: r.toName.lowercased().trimmingCharacters(in: .whitespaces),
                kind: r.kind.lowercased().trimmingCharacters(in: .whitespaces),
                status: r.status
            )
        }
        var counts: [Key: Int] = [:]
        var best: ProposedRelationship = votes[0]
        var bestCount = 0
        for vote in votes {
            let k = key(vote)
            let n = (counts[k] ?? 0) + 1
            counts[k] = n
            if n > bestCount {
                bestCount = n
                best = vote
            }
        }
        return [best]
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

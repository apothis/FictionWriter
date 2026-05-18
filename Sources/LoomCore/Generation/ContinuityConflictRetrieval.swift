import Foundation

/// Continuity Audit (L10) — Phase B, conflict-candidate retrieval
/// (pure data, deterministic).
///
/// Adjudicating every pair of claims is O(n²) and mostly wasted. This
/// step narrows the space to pairs worth a pairwise-NLI call: claims
/// about the **same subject** and the **same dimension**. Two routing
/// rules keep precision high before the LLM is ever asked:
///
/// - **Source-routing.** Only `narration` claims enter world-fact
///   conflict pairs. A `dialogue` / `thought` claim is the character's
///   assertion — a lie or a private belief is not a continuity error
///   (the spike's one false positive, p8, was exactly this).
/// - **Type-routing.** Only `attribute` / `temporal` / `spatial`
///   claims pair here. `event` is too noisy (a character does many
///   things); `knowledgeState` has its own dedicated check.
///
/// Subjects are expected to be already grounded to a canonical form
/// upstream (see `LOOM_CONTINUITY_AUDIT.md` §3.1); this layer
/// normalises the surface string as a fallback so it is testable and
/// useful on its own.
public enum ContinuityConflictRetrieval {

    public struct CandidatePair: Equatable {
        /// The claim from the earlier scene (manuscript order).
        public let earlier: ContinuityAudit.Claim
        /// The claim from the later scene.
        public let later: ContinuityAudit.Claim

        public init(earlier: ContinuityAudit.Claim, later: ContinuityAudit.Claim) {
            self.earlier = earlier
            self.later = later
        }
    }

    /// Claim types eligible for world-fact conflict pairing.
    static let pairableTypes: Set<ContinuityAudit.ClaimType> = [.attribute, .temporal, .spatial]

    /// Build the candidate-conflict pairs from a claim set. `sceneOrder`
    /// is the manuscript's scene ids in narrative order — it fixes
    /// which claim of a pair is `earlier`. Claims in a scene absent
    /// from `sceneOrder` are skipped. Output order is deterministic.
    public static func candidatePairs(
        claims: [ContinuityAudit.Claim],
        sceneOrder: [String]
    ) -> [CandidatePair] {
        var sceneIndex: [String: Int] = [:]
        for (i, id) in sceneOrder.enumerated() { sceneIndex[id] = i }

        struct Entry { let claim: ContinuityAudit.Claim; let sceneIdx: Int; let arrayIdx: Int }
        var groups: [String: [Entry]] = [:]
        for (i, claim) in claims.enumerated() {
            guard pairableTypes.contains(claim.type) else { continue }
            guard claim.source == .narration else { continue }
            guard let si = sceneIndex[claim.sourceSceneId] else { continue }
            groups[groupKey(claim), default: []].append(Entry(claim: claim, sceneIdx: si, arrayIdx: i))
        }

        var pairs: [CandidatePair] = []
        for key in groups.keys.sorted() {
            let sorted = groups[key]!.sorted {
                $0.sceneIdx != $1.sceneIdx ? $0.sceneIdx < $1.sceneIdx : $0.arrayIdx < $1.arrayIdx
            }
            guard sorted.count >= 2 else { continue }
            for i in 0..<sorted.count {
                for j in (i + 1)..<sorted.count {
                    // Cross-scene only — the audit detects drift *across*
                    // scenes. Two claims in one scene are far more often a
                    // conjunction the writer wrote as a unit ("a wind that
                    // smelled of salt and woodsmoke") than a continuity
                    // error, so a same-scene pair is never a candidate.
                    guard sorted[i].claim.sourceSceneId != sorted[j].claim.sourceSceneId else { continue }
                    pairs.append(CandidatePair(earlier: sorted[i].claim, later: sorted[j].claim))
                }
            }
        }
        return pairs
    }

    /// The grouping key — same key means a candidate-conflict group.
    /// Attribute claims also key on the (normalised) attribute key so
    /// eye colour and hair colour do not collide.
    private static func groupKey(_ c: ContinuityAudit.Claim) -> String {
        let subject = normalize(c.subject)
        if c.type == .attribute {
            return "attribute|\(subject)|\(normalize(c.attributeKey))"
        }
        return "\(c.type.rawValue)|\(subject)"
    }

    /// Lowercase, trim, drop a leading article, collapse whitespace —
    /// the fallback when a subject has not been entity-grounded.
    static func normalize(_ s: String) -> String {
        var t = s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for article in ["the ", "a ", "an "] where t.hasPrefix(article) {
            t = String(t.dropFirst(article.count))
            break
        }
        return t.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

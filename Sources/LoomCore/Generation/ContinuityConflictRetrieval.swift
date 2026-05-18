import Foundation

/// Continuity Audit (L10) — Phase B, conflict-candidate retrieval
/// (pure data, deterministic).
///
/// Adjudicating every pair of claims is O(n²) and mostly wasted. This
/// step narrows the space to pairs worth a pairwise-NLI call.
///
/// **Clustering by value similarity.** The original design grouped
/// claims by an exact `(type, subject)` key. The engine baseline
/// (`LOOM_CONTINUITY_AUDIT.md` §21) showed that lost ~67 points of
/// end-to-end recall: a contradiction's two claims were both extracted,
/// but the model gave them drifting subjects (`King Bren's death` vs
/// `the poisoning`) or different types, so the exact key never matched
/// and the pair never formed. Retrieval instead clusters claims by the
/// similarity of their **value** (the proposition text) — a
/// contradiction is two near-paraphrase claims that disagree on one
/// point, so similar values cluster while unrelated facts do not. This
/// is type-tolerant (type is not in the key) and drift-tolerant (the
/// subject lives inside the value), and stays bounded because only
/// near-paraphrases pair.
///
/// **Source-routing** is unchanged: only `narration` claims enter
/// world-fact conflict pairs. A `dialogue` / `thought` claim is the
/// character's assertion — a lie or a private belief is not a
/// continuity error. `knowledgeState` claims are excluded here; they
/// have a dedicated check (`ContinuityKnowledgeCheck`).
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

    /// Default value-similarity threshold for the built-in content-word
    /// Jaccard. An embedding-backed similarity (passed by the engine)
    /// wants its own, higher, cosine threshold.
    public static let defaultThreshold = 0.3

    /// Build the candidate-conflict pairs from a claim set.
    ///
    /// `sceneOrder` is the manuscript's scene ids in narrative order — it
    /// fixes which claim of a pair is `earlier`; claims in a scene absent
    /// from it are skipped. `similarity` scores two claim values 0…1;
    /// claims whose values score `>= threshold` cluster together and all
    /// cross-scene members of a cluster become candidate pairs. Output
    /// order is deterministic.
    public static func candidatePairs(
        claims: [ContinuityAudit.Claim],
        sceneOrder: [String],
        similarity: (String, String) -> Double = ContinuityConflictRetrieval.contentJaccard,
        threshold: Double = defaultThreshold
    ) -> [CandidatePair] {
        var sceneIndex: [String: Int] = [:]
        for (i, id) in sceneOrder.enumerated() { sceneIndex[id] = i }

        struct Entry { let claim: ContinuityAudit.Claim; let sceneIdx: Int; let arrayIdx: Int }
        var eligible: [Entry] = []
        for (i, claim) in claims.enumerated() {
            guard claim.type != .knowledgeState else { continue }
            guard claim.source == .narration else { continue }
            guard let si = sceneIndex[claim.sourceSceneId] else { continue }
            eligible.append(Entry(claim: claim, sceneIdx: si, arrayIdx: i))
        }

        // Greedy clustering by value similarity. A claim joins the first
        // cluster whose representative (its first member) it is similar
        // enough to; else it starts a cluster. Deterministic in `claims`
        // order.
        var clusters: [[Entry]] = []
        for entry in eligible {
            if let idx = clusters.firstIndex(where: {
                similarity($0[0].claim.value, entry.claim.value) >= threshold
            }) {
                clusters[idx].append(entry)
            } else {
                clusters.append([entry])
            }
        }

        var pairs: [CandidatePair] = []
        for cluster in clusters {
            let sorted = cluster.sorted {
                $0.sceneIdx != $1.sceneIdx ? $0.sceneIdx < $1.sceneIdx : $0.arrayIdx < $1.arrayIdx
            }
            guard sorted.count >= 2 else { continue }
            for i in 0..<sorted.count {
                for j in (i + 1)..<sorted.count {
                    // Cross-scene only — the audit detects drift *across*
                    // scenes; two claims in one scene are far more often a
                    // conjunction the writer wrote as a unit.
                    guard sorted[i].claim.sourceSceneId != sorted[j].claim.sourceSceneId else { continue }
                    pairs.append(CandidatePair(earlier: sorted[i].claim, later: sorted[j].claim))
                }
            }
        }
        return pairs
    }

    // MARK: - Default value similarity

    private static let stopwords: Set<String> = [
        "the", "a", "an", "is", "are", "was", "were", "of", "in", "on", "at",
        "to", "for", "and", "or", "it", "has", "have", "had", "be", "s",
    ]

    private static func contentTokens(_ s: String) -> Set<String> {
        Set(s.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !stopwords.contains($0) })
    }

    /// Default value similarity — content-word Jaccard overlap. The
    /// engine supplies an embedding-backed cosine instead for sharper
    /// clustering; this keeps retrieval usable and unit-testable on its
    /// own.
    public static func contentJaccard(_ a: String, _ b: String) -> Double {
        let x = contentTokens(a), y = contentTokens(b)
        if x.isEmpty && y.isEmpty { return 1 }
        let union = x.union(y).count
        return union == 0 ? 0 : Double(x.intersection(y).count) / Double(union)
    }

    /// Lowercase, trim, drop a leading article, collapse whitespace.
    /// Used by `ContinuitySubjectResolver` and `ContinuityClaimFilter`
    /// for surface-form subject/key matching.
    static func normalize(_ s: String) -> String {
        var t = s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for article in ["the ", "a ", "an "] where t.hasPrefix(article) {
            t = String(t.dropFirst(article.count))
            break
        }
        return t.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

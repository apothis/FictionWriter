import Foundation

// Continuity Audit (L10) — §25 Part B. World-state fact ledger types.
//
// `knowledge_violation` is a state-membership question ("had fact P
// entered the story's knowledge by scene N?"), not a similarity
// question — this is why embedding retrieval failed on it (§24) and
// why NLI failed on it (§26). The ledger answers the question
// deterministically once claims have been clustered into canonical
// fact nodes; the same-fact LLM judgment (§27) does the clustering.

public extension ContinuityAudit {

    /// A canonical fact in the world-state ledger — a cluster of one
    /// or more extracted claims that all assert the same proposition.
    /// `firstAppearanceScene` is the earliest source scene among the
    /// members in scene order — the answer to "by what scene has this
    /// fact entered the story?", which the `knowledge_violation`
    /// check needs.
    struct FactNode: Codable, Equatable, Identifiable {
        public var id: String
        /// The claim used as the cluster's anchor in same-fact
        /// comparisons; typically the first member encountered in
        /// scene order.
        public var representative: Claim
        public var firstAppearanceScene: String
        /// All claims clustered into this fact node, including the
        /// representative.
        public var members: [Claim]

        public init(
            id: String = UUID().uuidString,
            representative: Claim,
            firstAppearanceScene: String,
            members: [Claim]
        ) {
            self.id = id
            self.representative = representative
            self.firstAppearanceScene = firstAppearanceScene
            self.members = members
        }
    }

    /// The world-state fact ledger for a manuscript audit. A flat
    /// list of fact nodes built by walking non-knowledge claims in
    /// scene order; the knowledge-violation check is then a
    /// first-appearance lookup against this ledger.
    struct FactLedger: Codable, Equatable {
        public var nodes: [FactNode]

        public init(nodes: [FactNode] = []) {
            self.nodes = nodes
        }

        /// Build a ledger by single-pass online clustering.
        ///
        /// Claims are processed in scene order (the position of
        /// `claim.sourceSceneId` in `flatSceneIds`); claims whose
        /// scene is not in `flatSceneIds` are skipped. For each
        /// claim, every existing node whose representative passes
        /// `shouldCompare(rep, candidate)` is sent to the judge in
        /// node order — the first `same_fact` verdict attaches the
        /// candidate to that node, and the walk moves on. If no
        /// existing node matches, the candidate seeds a new node.
        ///
        /// `shouldCompare` is the cheap LLM-call prefilter — pairs
        /// it rejects are treated as `different_fact` without
        /// asking the judge. The §27 probe established this is
        /// essential for cost; a real audit pumps ~75+ claims
        /// through and the judge call is the only expensive op.
        public static func build(
            claims: [Claim],
            flatSceneIds: [String],
            judge: SameFactJudging,
            shouldCompare: @escaping (Claim, Claim) -> Bool,
            completion: @escaping (FactLedger) -> Void
        ) {
            // Order claims by scene-index; drop orphans (claim.scene
            // not in flatSceneIds — a scene was removed and the
            // claim is stale).
            let sceneIndex = Dictionary(uniqueKeysWithValues:
                flatSceneIds.enumerated().map { ($0.element, $0.offset) })
            let ordered = claims
                .enumerated()
                .compactMap { (i, c) -> (idx: Int, originalIdx: Int, claim: Claim)? in
                    guard let s = sceneIndex[c.sourceSceneId] else { return nil }
                    return (s, i, c)
                }
                // stable scene order with input order as the tiebreak —
                // claims from the same scene are processed in the
                // order they arrived in the input array.
                .sorted { lhs, rhs in
                    lhs.idx != rhs.idx ? lhs.idx < rhs.idx : lhs.originalIdx < rhs.originalIdx
                }
                .map(\.claim)

            var ledger = FactLedger()

            func step(_ i: Int) {
                if i >= ordered.count { completion(ledger); return }
                let candidate = ordered[i]
                matchAgainst(candidate, nodeIndex: 0) { matchedIndex in
                    if let m = matchedIndex {
                        ledger.nodes[m].members.append(candidate)
                    } else {
                        ledger.nodes.append(FactNode(
                            representative: candidate,
                            firstAppearanceScene: candidate.sourceSceneId,
                            members: [candidate]))
                    }
                    step(i + 1)
                }
            }

            func matchAgainst(
                _ candidate: Claim, nodeIndex i: Int,
                completion done: @escaping (Int?) -> Void
            ) {
                if i >= ledger.nodes.count { done(nil); return }
                let rep = ledger.nodes[i].representative
                if !shouldCompare(rep, candidate) {
                    matchAgainst(candidate, nodeIndex: i + 1, completion: done)
                    return
                }
                judge.judge(claimA: rep, claimB: candidate) { result in
                    let verdict = (try? result.get())?.verdict ?? .differentFact
                    if verdict == .sameFact { done(i); return }
                    matchAgainst(candidate, nodeIndex: i + 1, completion: done)
                }
            }

            step(0)
        }
    }
}

/// The async same-fact judgment primitive. Production code calls a
/// `SameFactLLMJudge` (LLM-backed); tests use a deferred stub. The
/// completion is invoked with `.success(judgment)` or `.failure(...)`;
/// on `.failure` the builder treats the pair as `different_fact`
/// (fail-soft — a transient kobold error must not corrupt the ledger
/// by accidentally merging two different facts).
public protocol SameFactJudging {
    func judge(
        claimA: ContinuityAudit.Claim,
        claimB: ContinuityAudit.Claim,
        completion: @escaping (Result<ContinuityAudit.SameFactJudgment, Error>) -> Void
    )
}

/// LLM-backed `SameFactJudging` impl — wraps an `OllamaCallProvider`
/// (the abstraction the audit engine already uses for both Ollama and
/// KoboldCpp via `KoboldGenerateProvider`). Builds the same-fact
/// prompt, requests the constrained JSON schema, parses the verdict.
/// A parse failure or transport failure maps to `.failure(_)` — the
/// `FactLedger.build` and `ContinuityKnowledgeCheck.violations` paths
/// then treat the pair as `different_fact` (fail-soft).
public final class SameFactLLMJudge: SameFactJudging {
    public enum JudgeError: Error { case parse }

    private let provider: OllamaCallProvider
    public init(provider: OllamaCallProvider) {
        self.provider = provider
    }

    public func judge(
        claimA: ContinuityAudit.Claim,
        claimB: ContinuityAudit.Claim,
        completion: @escaping (Result<ContinuityAudit.SameFactJudgment, Error>) -> Void
    ) {
        let prompt = ContinuityAudit.buildSameFactPrompt(claimA: claimA, claimB: claimB)
        provider.call(
            prompt: prompt,
            schema: ContinuityAudit.sameFactJSONSchema(),
            options: OllamaChatOptions(temperature: 0.2)
        ) { result in
            switch result {
            case .success(let raw):
                if let j = try? ContinuityAudit.parseSameFact(raw) {
                    completion(.success(j))
                } else {
                    completion(.failure(JudgeError.parse))
                }
            case .failure(let e):
                completion(.failure(e))
            }
        }
    }
}

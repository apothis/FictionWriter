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
    }
}

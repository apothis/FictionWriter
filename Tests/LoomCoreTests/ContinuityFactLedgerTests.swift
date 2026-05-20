import Foundation
@testable import LoomCore

/// Continuity Audit (L10) — §25 Part B. The world-state fact ledger
/// for `knowledge_violation`. Each `FactNode` is a cluster of claims
/// that assert the same proposition; `firstAppearanceScene` answers
/// the "by what scene has this fact entered the story?" question the
/// class actually asks (§24 measured this is a state-membership
/// question, not a similarity one — which is why embedding retrieval
/// and pairwise NLI both failed on it).
///
/// This file covers the value types and the deterministic builder.
/// The same-fact judgment is abstracted behind `SameFactJudging` so
/// the build is testable with a deterministic stub (no LLM call in
/// LoomCoreTests).
func continuityFactLedgerTests() -> TestSuite {
    let s = TestSuite("ContinuityFactLedger")

    func claim(
        _ type: ContinuityAudit.ClaimType = .attribute,
        subject: String = "Mara",
        key: String = "",
        value: String,
        scene: String,
        source: ContinuityAudit.ClaimSource = .narration,
        quote: String = ""
    ) -> ContinuityAudit.Claim {
        ContinuityAudit.Claim(
            type: type, subject: subject, attributeKey: key, value: value,
            sourceSceneId: scene, source: source, evidenceQuote: quote
        )
    }

    // MARK: - FactNode + FactLedger value types

    s.test("FactNode round-trips through Codable") {
        let c = claim(value: "Mara's eyes are green", scene: "s1")
        let node = ContinuityAudit.FactNode(
            id: "node-1", representative: c,
            firstAppearanceScene: "s1", members: [c])
        let data = try JSONEncoder().encode(node)
        let decoded = try JSONDecoder().decode(ContinuityAudit.FactNode.self, from: data)
        try expectEqual(decoded, node)
    }

    s.test("FactLedger round-trips through Codable with multiple nodes") {
        let c1 = claim(value: "Mara's eyes are green", scene: "s1")
        let c2 = claim(subject: "the vault", value: "the vault is on the fourteenth floor", scene: "s2")
        let n1 = ContinuityAudit.FactNode(id: "n1", representative: c1, firstAppearanceScene: "s1", members: [c1])
        let n2 = ContinuityAudit.FactNode(id: "n2", representative: c2, firstAppearanceScene: "s2", members: [c2])
        let ledger = ContinuityAudit.FactLedger(nodes: [n1, n2])
        let data = try JSONEncoder().encode(ledger)
        let decoded = try JSONDecoder().decode(ContinuityAudit.FactLedger.self, from: data)
        try expectEqual(decoded, ledger)
    }

    s.test("FactLedger() defaults to an empty node list") {
        let ledger = ContinuityAudit.FactLedger()
        try expectEqual(ledger.nodes.count, 0)
    }

    return s
}

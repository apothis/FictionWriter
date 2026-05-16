import Foundation
@testable import LoomCore

/// Phase 10 Part B/2 — bridge intents `acceptRelationshipProposal` +
/// `rejectRelationshipProposal`. JS side calls
/// `postIntent({kind: "acceptRelationshipProposal", proposalId, demoteConflicting})`;
/// Swift decodes via `BibleWorkspaceIntent`. Tests pin the wire shape
/// so the JS-Swift contract stays auditable.
func phase10BibleWorkspaceIntentRelationshipTests() -> TestSuite {
    let s = TestSuite("Phase10BibleWorkspaceIntentRelationship")

    s.test("acceptRelationshipProposal encodes with kind + proposalId + demoteConflicting") {
        let id = UUID()
        let intent = BibleWorkspaceIntent.acceptRelationshipProposal(
            proposalId: id, demoteConflicting: true
        )
        let data = try JSONEncoder().encode(intent)
        let obj = try (JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        try expectEqual(obj["kind"] as? String, "acceptRelationshipProposal")
        try expectEqual(obj["proposalId"] as? String, id.uuidString)
        try expectEqual(obj["demoteConflicting"] as? Bool, true)
    }

    s.test("acceptRelationshipProposal round-trips through Codable") {
        for demote in [true, false] {
            let intent = BibleWorkspaceIntent.acceptRelationshipProposal(
                proposalId: UUID(), demoteConflicting: demote
            )
            let data = try JSONEncoder().encode(intent)
            let back = try JSONDecoder().decode(BibleWorkspaceIntent.self, from: data)
            try expectEqual(back, intent)
        }
    }

    s.test("rejectRelationshipProposal encodes with kind + proposalId only") {
        let id = UUID()
        let intent = BibleWorkspaceIntent.rejectRelationshipProposal(proposalId: id)
        let data = try JSONEncoder().encode(intent)
        let obj = try (JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        try expectEqual(obj["kind"] as? String, "rejectRelationshipProposal")
        try expectEqual(obj["proposalId"] as? String, id.uuidString)
    }

    s.test("rejectRelationshipProposal round-trips through Codable") {
        let intent = BibleWorkspaceIntent.rejectRelationshipProposal(proposalId: UUID())
        let data = try JSONEncoder().encode(intent)
        let back = try JSONDecoder().decode(BibleWorkspaceIntent.self, from: data)
        try expectEqual(back, intent)
    }

    return s
}

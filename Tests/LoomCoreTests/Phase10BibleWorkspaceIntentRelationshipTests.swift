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

    s.test("setRelationshipNodePosition encodes with kind + characterId + x + y") {
        let id = UUID()
        let intent = BibleWorkspaceIntent.setRelationshipNodePosition(
            characterId: id, x: 120.5, y: -8.0
        )
        let data = try JSONEncoder().encode(intent)
        let obj = try (JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        try expectEqual(obj["kind"] as? String, "setRelationshipNodePosition")
        try expectEqual(obj["characterId"] as? String, id.uuidString)
        try expectEqual(obj["x"] as? Double, 120.5)
        try expectEqual(obj["y"] as? Double, -8.0)
    }

    s.test("setRelationshipNodePosition round-trips through Codable") {
        let intent = BibleWorkspaceIntent.setRelationshipNodePosition(
            characterId: UUID(), x: 3.0, y: 4.0
        )
        let data = try JSONEncoder().encode(intent)
        let back = try JSONDecoder().decode(BibleWorkspaceIntent.self, from: data)
        try expectEqual(back, intent)
    }

    s.test("setRelationshipEdge encodes with kind discriminator + edge fields") {
        let from = UUID(), to = UUID()
        let intent = BibleWorkspaceIntent.setRelationshipEdge(
            fromCharacterId: from, toCharacterId: to,
            edgeKind: "girlfriend", status: "current", notes: "since the beach"
        )
        let data = try JSONEncoder().encode(intent)
        let obj = try (JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        try expectEqual(obj["kind"] as? String, "setRelationshipEdge")
        try expectEqual(obj["fromCharacterId"] as? String, from.uuidString)
        try expectEqual(obj["toCharacterId"] as? String, to.uuidString)
        // The relationship's own kind rides as `edgeKind` — `kind` is
        // the intent discriminator.
        try expectEqual(obj["edgeKind"] as? String, "girlfriend")
        try expectEqual(obj["status"] as? String, "current")
        try expectEqual(obj["notes"] as? String, "since the beach")
    }

    s.test("setRelationshipEdge round-trips through Codable") {
        let intent = BibleWorkspaceIntent.setRelationshipEdge(
            fromCharacterId: UUID(), toCharacterId: UUID(),
            edgeKind: "rival", status: "past", notes: ""
        )
        let data = try JSONEncoder().encode(intent)
        let back = try JSONDecoder().decode(BibleWorkspaceIntent.self, from: data)
        try expectEqual(back, intent)
    }

    s.test("deleteRelationshipEdge round-trips through Codable") {
        let intent = BibleWorkspaceIntent.deleteRelationshipEdge(
            fromCharacterId: UUID(), toCharacterId: UUID(), edgeKind: "friend"
        )
        let data = try JSONEncoder().encode(intent)
        let back = try JSONDecoder().decode(BibleWorkspaceIntent.self, from: data)
        try expectEqual(back, intent)
    }

    return s
}

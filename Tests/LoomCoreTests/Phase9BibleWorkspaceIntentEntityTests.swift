import Foundation
@testable import LoomCore

/// Phase 9 entity-discovery — bridge intents
/// `acceptEntityProposal` + `rejectEntityProposal`. JS side calls
/// `postIntent({kind: "acceptEntityProposal", proposalId, accepted: {...}})`;
/// Swift decodes via `BibleWorkspaceIntent` then dispatches through
/// `BibleWorkspaceWindowController` → `AppState`. Tests pin the wire
/// shape so the JS-Swift contract stays auditable.
func phase9BibleWorkspaceIntentEntityTests() -> TestSuite {
    let s = TestSuite("Phase9BibleWorkspaceIntentEntity")

    s.test("acceptEntityProposal encodes with kind + proposalId + accepted") {
        let proposalId = UUID()
        let intent = BibleWorkspaceIntent.acceptEntityProposal(
            proposalId: proposalId,
            accepted: ProposedEntityAcceptance(
                canonicalName: "Marius Thorn",
                aliases: ["Dr Thorn"],
                oneLine: "Doctor."
            )
        )
        let data = try JSONEncoder().encode(intent)
        let obj = try (JSONSerialization.jsonObject(with: data) as? [String: Any])
            ?? [:]
        try expectEqual(obj["kind"] as? String, "acceptEntityProposal")
        // proposalId encoded as UUID (uppercase string).
        try expectEqual(obj["proposalId"] as? String, proposalId.uuidString)
        let accepted = try expectNotNil(obj["accepted"] as? [String: Any])
        try expectEqual(accepted["canonicalName"] as? String, "Marius Thorn")
    }

    s.test("acceptEntityProposal round-trips through Codable") {
        let id = UUID()
        let intent = BibleWorkspaceIntent.acceptEntityProposal(
            proposalId: id,
            accepted: ProposedEntityAcceptance(
                canonicalName: "Velka",
                aliases: [],
                oneLine: "Singer."
            )
        )
        let data = try JSONEncoder().encode(intent)
        let back = try JSONDecoder().decode(BibleWorkspaceIntent.self, from: data)
        try expectEqual(back, intent)
    }

    s.test("rejectEntityProposal encodes with kind + proposalId only") {
        let id = UUID()
        let intent = BibleWorkspaceIntent.rejectEntityProposal(proposalId: id)
        let data = try JSONEncoder().encode(intent)
        let obj = try (JSONSerialization.jsonObject(with: data) as? [String: Any])
            ?? [:]
        try expectEqual(obj["kind"] as? String, "rejectEntityProposal")
        try expectEqual(obj["proposalId"] as? String, id.uuidString)
    }

    s.test("rejectEntityProposal round-trips through Codable") {
        let id = UUID()
        let intent = BibleWorkspaceIntent.rejectEntityProposal(proposalId: id)
        let data = try JSONEncoder().encode(intent)
        let back = try JSONDecoder().decode(BibleWorkspaceIntent.self, from: data)
        try expectEqual(back, intent)
    }

    s.test("ProposedEntityAcceptance round-trips") {
        let accepted = ProposedEntityAcceptance(
            canonicalName: "Theo",
            aliases: ["Theodore"],
            oneLine: "Ex-lover."
        )
        let data = try JSONEncoder().encode(accepted)
        let back = try JSONDecoder().decode(ProposedEntityAcceptance.self, from: data)
        try expectEqual(back, accepted)
    }

    s.test("decoding an unknown kind for the entity-discovery family throws") {
        // Sanity: the existing "unknown kind throws" guard already
        // catches typos in the new intent names.
        let json = "{\"kind\": \"acceptEntityPropsal\", \"proposalId\": \"\(UUID().uuidString)\"}"
        let data = json.data(using: .utf8)!
        do {
            _ = try JSONDecoder().decode(BibleWorkspaceIntent.self, from: data)
            throw TestFailure(message: "expected decoding error", file: #file, line: #line)
        } catch {
            // ok
        }
    }

    return s
}

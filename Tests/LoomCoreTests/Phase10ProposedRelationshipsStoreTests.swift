import Foundation
@testable import LoomCore

/// Phase 10 step 4b — `ProposedRelationshipsStore` sidecar.
func phase10ProposedRelationshipsStoreTests() -> TestSuite {
    let s = TestSuite("Phase10ProposedRelationshipsStore")

    func tempProjectURL() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("loom-pr-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func proposal(_ from: String, _ to: String, scene: UUID, kind: String = "friend") -> RelationshipDiscovery.Proposal {
        RelationshipDiscovery.Proposal(
            fromName: from, toName: to, kind: kind,
            status: .current, evidenceQuote: "q", sourceSceneId: scene
        )
    }

    s.test("load on absent project → nil (no error)") {
        let project = tempProjectURL()
        defer { try? FileManager.default.removeItem(at: project) }
        try expectNil(ProposedRelationshipsStore.load(in: project))
    }

    s.test("save then load round-trips proposals") {
        let project = tempProjectURL()
        defer { try? FileManager.default.removeItem(at: project) }
        let scene = UUID()
        try ProposedRelationshipsStore.save(
            ProposedRelationshipsPayload(
                proposals: [proposal("Chantal", "Muriel", scene: scene, kind: "girlfriend")],
                updatedAt: Date()
            ),
            in: project
        )
        let back = try expectNotNil(ProposedRelationshipsStore.load(in: project))
        try expectEqual(back.proposals.count, 1)
        try expectEqual(back.proposals[0].kind, "girlfriend")
        try expectEqual(back.proposals[0].status, .current)
    }

    s.test("save creates the sidecar directory if missing") {
        let project = tempProjectURL()
        defer { try? FileManager.default.removeItem(at: project) }
        try ProposedRelationshipsStore.save(
            ProposedRelationshipsPayload(proposals: [], updatedAt: Date()),
            in: project
        )
        try expectTrue(FileManager.default.fileExists(
            atPath: project.appendingPathComponent("proposed-relationships/proposed-relationships.json").path
        ))
    }

    s.test("replaceProposals supersedes the scene's prior set, keeps other scenes") {
        let project = tempProjectURL()
        defer { try? FileManager.default.removeItem(at: project) }
        let sceneA = UUID()
        let sceneB = UUID()
        try ProposedRelationshipsStore.save(
            ProposedRelationshipsPayload(
                proposals: [
                    proposal("StaleA", "StaleB", scene: sceneA),
                    proposal("OtherA", "OtherB", scene: sceneB),
                ],
                updatedAt: Date()
            ),
            in: project
        )
        try ProposedRelationshipsStore.replaceProposals(
            forSceneId: sceneA,
            proposals: [proposal("Chantal", "Muriel", scene: sceneA)],
            in: project
        )
        let back = try expectNotNil(ProposedRelationshipsStore.load(in: project))
        let froms = Set(back.proposals.map(\.fromName))
        try expectEqual(froms, Set(["Chantal", "OtherA"]))
    }

    s.test("replaceProposals on absent project starts fresh") {
        let project = tempProjectURL()
        defer { try? FileManager.default.removeItem(at: project) }
        let scene = UUID()
        try ProposedRelationshipsStore.replaceProposals(
            forSceneId: scene,
            proposals: [proposal("Chantal", "Muriel", scene: scene)],
            in: project
        )
        let back = try expectNotNil(ProposedRelationshipsStore.load(in: project))
        try expectEqual(back.proposals.count, 1)
    }

    s.test("remove drops a proposal by id") {
        let project = tempProjectURL()
        defer { try? FileManager.default.removeItem(at: project) }
        let scene = UUID()
        let keep = proposal("Keep", "X", scene: scene)
        let drop = proposal("Drop", "Y", scene: scene)
        try ProposedRelationshipsStore.save(
            ProposedRelationshipsPayload(proposals: [keep, drop], updatedAt: Date()),
            in: project
        )
        try ProposedRelationshipsStore.remove(proposalId: drop.id, in: project)
        let back = try expectNotNil(ProposedRelationshipsStore.load(in: project))
        try expectEqual(back.proposals.count, 1)
        try expectEqual(back.proposals[0].fromName, "Keep")
    }

    s.test("Proposal(discovered:sourceSceneId:) lifts a name-based result") {
        let scene = UUID()
        let discovered = RelationshipDiscovery.ProposedRelationship(
            fromName: "Chantal", toName: "Jacob", kind: "ex-boyfriend",
            status: .past, evidenceQuote: "q"
        )
        let p = RelationshipDiscovery.Proposal(discovered: discovered, sourceSceneId: scene)
        try expectEqual(p.fromName, "Chantal")
        try expectEqual(p.toName, "Jacob")
        try expectEqual(p.status, .past)
        try expectEqual(p.sourceSceneId, scene)
    }

    s.test("malformed JSON on disk → load returns nil (defensive)") {
        let project = tempProjectURL()
        defer { try? FileManager.default.removeItem(at: project) }
        let dir = project.appendingPathComponent("proposed-relationships", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "{ not json".write(
            to: dir.appendingPathComponent("proposed-relationships.json"),
            atomically: true, encoding: .utf8
        )
        try expectNil(ProposedRelationshipsStore.load(in: project))
    }

    return s
}

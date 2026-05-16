import Foundation
@testable import LoomCore

/// Phase 10 step 4b — AppState relationship-discovery completion
/// handler: persists proposals and posts the change notification on
/// every exit path.
func phase10RelationshipDiscoveryWiringTests() -> TestSuite {
    let s = TestSuite("Phase10RelationshipDiscoveryWiring")

    func freshAppState() -> AppState {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("loom-rel-wiring-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return AppState(settingsStore: AppSettingsStore(fileManager: .default, rootDir: tmp))
    }

    func tempProjectURL() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("loom-rel-proj-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    struct StubError: Error {}

    s.test("successful discovery persists proposals + posts the change notification") {
        let appState = freshAppState()
        let project = tempProjectURL()
        defer { try? FileManager.default.removeItem(at: project) }
        let sceneId = UUID()
        var fired = false
        let token = NotificationCenter.default.addObserver(
            forName: AppState.proposedRelationshipsDidChangeNotification,
            object: appState, queue: nil
        ) { _ in fired = true }
        defer { NotificationCenter.default.removeObserver(token) }

        appState.handleRelationshipDiscoveryComplete(
            projectURL: project,
            sceneId: sceneId,
            result: .success([
                RelationshipDiscovery.ProposedRelationship(
                    fromName: "Chantal", toName: "Muriel", kind: "girlfriend",
                    status: .current, evidenceQuote: "q"
                ),
            ])
        )
        try expectTrue(fired, "must post the change notification")
        let payload = try expectNotNil(ProposedRelationshipsStore.load(in: project))
        try expectEqual(payload.proposals.count, 1)
        try expectEqual(payload.proposals[0].fromName, "Chantal")
        try expectEqual(payload.proposals[0].sourceSceneId, sceneId)
    }

    s.test("failed discovery still posts the change notification") {
        let appState = freshAppState()
        let project = tempProjectURL()
        defer { try? FileManager.default.removeItem(at: project) }
        var fired = false
        let token = NotificationCenter.default.addObserver(
            forName: AppState.proposedRelationshipsDidChangeNotification,
            object: appState, queue: nil
        ) { _ in fired = true }
        defer { NotificationCenter.default.removeObserver(token) }

        appState.handleRelationshipDiscoveryComplete(
            projectURL: project,
            sceneId: UUID(),
            result: .failure(StubError())
        )
        try expectTrue(fired, "failure must post the change notification")
    }

    s.test("empty discovery supersedes a scene's prior proposals") {
        let appState = freshAppState()
        let project = tempProjectURL()
        defer { try? FileManager.default.removeItem(at: project) }
        let sceneId = UUID()
        // Seed a prior proposal for the scene.
        try ProposedRelationshipsStore.save(
            ProposedRelationshipsPayload(
                proposals: [RelationshipDiscovery.Proposal(
                    fromName: "Stale", toName: "Edge", kind: "friend",
                    status: .current, evidenceQuote: "q", sourceSceneId: sceneId
                )],
                updatedAt: Date()
            ),
            in: project
        )
        appState.handleRelationshipDiscoveryComplete(
            projectURL: project, sceneId: sceneId, result: .success([])
        )
        let payload = try expectNotNil(ProposedRelationshipsStore.load(in: project))
        try expectEqual(payload.proposals.count, 0, "empty re-discovery should clear the scene")
    }

    return s
}

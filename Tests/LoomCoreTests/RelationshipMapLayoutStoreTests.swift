import Foundation
@testable import LoomCore

/// Relationship-mapper increment 2 — `RelationshipMapLayoutStore`
/// sidecar that persists dragged node positions.
func relationshipMapLayoutStoreTests() -> TestSuite {
    let s = TestSuite("RelationshipMapLayoutStore")

    func tempProjectURL() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("loom-rml-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    s.test("load on absent project → nil (no error)") {
        let project = tempProjectURL()
        defer { try? FileManager.default.removeItem(at: project) }
        try expectNil(RelationshipMapLayoutStore.load(in: project))
    }

    s.test("save then load round-trips positions") {
        let project = tempProjectURL()
        defer { try? FileManager.default.removeItem(at: project) }
        let a = UUID()
        try RelationshipMapLayoutStore.save(
            RelationshipMapLayoutPayload(
                positions: [RelationshipMapPosition(characterId: a, x: 12.5, y: -3.0)],
                updatedAt: Date()
            ),
            in: project
        )
        let back = try expectNotNil(RelationshipMapLayoutStore.load(in: project))
        try expectEqual(back.positions.count, 1)
        try expectEqual(back.positions[0].characterId, a)
        try expectEqual(back.positions[0].x, 12.5)
        try expectEqual(back.positions[0].y, -3.0)
    }

    s.test("setPosition upserts one node, leaves the others untouched") {
        let project = tempProjectURL()
        defer { try? FileManager.default.removeItem(at: project) }
        let a = UUID(), b = UUID()
        try RelationshipMapLayoutStore.setPosition(characterId: a, x: 1, y: 1, in: project)
        try RelationshipMapLayoutStore.setPosition(characterId: b, x: 2, y: 2, in: project)
        // Move a again — replaces, does not duplicate.
        try RelationshipMapLayoutStore.setPosition(characterId: a, x: 9, y: 9, in: project)
        let back = try expectNotNil(RelationshipMapLayoutStore.load(in: project))
        try expectEqual(back.positions.count, 2)
        let byId = Dictionary(uniqueKeysWithValues: back.positions.map { ($0.characterId, $0) })
        try expectEqual(byId[a]?.x, 9)
        try expectEqual(byId[b]?.x, 2)
    }

    s.test("setPosition on absent project starts a fresh layout") {
        let project = tempProjectURL()
        defer { try? FileManager.default.removeItem(at: project) }
        let a = UUID()
        try RelationshipMapLayoutStore.setPosition(characterId: a, x: 4, y: 5, in: project)
        let back = try expectNotNil(RelationshipMapLayoutStore.load(in: project))
        try expectEqual(back.positions.count, 1)
    }

    s.test("malformed JSON on disk → load returns nil (defensive)") {
        let project = tempProjectURL()
        defer { try? FileManager.default.removeItem(at: project) }
        let dir = project.appendingPathComponent("relationship-map", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "{ not json".write(
            to: dir.appendingPathComponent("layout.json"),
            atomically: true, encoding: .utf8
        )
        try expectNil(RelationshipMapLayoutStore.load(in: project))
    }

    return s
}

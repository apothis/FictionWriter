import Foundation
@testable import LoomCore

/// Phase 2 #9 — auto-snapshot policy. Identifies which generation
/// modes warrant capturing the scene's prose first (the "before AI
/// rewrite" insurance per HANDOFF §9.1 row 9). Pure-data tests pin
/// the mode-classification contract; the coordinator wires it in.
func phase2SnapshotOnRewriteTests() -> TestSuite {
    let s = TestSuite("Phase2SnapshotOnRewrite")

    s.test("rewrite-family modes are flagged for snapshotting") {
        try expectTrue(SnapshotPolicy.shouldSnapshot(beforeMode: .rewrite))
        try expectTrue(SnapshotPolicy.shouldSnapshot(beforeMode: .rewriteVoice))
        try expectTrue(SnapshotPolicy.shouldSnapshot(beforeMode: .rewriteTense))
        try expectTrue(SnapshotPolicy.shouldSnapshot(beforeMode: .rewritePOV))
        try expectTrue(SnapshotPolicy.shouldSnapshot(beforeMode: .rewriteLength))
    }

    s.test("non-rewrite modes are not flagged") {
        try expectFalse(SnapshotPolicy.shouldSnapshot(beforeMode: .continueProse))
        try expectFalse(SnapshotPolicy.shouldSnapshot(beforeMode: .expand))
        try expectFalse(SnapshotPolicy.shouldSnapshot(beforeMode: .brainstorm))
        try expectFalse(SnapshotPolicy.shouldSnapshot(beforeMode: .critique))
        try expectFalse(SnapshotPolicy.shouldSnapshot(beforeMode: .describe))
    }

    s.test("captureBeforeRewriteIfNeeded writes a file for rewrite + skips for continue") {
        let projectDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("loom-test-rewriteauto-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: projectDir) }

        let session = ProjectSession(project: Project(title: "T"), url: projectDir)
        let scene = session.addScene(title: "S1")
        session.updateProse(id: scene.id, prose: "Pre-rewrite prose body.")

        // Continue → no snapshot.
        let cont = session.captureBeforeRewriteIfNeeded(mode: .continueProse, sceneId: scene.id)
        try expectNil(cont)
        try expectEqual(SnapshotStore().list(in: projectDir).count, 0)

        // Rewrite → snapshot written.
        let rewrite = session.captureBeforeRewriteIfNeeded(mode: .rewrite, sceneId: scene.id)
        let record = try expectNotNil(rewrite)
        try expectEqual(record.contentSnapshot, "Pre-rewrite prose body.")
        try expectEqual(record.label, "Before Rewrite")
        let disk = SnapshotStore().list(in: projectDir)
        try expectEqual(disk.count, 1)
        try expectEqual(disk[0].id, record.id)
    }

    return s
}

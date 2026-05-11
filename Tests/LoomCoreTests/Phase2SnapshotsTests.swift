import Foundation
@testable import LoomCore

/// Phase 2 #9 — Snapshots before AI rewrite (Scrivener pattern,
/// HANDOFF §9.1 row 9). On-disk shape mirrors generation-log: one
/// JSON file per snapshot at `<project>/snapshots/<ts>-<uuid>.json`.
///
/// Pure-data tests-first per the always-TDD memory contract.
func phase2SnapshotsTests() -> TestSuite {
    let s = TestSuite("Phase2Snapshots")

    func makeTempProjectDir() -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("loom-test-snapshots-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    s.test("PersistedSnapshot round-trips through JSON") {
        let sceneId = UUID()
        let snap = PersistedSnapshot(
            sceneId: sceneId,
            takenAt: Date(timeIntervalSince1970: 1_700_000_000),
            label: "Before Rewrite",
            contentSnapshot: "The original prose body."
        )
        let data = try JSONEncoder.loomPretty.encode(snap)
        let back = try JSONDecoder.loom.decode(PersistedSnapshot.self, from: data)
        try expectEqual(back.sceneId, sceneId)
        try expectEqual(back.label, "Before Rewrite")
        try expectEqual(back.contentSnapshot, "The original prose body.")
    }

    s.test("SnapshotStore.write creates the snapshots dir and returns a file URL") {
        let projectDir = makeTempProjectDir()
        defer { try? FileManager.default.removeItem(at: projectDir) }
        let store = SnapshotStore()
        let snap = PersistedSnapshot(
            sceneId: UUID(),
            takenAt: Date(),
            label: nil,
            contentSnapshot: "Body"
        )
        let url = try store.write(snap, in: projectDir)
        try expectTrue(FileManager.default.fileExists(atPath: url.path))
        try expectTrue(url.path.contains("snapshots"))
        try expectEqual(url.pathExtension, "json")
    }

    s.test("SnapshotStore.list returns all snapshots, newest first") {
        let projectDir = makeTempProjectDir()
        defer { try? FileManager.default.removeItem(at: projectDir) }
        let store = SnapshotStore()
        let scene = UUID()
        let older = PersistedSnapshot(sceneId: scene, takenAt: Date(timeIntervalSince1970: 1_700_000_000), label: "A", contentSnapshot: "first")
        let newer = PersistedSnapshot(sceneId: scene, takenAt: Date(timeIntervalSince1970: 1_700_001_000), label: "B", contentSnapshot: "second")
        _ = try store.write(older, in: projectDir)
        _ = try store.write(newer, in: projectDir)
        let listed = store.list(in: projectDir)
        try expectEqual(listed.count, 2)
        try expectEqual(listed[0].label, "B")
        try expectEqual(listed[1].label, "A")
    }

    s.test("SnapshotStore.list silently skips corrupt files (best-effort recovery)") {
        let projectDir = makeTempProjectDir()
        defer { try? FileManager.default.removeItem(at: projectDir) }
        let store = SnapshotStore()
        _ = try store.write(
            PersistedSnapshot(sceneId: UUID(), takenAt: Date(), label: "OK", contentSnapshot: "good"),
            in: projectDir
        )
        let snapshotsDir = projectDir.appendingPathComponent("snapshots", isDirectory: true)
        try Data("{ not valid json }".utf8).write(
            to: snapshotsDir.appendingPathComponent("corrupt.json")
        )
        let listed = store.list(in: projectDir)
        try expectEqual(listed.count, 1)
        try expectEqual(listed[0].label, "OK")
    }

    s.test("SnapshotStore.list on a project with no snapshots dir returns []") {
        let projectDir = makeTempProjectDir()
        defer { try? FileManager.default.removeItem(at: projectDir) }
        let store = SnapshotStore()
        try expectEqual(store.list(in: projectDir), [])
    }

    // MARK: ProjectSession.captureSnapshot

    s.test("captureSnapshot writes a snapshot file and returns the record") {
        let projectDir = makeTempProjectDir()
        defer { try? FileManager.default.removeItem(at: projectDir) }
        let project = Project(title: "T")
        let session = ProjectSession(project: project, url: projectDir)
        let scene = session.addScene(title: "S1")
        session.updateProse(id: scene.id, prose: "Original prose here.")

        let record = try expectNotNil(
            session.captureSnapshot(sceneId: scene.id, label: "Before Rewrite")
        )
        try expectEqual(record.sceneId, scene.id)
        try expectEqual(record.label, "Before Rewrite")
        try expectEqual(record.contentSnapshot, "Original prose here.")

        // Disk has exactly one snapshot file under the project dir.
        let listed = SnapshotStore().list(in: projectDir)
        try expectEqual(listed.count, 1)
        try expectEqual(listed[0].id, record.id)
    }

    s.test("captureSnapshot returns nil when the session has no URL (in-memory project)") {
        let session = ProjectSession(project: Project(title: "T"))   // url defaults to nil
        let scene = session.addScene(title: "S1")
        session.updateProse(id: scene.id, prose: "X")
        let record = session.captureSnapshot(sceneId: scene.id, label: "Try")
        try expectNil(record)
    }

    s.test("captureSnapshot returns nil for a stale sceneId") {
        let projectDir = makeTempProjectDir()
        defer { try? FileManager.default.removeItem(at: projectDir) }
        let session = ProjectSession(project: Project(title: "T"), url: projectDir)
        let record = session.captureSnapshot(sceneId: UUID(), label: nil)
        try expectNil(record)
    }

    return s
}

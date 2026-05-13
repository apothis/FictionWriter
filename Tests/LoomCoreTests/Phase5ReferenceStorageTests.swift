import Foundation
@testable import LoomCore

/// Disk-layer tests for Phase 5 reference text + index storage
/// (LOOM_PLAN.md §5 scope-lock #3). Each test creates a fresh
/// temp directory, exercises the storage API, cleans up via defer.
func phase5ReferenceStorageTests() -> TestSuite {
    let s = TestSuite("Phase5ReferenceStorage")

    func makeTempProjectURL() -> URL {
        let name = "loom-ref-storage-test-\(UUID().uuidString).loom"
        return FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }

    func makeProject(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    s.test("ensureDirectory creates references/ under the project") {
        let dir = makeTempProjectURL()
        defer { try? FileManager.default.removeItem(at: dir) }
        try makeProject(at: dir)

        try ReferenceStorage.ensureDirectory(in: dir)
        try expectTrue(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("references").path
        ))
    }

    s.test("ensureDirectory is idempotent — calling twice does not fail") {
        let dir = makeTempProjectURL()
        defer { try? FileManager.default.removeItem(at: dir) }
        try makeProject(at: dir)
        try ReferenceStorage.ensureDirectory(in: dir)
        try ReferenceStorage.ensureDirectory(in: dir)
    }

    s.test("saveReference + loadReference round-trip a reference text") {
        let dir = makeTempProjectURL()
        defer { try? FileManager.default.removeItem(at: dir) }
        try makeProject(at: dir)

        let id = UUID()
        let ref = ReferenceText(
            id: id,
            name: "Hemingway",
            nsfw: false,
            createdAt: LoomISO8601.roundedToMillisecond(Date()),
            body: "He walked to the door.\nIt was cold."
        )
        try ReferenceStorage.saveReference(ref, in: dir)

        let path = dir.appendingPathComponent("references/\(id.uuidString).md")
        try expectTrue(FileManager.default.fileExists(atPath: path.path))

        let loaded = try ReferenceStorage.loadReference(id: id, in: dir)
        try expectEqual(loaded.id, ref.id)
        try expectEqual(loaded.name, ref.name)
        try expectEqual(loaded.nsfw, ref.nsfw)
        try expectEqual(loaded.createdAt, ref.createdAt)
        try expectEqual(loaded.body, ref.body)
    }

    s.test("saveReference creates references/ on demand if missing") {
        let dir = makeTempProjectURL()
        defer { try? FileManager.default.removeItem(at: dir) }
        try makeProject(at: dir)
        // Don't call ensureDirectory — saveReference must create it.
        let ref = ReferenceText(id: UUID(), name: "x", body: "Body.")
        try ReferenceStorage.saveReference(ref, in: dir)
        try expectTrue(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("references").path
        ))
    }

    s.test("loadReference on missing file throws (caller decides whether to surface)") {
        let dir = makeTempProjectURL()
        defer { try? FileManager.default.removeItem(at: dir) }
        try makeProject(at: dir)
        try expectThrows {
            _ = try ReferenceStorage.loadReference(id: UUID(), in: dir)
        }
    }

    s.test("saveIndex + loadIndex round-trip a full index sidecar") {
        let dir = makeTempProjectURL()
        defer { try? FileManager.default.removeItem(at: dir) }
        try makeProject(at: dir)

        let id = UUID()
        let idx = ReferenceTextIndex(
            schemaVersion: 1,
            dModel: .init(id: "StyleDistance/styledistance (mlx-fp16)", dim: 3),
            eModel: .init(id: "loom/funcword-z-top150", dim: 3),
            chunks: [
                .init(text: "He walked.", wordRangeStart: 0, wordRangeEnd: 2,
                      modality: "action", dVec: [0.1, 0.2, -0.3], eVec: [1.0, -1.0, 0.0]),
                .init(text: "It was cold.", wordRangeStart: 2, wordRangeEnd: 5,
                      modality: "description", dVec: [-0.4, 0.5, 0.6], eVec: [0.5, 0.5, -1.0]),
            ]
        )
        try ReferenceStorage.saveIndex(idx, for: id, in: dir)

        let loaded = try expectNotNil(ReferenceStorage.loadIndex(for: id, in: dir))
        try expectEqual(loaded, idx)
    }

    s.test("loadIndex returns nil on a missing sidecar (rebuildable, not fatal)") {
        let dir = makeTempProjectURL()
        defer { try? FileManager.default.removeItem(at: dir) }
        try makeProject(at: dir)
        try expectNil(ReferenceStorage.loadIndex(for: UUID(), in: dir))
    }

    s.test("loadIndex returns nil on a malformed sidecar (corrupted file, log + rebuild)") {
        let dir = makeTempProjectURL()
        defer { try? FileManager.default.removeItem(at: dir) }
        try makeProject(at: dir)
        try ReferenceStorage.ensureDirectory(in: dir)

        let id = UUID()
        let path = dir.appendingPathComponent("references/\(id.uuidString).index")
        try "not valid JSON {".data(using: .utf8)!.write(to: path)
        try expectNil(ReferenceStorage.loadIndex(for: id, in: dir))
    }

    s.test("deleteReference removes both .md and .index files") {
        let dir = makeTempProjectURL()
        defer { try? FileManager.default.removeItem(at: dir) }
        try makeProject(at: dir)

        let id = UUID()
        let ref = ReferenceText(id: id, name: "x", body: "Body.")
        try ReferenceStorage.saveReference(ref, in: dir)
        try ReferenceStorage.saveIndex(ReferenceTextIndex(), for: id, in: dir)

        let mdPath = dir.appendingPathComponent("references/\(id.uuidString).md").path
        let indexPath = dir.appendingPathComponent("references/\(id.uuidString).index").path
        try expectTrue(FileManager.default.fileExists(atPath: mdPath))
        try expectTrue(FileManager.default.fileExists(atPath: indexPath))

        try ReferenceStorage.deleteReference(id: id, in: dir)

        try expectFalse(FileManager.default.fileExists(atPath: mdPath))
        try expectFalse(FileManager.default.fileExists(atPath: indexPath))
    }

    s.test("deleteReference on missing files does not throw (idempotent)") {
        let dir = makeTempProjectURL()
        defer { try? FileManager.default.removeItem(at: dir) }
        try makeProject(at: dir)
        try ReferenceStorage.deleteReference(id: UUID(), in: dir)
    }

    s.test("listReferenceIds enumerates the .md files in references/") {
        let dir = makeTempProjectURL()
        defer { try? FileManager.default.removeItem(at: dir) }
        try makeProject(at: dir)

        let id1 = UUID(), id2 = UUID(), id3 = UUID()
        for id in [id1, id2, id3] {
            try ReferenceStorage.saveReference(
                ReferenceText(id: id, name: "ref-\(id.uuidString.prefix(4))"),
                in: dir
            )
        }
        // Also drop a non-.md file — must be ignored.
        try "junk".data(using: .utf8)!.write(
            to: dir.appendingPathComponent("references/junk.txt")
        )

        let ids = Set(try ReferenceStorage.listReferenceIds(in: dir))
        try expectEqual(ids, Set([id1, id2, id3]))
    }

    s.test("listReferenceIds returns empty when references/ is absent") {
        let dir = makeTempProjectURL()
        defer { try? FileManager.default.removeItem(at: dir) }
        try makeProject(at: dir)
        try expectEqual(try ReferenceStorage.listReferenceIds(in: dir), [])
    }

    return s
}

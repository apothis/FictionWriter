import Foundation
@testable import LoomCore

/// Phase 5 production A2.1 — Bible Workspace surface for references.
///
/// Mirrors Phase 4.5 Sessions 2–5 patterns one slot wider: a fifth
/// entity type (References) joins Characters / Lorebook / Scenes /
/// Suggestions in the workspace snapshot, with the same patch + intent
/// shape the other entities already use.
///
/// Architectural divergence worth keeping in mind: unlike Characters
/// (which live in `project.bible.characters`) or Lorebook entries
/// (which live in `project.bible.lorebook`), references are NOT in
/// the Project struct — they live on disk only under `references/`
/// via `ReferenceStorage`. The `Project.swift` header even calls this
/// out as intentional ("references (Phase 5) are intentionally
/// absent from this struct"). So `ProjectSession` proxies wrap the
/// disk operations + post `didChangeNotification`, and
/// `BibleWorkspaceSnapshot.build` accepts the references list as an
/// explicit parameter (the caller — `BibleWorkspaceWindowController` —
/// does the disk reads).
func phase5BibleWorkspaceReferencesTests() -> TestSuite {
    let s = TestSuite("Phase5BibleWorkspaceReferences")

    func makeTempProject() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("loom-bw-refs-\(UUID().uuidString).loom")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - ReferencePatch

    s.test("ReferencePatch round-trips Codable with all fields set") {
        let patch = ReferencePatch(name: "Hemingway sample", nsfw: true, body: "She walked.")
        let data = try JSONEncoder().encode(patch)
        let decoded = try JSONDecoder().decode(ReferencePatch.self, from: data)
        try expectEqual(decoded, patch)
    }

    s.test("ReferencePatch round-trips Codable with sparse fields") {
        let patch = ReferencePatch(name: nil, nsfw: nil, body: "Updated body only.")
        let data = try JSONEncoder().encode(patch)
        let decoded = try JSONDecoder().decode(ReferencePatch.self, from: data)
        try expectEqual(decoded, patch)
    }

    s.test("ReferencePatch.apply replaces only non-nil fields") {
        let original = ReferenceText(
            id: UUID(),
            name: "Original",
            nsfw: false,
            createdAt: Date(timeIntervalSince1970: 1000),
            extraFrontmatter: [:],
            body: "Original body."
        )
        let patch = ReferencePatch(name: "Renamed", nsfw: nil, body: nil)
        let result = patch.apply(to: original)
        try expectEqual(result.name, "Renamed")
        try expectEqual(result.nsfw, false)
        try expectEqual(result.body, "Original body.")
        // Non-patched fields preserved exactly.
        try expectEqual(result.id, original.id)
        try expectEqual(result.createdAt, original.createdAt)
    }

    s.test("ReferencePatch.apply with nsfw toggle works") {
        let original = ReferenceText(id: UUID(), name: "n", nsfw: false, body: "")
        let toggled = ReferencePatch(nsfw: true).apply(to: original)
        try expectEqual(toggled.nsfw, true)
    }

    // MARK: - SnapshotReference

    s.test("SnapshotReference projects fields from ReferenceText (chunk count nil)") {
        let ref = ReferenceText(
            id: UUID(),
            name: "ref",
            nsfw: true,
            createdAt: Date(timeIntervalSince1970: 2000),
            body: "Body text."
        )
        let snap = SnapshotReference(from: ref, chunkCount: nil)
        try expectEqual(snap.id, ref.id)
        try expectEqual(snap.name, "ref")
        try expectEqual(snap.nsfw, true)
        try expectEqual(snap.createdAt, ref.createdAt)
        try expectEqual(snap.body, "Body text.")
        // `chunkCount: nil` signals "no index sidecar on disk" — the
        // React side renders an "Ingest" prompt when nil and a chunk
        // count when non-nil.
        try expectEqual(snap.chunkCount, nil)
    }

    s.test("SnapshotReference carries chunkCount when provided") {
        let ref = ReferenceText(id: UUID(), name: "ref", body: "")
        let snap = SnapshotReference(from: ref, chunkCount: 7)
        try expectEqual(snap.chunkCount, 7)
    }

    // MARK: - BibleWorkspaceSnapshot.build

    s.test("BibleWorkspaceSnapshot.build includes references in stable order") {
        let project = Project(title: "Test")
        let ref1 = SnapshotReference(
            from: ReferenceText(id: UUID(), name: "a", body: ""),
            chunkCount: 3
        )
        let ref2 = SnapshotReference(
            from: ReferenceText(id: UUID(), name: "b", body: ""),
            chunkCount: nil
        )
        let snap = BibleWorkspaceSnapshot.build(
            project: project,
            scenes: [:],
            references: [ref1, ref2],
            suggestionsQueue: LedgerSuggestionsQueue()
        )
        try expectEqual(snap.references.map(\.name), ["a", "b"])
        try expectEqual(snap.references.first?.chunkCount, 3)
    }

    s.test("BibleWorkspaceSnapshot.build with no references emits an empty array") {
        let project = Project(title: "Test")
        let snap = BibleWorkspaceSnapshot.build(
            project: project,
            scenes: [:],
            references: [],
            suggestionsQueue: LedgerSuggestionsQueue()
        )
        try expectEqual(snap.references, [])
    }

    // MARK: - BibleWorkspaceIntent (new cases)

    s.test("BibleWorkspaceIntent.createReference round-trips Codable") {
        let intent = BibleWorkspaceIntent.createReference(name: "Hemingway sample")
        let data = try JSONEncoder().encode(intent)
        let decoded = try BibleWorkspaceBridge.decodeIntent(data)
        try expectEqual(decoded, intent)
    }

    s.test("BibleWorkspaceIntent.patchReference round-trips Codable") {
        let id = UUID()
        let intent = BibleWorkspaceIntent.patchReference(
            id: id,
            patch: ReferencePatch(name: "Renamed", nsfw: true)
        )
        let data = try JSONEncoder().encode(intent)
        let decoded = try BibleWorkspaceBridge.decodeIntent(data)
        try expectEqual(decoded, intent)
    }

    s.test("BibleWorkspaceIntent.deleteReference round-trips Codable") {
        let id = UUID()
        let intent = BibleWorkspaceIntent.deleteReference(id: id)
        let data = try JSONEncoder().encode(intent)
        let decoded = try BibleWorkspaceBridge.decodeIntent(data)
        try expectEqual(decoded, intent)
    }

    s.test("BibleWorkspaceIntent.ingestReference round-trips Codable") {
        let id = UUID()
        let intent = BibleWorkspaceIntent.ingestReference(id: id)
        let data = try JSONEncoder().encode(intent)
        let decoded = try BibleWorkspaceBridge.decodeIntent(data)
        try expectEqual(decoded, intent)
    }

    s.test("BibleWorkspaceIntent decodes wire-shape JSON for createReference") {
        // Mirror the JS-side bridge wire format: `kind` discriminator
        // + flat case-specific fields. (The React side builds these by
        // hand in bridge.ts.)
        let raw = #"{"kind":"createReference","name":"sample"}"#
        let intent = try BibleWorkspaceBridge.decodeIntent(raw.data(using: .utf8)!)
        try expectEqual(intent, .createReference(name: "sample"))
    }

    // MARK: - ProjectSession proxies

    s.test("ProjectSession.addReference is a no-op for in-memory sessions") {
        let session = ProjectSession(project: Project(title: "u"))
        let ref = session.addReference(name: "x")
        try expectEqual(ref, nil)
    }

    s.test("ProjectSession.addReference writes to disk and posts didChange") {
        let projectURL = makeTempProject()
        defer { try? FileManager.default.removeItem(at: projectURL) }
        let session = ProjectSession(project: Project(title: "p"), url: projectURL)

        var didChangeCount = 0
        let token = NotificationCenter.default.addObserver(
            forName: ProjectSession.didChangeNotification, object: session, queue: nil
        ) { _ in didChangeCount += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        guard let ref = session.addReference(name: "Hemingway") else {
            try expectFalse(true, "addReference returned nil for disk-backed session")
            return
        }
        try expectEqual(ref.name, "Hemingway")
        try expectEqual(didChangeCount, 1)
        // Round-trip via storage to prove disk write.
        let onDisk = try ReferenceStorage.loadReference(id: ref.id, in: projectURL)
        try expectEqual(onDisk.id, ref.id)
        try expectEqual(onDisk.name, "Hemingway")
    }

    s.test("ProjectSession.updateReference persists changes and posts didChange") {
        let projectURL = makeTempProject()
        defer { try? FileManager.default.removeItem(at: projectURL) }
        let session = ProjectSession(project: Project(title: "p"), url: projectURL)
        let ref = session.addReference(name: "orig")!

        var didChangeCount = 0
        let token = NotificationCenter.default.addObserver(
            forName: ProjectSession.didChangeNotification, object: session, queue: nil
        ) { _ in didChangeCount += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        var updated = ref
        updated.name = "renamed"
        updated.body = "fresh body"
        updated.nsfw = true
        session.updateReference(updated)

        try expectEqual(didChangeCount, 1)
        let onDisk = try ReferenceStorage.loadReference(id: ref.id, in: projectURL)
        try expectEqual(onDisk.name, "renamed")
        try expectEqual(onDisk.nsfw, true)
        // ReferenceFile encodes the body in the .md body; round-trip
        // load proves the body landed.
        try expectEqual(onDisk.body, "fresh body")
    }

    s.test("ProjectSession.deleteReference removes from disk and posts didChange") {
        let projectURL = makeTempProject()
        defer { try? FileManager.default.removeItem(at: projectURL) }
        let session = ProjectSession(project: Project(title: "p"), url: projectURL)
        let ref = session.addReference(name: "to-delete")!

        var didChangeCount = 0
        let token = NotificationCenter.default.addObserver(
            forName: ProjectSession.didChangeNotification, object: session, queue: nil
        ) { _ in didChangeCount += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        session.deleteReference(id: ref.id)
        try expectEqual(didChangeCount, 1)
        let ids = try ReferenceStorage.listReferenceIds(in: projectURL)
        try expectFalse(ids.contains(ref.id))
    }

    s.test("ProjectSession.listReferenceSnapshots enumerates disk references with chunk counts") {
        let projectURL = makeTempProject()
        defer { try? FileManager.default.removeItem(at: projectURL) }
        let session = ProjectSession(project: Project(title: "p"), url: projectURL)
        let a = session.addReference(name: "a")!
        _ = session.addReference(name: "b")

        // Write an index sidecar for `a` so chunkCount surfaces.
        let idx = ReferenceTextIndex(
            chunks: [
                ReferenceTextIndex.Chunk(text: "x", wordRangeStart: 0, wordRangeEnd: 1),
                ReferenceTextIndex.Chunk(text: "y", wordRangeStart: 1, wordRangeEnd: 2),
            ]
        )
        try ReferenceStorage.saveIndex(idx, for: a.id, in: projectURL)

        let snaps = session.listReferenceSnapshots()
        try expectEqual(snaps.count, 2)
        let aSnap = snaps.first(where: { $0.id == a.id })!
        try expectEqual(aSnap.chunkCount, 2)
        let bSnap = snaps.first(where: { $0.name == "b" })!
        try expectEqual(bSnap.chunkCount, nil)
    }

    s.test("ProjectSession.listReferenceSnapshots returns [] for in-memory sessions") {
        let session = ProjectSession(project: Project(title: "u"))
        try expectEqual(session.listReferenceSnapshots(), [])
    }

    return s
}

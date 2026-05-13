import Foundation
@testable import LoomCore

/// Phase 7.b.5 — Bible Workspace surface for Template Scenes.
///
/// Mirrors the Phase 5 A2.1 References pattern verbatim: a new entity
/// type (Template Scenes) joins Characters / Lorebook / References /
/// Scenes / Suggestions in the workspace snapshot, with the same
/// patch + intent shape the other entities use.
///
/// Architectural parallel to References: template scenes are NOT in
/// the Project struct — they live on disk only under `templates/`
/// via `TemplateSceneStorage`. So `ProjectSession` proxies wrap the
/// disk operations + post `didChangeNotification`, and
/// `BibleWorkspaceSnapshot.build` accepts the template-scenes list
/// as an explicit parameter (the caller — `BibleWorkspaceWindowController` —
/// does the disk reads).
func phase7BibleWorkspaceTemplatesTests() -> TestSuite {
    let s = TestSuite("Phase7BibleWorkspaceTemplates")

    func makeTempProject() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("loom-bw-tmpl-\(UUID().uuidString).loom")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - TemplateScenePatch

    s.test("TemplateScenePatch round-trips Codable with all fields set") {
        let patch = TemplateScenePatch(name: "Action template", nsfw: true, body: "She ran.")
        let data = try JSONEncoder().encode(patch)
        let decoded = try JSONDecoder().decode(TemplateScenePatch.self, from: data)
        try expectEqual(decoded, patch)
    }

    s.test("TemplateScenePatch round-trips Codable with sparse fields") {
        let patch = TemplateScenePatch(name: nil, nsfw: nil, body: "Body only.")
        let data = try JSONEncoder().encode(patch)
        let decoded = try JSONDecoder().decode(TemplateScenePatch.self, from: data)
        try expectEqual(decoded, patch)
    }

    s.test("TemplateScenePatch.apply replaces only non-nil fields") {
        let original = TemplateScene(
            id: UUID(),
            name: "Original",
            nsfw: false,
            createdAt: Date(timeIntervalSince1970: 1000),
            extraFrontmatter: [:],
            body: "Original body."
        )
        let patch = TemplateScenePatch(name: "Renamed", nsfw: nil, body: nil)
        let result = patch.apply(to: original)
        try expectEqual(result.name, "Renamed")
        try expectEqual(result.nsfw, false)
        try expectEqual(result.body, "Original body.")
        try expectEqual(result.id, original.id)
        try expectEqual(result.createdAt, original.createdAt)
    }

    // MARK: - SnapshotTemplateScene

    s.test("SnapshotTemplateScene projects TemplateScene fields with nil beatCount") {
        let scene = TemplateScene(
            id: UUID(),
            name: "scene",
            nsfw: true,
            createdAt: Date(timeIntervalSince1970: 2000),
            body: "Body text."
        )
        let snap = SnapshotTemplateScene(from: scene, beatCount: nil)
        try expectEqual(snap.id, scene.id)
        try expectEqual(snap.name, "scene")
        try expectEqual(snap.nsfw, true)
        try expectEqual(snap.createdAt, scene.createdAt)
        try expectEqual(snap.body, "Body text.")
        try expectEqual(snap.beatCount, nil)
    }

    s.test("SnapshotTemplateScene carries beatCount when provided") {
        let scene = TemplateScene(id: UUID(), name: "x", body: "")
        let snap = SnapshotTemplateScene(from: scene, beatCount: 9)
        try expectEqual(snap.beatCount, 9)
    }

    // MARK: - BibleWorkspaceSnapshot.build

    s.test("BibleWorkspaceSnapshot.build includes template scenes alongside references") {
        let project = Project(title: "Test")
        let template = SnapshotTemplateScene(
            from: TemplateScene(id: UUID(), name: "T", body: ""),
            beatCount: 5
        )
        let snap = BibleWorkspaceSnapshot.build(
            project: project,
            scenes: [:],
            references: [],
            templateScenes: [template],
            suggestionsQueue: LedgerSuggestionsQueue()
        )
        try expectEqual(snap.templateScenes.count, 1)
        try expectEqual(snap.templateScenes.first?.beatCount, 5)
    }

    s.test("BibleWorkspaceSnapshot.build with no template scenes emits an empty array") {
        let project = Project(title: "Test")
        let snap = BibleWorkspaceSnapshot.build(
            project: project,
            scenes: [:],
            references: [],
            templateScenes: [],
            suggestionsQueue: LedgerSuggestionsQueue()
        )
        try expectEqual(snap.templateScenes, [])
    }

    // MARK: - BibleWorkspaceIntent (new cases)

    s.test("BibleWorkspaceIntent.createTemplateScene round-trips Codable") {
        let intent = BibleWorkspaceIntent.createTemplateScene(name: "Action template")
        let data = try JSONEncoder().encode(intent)
        let decoded = try BibleWorkspaceBridge.decodeIntent(data)
        try expectEqual(decoded, intent)
    }

    s.test("BibleWorkspaceIntent.patchTemplateScene round-trips Codable") {
        let id = UUID()
        let intent = BibleWorkspaceIntent.patchTemplateScene(
            id: id,
            patch: TemplateScenePatch(name: "Renamed", nsfw: true)
        )
        let data = try JSONEncoder().encode(intent)
        let decoded = try BibleWorkspaceBridge.decodeIntent(data)
        try expectEqual(decoded, intent)
    }

    s.test("BibleWorkspaceIntent.deleteTemplateScene round-trips Codable") {
        let id = UUID()
        let intent = BibleWorkspaceIntent.deleteTemplateScene(id: id)
        let data = try JSONEncoder().encode(intent)
        let decoded = try BibleWorkspaceBridge.decodeIntent(data)
        try expectEqual(decoded, intent)
    }

    s.test("BibleWorkspaceIntent.extractTemplateScene round-trips Codable") {
        let id = UUID()
        let intent = BibleWorkspaceIntent.extractTemplateScene(id: id)
        let data = try JSONEncoder().encode(intent)
        let decoded = try BibleWorkspaceBridge.decodeIntent(data)
        try expectEqual(decoded, intent)
    }

    s.test("BibleWorkspaceIntent decodes wire-shape JSON for createTemplateScene") {
        let raw = #"{"kind":"createTemplateScene","name":"sample"}"#
        let intent = try BibleWorkspaceBridge.decodeIntent(raw.data(using: .utf8)!)
        try expectEqual(intent, .createTemplateScene(name: "sample"))
    }

    // MARK: - ProjectSession proxies

    s.test("ProjectSession.addTemplateScene is a no-op for in-memory sessions") {
        let session = ProjectSession(project: Project(title: "u"))
        let scene = session.addTemplateScene(name: "x")
        try expectEqual(scene, nil)
    }

    s.test("ProjectSession.addTemplateScene writes to disk and posts didChange") {
        let projectURL = makeTempProject()
        defer { try? FileManager.default.removeItem(at: projectURL) }
        let session = ProjectSession(project: Project(title: "p"), url: projectURL)

        var didChangeCount = 0
        let token = NotificationCenter.default.addObserver(
            forName: ProjectSession.didChangeNotification, object: session, queue: nil
        ) { _ in didChangeCount += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        guard let scene = session.addTemplateScene(name: "Hemingway") else {
            try expectFalse(true, "addTemplateScene returned nil for disk-backed session")
            return
        }
        try expectEqual(scene.name, "Hemingway")
        try expectEqual(didChangeCount, 1)
        let onDisk = try TemplateSceneStorage.loadTemplate(id: scene.id, in: projectURL)
        try expectEqual(onDisk.id, scene.id)
        try expectEqual(onDisk.name, "Hemingway")
    }

    s.test("ProjectSession.updateTemplateScene persists changes and posts didChange") {
        let projectURL = makeTempProject()
        defer { try? FileManager.default.removeItem(at: projectURL) }
        let session = ProjectSession(project: Project(title: "p"), url: projectURL)
        let scene = session.addTemplateScene(name: "orig")!

        var didChangeCount = 0
        let token = NotificationCenter.default.addObserver(
            forName: ProjectSession.didChangeNotification, object: session, queue: nil
        ) { _ in didChangeCount += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        var updated = scene
        updated.name = "renamed"
        updated.body = "fresh body"
        updated.nsfw = true
        session.updateTemplateScene(updated)

        try expectEqual(didChangeCount, 1)
        let onDisk = try TemplateSceneStorage.loadTemplate(id: scene.id, in: projectURL)
        try expectEqual(onDisk.name, "renamed")
        try expectEqual(onDisk.nsfw, true)
        try expectEqual(onDisk.body, "fresh body")
    }

    s.test("ProjectSession.deleteTemplateScene removes from disk and posts didChange") {
        let projectURL = makeTempProject()
        defer { try? FileManager.default.removeItem(at: projectURL) }
        let session = ProjectSession(project: Project(title: "p"), url: projectURL)
        let scene = session.addTemplateScene(name: "to-delete")!

        var didChangeCount = 0
        let token = NotificationCenter.default.addObserver(
            forName: ProjectSession.didChangeNotification, object: session, queue: nil
        ) { _ in didChangeCount += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        session.deleteTemplateScene(id: scene.id)
        try expectEqual(didChangeCount, 1)
        let ids = try TemplateSceneStorage.listTemplateIds(in: projectURL)
        try expectFalse(ids.contains(scene.id))
    }

    s.test("ProjectSession.listTemplateSceneSnapshots enumerates disk templates with beat counts") {
        let projectURL = makeTempProject()
        defer { try? FileManager.default.removeItem(at: projectURL) }
        let session = ProjectSession(project: Project(title: "p"), url: projectURL)
        let a = session.addTemplateScene(name: "a")!
        _ = session.addTemplateScene(name: "b")

        let skel = ExtractedSceneSkeleton(
            beats: [
                SceneBeat(index: 0, summary: "x", modality: .action, function: .setup, targetWords: 50, wordRangeStart: 0, wordRangeEnd: 50, beatTensionChange: 0),
                SceneBeat(index: 1, summary: "y", modality: .dialogue, function: .conflict, targetWords: 60, wordRangeStart: 50, wordRangeEnd: 110, beatTensionChange: 1),
            ],
            sourceCharacters: [], sourceSettingMarkers: []
        )
        try TemplateSceneStorage.saveSkeleton(skel, for: a.id, in: projectURL)

        let snaps = session.listTemplateSceneSnapshots()
        try expectEqual(snaps.count, 2)
        let aSnap = snaps.first(where: { $0.id == a.id })!
        try expectEqual(aSnap.beatCount, 2)
        let bSnap = snaps.first(where: { $0.name == "b" })!
        try expectEqual(bSnap.beatCount, nil)
    }

    s.test("ProjectSession.listTemplateSceneSnapshots returns [] for in-memory sessions") {
        let session = ProjectSession(project: Project(title: "u"))
        try expectEqual(session.listTemplateSceneSnapshots(), [])
    }

    return s
}

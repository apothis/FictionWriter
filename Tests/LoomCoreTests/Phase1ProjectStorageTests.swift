import Foundation
@testable import LoomCore

/// Sub-step 1.b — ProjectStorage smoke against a temp directory. End-to-end:
/// create a new project on disk, populate it with scenes + characters,
/// reload from disk, expect-equal.
///
/// All tests use a fresh temp directory under $TMPDIR; the directory is
/// cleaned up afterwards. The TestKit doesn't have a setup/teardown hook,
/// so each test does its own try/defer cleanup.
func phase1ProjectStorageTests() -> TestSuite {
    let s = TestSuite("Phase1ProjectStorage")

    s.test("createNewProject lays out the expected directory shape") {
        let dir = makeTempProjectURL()
        defer { try? FileManager.default.removeItem(at: dir) }

        let storage = ProjectStorage()
        _ = try storage.createNewProject(at: dir, title: "MyNovel", author: "K.A.")

        let fm = FileManager.default
        try expectTrue(fm.fileExists(atPath: dir.appendingPathComponent("project.json").path))
        try expectTrue(fm.fileExists(atPath: dir.appendingPathComponent("scenes").path))
        try expectTrue(fm.fileExists(atPath: dir.appendingPathComponent("generation-log").path))
    }

    s.test("save 3 scenes + 2 characters and reload yields identical project") {
        let dir = makeTempProjectURL()
        defer { try? FileManager.default.removeItem(at: dir) }

        let storage = ProjectStorage()
        var project = try storage.createNewProject(at: dir, title: "Three Scenes", author: nil)

        // Three scenes with distinct prose and metadata.
        var scenes: [Scene] = []
        for i in 1...3 {
            var scene = Scene.empty(id: UUID(), title: "Scene \(i)")
            scene.prose = "Scene \(i) prose paragraph one.\n\nParagraph two."
            scene.summary = "Scene \(i) summary."
            scene.conflict = "Conflict \(i)"
            scenes.append(scene)
            try storage.saveScene(scene, in: dir)
        }
        project.manuscript.orphanedSceneIds = scenes.map { $0.id }

        // Two characters.
        var mia = Character.empty(name: "Mia")
        mia.role = .protagonist
        mia.oneLine = "A reluctant doorkeeper."
        mia.description = "A woman in her thirties, skeptical, kind."
        var bob = Character.empty(name: "Bob")
        bob.role = .antagonist
        bob.oneLine = "The stranger."
        project.bible.characters = [mia, bob]

        try storage.saveProject(project, at: dir)

        // Reload and compare.
        let reloaded = try storage.loadProject(from: dir)
        try expectEqual(reloaded.project.title, project.title)
        try expectEqual(reloaded.project.bible.characters.count, 2)
        try expectEqual(reloaded.project.bible.characters[0].name, "Mia")
        try expectEqual(reloaded.project.bible.characters[1].name, "Bob")
        try expectEqual(reloaded.project.manuscript.orphanedSceneIds.count, 3)
        try expectEqual(reloaded.scenes.count, 3)
        for original in scenes {
            let loaded = try expectNotNil(reloaded.scenes[original.id])
            try expectEqual(loaded.title, original.title)
            try expectEqual(loaded.prose, original.prose)
            try expectEqual(loaded.summary, original.summary)
            try expectEqual(loaded.conflict, original.conflict)
        }
    }

    s.test("loading a project with no scenes/ directory still works") {
        // A project that's been newly created and has no scenes yet.
        let dir = makeTempProjectURL()
        defer { try? FileManager.default.removeItem(at: dir) }

        let storage = ProjectStorage()
        _ = try storage.createNewProject(at: dir, title: "Empty", author: nil)
        let reloaded = try storage.loadProject(from: dir)
        try expectEqual(reloaded.project.title, "Empty")
        try expectEqual(reloaded.scenes.count, 0)
    }

    return s
}

/// Builds a unique URL under $TMPDIR for a test's project directory. The
/// caller is responsible for cleanup; createNewProject creates the dir.
func makeTempProjectURL() -> URL {
    let name = "loom-test-\(UUID().uuidString).loom"
    return FileManager.default.temporaryDirectory.appendingPathComponent(name)
}

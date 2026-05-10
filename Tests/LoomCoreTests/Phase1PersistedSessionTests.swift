import Foundation
@testable import LoomCore

/// Sub-step 1.j.A — ProjectSession gains an on-disk URL + dirty flag +
/// debounced auto-save. These tests drive the *synchronous* save/load
/// path (we test the debounce timer separately by calling `flushSave`
/// directly).
func phase1PersistedSessionTests() -> TestSuite {
    let s = TestSuite("Phase1PersistedSession")

    s.test("new session has nil url and is not dirty") {
        let session = ProjectSession(project: Project(title: "X"))
        try expectNil(session.url)
        try expectFalse(session.isDirty)
    }

    s.test("addScene marks the session dirty") {
        let session = ProjectSession(project: Project(title: "X"))
        _ = session.addScene()
        try expectTrue(session.isDirty)
    }

    s.test("updateProse marks the session dirty (was previously silent)") {
        let session = ProjectSession(project: Project(title: "X"))
        let scene = session.addScene()
        session.markCleanForTest()    // simulate a save
        try expectFalse(session.isDirty)
        session.updateProse(id: scene.id, prose: "the wind picks up")
        try expectTrue(session.isDirty)
    }

    s.test("flushSave is a no-op when url is nil") {
        let session = ProjectSession(project: Project(title: "X"))
        _ = session.addScene()
        try session.flushSave()        // should not throw
        try expectTrue(session.isDirty, "no url means no save means still dirty")
    }

    s.test("flushSave persists project + scenes when url is set") {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("loom-test-\(UUID().uuidString).loom")
        defer { try? FileManager.default.removeItem(at: dir) }

        let storage = ProjectStorage()
        var project = try storage.createNewProject(at: dir, title: "ToSave", author: nil)
        let scene = Scene.empty(id: UUID(), title: "Scene 1")
        project.manuscript.orphanedSceneIds = [scene.id]

        let session = ProjectSession(project: project, scenes: [scene.id: scene])
        session.url = dir
        session.updateProse(id: scene.id, prose: "the wind picks up")
        // Edit the title too (mutates project.json):
        session.renameScene(id: scene.id, to: "Opening")
        try expectTrue(session.isDirty)

        try session.flushSave()
        try expectFalse(session.isDirty)

        // Round-trip: reload via ProjectStorage and verify.
        let loaded = try storage.loadProject(from: dir)
        try expectEqual(loaded.project.title, "ToSave")
        try expectEqual(loaded.scenes[scene.id]?.title, "Opening")
        try expectEqual(loaded.scenes[scene.id]?.prose, "the wind picks up")
    }

    s.test("AppState.createProject swaps in a fresh on-disk session") {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("loom-test-\(UUID().uuidString).loom")
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = AppSettingsStore(rootDir: FileManager.default.temporaryDirectory
            .appendingPathComponent("loom-appstate-\(UUID().uuidString)"))
        defer { try? FileManager.default.removeItem(at: store.settingsURL.deletingLastPathComponent()) }
        let appState = AppState(settingsStore: store)

        try appState.createProject(at: dir, title: "Fresh")
        try expectEqual(appState.currentSession.project.title, "Fresh")
        try expectEqual(appState.currentSession.url, dir)
        // Fresh project should have one starter scene.
        try expectEqual(appState.currentSession.project.manuscript.orphanedSceneIds.count, 1)
        try expectFalse(appState.currentSession.isDirty,
                        "freshly-created session should be clean (just-saved)")
    }

    s.test("AppState.openProject loads an existing on-disk project") {
        // First, persist one.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("loom-test-\(UUID().uuidString).loom")
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = ProjectStorage()
        var project = try storage.createNewProject(at: dir, title: "Existing", author: "K.")
        let scene = Scene(id: UUID(), title: "Foo", contentPath: nil, prose: "body text")
        project.manuscript.orphanedSceneIds = [scene.id]
        try storage.saveScene(scene, in: dir)
        try storage.saveProject(project, at: dir)

        let store = AppSettingsStore(rootDir: FileManager.default.temporaryDirectory
            .appendingPathComponent("loom-appstate-\(UUID().uuidString)"))
        defer { try? FileManager.default.removeItem(at: store.settingsURL.deletingLastPathComponent()) }
        let appState = AppState(settingsStore: store)

        try appState.openProject(at: dir)
        try expectEqual(appState.currentSession.project.title, "Existing")
        try expectEqual(appState.currentSession.scenes[scene.id]?.prose, "body text")
        try expectEqual(appState.currentSession.url, dir)
    }

    return s
}

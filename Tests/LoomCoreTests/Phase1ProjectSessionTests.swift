import Foundation
@testable import LoomCore

/// Sub-step 1.e — ProjectSession is the in-memory mutable wrapper around
/// a Project + its loaded Scenes. Sidebar/Editor/Inspector all read from
/// and write to the same session; mutations flip an underlying changed-
/// counter so observers can refresh without depending on Notification-
/// Center plumbing for the test surface.
func phase1ProjectSessionTests() -> TestSuite {
    let s = TestSuite("Phase1ProjectSession")

    s.test("addScene appends a new scene and returns it") {
        let session = ProjectSession(project: Project(title: "T"), scenes: [:])
        try expectEqual(session.project.manuscript.orphanedSceneIds.count, 0)
        let scene = session.addScene()
        try expectEqual(session.project.manuscript.orphanedSceneIds, [scene.id])
        try expectEqual(session.scenes[scene.id]?.id, scene.id)
        // Default title — caller can rename. "Scene 1" matches the "first
        // scene of an empty project" pattern from LOOM_DESIGN_LANGUAGE.md
        // §14.3 sidebar empty state.
        try expectEqual(scene.title, "Scene 1")
    }

    s.test("addScene assigns sequential default titles") {
        let session = ProjectSession(project: Project(title: "T"), scenes: [:])
        let s1 = session.addScene()
        let s2 = session.addScene()
        let s3 = session.addScene()
        try expectEqual(s1.title, "Scene 1")
        try expectEqual(s2.title, "Scene 2")
        try expectEqual(s3.title, "Scene 3")
    }

    s.test("renameScene updates the scene's title") {
        let session = ProjectSession(project: Project(title: "T"), scenes: [:])
        let scene = session.addScene()
        session.renameScene(id: scene.id, to: "The Opening")
        try expectEqual(session.scenes[scene.id]?.title, "The Opening")
    }

    s.test("deleteScene moves id from manuscript to trash; Scene struct preserved") {
        let session = ProjectSession(project: Project(title: "T"), scenes: [:])
        let scene = session.addScene()
        session.deleteScene(id: scene.id)
        try expectEqual(session.project.manuscript.orphanedSceneIds, [])
        try expectEqual(session.project.manuscript.trashedSceneIds, [scene.id])
        // Scene still in scenes map — undelete should be cheap.
        try expectNotNil(session.scenes[scene.id])
    }

    s.test("restoreFromTrash moves id back to the end of orphanedSceneIds") {
        let session = ProjectSession(project: Project(title: "T"), scenes: [:])
        let s1 = session.addScene()
        let s2 = session.addScene()
        session.deleteScene(id: s1.id)
        session.restoreFromTrash(id: s1.id)
        try expectEqual(session.project.manuscript.orphanedSceneIds, [s2.id, s1.id])
        try expectEqual(session.project.manuscript.trashedSceneIds, [])
    }

    s.test("reorderScenes moves an entry within orphanedSceneIds") {
        let session = ProjectSession(project: Project(title: "T"), scenes: [:])
        let a = session.addScene()
        let b = session.addScene()
        let c = session.addScene()
        session.reorderScenes(from: 0, to: 2)
        try expectEqual(session.project.manuscript.orphanedSceneIds, [b.id, c.id, a.id])
    }

    s.test("changeCounter increments on each mutation") {
        let session = ProjectSession(project: Project(title: "T"), scenes: [:])
        let initial = session.changeCounter
        _ = session.addScene()
        try expectGreaterThan(session.changeCounter, initial)
        let after = session.changeCounter
        session.reorderScenes(from: 0, to: 0)   // same-index reorder still bumps
        try expectGreaterThan(session.changeCounter, after)
    }

    return s
}

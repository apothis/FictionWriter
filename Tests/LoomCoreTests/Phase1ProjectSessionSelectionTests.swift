import Foundation
@testable import LoomCore

/// Sub-step 1.f — selection + prose mutation on ProjectSession. The
/// editor binds to the current selection; the sidebar drives it.
func phase1ProjectSessionSelectionTests() -> TestSuite {
    let s = TestSuite("Phase1ProjectSessionSelection")

    s.test("addScene auto-selects when nothing is selected") {
        let session = ProjectSession(project: Project(title: "T"))
        try expectNil(session.currentSceneId)
        let scene = session.addScene()
        try expectEqual(session.currentSceneId, scene.id)
    }

    s.test("addScene preserves existing selection") {
        let session = ProjectSession(project: Project(title: "T"))
        let s1 = session.addScene()
        _ = session.addScene()   // s2
        try expectEqual(session.currentSceneId, s1.id)
    }

    s.test("selectScene changes currentSceneId") {
        let session = ProjectSession(project: Project(title: "T"))
        let s1 = session.addScene()
        let s2 = session.addScene()
        session.selectScene(id: s2.id)
        try expectEqual(session.currentSceneId, s2.id)
        _ = s1
    }

    s.test("selectScene of unknown id is a no-op") {
        let session = ProjectSession(project: Project(title: "T"))
        let s1 = session.addScene()
        session.selectScene(id: UUID())
        try expectEqual(session.currentSceneId, s1.id)   // unchanged
    }

    s.test("selectScene posts selectionDidChangeNotification") {
        let session = ProjectSession(project: Project(title: "T"))
        _ = session.addScene()
        let s2 = session.addScene()
        var fired = false
        let obs = NotificationCenter.default.addObserver(
            forName: ProjectSession.selectionDidChangeNotification,
            object: session, queue: nil
        ) { _ in fired = true }
        defer { NotificationCenter.default.removeObserver(obs) }
        session.selectScene(id: s2.id)
        try expectTrue(fired)
    }

    s.test("updateProse modifies scene prose without changing selection") {
        let session = ProjectSession(project: Project(title: "T"))
        let s1 = session.addScene()
        session.updateProse(id: s1.id, prose: "the wind had been picking up")
        try expectEqual(session.scenes[s1.id]?.prose, "the wind had been picking up")
        try expectEqual(session.currentSceneId, s1.id)
    }

    s.test("deleteScene of the current selection clears currentSceneId") {
        let session = ProjectSession(project: Project(title: "T"))
        let s1 = session.addScene()
        session.deleteScene(id: s1.id)
        try expectNil(session.currentSceneId)
    }

    return s
}

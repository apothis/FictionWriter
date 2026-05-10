import Foundation
@testable import LoomCore

/// Sub-step 1.m — pure data-shape verification for "should the editor
/// show the empty-project placeholder vs the text view?". Per
/// LOOM_DESIGN_LANGUAGE.md §14.7, the empty state is shown when the
/// project has no scenes (or no current selection).
func phase1EmptyStateTests() -> TestSuite {
    let s = TestSuite("Phase1EmptyState")

    s.test("session with no scenes triggers empty state") {
        let session = ProjectSession(project: Project(title: "Empty"))
        try expectTrue(EmptyProjectState.shouldShow(in: session))
    }

    s.test("session with scenes and a current selection does NOT trigger empty state") {
        let session = ProjectSession(project: Project(title: "Has scenes"))
        _ = session.addScene()    // auto-selects
        try expectFalse(EmptyProjectState.shouldShow(in: session))
    }

    s.test("session with scenes but no current selection triggers empty state") {
        // After deleteScene of the only scene, currentSceneId becomes nil
        // even though trash has the scene.
        let session = ProjectSession(project: Project(title: "Cleared"))
        let scene = session.addScene()
        session.deleteScene(id: scene.id)
        try expectTrue(EmptyProjectState.shouldShow(in: session))
    }

    return s
}

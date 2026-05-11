import Foundation
import AppKit
@testable import LoomCore

/// Phase 3 §E — PlanViewController smoke. The collection view
/// rendering itself is honest UI; this suite pins the public
/// surface the standalone Plan window plugs into.
func phase3PlanViewControllerTests() -> TestSuite {
    let s = TestSuite("Phase3PlanViewController")

    s.test("controller mounts with cards reflecting the session's manuscript") {
        let session = ProjectSession(project: Project(title: "T"))
        let s1 = session.addScene(title: "Opener")
        session.updateProse(id: s1.id, prose: "Words go here.")

        let vc = PlanViewController(session: session)
        _ = vc.view
        try expectEqual(vc.cardsForTesting.count, 1)
        try expectEqual(vc.cardsForTesting[0].sceneId, s1.id)
        try expectEqual(vc.cardsForTesting[0].title, "Opener")
    }

    s.test("session mutations trigger reload — new scene shows up") {
        let session = ProjectSession(project: Project(title: "T"))
        let vc = PlanViewController(session: session)
        _ = vc.view
        try expectEqual(vc.cardsForTesting.count, 0)
        _ = session.addScene(title: "Late arrival")
        vc.reload()
        try expectEqual(vc.cardsForTesting.count, 1)
        try expectEqual(vc.cardsForTesting[0].title, "Late arrival")
    }

    s.test("simulateCardClick routes through onSceneClicked → session.selectScene") {
        let session = ProjectSession(project: Project(title: "T"))
        let s1 = session.addScene(title: "A")
        let s2 = session.addScene(title: "B")
        let vc = PlanViewController(session: session)
        _ = vc.view
        try expectEqual(session.currentSceneId, s1.id)
        vc.simulateCardClickForTesting(at: 1)
        try expectEqual(session.currentSceneId, s2.id)
    }

    return s
}

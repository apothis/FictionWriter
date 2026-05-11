import Foundation
@testable import LoomCore

/// Phase 3 §E — pure-data projection from a Project into the card
/// list the Plan view renders. Each card carries the scene id,
/// title, current word count, status, and the scene's summary
/// (empty when not set). Phase 3's first iteration ships a flat
/// card list in manuscript order; chapter/part grouping is a
/// follow-on polish (the layout already supports it via the
/// `groupTitle` field on each card).
func phase3PlanViewLayoutTests() -> TestSuite {
    let s = TestSuite("Phase3PlanViewLayout")

    s.test("empty project → no cards") {
        let project = Project.empty(title: "T")
        let layout = PlanViewLayout.build(for: project, scenes: [:])
        try expectEqual(layout.cards, [])
    }

    s.test("orphan scenes produce cards labelled 'Untitled'") {
        let session = ProjectSession(project: Project(title: "T"))
        let s1 = session.addScene(title: "Opening")
        session.updateProse(id: s1.id, prose: "one two three four five")

        let layout = PlanViewLayout.build(for: session.project, scenes: session.scenes)
        try expectEqual(layout.cards.count, 1)
        try expectEqual(layout.cards[0].sceneId, s1.id)
        try expectEqual(layout.cards[0].title, "Opening")
        try expectEqual(layout.cards[0].wordCount, 5)
        try expectEqual(layout.cards[0].groupTitle, "Untitled")
    }

    s.test("scenes inside Part/Chapter carry the chapter title as group label") {
        let session = ProjectSession(project: Project(title: "T"))
        let part = session.addPart(title: "Act 1")
        let chap = session.addChapter(title: "Opening Chapter", in: part.id)!
        let scene = session.addScene(title: "Scene 1")
        session.updateProse(id: scene.id, prose: "alpha beta gamma")
        session.placeScene(scene.id, in: chap.id)

        let layout = PlanViewLayout.build(for: session.project, scenes: session.scenes)
        try expectEqual(layout.cards.count, 1)
        try expectEqual(layout.cards[0].groupTitle, "Opening Chapter")
        try expectEqual(layout.cards[0].wordCount, 3)
    }

    s.test("cards appear in manuscript order: chapters first (in part order), then orphan") {
        let session = ProjectSession(project: Project(title: "T"))
        let part = session.addPart(title: "Act 1")
        let chap = session.addChapter(title: "Ch 1", in: part.id)!
        let placed = session.addScene(title: "Placed")
        let orphan = session.addScene(title: "Orphan")
        session.placeScene(placed.id, in: chap.id)

        let layout = PlanViewLayout.build(for: session.project, scenes: session.scenes)
        try expectEqual(layout.cards.map(\.sceneId), [placed.id, orphan.id])
    }

    s.test("cards reflect status + summary when set via session") {
        let session = ProjectSession(project: Project(title: "T"))
        let scene = session.addScene(title: "Scene 1")
        session.setSceneStatus(id: scene.id, to: .revised)
        session.setSceneSummary(id: scene.id, to: "Mia confronts the stranger.")

        let layout = PlanViewLayout.build(for: session.project, scenes: session.scenes)
        try expectEqual(layout.cards[0].status, .revised)
        try expectEqual(layout.cards[0].summary, "Mia confronts the stranger.")
    }

    s.test("cards carry the scene's targetWordCount when set, nil otherwise") {
        let session = ProjectSession(project: Project(title: "T"))
        let scene = session.addScene(title: "S1")
        var layout = PlanViewLayout.build(for: session.project, scenes: session.scenes)
        try expectNil(layout.cards[0].targetWordCount)
        session.setSceneTargetWordCount(id: scene.id, to: 1500)
        layout = PlanViewLayout.build(for: session.project, scenes: session.scenes)
        try expectEqual(layout.cards[0].targetWordCount, 1500)
    }

    return s
}

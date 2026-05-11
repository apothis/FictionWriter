import Foundation
@testable import LoomCore

/// Phase 3 §B — ProjectSession mutations for Parts and Chapters.
/// Mirrors the Phase 1 character-mutations contract: add/update/
/// delete + change-counter bump + a `moveScene(_:to:)` helper that
/// transfers a scene id between chapters (or to/from
/// orphanedSceneIds).
///
/// Tests-first per the always-TDD memory contract.
func phase3ManuscriptMutationsTests() -> TestSuite {
    let s = TestSuite("Phase3ManuscriptMutations")

    // MARK: Part CRUD

    s.test("addPart appends to manuscript.parts + bumps changeCounter") {
        let session = ProjectSession(project: Project(title: "T"))
        let before = session.changeCounter
        let part = session.addPart(title: "Act One")
        try expectEqual(session.project.manuscript.parts.count, 1)
        try expectEqual(session.project.manuscript.parts[0].id, part.id)
        try expectGreaterThan(session.changeCounter, before)
    }

    s.test("updatePart mutates in place by id, preserves order; unknown id is no-op") {
        let session = ProjectSession(project: Project(title: "T"))
        _ = session.addPart(title: "Act 1")
        let act2 = session.addPart(title: "Act 2")
        var updated = act2
        updated.title = "Act II"
        updated.notes = "Climbing tension."
        session.updatePart(updated)
        try expectEqual(session.project.manuscript.parts[1].title, "Act II")
        try expectEqual(session.project.manuscript.parts[1].notes, "Climbing tension.")

        let bogus = Part(title: "Stranger")
        session.updatePart(bogus)
        try expectEqual(session.project.manuscript.parts.count, 2)
    }

    s.test("deletePart removes the part; chapters inside it are dissolved back into orphanedSceneIds") {
        let session = ProjectSession(project: Project(title: "T"))
        let s1 = UUID(); let s2 = UUID()
        let chap = Chapter(title: "Ch1", sceneIds: [s1, s2])
        let part = Part(title: "Act 1", chapters: [chap])
        session.addPart(part)
        try expectEqual(session.project.manuscript.parts.count, 1)
        session.deletePart(id: part.id)
        try expectEqual(session.project.manuscript.parts.count, 0)
        // Scenes don't vanish — they fall back to orphaned so the user
        // can re-place them.
        try expectTrue(session.project.manuscript.orphanedSceneIds.contains(s1))
        try expectTrue(session.project.manuscript.orphanedSceneIds.contains(s2))
    }

    s.test("reorderParts moves a part to a new position") {
        let session = ProjectSession(project: Project(title: "T"))
        let a = session.addPart(title: "A")
        let b = session.addPart(title: "B")
        let c = session.addPart(title: "C")
        session.reorderParts(from: 0, to: 2)
        try expectEqual(session.project.manuscript.parts.map(\.id), [b.id, c.id, a.id])
    }

    // MARK: Chapter CRUD

    s.test("addChapter appends to its part + bumps changeCounter") {
        let session = ProjectSession(project: Project(title: "T"))
        let part = session.addPart(title: "Act 1")
        let before = session.changeCounter
        let chap = try expectNotNil(session.addChapter(title: "Ch 1", in: part.id))
        try expectEqual(session.project.manuscript.parts[0].chapters.count, 1)
        try expectEqual(session.project.manuscript.parts[0].chapters[0].id, chap.id)
        try expectGreaterThan(session.changeCounter, before)
    }

    s.test("addChapter in a stale partId is a no-op (returns nil)") {
        let session = ProjectSession(project: Project(title: "T"))
        let chap = session.addChapter(title: "Ghost", in: UUID())
        try expectNil(chap)
    }

    s.test("updateChapter mutates in place by id across any part") {
        let session = ProjectSession(project: Project(title: "T"))
        let part = session.addPart(title: "Act 1")
        let chap = session.addChapter(title: "Ch 1", in: part.id)!
        var updated = chap
        updated.title = "Chapter One"
        updated.summary = "Mia opens the door."
        session.updateChapter(updated)
        try expectEqual(session.project.manuscript.parts[0].chapters[0].title, "Chapter One")
        try expectEqual(session.project.manuscript.parts[0].chapters[0].summary, "Mia opens the door.")
    }

    s.test("deleteChapter removes the chapter; its scenes go to orphanedSceneIds") {
        let session = ProjectSession(project: Project(title: "T"))
        let part = session.addPart(title: "Act 1")
        let s1 = UUID(); let s2 = UUID()
        let chap = Chapter(title: "Ch 1", sceneIds: [s1, s2])
        session.addChapter(chap, in: part.id)
        session.deleteChapter(id: chap.id)
        try expectEqual(session.project.manuscript.parts[0].chapters.count, 0)
        try expectTrue(session.project.manuscript.orphanedSceneIds.contains(s1))
        try expectTrue(session.project.manuscript.orphanedSceneIds.contains(s2))
    }

    // MARK: Scene movement

    s.test("placeScene(_:in:) moves a scene from orphan into a chapter") {
        let session = ProjectSession(project: Project(title: "T"))
        let scene = session.addScene(title: "S1")
        let part = session.addPart(title: "Act 1")
        let chap = session.addChapter(title: "Ch 1", in: part.id)!

        try expectTrue(session.project.manuscript.orphanedSceneIds.contains(scene.id))
        session.placeScene(scene.id, in: chap.id)
        try expectFalse(session.project.manuscript.orphanedSceneIds.contains(scene.id))
        try expectTrue(session.project.manuscript.parts[0].chapters[0].sceneIds.contains(scene.id))
    }

    s.test("placeScene moving between two chapters removes from origin + adds to destination") {
        let session = ProjectSession(project: Project(title: "T"))
        let part = session.addPart(title: "Act 1")
        let chA = session.addChapter(title: "A", in: part.id)!
        let chB = session.addChapter(title: "B", in: part.id)!
        let sceneId = UUID()
        // Manually seed scene into chapter A.
        var aMutable = chA
        aMutable.sceneIds = [sceneId]
        session.updateChapter(aMutable)

        session.placeScene(sceneId, in: chB.id)
        try expectFalse(session.project.manuscript.parts[0].chapters[0].sceneIds.contains(sceneId))
        try expectTrue(session.project.manuscript.parts[0].chapters[1].sceneIds.contains(sceneId))
    }

    s.test("unplaceScene(_:) returns a scene to orphanedSceneIds") {
        let session = ProjectSession(project: Project(title: "T"))
        let part = session.addPart(title: "Act 1")
        let chap = session.addChapter(title: "Ch 1", in: part.id)!
        let sceneId = UUID()
        var c = chap
        c.sceneIds = [sceneId]
        session.updateChapter(c)

        session.unplaceScene(sceneId)
        try expectFalse(session.project.manuscript.parts[0].chapters[0].sceneIds.contains(sceneId))
        try expectTrue(session.project.manuscript.orphanedSceneIds.contains(sceneId))
    }

    return s
}

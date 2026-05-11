import Foundation
@testable import LoomCore

/// Phase 3 §C — pure-data helpers to walk the manuscript tree.
/// Returns scenes in manuscript order (across Parts/Chapters then
/// orphan scenes), and folds word counts up the hierarchy. The
/// Plan-view rendering surface and the Phase 2 #11 mention
/// sparkline both consume these.
func phase3ManuscriptWalkTests() -> TestSuite {
    let s = TestSuite("Phase3ManuscriptWalk")

    s.test("flatSceneIds on an empty manuscript returns []") {
        let m = Manuscript.empty
        try expectEqual(m.flatSceneIds, [])
    }

    s.test("flatSceneIds walks Parts → Chapters → Scenes in order, then orphan") {
        let s1 = UUID(); let s2 = UUID(); let s3 = UUID(); let s4 = UUID(); let s5 = UUID()
        let chap1 = Chapter(title: "Ch1", sceneIds: [s1, s2])
        let chap2 = Chapter(title: "Ch2", sceneIds: [s3])
        let part1 = Part(title: "Act 1", chapters: [chap1, chap2])
        let part2 = Part(title: "Act 2", chapters: [Chapter(title: "Ch3", sceneIds: [s4])])
        var m = Manuscript(parts: [part1, part2])
        m.orphanedSceneIds = [s5]
        try expectEqual(m.flatSceneIds, [s1, s2, s3, s4, s5])
    }

    s.test("ManuscriptWordCount: chapter sums scene-word-counts in its sceneIds") {
        let session = ProjectSession(project: Project(title: "T"))
        let part = session.addPart(title: "Act 1")
        let chap = session.addChapter(title: "Ch 1", in: part.id)!
        let s1 = session.addScene(title: "A")
        let s2 = session.addScene(title: "B")
        session.updateProse(id: s1.id, prose: "one two three four five")        // 5 words
        session.updateProse(id: s2.id, prose: "alpha beta gamma")                // 3 words
        session.placeScene(s1.id, in: chap.id)
        session.placeScene(s2.id, in: chap.id)

        let counts = ManuscriptWordCount.compute(for: session.project, scenes: session.scenes)
        try expectEqual(counts.totalWords, 8)
        try expectEqual(counts.byChapterId[chap.id], 8)
        try expectEqual(counts.byPartId[part.id], 8)
    }

    s.test("ManuscriptWordCount: orphan scenes count toward project total but not toward Part/Chapter") {
        let session = ProjectSession(project: Project(title: "T"))
        let part = session.addPart(title: "Act 1")
        let chap = session.addChapter(title: "Ch 1", in: part.id)!
        let placed = session.addScene(title: "Placed")
        let orphan = session.addScene(title: "Orphan")
        session.updateProse(id: placed.id, prose: "one two three")          // 3
        session.updateProse(id: orphan.id, prose: "alpha beta gamma delta") // 4
        session.placeScene(placed.id, in: chap.id)
        // `orphan` stays in orphanedSceneIds.

        let counts = ManuscriptWordCount.compute(for: session.project, scenes: session.scenes)
        try expectEqual(counts.totalWords, 7)
        try expectEqual(counts.byPartId[part.id], 3)
        try expectEqual(counts.byChapterId[chap.id], 3)
    }

    s.test("ManuscriptWordCount: empty manuscript has zero everywhere") {
        let session = ProjectSession(project: Project(title: "T"))
        let counts = ManuscriptWordCount.compute(for: session.project, scenes: session.scenes)
        try expectEqual(counts.totalWords, 0)
        try expectEqual(counts.byPartId, [:])
        try expectEqual(counts.byChapterId, [:])
    }

    return s
}

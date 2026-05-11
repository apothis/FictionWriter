import Foundation
@testable import LoomCore

/// Phase 3 §A — schema for Part + Chapter on Manuscript. Per
/// LOOM_DATA_MODEL.md §2: a Project's manuscript holds an ordered
/// list of Parts; each Part holds an ordered list of Chapters; each
/// Chapter holds an ordered list of scene ids. Phase 1's
/// `orphanedSceneIds` stays as the implicit "untitled chapter" slot
/// so existing projects load without forced restructuring.
///
/// Tests-first per the always-TDD memory contract.
func phase3ManuscriptHierarchyTests() -> TestSuite {
    let s = TestSuite("Phase3ManuscriptHierarchy")

    s.test("Manuscript defaults to no parts + no orphan scenes") {
        let m = Manuscript.empty
        try expectEqual(m.parts, [])
        try expectEqual(m.orphanedSceneIds, [])
    }

    s.test("Part round-trips with full populated fields") {
        let chap = Chapter(
            title: "Chapter 1",
            sceneIds: [UUID(), UUID()],
            summary: "Mia opens the door.",
            summaryDirty: false,
            targetWordCount: 3000,
            notes: "Opening beat — set the tone."
        )
        let part = Part(
            title: "Act One",
            chapters: [chap],
            notes: "Rising action."
        )
        let data = try JSONEncoder.loomPretty.encode(part)
        let back = try JSONDecoder.loom.decode(Part.self, from: data)
        try expectEqual(back, part)
    }

    s.test("Manuscript with parts + chapters + orphan scenes round-trips through Project") {
        var p = Project.empty(title: "T")
        let chap = Chapter(title: "Ch 1", sceneIds: [UUID()])
        let part = Part(title: "Act 1", chapters: [chap])
        p.manuscript.parts = [part]
        p.manuscript.orphanedSceneIds = [UUID()]

        let data = try JSONEncoder.loomPretty.encode(p)
        let back = try JSONDecoder.loom.decode(Project.self, from: data)
        try expectEqual(back.manuscript.parts.count, 1)
        try expectEqual(back.manuscript.parts[0].title, "Act 1")
        try expectEqual(back.manuscript.parts[0].chapters.count, 1)
        try expectEqual(back.manuscript.orphanedSceneIds.count, 1)
        try expectEqual(back, p)
    }

    s.test("Chapter defaults: empty sceneIds, summary nil, dirty false, no target") {
        let c = Chapter(title: "X")
        try expectEqual(c.sceneIds, [])
        try expectNil(c.summary)
        try expectFalse(c.summaryDirty)
        try expectNil(c.targetWordCount)
        try expectEqual(c.notes, "")
    }

    s.test("Phase 1/2 Manuscript JSON (no parts field) decodes with parts == [] — §9.4 risk #1") {
        // The Phase 1 shape only carried partIds + orphanedSceneIds +
        // trashedSceneIds. A bundle on disk in that shape must load
        // cleanly with the new `parts` array defaulting to empty.
        let json = """
        {
          "partIds": [],
          "orphanedSceneIds": ["\(UUID().uuidString)"],
          "trashedSceneIds": []
        }
        """
        let decoded = try JSONDecoder.loom.decode(Manuscript.self, from: Data(json.utf8))
        try expectEqual(decoded.parts, [])
        try expectEqual(decoded.orphanedSceneIds.count, 1)
    }

    s.test("Phase 1/2 Chapter-less Project still functions: orphanedSceneIds is the manuscript") {
        // Phase 3's hierarchy is opt-in. A Phase 1/2 project whose
        // user never structured it should keep working: all scenes
        // stay in orphanedSceneIds, no Parts forced.
        var p = Project.empty(title: "Unstructured")
        let s1 = UUID(), s2 = UUID(), s3 = UUID()
        p.manuscript.orphanedSceneIds = [s1, s2, s3]
        try expectEqual(p.manuscript.parts, [])
        try expectEqual(p.manuscript.orphanedSceneIds, [s1, s2, s3])
    }

    return s
}

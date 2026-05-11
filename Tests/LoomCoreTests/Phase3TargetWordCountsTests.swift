import Foundation
@testable import LoomCore

/// Phase 3 §F — target word counts at scene / chapter / project
/// levels. Scene + Chapter already carry `targetWordCount: Int?`
/// in their schema (LOOM_DATA_MODEL.md §2); this work item adds
/// the project-level target on `ProjectSettings` and the session
/// setters that wire the editing surfaces.
///
/// Tests-first per the always-TDD memory contract.
func phase3TargetWordCountsTests() -> TestSuite {
    let s = TestSuite("Phase3TargetWordCounts")

    s.test("ProjectSettings.targetWordCount defaults to nil") {
        let p = Project.empty(title: "X")
        try expectNil(p.settings.targetWordCount)
    }

    s.test("ProjectSettings.targetWordCount round-trips") {
        var p = Project.empty(title: "X")
        p.settings.targetWordCount = 80_000
        let data = try JSONEncoder.loomPretty.encode(p)
        let back = try JSONDecoder.loom.decode(Project.self, from: data)
        try expectEqual(back.settings.targetWordCount, 80_000)
    }

    s.test("Phase 1 project.json without targetWordCount decodes with nil — §9.4 risk #1") {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "title": "Pre-Phase-3",
          "createdAt": "2026-04-01T00:00:00Z",
          "schemaVersion": 1,
          "kind": "originalFiction",
          "settings": {
            "contextBudgetTokens": 8192,
            "generationDefaults": \(targetWordEncoded(GenerationDefaults.phase1Defaults)),
            "authorsNote": "",
            "authorsNoteDepthLines": 4,
            "memory": "",
            "instructTemplate": "auto"
          },
          "manuscript": { "partIds": [], "orphanedSceneIds": [] },
          "bible": { "characters": [] }
        }
        """
        let decoded = try JSONDecoder.loom.decode(Project.self, from: Data(json.utf8))
        try expectNil(decoded.settings.targetWordCount)
    }

    // MARK: Session setters

    s.test("session.setProjectTargetWordCount updates settings + marks dirty") {
        let session = ProjectSession(project: Project(title: "T"))
        try expectFalse(session.isDirty)
        session.setProjectTargetWordCount(50_000)
        try expectEqual(session.project.settings.targetWordCount, 50_000)
        try expectTrue(session.isDirty)
    }

    s.test("session.setProjectTargetWordCount(nil) clears the target") {
        let session = ProjectSession(project: Project(title: "T"))
        session.setProjectTargetWordCount(50_000)
        session.setProjectTargetWordCount(nil)
        try expectNil(session.project.settings.targetWordCount)
    }

    s.test("session.setChapterTargetWordCount updates the chapter in place") {
        let session = ProjectSession(project: Project(title: "T"))
        let part = session.addPart(title: "Act 1")
        let chap = session.addChapter(title: "Ch 1", in: part.id)!
        session.setChapterTargetWordCount(id: chap.id, to: 4_000)
        try expectEqual(session.project.manuscript.parts[0].chapters[0].targetWordCount, 4_000)
        session.setChapterTargetWordCount(id: chap.id, to: nil)
        try expectNil(session.project.manuscript.parts[0].chapters[0].targetWordCount)
    }

    s.test("session.setChapterTargetWordCount on a stale id is a no-op") {
        let session = ProjectSession(project: Project(title: "T"))
        let part = session.addPart(title: "Act 1")
        _ = session.addChapter(title: "Ch 1", in: part.id)
        session.setChapterTargetWordCount(id: UUID(), to: 1_000)
        try expectNil(session.project.manuscript.parts[0].chapters[0].targetWordCount)
    }

    s.test("session.setSceneTargetWordCount updates the scene") {
        let session = ProjectSession(project: Project(title: "T"))
        let scene = session.addScene(title: "S1")
        session.setSceneTargetWordCount(id: scene.id, to: 1_500)
        try expectEqual(session.scenes[scene.id]?.targetWordCount, 1_500)
        session.setSceneTargetWordCount(id: scene.id, to: nil)
        try expectNil(session.scenes[scene.id]?.targetWordCount)
    }

    return s
}

private func targetWordEncoded<T: Encodable>(_ value: T) -> String {
    let data = try! JSONEncoder().encode(value)
    return String(data: data, encoding: .utf8)!
}

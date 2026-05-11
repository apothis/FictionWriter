import Foundation
@testable import LoomCore

/// Phase 2 #6 (schema layer) — POVStyle + NarrativeTense on
/// ProjectSettings. Per HANDOFF §9.1 row 6, the Settings window
/// grows pill-pickers for POV / Tense / Direction / Vocabulary /
/// Explicitness; the last three already live on WritingDirection
/// (#1). POV and Tense are net-new project-level fields that the
/// pill-pickers will wire to.
///
/// Tests-first per the always-TDD memory contract. Defaults pick
/// the most-common-for-mainstream-fiction choices (third-person
/// limited / past tense) so a fresh project reads as "the typical
/// novel" without the user having to configure.
func phase2NarrativeStyleTests() -> TestSuite {
    let s = TestSuite("Phase2NarrativeStyle")

    s.test("POVStyle covers the four standard narrative POVs") {
        let expected: Set<POVStyle> = [
            .firstPerson,
            .secondPerson,
            .thirdPersonLimited,
            .thirdPersonOmniscient,
        ]
        try expectEqual(Set(POVStyle.allCases), expected)
    }

    s.test("NarrativeTense covers past + present") {
        let expected: Set<NarrativeTense> = [.past, .present]
        try expectEqual(Set(NarrativeTense.allCases), expected)
    }

    s.test("ProjectSettings defaults: pov = .thirdPersonLimited, tense = .past") {
        let p = Project.empty(title: "X")
        try expectEqual(p.settings.pov, .thirdPersonLimited)
        try expectEqual(p.settings.tense, .past)
    }

    s.test("ProjectSettings round-trips pov + tense through Project") {
        var p = Project.empty(title: "X")
        p.settings.pov = .firstPerson
        p.settings.tense = .present
        let data = try JSONEncoder.loomPretty.encode(p)
        let back = try JSONDecoder.loom.decode(Project.self, from: data)
        try expectEqual(back.settings.pov, .firstPerson)
        try expectEqual(back.settings.tense, .present)
        try expectEqual(back, p)
    }

    s.test("Phase 1 project.json without pov/tense decodes with defaults — §9.4 risk #1") {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "title": "Pre-Phase-2 Bundle",
          "createdAt": "2026-04-01T00:00:00Z",
          "schemaVersion": 1,
          "kind": "originalFiction",
          "settings": {
            "contextBudgetTokens": 8192,
            "generationDefaults": \(narrativeStyleEncoded(GenerationDefaults.phase1Defaults)),
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
        try expectEqual(decoded.settings.pov, .thirdPersonLimited)
        try expectEqual(decoded.settings.tense, .past)
    }

    // MARK: ProjectSession setters

    s.test("session.setPOV updates settings and marks dirty") {
        let session = ProjectSession(project: Project(title: "T"))
        try expectFalse(session.isDirty)
        session.setPOV(.firstPerson)
        try expectEqual(session.project.settings.pov, .firstPerson)
        try expectTrue(session.isDirty)
    }

    s.test("session.setTense updates settings and marks dirty") {
        let session = ProjectSession(project: Project(title: "T"))
        session.setTense(.present)
        try expectEqual(session.project.settings.tense, .present)
        try expectTrue(session.isDirty)
    }

    s.test("session.setWritingDirectionKind/Register/Explicitness mutate WritingDirection in place") {
        let session = ProjectSession(project: Project(title: "T"))
        try expectEqual(session.project.settings.writingDirection.kind, .literary)
        session.setWritingDirectionKind(.erotica)
        session.setWritingDirectionRegister(.earthy)
        session.setWritingDirectionExplicitness(.graphic)
        try expectEqual(session.project.settings.writingDirection.kind, .erotica)
        try expectEqual(session.project.settings.writingDirection.register, .earthy)
        try expectEqual(session.project.settings.writingDirection.explicitnessLevel, .graphic)
        try expectTrue(session.isDirty)
    }

    return s
}

private func narrativeStyleEncoded<T: Encodable>(_ value: T) -> String {
    let data = try! JSONEncoder().encode(value)
    return String(data: data, encoding: .utf8)!
}

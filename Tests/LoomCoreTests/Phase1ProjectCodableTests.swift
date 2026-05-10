import Foundation
@testable import LoomCore

/// Sub-step 1.b — Codable round-trip for Project, ProjectSettings,
/// GenerationDefaults, InstructTemplate, ProjectKind. Pure data tests:
/// build a Project in memory, JSONEncode + JSONDecode, expect-equal.
///
/// The point isn't to exercise every field — Equatable conformance does
/// that — but to pin the *defaults*, the *enum cases*, and the *forward-
/// compat behaviour* (decodeIfPresent, schemaVersion).
func phase1ProjectCodableTests() -> TestSuite {
    let s = TestSuite("Phase1ProjectCodable")

    s.test("default Project round-trips") {
        let p = Project.empty(title: "MyNovel")
        let data = try JSONEncoder.loomPretty.encode(p)
        let decoded = try JSONDecoder.loom.decode(Project.self, from: data)
        try expectEqual(decoded, p)
    }

    s.test("populated Project round-trips") {
        var p = Project.empty(title: "MyNovel", author: "K. Appleyard")
        let s1 = UUID()
        let s2 = UUID()
        let s3 = UUID()
        p.manuscript.orphanedSceneIds = [s1, s2, s3]
        let mia = Character.empty(name: "Mia")
        let bob = Character.empty(name: "Bob")
        p.bible.characters = [mia, bob]

        let data = try JSONEncoder.loomPretty.encode(p)
        let decoded = try JSONDecoder.loom.decode(Project.self, from: data)
        try expectEqual(decoded, p)
    }

    s.test("ProjectSettings defaults match the Phase 1 contract") {
        let p = Project.empty(title: "X")
        try expectEqual(p.settings.contextBudgetTokens, 8192)
        try expectEqual(p.settings.authorsNoteDepthLines, 4)
        try expectEqual(p.settings.instructTemplate, .auto)
        try expectEqual(p.settings.authorsNote, "")
        try expectEqual(p.settings.memory, "")
    }

    s.test("InstructTemplate encodes all cases") {
        for t in InstructTemplate.allCases {
            let data = try JSONEncoder().encode(t)
            let back = try JSONDecoder().decode(InstructTemplate.self, from: data)
            try expectEqual(back, t)
        }
    }

    s.test("GenerationDefaults round-trips") {
        let d = GenerationDefaults.phase1Defaults
        let data = try JSONEncoder().encode(d)
        let back = try JSONDecoder().decode(GenerationDefaults.self, from: data)
        try expectEqual(back, d)
    }

    s.test("schemaVersion is 1 in newly-created Project") {
        let p = Project.empty(title: "X")
        try expectEqual(p.schemaVersion, 1)
    }

    s.test("ProjectKind defaults to .originalFiction") {
        let p = Project.empty(title: "X")
        try expectEqual(p.kind, .originalFiction)
    }

    return s
}

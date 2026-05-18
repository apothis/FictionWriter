import Foundation
@testable import LoomCore

/// P2c — anti-slop phrase list. A curated, editable per-project list
/// (data resource only — transport wiring deferred).
func phase4AntiSlopTests() -> TestSuite {
    let s = TestSuite("Phase4AntiSlop")

    s.test("the default list is non-empty and has no duplicates or blanks") {
        let p = AntiSlopDefaults.phrases
        try expectGreaterThan(p.count, 20)
        try expectEqual(Set(p).count, p.count)
        for phrase in p {
            try expectFalse(phrase.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    s.test("the default list includes the canonical slop phrases") {
        let p = AntiSlopDefaults.phrases
        try expectTrue(p.contains("voice barely above a whisper"))
        try expectTrue(p.contains("a testament to"))
    }

    s.test("antiSlopPhrases defaults to empty in the schema — forward-load safety") {
        try expectEqual(ProjectSettings.defaults.antiSlopPhrases, [])
    }

    s.test("antiSlopPhrases round-trips through Project Codable") {
        var p = Project(title: "X")
        p.settings.antiSlopPhrases = ["one phrase", "another phrase"]
        let data = try JSONEncoder.loomPretty.encode(p)
        let back = try JSONDecoder.loom.decode(Project.self, from: data)
        try expectEqual(back.settings.antiSlopPhrases, ["one phrase", "another phrase"])
    }

    s.test("a pre-P2c project.json without antiSlopPhrases decodes to empty") {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "title": "Old",
          "createdAt": "2026-04-01T00:00:00Z",
          "schemaVersion": 1,
          "kind": "originalFiction",
          "settings": { "contextBudgetTokens": 8192 },
          "manuscript": { "partIds": [], "orphanedSceneIds": [] },
          "bible": { "characters": [] }
        }
        """
        let decoded = try JSONDecoder.loom.decode(Project.self, from: Data(json.utf8))
        try expectEqual(decoded.settings.antiSlopPhrases, [])
    }

    s.test("GenerateRequest carries banned strings, defaulting to empty") {
        let bare = GenerateRequest(prompt: "p", params: SamplerParams(), maxContextLength: 8192)
        try expectEqual(bare.bannedStrings, [])
        let banned = GenerateRequest(
            prompt: "p", params: SamplerParams(), maxContextLength: 8192,
            bannedStrings: ["a testament to", "her core"]
        )
        try expectEqual(banned.bannedStrings, ["a testament to", "her core"])
    }

    s.test("createNewProject seeds the curated anti-slop list") {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("antislop-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let project = try ProjectStorage().createNewProject(at: dir, title: "Seeded", author: nil)
        try expectEqual(project.settings.antiSlopPhrases, AntiSlopDefaults.phrases)
    }

    return s
}

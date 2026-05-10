import Foundation
@testable import LoomCore

/// Phase 2 #1 — WritingDirection schema on ProjectSettings.
/// Per HANDOFF §9.1 + LOOM_NSFW.md §3.1: `kind` / `register` /
/// `explicitnessLevel` / `themes[]` / `pacing` / `fadeToBlackPolicy`.
///
/// Pure-data tests-first (HANDOFF §10.6 TDD posture). Covers:
///   1. Default values match the §9.4-locked defaults
///      (literary / literary / fadeToBlack).
///   2. All five DirectionKind cases round-trip (NSFW.md §3.1).
///   3. Enum cases for VocabularyRegister, ExplicitnessLevel,
///      PacingProfile, FTBPolicy round-trip.
///   4. A Phase 1 project.json bundle (no writingDirection field)
///      decodes cleanly with the defaults populated — the
///      lazy-versioning posture enforced for §9.4 risk #1.
///   5. The full schema round-trips with populated themes.
func phase2WritingDirectionTests() -> TestSuite {
    let s = TestSuite("Phase2WritingDirection")

    s.test("default WritingDirection matches HANDOFF §9.4 (literary / literary / fadeToBlack)") {
        let d = WritingDirection.defaults
        try expectEqual(d.kind, .literary)
        try expectEqual(d.register, .literary)
        try expectEqual(d.explicitnessLevel, .fadeToBlack)
        try expectEqual(d.themes, [])
        try expectEqual(d.pacing, .balanced)
        try expectEqual(d.fadeToBlackPolicy, .modelDecides)
    }

    s.test("DirectionKind covers all five cases per LOOM_NSFW.md §3.1") {
        // The schema must distinguish .porn from .erotica because
        // HANDOFF §9.3 commits depth-2 A/N + longer Continue defaults
        // to the .porn case specifically.
        let expected: Set<DirectionKind> = [.literary, .mainstream, .romance, .erotica, .porn]
        try expectEqual(Set(DirectionKind.allCases), expected)
    }

    s.test("VocabularyRegister covers all five cases") {
        let expected: Set<VocabularyRegister> = [.clinical, .literary, .earthy, .crude, .mixed]
        try expectEqual(Set(VocabularyRegister.allCases), expected)
    }

    s.test("ExplicitnessLevel covers all five cases") {
        let expected: Set<ExplicitnessLevel> = [.fadeToBlack, .suggestive, .onScreen, .graphic, .extreme]
        try expectEqual(Set(ExplicitnessLevel.allCases), expected)
    }

    s.test("PacingProfile covers all four cases") {
        let expected: Set<PacingProfile> = [.fastPlot, .balanced, .slowExplicit, .explicitForeground]
        try expectEqual(Set(PacingProfile.allCases), expected)
    }

    s.test("FTBPolicy covers all three cases") {
        let expected: Set<FTBPolicy> = [.never, .userChoice, .modelDecides]
        try expectEqual(Set(FTBPolicy.allCases), expected)
    }

    s.test("WritingDirection round-trips with populated themes") {
        let theme = Theme(
            name: "Established practice",
            description: "Two long-married characters; intimacy as daily fabric.",
            alwaysOn: true,
            styleExemplarRefs: []
        )
        let d = WritingDirection(
            kind: .erotica,
            register: .earthy,
            explicitnessLevel: .graphic,
            themes: [theme],
            pacing: .slowExplicit,
            fadeToBlackPolicy: .never
        )
        let data = try JSONEncoder.loomPretty.encode(d)
        let back = try JSONDecoder.loom.decode(WritingDirection.self, from: data)
        try expectEqual(back, d)
    }

    s.test("ProjectSettings exposes writingDirection wired to defaults") {
        let p = Project.empty(title: "X")
        try expectEqual(p.settings.writingDirection, WritingDirection.defaults)
    }

    s.test("ProjectSettings.writingDirection round-trips through Project") {
        var p = Project.empty(title: "X")
        p.settings.writingDirection = WritingDirection(
            kind: .porn,
            register: .crude,
            explicitnessLevel: .extreme,
            themes: [],
            pacing: .explicitForeground,
            fadeToBlackPolicy: .never
        )
        let data = try JSONEncoder.loomPretty.encode(p)
        let back = try JSONDecoder.loom.decode(Project.self, from: data)
        try expectEqual(back.settings.writingDirection.kind, .porn)
        try expectEqual(back.settings.writingDirection.explicitnessLevel, .extreme)
        try expectEqual(back, p)
    }

    s.test("Phase 1 project.json without writingDirection decodes with defaults — §9.4 risk #1") {
        // Hand-rolled JSON simulating a Phase 1 bundle on disk: settings
        // block has none of the Phase 2 fields. Lazy-versioning must
        // populate WritingDirection.defaults so the load doesn't throw
        // and the user opens a sensible project state.
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "title": "Pre-Phase-2 Bundle",
          "createdAt": "2026-04-01T00:00:00Z",
          "schemaVersion": 1,
          "kind": "originalFiction",
          "settings": {
            "contextBudgetTokens": 8192,
            "generationDefaults": \(encodedJSON(GenerationDefaults.phase1Defaults)),
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
        try expectEqual(decoded.settings.writingDirection, WritingDirection.defaults)
        try expectEqual(decoded.title, "Pre-Phase-2 Bundle")
    }

    return s
}

private func encodedJSON<T: Encodable>(_ value: T) -> String {
    let data = try! JSONEncoder().encode(value)
    return String(data: data, encoding: .utf8)!
}

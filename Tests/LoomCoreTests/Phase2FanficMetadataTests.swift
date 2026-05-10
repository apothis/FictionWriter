import Foundation
@testable import LoomCore

/// Phase 2 #2 — FanficMetadata schema on Project.
/// Per HANDOFF §9.1 + LOOM_FANFIC.md §3.1: fandoms, ATTG, ratings,
/// warnings, category, ships, primaryCharacters, tropes, aus.
/// Populated only when kind == .fanfic; nil otherwise.
///
/// Phase 2 ships the schema. UI to populate this is Phase 5.b-c
/// (canon brief storage + fanfic project type). The schema lands
/// now so existing projects (and the schema migration itself) only
/// take one hit; see HANDOFF §9 preamble.
func phase2FanficMetadataTests() -> TestSuite {
    let s = TestSuite("Phase2FanficMetadata")

    s.test("new originalFiction Project has nil fanficMetadata") {
        let p = Project.empty(title: "Original")
        try expectNil(p.fanficMetadata)
    }

    s.test("AO3Rating covers the four canonical AO3 rating cases") {
        let expected: Set<AO3Rating> = [.general, .teen, .mature, .explicit]
        try expectEqual(Set(AO3Rating.allCases), expected)
    }

    s.test("AO3Warning covers the canonical AO3 warning cases") {
        let expected: Set<AO3Warning> = [
            .noArchiveWarningsApply,
            .graphicDepictionsOfViolence,
            .majorCharacterDeath,
            .rapeNonCon,
            .underage,
            .chooseNotToWarn,
        ]
        try expectEqual(Set(AO3Warning.allCases), expected)
    }

    s.test("AO3Category covers the canonical AO3 category cases") {
        let expected: Set<AO3Category> = [.gen, .ff, .fm, .mm, .multi, .other]
        try expectEqual(Set(AO3Category.allCases), expected)
    }

    s.test("ShipKind + ShipDynamic enums match LOOM_FANFIC.md §3.1") {
        let kinds: Set<ShipKind> = [.romantic, .sexual, .platonic, .familial, .antagonistic, .friendship]
        try expectEqual(Set(ShipKind.allCases), kinds)

        let dynamics: Set<ShipDynamic> = [
            .established, .slowBurn, .mutualPining,
            .enemiesToLovers, .friendsToLovers, .fakeMarriage,
            .soulmates, .otherWorks,
        ]
        try expectEqual(Set(ShipDynamic.allCases), dynamics)
    }

    s.test("default FanficMetadata round-trips") {
        let m = FanficMetadata()
        let data = try JSONEncoder.loomPretty.encode(m)
        let back = try JSONDecoder.loom.decode(FanficMetadata.self, from: data)
        try expectEqual(back, m)
    }

    s.test("populated FanficMetadata round-trips") {
        let fandom = Fandom(
            name: "Marvel Cinematic Universe",
            canonicalName: "Marvel Cinematic Universe",
            aliases: ["MCU"],
            fandomWikiURL: nil,
            canonReferences: []
        )
        let charA = UUID()
        let charB = UUID()
        let ship = Ship(
            characters: [charA, charB],
            kind: .romantic,
            canonicalForm: "Stucky",
            dynamic: .slowBurn,
            notes: ""
        )
        let trope = Trope(
            name: "Slow Burn",
            aliases: [],
            category: .pacing,
            description: "Defer romantic resolution.",
            typicalLength: TropeLength(minChapters: 20, maxChapters: 100, minWords: 50_000, maxWords: 300_000),
            generationHints: TropeHints(
                pacingNote: "emphasise gradual escalation",
                avoidances: ["I love you before midpoint"],
                beatPatterns: []
            )
        )
        let au = AU(
            name: "Coffeeshop AU",
            description: "Modern setting; one character barista.",
            setting: "Brooklyn 2026",
            canonRetained: ["names", "relationships"],
            canonChanged: ["no powers"],
            addedElements: ["espresso machines"]
        )
        let m = FanficMetadata(
            fandoms: [fandom],
            attg: ATTG(
                author: "kjorth",
                title: "Coffee Run",
                fandom: "Marvel Cinematic Universe",
                tags: ["coffeeshop AU", "slow burn"],
                rating: "Mature",
                genre: "drama, romance",
                category: "M/M",
                relationship: "Steve Rogers/Bucky Barnes",
                storyStage: 2
            ),
            rating: .mature,
            warnings: [.noArchiveWarningsApply],
            category: .mm,
            ships: [ship],
            primaryCharacters: [charA, charB],
            tropes: [trope],
            aus: [au]
        )
        let data = try JSONEncoder.loomPretty.encode(m)
        let back = try JSONDecoder.loom.decode(FanficMetadata.self, from: data)
        try expectEqual(back, m)
    }

    s.test("Project with kind == .fanfic carries non-nil fanficMetadata through round-trip") {
        var p = Project.empty(title: "Stucky Slow Burn")
        p.kind = .fanfic
        p.fanficMetadata = FanficMetadata(rating: .explicit, category: .mm)
        let data = try JSONEncoder.loomPretty.encode(p)
        let back = try JSONDecoder.loom.decode(Project.self, from: data)
        try expectEqual(back.kind, .fanfic)
        try expectEqual(back.fanficMetadata?.rating, .explicit)
        try expectEqual(back.fanficMetadata?.category, .mm)
        try expectEqual(back, p)
    }

    s.test("Phase 1 project.json without fanficMetadata field decodes with nil — §9.4 risk #1") {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "title": "Pre-Phase-2 Bundle",
          "createdAt": "2026-04-01T00:00:00Z",
          "schemaVersion": 1,
          "kind": "originalFiction",
          "settings": \(encodedJSONForFanficTest(ProjectSettings.defaults)),
          "manuscript": { "partIds": [], "orphanedSceneIds": [] },
          "bible": { "characters": [] }
        }
        """
        let decoded = try JSONDecoder.loom.decode(Project.self, from: Data(json.utf8))
        try expectNil(decoded.fanficMetadata)
    }

    return s
}

private func encodedJSONForFanficTest<T: Encodable>(_ value: T) -> String {
    let data = try! JSONEncoder().encode(value)
    return String(data: data, encoding: .utf8)!
}

import Foundation
@testable import LoomCore

/// Phase 2 #5 — Setting + Object Bible entities. Same shape pattern as
/// Character (per HANDOFF §9.1 row 5: "Schema reuses #3's pattern;
/// small marginal cost"). Schema source of truth: LOOM_DATA_MODEL.md
/// §3.2 (Setting) and §3.3 (Object).
///
/// Pure-data tests-first: round-trip the new types, confirm Bible
/// gains additive fields, and pin the Phase 1 forward-load behaviour
/// (existing project.json without settings/objects arrays decodes
/// cleanly).
func phase2BibleEntitiesTests() -> TestSuite {
    let s = TestSuite("Phase2BibleEntities")

    s.test("default Bible exposes empty settings + objects arrays") {
        let b = Bible.empty
        try expectEqual(b.settings, [])
        try expectEqual(b.objects, [])
    }

    s.test("Setting round-trips with full populated fields") {
        let obj1 = UUID()
        let obj2 = UUID()
        let setting = Setting(
            name: "221B Baker Street",
            aliases: ["the flat", "the rooms upstairs"],
            description: "Cluttered Victorian sitting-room on the first floor.",
            sensoryNotes: "Pipe tobacco; wood polish; coal fire; rain against glass.",
            significantObjectIds: [obj1, obj2],
            notes: "Holmes's home of record; many scenes anchor here."
        )
        let data = try JSONEncoder.loomPretty.encode(setting)
        let back = try JSONDecoder.loom.decode(Setting.self, from: data)
        try expectEqual(back, setting)
    }

    s.test("BibleObject round-trips with full populated fields") {
        let obj = BibleObject(
            name: "Persian Slipper",
            aliases: ["the slipper", "Holmes's slipper"],
            description: "A Persian-style slipper kept on the mantel.",
            significance: "Holmes stores his pipe tobacco in the toe.",
            notes: "Recurring detail; signals settled domesticity in opening scenes."
        )
        let data = try JSONEncoder.loomPretty.encode(obj)
        let back = try JSONDecoder.loom.decode(BibleObject.self, from: data)
        try expectEqual(back, obj)
    }

    s.test("Bible carries Setting + Object arrays through Project round-trip") {
        var p = Project.empty(title: "X")
        let s1 = Setting(name: "221B Baker Street")
        let o1 = BibleObject(name: "Persian Slipper")
        p.bible.settings = [s1]
        p.bible.objects = [o1]
        let data = try JSONEncoder.loomPretty.encode(p)
        let back = try JSONDecoder.loom.decode(Project.self, from: data)
        try expectEqual(back.bible.settings, [s1])
        try expectEqual(back.bible.objects, [o1])
        try expectEqual(back, p)
    }

    s.test("Phase 1 Bible JSON without settings/objects keys decodes with empty arrays — §9.4 risk #1") {
        // Old shape: only `characters` field was present on Bible.
        let json = """
        {
          "characters": []
        }
        """
        let decoded = try JSONDecoder.loom.decode(Bible.self, from: Data(json.utf8))
        try expectEqual(decoded.settings, [])
        try expectEqual(decoded.objects, [])
        try expectEqual(decoded.characters, [])
    }

    return s
}

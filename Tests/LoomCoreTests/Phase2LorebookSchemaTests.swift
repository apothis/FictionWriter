import Foundation
@testable import LoomCore

/// Phase 2 #8 (schema layer) — Lorebook entries on Bible.
/// Per HANDOFF §9.1 row 8 + LOOM_DATA_MODEL.md §3.6, with Phase 2
/// additions for the Phase 4 Sphiratrioth pattern: group / weight /
/// sticky. UI for editing these lands Phase 4 when Sphiratrioth's
/// active-scenario lorebook entries become a first-class affordance;
/// schema lands now so prompt-injection plumbing works alongside #7.
func phase2LorebookSchemaTests() -> TestSuite {
    let s = TestSuite("Phase2LorebookSchema")

    s.test("default Bible exposes empty lorebook") {
        let b = Bible.empty
        try expectEqual(b.lorebook, [])
    }

    s.test("LorebookActivationMode covers constant / keyed / vectorised") {
        try expectEqual(
            Set(LorebookActivationMode.allCases),
            [.constant, .keyed, .vectorised]
        )
    }

    s.test("LorebookPositionMode covers top / bottom / depthN") {
        try expectEqual(
            Set(LorebookPositionMode.allCases),
            [.top, .bottom, .depthN]
        )
    }

    s.test("default LorebookEntry pins the Phase 2 #8-required defaults") {
        let entry = LorebookEntry(name: "Rule")
        try expectEqual(entry.activationMode, .keyed)
        try expectEqual(entry.keys, [])
        try expectEqual(entry.secondaryKeys, [])
        try expectTrue(entry.enabled)
        try expectEqual(entry.priority, 0)
        try expectEqual(entry.positionMode, .top)
        try expectNil(entry.depth)
        // Phase 2 #8 additions:
        try expectNil(entry.group)
        try expectNil(entry.weight)
        try expectFalse(entry.sticky)
    }

    s.test("populated LorebookEntry round-trips through JSON") {
        let entry = LorebookEntry(
            name: "Magic system",
            content: "Casting drains stamina proportional to spell tier.",
            activationMode: .keyed,
            keys: ["cast", "casting", "spell"],
            secondaryKeys: ["mage"],
            enabled: true,
            priority: 10,
            positionMode: .depthN,
            depth: 3,
            maxRecentScenesScanned: 5,
            group: "magic_rules",
            weight: 80,
            sticky: true
        )
        let data = try JSONEncoder.loomPretty.encode(entry)
        let back = try JSONDecoder.loom.decode(LorebookEntry.self, from: data)
        try expectEqual(back, entry)
    }

    s.test("Lorebook entries round-trip through Bible/Project") {
        var p = Project.empty(title: "T")
        p.bible.lorebook = [
            LorebookEntry(name: "A", keys: ["alpha"]),
            LorebookEntry(name: "B", activationMode: .constant),
        ]
        let data = try JSONEncoder.loomPretty.encode(p)
        let back = try JSONDecoder.loom.decode(Project.self, from: data)
        try expectEqual(back.bible.lorebook.count, 2)
        try expectEqual(back, p)
    }

    s.test("Phase 1 Bible JSON without lorebook decodes with empty array — §9.4 risk #1") {
        let json = """
        {
          "characters": []
        }
        """
        let decoded = try JSONDecoder.loom.decode(Bible.self, from: Data(json.utf8))
        try expectEqual(decoded.lorebook, [])
    }

    s.test("Phase 1 LorebookEntry JSON without group/weight/sticky decodes with defaults — §9.4 risk #1") {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "name": "Old Entry",
          "content": "Some lore",
          "activationMode": "keyed",
          "keys": ["x"],
          "secondaryKeys": [],
          "enabled": true,
          "priority": 0,
          "positionMode": "top",
          "maxRecentScenesScanned": 3
        }
        """
        let decoded = try JSONDecoder.loom.decode(LorebookEntry.self, from: Data(json.utf8))
        try expectNil(decoded.group)
        try expectNil(decoded.weight)
        try expectFalse(decoded.sticky)
        try expectEqual(decoded.name, "Old Entry")
    }

    // MARK: Session CRUD

    s.test("addLorebookEntry appends + bumps changeCounter") {
        let session = ProjectSession(project: Project(title: "T"))
        let initial = session.changeCounter
        let e = session.addLorebookEntry(name: "Rule")
        try expectEqual(session.project.bible.lorebook.count, 1)
        try expectEqual(session.project.bible.lorebook[0].id, e.id)
        try expectGreaterThan(session.changeCounter, initial)
    }

    s.test("updateLorebookEntry mutates in place; unknown id is no-op") {
        let session = ProjectSession(project: Project(title: "T"))
        let e = session.addLorebookEntry(name: "Rule")
        var updated = e
        updated.content = "Detailed lore."
        updated.sticky = true
        session.updateLorebookEntry(updated)
        try expectEqual(session.project.bible.lorebook[0].content, "Detailed lore.")
        try expectTrue(session.project.bible.lorebook[0].sticky)

        let bogus = LorebookEntry(name: "Stranger")   // different id
        session.updateLorebookEntry(bogus)
        try expectEqual(session.project.bible.lorebook.count, 1)
        try expectEqual(session.project.bible.lorebook[0].id, e.id)
    }

    s.test("deleteLorebookEntry removes; absent id is no-op") {
        let session = ProjectSession(project: Project(title: "T"))
        let a = session.addLorebookEntry(name: "A")
        let b = session.addLorebookEntry(name: "B")
        session.deleteLorebookEntry(id: a.id)
        try expectEqual(session.project.bible.lorebook.count, 1)
        try expectEqual(session.project.bible.lorebook[0].id, b.id)
        session.deleteLorebookEntry(id: UUID())
        try expectEqual(session.project.bible.lorebook.count, 1)
    }

    return s
}

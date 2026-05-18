import Foundation
@testable import LoomCore

/// P2b — Dynamic Sheet. A structured per-relationship spec (roles,
/// wants, soft/hard limits, safeword, arc) fed to the writer model as
/// a generation constraint, modelled on the kink community's
/// negotiation-sheet convention. Lives on the Bible alongside the
/// lorebook.
func phase4DynamicSheetTests() -> TestSuite {
    let s = TestSuite("Phase4DynamicSheet")

    s.test("DynamicSheet round-trips through Codable") {
        let d = DynamicSheet(
            name: "Mira & Cole",
            participantIds: [UUID(), UUID()],
            roles: "Mira leads; Cole yields.",
            wants: "Both want the power gap made explicit.",
            softLimits: "No humiliation in front of others.",
            hardLimits: "No permanent marks.",
            safeword: "\"winter\"",
            arc: "Starts as a game; becomes the relationship's core.",
            alwaysOn: true,
            enabled: true
        )
        let data = try JSONEncoder.loomPretty.encode(d)
        let back = try JSONDecoder.loom.decode(DynamicSheet.self, from: data)
        try expectEqual(back, d)
    }

    s.test("Bible without dynamics decodes to an empty list") {
        let json = """
        { "characters": [], "settings": [], "objects": [], "lorebook": [] }
        """
        let bible = try JSONDecoder.loom.decode(Bible.self, from: Data(json.utf8))
        try expectEqual(bible.dynamics, [])
    }

    s.test("alwaysOn dynamics activate unconditionally; disabled never activate") {
        let on = DynamicSheet(name: "On", alwaysOn: true, enabled: true)
        let off = DynamicSheet(name: "Off", alwaysOn: true, enabled: false)
        let active = DynamicSheetInjector.activated(
            dynamics: [on, off], characters: [], recentProse: "nothing here"
        )
        try expectEqual(active.map(\.name), ["On"])
    }

    s.test("a keyed dynamic activates when a participant name appears in recent prose") {
        let mira = Character(name: "Mira")
        let d = DynamicSheet(
            name: "The dynamic", participantIds: [mira.id], alwaysOn: false, enabled: true
        )
        let hit = DynamicSheetInjector.activated(
            dynamics: [d], characters: [mira], recentProse: "Mira closed the door."
        )
        try expectEqual(hit.count, 1)
        let miss = DynamicSheetInjector.activated(
            dynamics: [d], characters: [mira], recentProse: "Nobody was there."
        )
        try expectTrue(miss.isEmpty)
    }

    s.test("render omits empty fields and labels the populated ones") {
        let d = DynamicSheet(name: "X", roles: "A leads.", safeword: "\"red\"")
        let block = DynamicSheetPrompt.render([d])
        try expectTrue(block.contains("A leads."))
        try expectTrue(block.contains("\"red\""))
        try expectFalse(block.lowercased().contains("hard limits"))
    }

    s.test("an alwaysOn dynamic reaches the assembled prompt") {
        var project = Project(title: "T")
        project.bible.dynamics = [
            DynamicSheet(name: "Mira & Cole", roles: "Mira leads.", alwaysOn: true, enabled: true)
        ]
        let scene = Scene.empty(id: UUID(), title: "S")
        project.manuscript.orphanedSceneIds = [scene.id]
        var sceneCopy = scene
        sceneCopy.prose = "Some prose."
        let context = PromptContext(
            mode: .continueProse,
            project: project,
            scenes: [scene.id: sceneCopy],
            currentSceneId: scene.id,
            cursorOffset: sceneCopy.prose.count,
            selectionRange: nil,
            modelName: nil,
            contextBudgetTokens: 8192,
            replyBudgetTokens: 1024
        )
        let result = PromptBuilder.build(context)
        try expectTrue(result.fullPrompt.contains("Mira leads."))
        try expectNotNil(result.chiclets.first { $0.sourceKind == .dynamicSheet })
    }

    return s
}

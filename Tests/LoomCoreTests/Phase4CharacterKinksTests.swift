import Foundation
@testable import LoomCore

/// Per-character kink profile — free-form names with a stance
/// (into / curious / soft or hard limit), rendered into the
/// character's bible entry.
func phase4CharacterKinksTests() -> TestSuite {
    let s = TestSuite("Phase4CharacterKinks")

    s.test("Character.kinks defaults empty and round-trips") {
        try expectEqual(Character.empty(name: "Mira").kinks, [])
        var c = Character.empty(name: "Mira")
        c.kinks = [
            CharacterKink(name: "restraint", stance: .into),
            CharacterKink(name: "pain", stance: .hardLimit),
        ]
        let data = try JSONEncoder.loomPretty.encode(c)
        let back = try JSONDecoder.loom.decode(Character.self, from: data)
        try expectEqual(back.kinks, c.kinks)
    }

    s.test("a pre-feature character decodes with no kinks") {
        let json = """
        { "id": "\(UUID().uuidString)", "name": "Old", "aliases": [],
          "role": "supporting", "relationships": [], "knownFactsBySceneId": [],
          "customFields": [], "injectionMode": "constant" }
        """
        try expectEqual(
            try JSONDecoder.loom.decode(Character.self, from: Data(json.utf8)).kinks, []
        )
    }

    s.test("a CharacterKink without a stance decodes as .into") {
        let kink = try JSONDecoder.loom.decode(
            CharacterKink.self, from: Data("{\"name\":\"praise\"}".utf8)
        )
        try expectEqual(kink.stance, .into)
    }

    s.test("KinkStance covers the four cases") {
        try expectEqual(
            Set(KinkStance.allCases), [.into, .curious, .softLimit, .hardLimit]
        )
    }

    s.test("a character's kinks render into the bible block, grouped by stance") {
        var project = Project(title: "T")
        var mira = Character(name: "Mira")
        mira.kinks = [
            CharacterKink(name: "restraint", stance: .into),
            CharacterKink(name: "praise", stance: .into),
            CharacterKink(name: "knife play", stance: .hardLimit),
        ]
        project.bible.characters = [mira]
        let scene = Scene.empty(id: UUID(), title: "S")
        project.manuscript.orphanedSceneIds = [scene.id]
        var sceneCopy = scene
        sceneCopy.prose = "Some prose."
        let result = PromptBuilder.build(PromptContext(
            mode: .continueProse, project: project,
            scenes: [scene.id: sceneCopy], currentSceneId: scene.id,
            cursorOffset: sceneCopy.prose.count, selectionRange: nil,
            modelName: nil, contextBudgetTokens: 8192, replyBudgetTokens: 1024
        ))
        try expectTrue(result.systemBlock.contains("Kinks — into restraint, praise"))
        try expectTrue(result.systemBlock.contains("hard limit knife play"))
    }

    s.test("a character with no kinks adds no kink line") {
        var project = Project(title: "T")
        project.bible.characters = [Character(name: "Plain")]
        let scene = Scene.empty(id: UUID(), title: "S")
        project.manuscript.orphanedSceneIds = [scene.id]
        var sceneCopy = scene
        sceneCopy.prose = "Some prose."
        let result = PromptBuilder.build(PromptContext(
            mode: .continueProse, project: project,
            scenes: [scene.id: sceneCopy], currentSceneId: scene.id,
            cursorOffset: sceneCopy.prose.count, selectionRange: nil,
            modelName: nil, contextBudgetTokens: 8192, replyBudgetTokens: 1024
        ))
        try expectFalse(result.systemBlock.contains("Kinks —"))
    }

    return s
}

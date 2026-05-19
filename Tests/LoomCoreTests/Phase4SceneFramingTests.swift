import Foundation
@testable import LoomCore

/// P2a — per-scene framing block. A free-text scenario field on Scene,
/// injected near the cursor at generation time (unlike `notes`, which
/// is private). Schema-migration coverage includes the forward-load
/// case per the repo TDD posture.
func phase4SceneFramingTests() -> TestSuite {
    let s = TestSuite("Phase4SceneFraming")

    s.test("framing defaults to empty") {
        try expectEqual(Scene.empty(title: "S").framing, "")
    }

    s.test("framing round-trips through Codable") {
        var scene = Scene.empty(title: "S")
        scene.framing = "D/s dynamic; she is testing his limits; high tension."
        let data = try JSONEncoder.loomPretty.encode(scene)
        let back = try JSONDecoder.loom.decode(Scene.self, from: data)
        try expectEqual(back.framing, scene.framing)
    }

    s.test("a pre-P2a scene JSON without framing decodes to empty") {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "title": "Old Scene",
          "status": "draft",
          "summary": "",
          "summaryDirty": false,
          "contentPath": "scenes/\(id.uuidString).md",
          "notes": "",
          "generatedSpans": [],
          "snapshots": [],
          "extraFrontmatter": {}
        }
        """
        let scene = try JSONDecoder.loom.decode(Scene.self, from: Data(json.utf8))
        try expectEqual(scene.framing, "")
    }

    s.test("framing round-trips through SceneFile frontmatter, newlines intact") {
        var scene = Scene.empty(title: "S")
        scene.framing = "Line one of the framing.\nLine two: what's at stake."
        scene.prose = "The body."
        let encoded = SceneFile.encode(scene)
        let back = try SceneFile.decode(encoded, contentPath: scene.contentPath)
        try expectEqual(back.framing, scene.framing)
    }

    s.test("a SceneFile without a framing line decodes to empty framing") {
        let id = UUID()
        let text = """
        ---
        id: "\(id.uuidString)"
        title: "No Framing"
        status: "draft"
        summaryDirty: false
        ---

        Body text.
        """
        let scene = try SceneFile.decode(text, contentPath: "scenes/\(id.uuidString).md")
        try expectEqual(scene.framing, "")
    }

    s.test("explicitnessLevel override defaults to nil and round-trips") {
        try expectNil(Scene.empty(title: "S").explicitnessLevel)
        var scene = Scene.empty(title: "S")
        scene.explicitnessLevel = .extreme
        let data = try JSONEncoder.loomPretty.encode(scene)
        try expectEqual(
            try JSONDecoder.loom.decode(Scene.self, from: data).explicitnessLevel, .extreme
        )
    }

    s.test("explicitnessLevel round-trips through SceneFile frontmatter") {
        var scene = Scene.empty(title: "S")
        scene.explicitnessLevel = .graphic
        scene.prose = "Body."
        let back = try SceneFile.decode(
            SceneFile.encode(scene), contentPath: scene.contentPath
        )
        try expectEqual(back.explicitnessLevel, .graphic)
    }

    s.test("undressedCharacterIds defaults empty and round-trips via SceneFile") {
        try expectEqual(Scene.empty(title: "S").undressedCharacterIds, [])
        let a = UUID(), b = UUID()
        var scene = Scene.empty(title: "S")
        scene.undressedCharacterIds = [a, b]
        scene.prose = "Body."
        let back = try SceneFile.decode(
            SceneFile.encode(scene), contentPath: scene.contentPath
        )
        try expectEqual(back.undressedCharacterIds, [a, b])
    }

    s.test("a SceneFile without an explicitnessLevel line decodes to nil") {
        let id = UUID()
        let text = "---\nid: \"\(id.uuidString)\"\ntitle: \"X\"\nstatus: \"draft\"\nsummaryDirty: false\n---\n\nBody."
        try expectNil(
            try SceneFile.decode(text, contentPath: "scenes/\(id.uuidString).md").explicitnessLevel
        )
    }

    s.test("framing is injected into the prompt for the current scene") {
        var project = Project(title: "T")
        let scene = Scene.empty(id: UUID(), title: "S")
        project.manuscript.orphanedSceneIds = [scene.id]
        var sceneCopy = scene
        sceneCopy.framing = "Hate-sex dynamic; neither will say it first."
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
        try expectTrue(result.userBlock.contains("Hate-sex dynamic"))
        try expectNotNil(result.chiclets.first { $0.sourceKind == .sceneFraming })
    }

    s.test("an empty framing adds no layer") {
        var project = Project(title: "T")
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
        try expectNil(result.chiclets.first { $0.sourceKind == .sceneFraming })
    }

    return s
}

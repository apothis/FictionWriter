import Foundation
@testable import LoomCore

/// Phase 2 #7 (integration) — PromptBuilder consumes BibleInjector so
/// the assembled prompt reflects per-entity injection mode.
///
/// - .constant entities continue to appear in the above-cache
///   bibleConstant layer (current Phase 1 behaviour preserved).
/// - .keyed entities only appear when their name/alias is in recent
///   prose, and they go in a separate below-cache bibleKeyed layer.
func phase2BibleKeyedIntegrationTests() -> TestSuite {
    let s = TestSuite("Phase2BibleKeyedIntegration")

    s.test("keyed character whose name is in recent prose appears in the assembled prompt") {
        var project = Project(title: "T")
        var bob = Character(name: "Bob")
        bob.description = "Bob is the antagonist's quiet older brother."
        bob.injectionMode = .keyed
        project.bible.characters = [bob]

        let scene = Scene.empty(id: UUID(), title: "S1")
        let prose = "Bob walked through the door."
        let ctx = makeKeyedContext(project: project, scene: scene, prose: prose)
        let result = PromptBuilder.build(ctx)

        let combined = result.systemBlock + result.userBlock
        try expectTrue(combined.contains("Bob is the antagonist's quiet older brother."),
                       "Keyed entity description should appear when its name is in recent prose")
    }

    s.test("keyed character whose name is NOT in recent prose is omitted from the assembled prompt") {
        var project = Project(title: "T")
        var ghost = Character(name: "Ghost")
        ghost.description = "Ghost is a hidden character whose presence is a spoiler."
        ghost.injectionMode = .keyed
        project.bible.characters = [ghost]

        let scene = Scene.empty(id: UUID(), title: "S1")
        let prose = "The detective walked into the room."
        let ctx = makeKeyedContext(project: project, scene: scene, prose: prose)
        let result = PromptBuilder.build(ctx)

        let combined = result.systemBlock + result.userBlock
        try expectFalse(combined.contains("Ghost is a hidden character"),
                        "Keyed entity description must NOT appear when its name is absent from recent prose")
    }

    s.test("constant character is included regardless of recent prose content") {
        var project = Project(title: "T")
        var mia = Character(name: "Mia")
        mia.description = "Mia is the protagonist."
        mia.injectionMode = .constant
        project.bible.characters = [mia]

        let scene = Scene.empty(id: UUID(), title: "S1")
        let prose = "Nothing relevant here at all."
        let ctx = makeKeyedContext(project: project, scene: scene, prose: prose)
        let result = PromptBuilder.build(ctx)

        let combined = result.systemBlock + result.userBlock
        try expectTrue(combined.contains("Mia"),
                       "Constant entity should always be included")
    }

    s.test("keyed entity injection produces a bibleKeyed chiclet, constant produces bibleConstant") {
        var project = Project(title: "T")
        var mia = Character(name: "Mia")
        mia.injectionMode = .constant
        var bob = Character(name: "Bob")
        bob.injectionMode = .keyed
        project.bible.characters = [mia, bob]

        let scene = Scene.empty(id: UUID(), title: "S1")
        let ctx = makeKeyedContext(project: project, scene: scene, prose: "Bob looked up.")
        let result = PromptBuilder.build(ctx)
        let kinds = Set(result.chiclets.map(\.sourceKind))
        try expectTrue(kinds.contains(.bibleConstant), "Constant entities should produce a bibleConstant chiclet")
        try expectTrue(kinds.contains(.bibleKeyed), "Keyed-and-activated entities should produce a bibleKeyed chiclet")
    }

    s.test("no bibleKeyed chiclet when no keyed entities activate this turn") {
        var project = Project(title: "T")
        var mia = Character(name: "Mia")
        mia.injectionMode = .constant
        var ghost = Character(name: "Ghost")
        ghost.injectionMode = .keyed
        project.bible.characters = [mia, ghost]

        let scene = Scene.empty(id: UUID(), title: "S1")
        let ctx = makeKeyedContext(project: project, scene: scene, prose: "No keyed name here.")
        let result = PromptBuilder.build(ctx)
        let hasKeyed = result.chiclets.contains { $0.sourceKind == .bibleKeyed }
        try expectFalse(hasKeyed, "No keyed activations → no bibleKeyed chiclet")
    }

    s.test("keyed-Setting activation works (alias match)") {
        var project = Project(title: "T")
        var baker = Setting(name: "221B Baker Street")
        baker.aliases = ["the flat"]
        baker.description = "Holmes's cluttered Victorian sitting-room."
        baker.injectionMode = .keyed
        project.bible.settings = [baker]

        let scene = Scene.empty(id: UUID(), title: "S1")
        let ctx = makeKeyedContext(
            project: project, scene: scene,
            prose: "He shut the door of the flat and lit his pipe."
        )
        let result = PromptBuilder.build(ctx)
        let combined = result.systemBlock + result.userBlock
        try expectTrue(combined.contains("Holmes's cluttered Victorian sitting-room."),
                       "Keyed Setting should activate on alias match")
    }

    return s
}

private func makeKeyedContext(project: Project, scene: Scene, prose: String) -> PromptContext {
    var sceneCopy = scene
    sceneCopy.prose = prose
    var p = project
    if !p.manuscript.orphanedSceneIds.contains(scene.id) {
        p.manuscript.orphanedSceneIds.append(scene.id)
    }
    return PromptContext(
        mode: .continueProse,
        project: p,
        scenes: [scene.id: sceneCopy],
        currentSceneId: scene.id,
        cursorOffset: prose.count,
        selectionRange: nil,
        modelName: nil,
        contextBudgetTokens: 8192,
        replyBudgetTokens: 1024
    )
}

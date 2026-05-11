import Foundation
@testable import LoomCore

/// Phase 2 #8 (integration) — Lorebook entries participate in
/// prompt assembly. Reuses BibleInjector's plumbing per HANDOFF
/// §9.1 row 8: word-boundary regex matching against keys, with
/// AND-gating on secondaryKeys.
func phase2LorebookIntegrationTests() -> TestSuite {
    let s = TestSuite("Phase2LorebookIntegration")

    s.test("constant lorebook entry is always injected") {
        var project = Project(title: "T")
        project.bible.lorebook = [
            LorebookEntry(
                name: "Tone",
                content: "World rule: magic costs blood.",
                activationMode: .constant
            )
        ]
        let scene = Scene.empty(id: UUID(), title: "S1")
        let ctx = makeLorebookContext(project: project, scene: scene, prose: "Some prose body.")
        let result = PromptBuilder.build(ctx)
        let combined = result.systemBlock + result.userBlock
        try expectTrue(combined.contains("World rule: magic costs blood."))
    }

    s.test("keyed lorebook entry injects when key appears in recent prose") {
        var project = Project(title: "T")
        project.bible.lorebook = [
            LorebookEntry(
                name: "Dragons",
                content: "Dragons in this world breathe ice, not fire.",
                activationMode: .keyed,
                keys: ["dragon", "wyrm"]
            )
        ]
        let scene = Scene.empty(id: UUID(), title: "S1")
        let ctx = makeLorebookContext(
            project: project, scene: scene,
            prose: "The dragon emerged from the cave."
        )
        let result = PromptBuilder.build(ctx)
        let combined = result.systemBlock + result.userBlock
        try expectTrue(combined.contains("Dragons in this world breathe ice, not fire."))
    }

    s.test("keyed lorebook entry does NOT inject when key absent") {
        var project = Project(title: "T")
        project.bible.lorebook = [
            LorebookEntry(
                name: "Dragons",
                content: "Dragons breathe ice.",
                activationMode: .keyed,
                keys: ["dragon"]
            )
        ]
        let scene = Scene.empty(id: UUID(), title: "S1")
        let ctx = makeLorebookContext(project: project, scene: scene, prose: "Nothing relevant here.")
        let result = PromptBuilder.build(ctx)
        let combined = result.systemBlock + result.userBlock
        try expectFalse(combined.contains("Dragons breathe ice."))
    }

    s.test("disabled lorebook entry never injects, even constant or matched") {
        var project = Project(title: "T")
        project.bible.lorebook = [
            LorebookEntry(
                name: "Disabled rule",
                content: "Should not appear.",
                activationMode: .constant,
                enabled: false
            )
        ]
        let scene = Scene.empty(id: UUID(), title: "S1")
        let ctx = makeLorebookContext(project: project, scene: scene, prose: "X")
        let result = PromptBuilder.build(ctx)
        let combined = result.systemBlock + result.userBlock
        try expectFalse(combined.contains("Should not appear."))
    }

    s.test("AND-gating: secondaryKeys must also match for keyed entry to fire") {
        var project = Project(title: "T")
        project.bible.lorebook = [
            LorebookEntry(
                name: "Combat tactics",
                content: "Combat in caves is close-quarters only.",
                activationMode: .keyed,
                keys: ["combat", "fight"],
                secondaryKeys: ["cave", "underground"]
            )
        ]
        let scene = Scene.empty(id: UUID(), title: "S1")

        // Primary key matches but no secondary — should NOT activate.
        let ctx1 = makeLorebookContext(project: project, scene: scene, prose: "The combat lasted hours.")
        let result1 = PromptBuilder.build(ctx1)
        try expectFalse((result1.systemBlock + result1.userBlock)
                            .contains("Combat in caves is close-quarters only."))

        // Both match — should activate.
        let ctx2 = makeLorebookContext(
            project: project, scene: scene,
            prose: "The combat in the cave lasted hours."
        )
        let result2 = PromptBuilder.build(ctx2)
        try expectTrue((result2.systemBlock + result2.userBlock)
                           .contains("Combat in caves is close-quarters only."))
    }

    s.test("vectorised mode is treated as inactive in Phase 2 (deferred to Phase 5)") {
        var project = Project(title: "T")
        project.bible.lorebook = [
            LorebookEntry(
                name: "Vector",
                content: "Vector-only content.",
                activationMode: .vectorised,
                keys: ["anything"]
            )
        ]
        let scene = Scene.empty(id: UUID(), title: "S1")
        let ctx = makeLorebookContext(
            project: project, scene: scene,
            prose: "anything in the prose body"
        )
        let result = PromptBuilder.build(ctx)
        try expectFalse((result.systemBlock + result.userBlock)
                            .contains("Vector-only content."))
    }

    return s
}

private func makeLorebookContext(project: Project, scene: Scene, prose: String) -> PromptContext {
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

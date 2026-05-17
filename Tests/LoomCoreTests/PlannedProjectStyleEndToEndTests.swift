import Foundation
@testable import LoomCore

/// Planned Project mode — the end-to-end check the Phase 3 style glue
/// was waiting on. Phase 3 wired a project's assigned styles into the
/// prompt, but until Phase 4 nothing could *create* a planned project
/// carrying assigned styles, so the chain was only component-tested
/// (resolve / render / the PromptBuilder layer each in isolation).
///
/// This exercises the whole path with no stubs: a real `.loom` bundle
/// created the way the app creates it (`ProjectStorage.createPlannedProject`),
/// loaded back from disk, its `plannedConfig.assignedStyleIds`
/// resolved against a style library and assembled into a prompt — the
/// exact resolution `GenerationCoordinator.start()` performs before it
/// fires the (network-only) generation request.
func plannedProjectStyleEndToEndTests() -> TestSuite {
    let s = TestSuite("PlannedProjectStyleEndToEnd")

    func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("loom-planned-e2e-\(UUID().uuidString).loom")
    }

    s.test("assigned styles survive disk round-trip and thread into the built prompt") {
        let noir = Style(
            name: "Noir", type: .genre,
            descriptor: "Rain-slicked cynicism.",
            constraints: ["Keep the narration cynical."]
        )
        let terse = Style(
            name: "Terse", type: .register,
            descriptor: "Short sentences only.",
            constraints: ["No throat-clearing."]
        )
        let library = [noir, terse]

        let dir = tempURL()
        defer { try? FileManager.default.removeItem(at: dir) }

        let scene = Scene(
            id: UUID(), title: "Opening", status: .todo, summary: "It begins."
        )
        let outline = OutlineGeneration.GeneratedOutline(
            manuscript: Manuscript(orphanedSceneIds: [scene.id]),
            scenes: [scene]
        )
        let config = PlannedProjectConfig(
            premise: "A heist goes wrong.",
            characterSketch: "Mara, a tired courier.",
            lengthScenario: .shortStory,
            assignedStyleIds: [noir.id, terse.id]
        )

        let storage = ProjectStorage()
        try storage.createPlannedProject(
            at: dir, title: "Styled", config: config, outline: outline
        )

        // Load the bundle exactly as the app would.
        let loaded = try storage.loadProjectWithRecovery(from: dir)
        let assignedIds = loaded.project.plannedConfig?.assignedStyleIds ?? []
        try expectEqual(assignedIds, [noir.id, terse.id])

        // The resolution `GenerationCoordinator.start()` runs.
        var context = PromptContext(
            mode: .continueProse,
            project: loaded.project,
            scenes: loaded.scenes,
            currentSceneId: scene.id,
            cursorOffset: 0,
            selectionRange: nil,
            modelName: nil,
            contextBudgetTokens: 8_192,
            replyBudgetTokens: 512
        )
        context.assignedStyles = StyleLibrary.resolve(assignedIds, in: library)
        let assembled = PromptBuilder.build(context)

        try expectTrue(
            assembled.fullPrompt.contains("Rain-slicked cynicism."),
            "the genre style's descriptor must reach the prompt"
        )
        try expectTrue(
            assembled.fullPrompt.contains("Keep the narration cynical."),
            "the genre style's constraint must reach the prompt"
        )
        try expectTrue(
            assembled.fullPrompt.contains("No throat-clearing."),
            "the register style's constraint must reach the prompt"
        )
        // The style layer is a labelled, above-cache chiclet.
        try expectTrue(
            assembled.chiclets.contains { $0.sourceKind == .styleSheet },
            "a styleSheet layer must be present"
        )
    }

    s.test("a planned project with no assigned styles adds no style layer") {
        let dir = tempURL()
        defer { try? FileManager.default.removeItem(at: dir) }

        let scene = Scene(id: UUID(), title: "Opening", status: .todo)
        let outline = OutlineGeneration.GeneratedOutline(
            manuscript: Manuscript(orphanedSceneIds: [scene.id]),
            scenes: [scene]
        )
        let storage = ProjectStorage()
        try storage.createPlannedProject(
            at: dir, title: "Plain",
            config: PlannedProjectConfig(premise: "P", characterSketch: "C"),
            outline: outline
        )
        let loaded = try storage.loadProjectWithRecovery(from: dir)

        var context = PromptContext(
            mode: .continueProse,
            project: loaded.project,
            scenes: loaded.scenes,
            currentSceneId: scene.id,
            cursorOffset: 0,
            selectionRange: nil,
            modelName: nil,
            contextBudgetTokens: 8_192,
            replyBudgetTokens: 512
        )
        context.assignedStyles = StyleLibrary.resolve(
            loaded.project.plannedConfig?.assignedStyleIds ?? [],
            in: StyleLibrary.builtInStarters
        )
        let assembled = PromptBuilder.build(context)
        try expectFalse(
            assembled.chiclets.contains { $0.sourceKind == .styleSheet },
            "no assigned styles → no styleSheet layer"
        )
    }

    return s
}

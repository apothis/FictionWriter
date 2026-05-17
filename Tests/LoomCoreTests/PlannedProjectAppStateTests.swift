import Foundation
@testable import LoomCore

/// Planned Project mode — Phase 4 item 2c. `AppState.createPlannedProject`
/// is the guided-creation counterpart of `createProject`: it writes a
/// `.loom` bundle from a generated outline and switches the current
/// session onto it, so the wizard's "Create" step lands the writer in
/// their new project. Mirrors the `AppState.createProject` glue test.
func plannedProjectAppStateTests() -> TestSuite {
    let s = TestSuite("PlannedProjectAppState")

    s.test("createPlannedProject swaps in the new on-disk session") {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("loom-planned-\(UUID().uuidString).loom")
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = AppSettingsStore(rootDir: FileManager.default.temporaryDirectory
            .appendingPathComponent("loom-appstate-\(UUID().uuidString)"))
        defer { try? FileManager.default.removeItem(at: store.settingsURL.deletingLastPathComponent()) }
        let appState = AppState(settingsStore: store)

        let scenes = [
            Scene(id: UUID(), title: "Opening", status: .todo, summary: "It begins."),
            Scene(id: UUID(), title: "Close", status: .todo, summary: "It ends."),
        ]
        let outline = OutlineGeneration.GeneratedOutline(
            manuscript: Manuscript(orphanedSceneIds: scenes.map(\.id)),
            scenes: scenes
        )
        let config = PlannedProjectConfig(
            premise: "A test premise.",
            characterSketch: "Vesna, a courier.",
            lengthScenario: .shortStory
        )

        try appState.createPlannedProject(
            at: dir, title: "Planned", config: config, outline: outline
        )

        try expectEqual(appState.currentSession.project.title, "Planned")
        try expectEqual(appState.currentSession.url, dir)
        try expectEqual(appState.currentSession.project.plannedConfig?.premise, "A test premise.")
        try expectEqual(appState.currentSession.project.bible.characters.first?.name, "Vesna")
        try expectEqual(appState.currentSession.scenes.count, 2)
        try expectFalse(appState.currentSession.isDirty,
                        "freshly-created planned session should be clean")
        // The first outline scene is selected — the writer lands
        // somewhere rather than in an empty selection.
        try expectEqual(appState.currentSession.currentSceneId, scenes.first?.id)
    }

    return s
}

import Foundation
@testable import LoomCore

/// Planned Project mode — Phase 4: creating a project bundle on disk
/// from a generated outline. `PlannedProjectConfig.seedCharacter` and
/// `ProjectStorage.createPlannedProject`. LOOM_PLANNED_PROJECT.md §6.
func plannedProjectCreationTests() -> TestSuite {
    let s = TestSuite("PlannedProjectCreation")

    func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("loom-planned-\(UUID().uuidString).loom")
    }

    // MARK: - seedCharacter

    s.test("seedCharacter takes the name before the first comma") {
        let config = PlannedProjectConfig(characterSketch: "Vesna, late thirties — a courier.")
        let character = try expectNotNil(config.seedCharacter())
        try expectEqual(character.name, "Vesna")
        try expectEqual(character.oneLine, "Vesna, late thirties — a courier.")
        // The sketch also seeds the fuller description field so the
        // bible character isn't created with an empty body.
        try expectEqual(character.description, "Vesna, late thirties — a courier.")
    }

    s.test("seedCharacter takes the name before an em-dash") {
        let config = PlannedProjectConfig(characterSketch: "Kael — a memory broker")
        try expectEqual(config.seedCharacter()?.name, "Kael")
    }

    s.test("seedCharacter handles a bare name") {
        try expectEqual(
            PlannedProjectConfig(characterSketch: "Marcus").seedCharacter()?.name,
            "Marcus"
        )
    }

    s.test("seedCharacter is nil when the sketch is empty") {
        try expectNil(PlannedProjectConfig(characterSketch: "   ").seedCharacter())
    }

    // MARK: - createPlannedProject

    s.test("createPlannedProject writes the outline, config, and seed character") {
        let dir = tempURL()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = ProjectStorage()

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

        let project = try storage.createPlannedProject(
            at: dir, title: "Planned", config: config, outline: outline
        )
        try expectEqual(project.plannedConfig?.premise, "A test premise.")

        // Full round-trip from disk.
        let loaded = try storage.loadProjectWithRecovery(from: dir)
        try expectEqual(loaded.project.manuscript.orphanedSceneIds.count, 2)
        try expectEqual(loaded.project.plannedConfig?.premise, "A test premise.")
        try expectEqual(loaded.project.bible.characters.first?.name, "Vesna")
        try expectEqual(loaded.scenes.count, 2)
        try expectTrue(loaded.scenes.values.allSatisfy { $0.status == .todo })
    }

    s.test("createPlannedProject refuses to overwrite an existing directory") {
        let dir = tempURL()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storage = ProjectStorage()
        let outline = OutlineGeneration.GeneratedOutline(manuscript: .empty, scenes: [])
        var threw = false
        do {
            _ = try storage.createPlannedProject(
                at: dir, title: "X", config: PlannedProjectConfig(), outline: outline
            )
        } catch {
            threw = true
        }
        try expectTrue(threw)
    }

    return s
}

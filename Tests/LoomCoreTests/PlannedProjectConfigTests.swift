import Foundation
@testable import LoomCore

/// Planned Project mode — `PlannedProjectConfig` and its additive
/// landing on `Project`. Includes the lazy-versioning forward-load
/// contract: a project.json from before this field decodes cleanly
/// with `plannedConfig` nil. LOOM_PLANNED_PROJECT.md §5.
func plannedProjectConfigTests() -> TestSuite {
    let s = TestSuite("PlannedProjectConfig")

    s.test("PlannedProjectConfig round-trips through Codable") {
        let config = PlannedProjectConfig(
            premise: "A courier smuggles a memory across a divided city.",
            characterSketch: "Vesna, 30s — a courier who never reads what she carries.",
            lengthScenario: .novella,
            frameworkId: "save-the-cat",
            assignedStyleIds: [UUID(), UUID()]
        )
        let data = try JSONEncoder.loomPretty.encode(config)
        let back = try JSONDecoder.loom.decode(PlannedProjectConfig.self, from: data)
        try expectEqual(back, config)
    }

    s.test("forward-load: an empty PlannedProjectConfig JSON decodes to defaults") {
        let config = try JSONDecoder.loom.decode(
            PlannedProjectConfig.self, from: Data("{}".utf8)
        )
        try expectEqual(config.premise, "")
        try expectEqual(config.characterSketch, "")
        try expectEqual(config.lengthScenario, .shortStory)
        try expectEqual(config.frameworkId, "save-the-cat")
        try expectEqual(config.assignedStyleIds, [])
    }

    s.test("a default Project has no planned config") {
        try expectNil(Project.empty(title: "Blank").plannedConfig)
    }

    s.test("forward-load: a project.json without plannedConfig decodes with it nil") {
        // A project from before Planned Project mode — no plannedConfig key.
        let legacy = Project.empty(title: "Legacy")
        let data = try JSONEncoder.loomPretty.encode(legacy)
        let json = String(data: data, encoding: .utf8) ?? ""
        try expectTrue(!json.contains("plannedConfig"), "a nil config must not encode a key")
        let decoded = try JSONDecoder.loom.decode(Project.self, from: data)
        try expectNil(decoded.plannedConfig)
    }

    s.test("a Project with a planned config round-trips") {
        var p = Project.empty(title: "Planned")
        p.plannedConfig = PlannedProjectConfig(
            premise: "x", characterSketch: "y",
            lengthScenario: .novel, frameworkId: "save-the-cat",
            assignedStyleIds: [UUID()]
        )
        let data = try JSONEncoder.loomPretty.encode(p)
        let decoded = try JSONDecoder.loom.decode(Project.self, from: data)
        try expectEqual(decoded, p)
    }

    return s
}

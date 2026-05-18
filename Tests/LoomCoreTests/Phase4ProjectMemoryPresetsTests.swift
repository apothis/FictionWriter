import Foundation
@testable import LoomCore

/// P0b — default Project Memory + preset starter pack (LOOM_NSFW.md
/// §2.3, §8 Phase 2). The schema default stays `""` for forward-load
/// safety; new projects are seeded at creation time with the
/// Loom-default preset, which carries the explicit anti-refusal clause.
func phase4ProjectMemoryPresetsTests() -> TestSuite {
    let s = TestSuite("Phase4ProjectMemoryPresets")

    s.test("loom-default preset carries the anti-refusal clause") {
        let text = ProjectMemoryPresets.loomDefault.text.lowercased()
        try expectTrue(text.contains("fiction writer"))
        try expectTrue(text.contains("not refuse") || text.contains("does not refuse"))
        try expectTrue(text.contains("subject matter"))
    }

    s.test("three presets, all non-empty, distinct text and titles") {
        let all = ProjectMemoryPresets.all
        try expectEqual(all.count, 3)
        for p in all {
            try expectFalse(p.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            try expectFalse(p.title.isEmpty)
        }
        try expectEqual(Set(all.map(\.text)).count, 3)
        try expectEqual(Set(all.map(\.title)).count, 3)
    }

    s.test("the Project schema default stays empty — forward-load safety") {
        try expectEqual(Project(title: "X").settings.memory, "")
    }

    s.test("createNewProject seeds the Loom-default memory") {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("memseed-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let project = try ProjectStorage().createNewProject(at: dir, title: "Seeded", author: nil)
        try expectEqual(project.settings.memory, ProjectMemoryPresets.loomDefault.text)
    }

    return s
}

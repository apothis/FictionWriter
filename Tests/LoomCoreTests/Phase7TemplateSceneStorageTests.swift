import Foundation
@testable import LoomCore

/// Phase 7.b.1 — TemplateScene entity + storage layer.
///
/// Mirrors `Phase5ReferenceStorageTests` / `Phase5ReferenceFileTests`
/// shape. A `TemplateScene` lives on disk at
/// `<project>/templates/<id>.md` (frontmatter + body) with a sidecar
/// `<project>/templates/<id>.beats.json` (the `ExtractedSceneSkeleton`).
///
/// Architecturally pinned in [`LOOM_SCENE_TEMPLATE.md`](LOOM_SCENE_TEMPLATE.md)
/// §6.1 + D1 (TemplateScene is a first-class entity, not a flagged
/// reference).
func phase7TemplateSceneStorageTests() -> TestSuite {
    let s = TestSuite("Phase7TemplateSceneStorage")

    func makeTempProject() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("loom-template-storage-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - TemplateScene model

    s.test("TemplateScene Codable round-trips metadata; body excluded from JSON") {
        let scene = TemplateScene(
            id: UUID(),
            name: "Hemingway farewell",
            nsfw: false,
            createdAt: Date(timeIntervalSince1970: 1000),
            body: "She stood in the doorway."
        )
        let data = try JSONEncoder().encode(scene)
        let json = String(data: data, encoding: .utf8) ?? ""
        // Body excluded from JSON (same as ReferenceText) — body lives
        // in the `.md` body, not in metadata JSON.
        try expectFalse(json.contains("She stood in the doorway"))
    }

    // MARK: - TemplateSceneFile encode/decode

    s.test("TemplateSceneFile round-trips frontmatter + body") {
        let scene = TemplateScene(
            id: UUID(),
            name: "Action scene template",
            nsfw: true,
            createdAt: Date(timeIntervalSince1970: 2000),
            body: "The fire was already in the curtains.\n\nHe ran."
        )
        let encoded = TemplateSceneFile.encode(scene)
        let decoded = try TemplateSceneFile.decode(encoded)
        try expectEqual(decoded.id, scene.id)
        try expectEqual(decoded.name, scene.name)
        try expectEqual(decoded.nsfw, scene.nsfw)
        try expectEqual(decoded.body, scene.body)
    }

    s.test("TemplateSceneFile.decode rejects missing frontmatter") {
        do {
            _ = try TemplateSceneFile.decode("just prose, no frontmatter")
            try expectFalse(true, "expected error for missing frontmatter")
        } catch {
            // pass
        }
    }

    // MARK: - TemplateSceneStorage

    s.test("TemplateSceneStorage.saveTemplate writes .md under templates/") {
        let projectURL = makeTempProject()
        defer { try? FileManager.default.removeItem(at: projectURL) }
        let scene = TemplateScene(id: UUID(), name: "x", body: "body text")
        try TemplateSceneStorage.saveTemplate(scene, in: projectURL)
        let path = projectURL
            .appendingPathComponent("templates")
            .appendingPathComponent("\(scene.id.uuidString).md")
        try expectTrue(FileManager.default.fileExists(atPath: path.path))
    }

    s.test("TemplateSceneStorage round-trips a template through disk") {
        let projectURL = makeTempProject()
        defer { try? FileManager.default.removeItem(at: projectURL) }
        let original = TemplateScene(id: UUID(), name: "Round-trip test", nsfw: true, body: "Body.")
        try TemplateSceneStorage.saveTemplate(original, in: projectURL)
        let loaded = try TemplateSceneStorage.loadTemplate(id: original.id, in: projectURL)
        try expectEqual(loaded.id, original.id)
        try expectEqual(loaded.name, "Round-trip test")
        try expectEqual(loaded.nsfw, true)
        try expectEqual(loaded.body, "Body.")
    }

    s.test("TemplateSceneStorage.saveSkeleton + loadSkeleton round-trip the beats sidecar") {
        let projectURL = makeTempProject()
        defer { try? FileManager.default.removeItem(at: projectURL) }
        let scene = TemplateScene(id: UUID(), name: "x", body: "body")
        try TemplateSceneStorage.saveTemplate(scene, in: projectURL)
        let skeleton = ExtractedSceneSkeleton(
            beats: [
                SceneBeat(
                    index: 0, summary: "{PROTAGONIST} enters.",
                    modality: .action, function: .arrival,
                    targetWords: 80, wordRangeStart: 0, wordRangeEnd: 80,
                    beatTensionChange: 1
                ),
            ],
            sourceCharacters: ["Mara"],
            sourceSettingMarkers: ["doorway"]
        )
        try TemplateSceneStorage.saveSkeleton(skeleton, for: scene.id, in: projectURL)
        let loaded = TemplateSceneStorage.loadSkeleton(for: scene.id, in: projectURL)
        try expectNotNil(loaded)
        try expectEqual(loaded?.beats.count, 1)
        try expectEqual(loaded?.beats.first?.summary, "{PROTAGONIST} enters.")
        try expectEqual(loaded?.sourceCharacters, ["Mara"])
    }

    s.test("TemplateSceneStorage.loadSkeleton returns nil for missing sidecar") {
        let projectURL = makeTempProject()
        defer { try? FileManager.default.removeItem(at: projectURL) }
        let result = TemplateSceneStorage.loadSkeleton(for: UUID(), in: projectURL)
        try expectTrue(result == nil)
    }

    s.test("TemplateSceneStorage.deleteTemplate removes both .md and .beats.json") {
        let projectURL = makeTempProject()
        defer { try? FileManager.default.removeItem(at: projectURL) }
        let scene = TemplateScene(id: UUID(), name: "to-delete", body: "x")
        try TemplateSceneStorage.saveTemplate(scene, in: projectURL)
        try TemplateSceneStorage.saveSkeleton(
            ExtractedSceneSkeleton(beats: [], sourceCharacters: [], sourceSettingMarkers: []),
            for: scene.id, in: projectURL
        )
        try TemplateSceneStorage.deleteTemplate(id: scene.id, in: projectURL)
        let ids = try TemplateSceneStorage.listTemplateIds(in: projectURL)
        try expectFalse(ids.contains(scene.id))
        try expectTrue(TemplateSceneStorage.loadSkeleton(for: scene.id, in: projectURL) == nil)
    }

    s.test("TemplateSceneStorage.listTemplateIds returns empty for new project") {
        let projectURL = makeTempProject()
        defer { try? FileManager.default.removeItem(at: projectURL) }
        let ids = try TemplateSceneStorage.listTemplateIds(in: projectURL)
        try expectEqual(ids.count, 0)
    }

    s.test("TemplateSceneStorage.listTemplateIds enumerates multiple templates") {
        let projectURL = makeTempProject()
        defer { try? FileManager.default.removeItem(at: projectURL) }
        let a = TemplateScene(id: UUID(), name: "a", body: "x")
        let b = TemplateScene(id: UUID(), name: "b", body: "y")
        try TemplateSceneStorage.saveTemplate(a, in: projectURL)
        try TemplateSceneStorage.saveTemplate(b, in: projectURL)
        let ids = try TemplateSceneStorage.listTemplateIds(in: projectURL)
        try expectEqual(Set(ids), Set([a.id, b.id]))
    }

    return s
}

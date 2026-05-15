import Foundation
@testable import LoomCore

// Phase 8.b.x — per-template persistence of the Write-Scene-From-
// Template menu's fields (cast mapping, additional instruction,
// imitate-content toggle). Stored as a small JSON sidecar at
// `<project>/template-gen-state/<templateId>.json`. The menu loads
// the state when the user picks a template (so they see what they
// typed last time) and writes the state on Generate (so the NEXT
// time the same template is picked, the fields populate).
//
// User goal: re-run a template generation with a tweaked hint or
// retry the same inputs after a problematic output, without re-
// typing the cast mapping every time.

func phase8TemplateGenStateStoreTests() -> TestSuite {
    let s = TestSuite("Phase8TemplateGenStateStore")

    func makeTempProject() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("loom-tg-state-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    s.test("load returns nil when no sidecar exists") {
        let url = makeTempProject()
        defer { try? FileManager.default.removeItem(at: url) }
        try expectNil(TemplateGenStateStore.load(templateId: UUID(), in: url))
    }

    s.test("save then load round-trips all three fields") {
        let url = makeTempProject()
        defer { try? FileManager.default.removeItem(at: url) }
        let templateId = UUID()
        let state = TemplateGenState(
            castMapping: "Maya, 32, journalist. Daniel, her father.",
            extraInstruction: "Keep dialogue terse.",
            imitateContent: true,
            savedAt: Date(timeIntervalSince1970: 1_715_000_000)
        )
        try TemplateGenStateStore.save(state, templateId: templateId, in: url)
        let loaded = try expectNotNil(TemplateGenStateStore.load(templateId: templateId, in: url))
        try expectEqual(loaded.castMapping, "Maya, 32, journalist. Daniel, her father.")
        try expectEqual(loaded.extraInstruction, "Keep dialogue terse.")
        try expectEqual(loaded.imitateContent, true)
        try expectEqual(loaded.savedAt, Date(timeIntervalSince1970: 1_715_000_000))
    }

    s.test("save overwrites a previously-saved state for the same template id") {
        let url = makeTempProject()
        defer { try? FileManager.default.removeItem(at: url) }
        let templateId = UUID()
        try TemplateGenStateStore.save(
            TemplateGenState(castMapping: "v1", extraInstruction: "", imitateContent: false, savedAt: Date()),
            templateId: templateId, in: url
        )
        try TemplateGenStateStore.save(
            TemplateGenState(castMapping: "v2", extraInstruction: "newer", imitateContent: true, savedAt: Date()),
            templateId: templateId, in: url
        )
        let loaded = try expectNotNil(TemplateGenStateStore.load(templateId: templateId, in: url))
        try expectEqual(loaded.castMapping, "v2")
        try expectEqual(loaded.extraInstruction, "newer")
        try expectEqual(loaded.imitateContent, true)
    }

    s.test("each template gets its own sidecar (no cross-template bleed)") {
        let url = makeTempProject()
        defer { try? FileManager.default.removeItem(at: url) }
        let a = UUID()
        let b = UUID()
        try TemplateGenStateStore.save(
            TemplateGenState(castMapping: "for A", extraInstruction: "", imitateContent: false, savedAt: Date()),
            templateId: a, in: url
        )
        try TemplateGenStateStore.save(
            TemplateGenState(castMapping: "for B", extraInstruction: "", imitateContent: true, savedAt: Date()),
            templateId: b, in: url
        )
        let loadedA = try expectNotNil(TemplateGenStateStore.load(templateId: a, in: url))
        let loadedB = try expectNotNil(TemplateGenStateStore.load(templateId: b, in: url))
        try expectEqual(loadedA.castMapping, "for A")
        try expectEqual(loadedA.imitateContent, false)
        try expectEqual(loadedB.castMapping, "for B")
        try expectEqual(loadedB.imitateContent, true)
    }

    s.test("save creates the parent directory if absent (fresh-project case)") {
        let url = makeTempProject()
        defer { try? FileManager.default.removeItem(at: url) }
        // Confirm template-gen-state dir doesn't exist yet
        let dir = url.appendingPathComponent("template-gen-state")
        try expectFalse(FileManager.default.fileExists(atPath: dir.path))
        try TemplateGenStateStore.save(
            TemplateGenState(castMapping: "x", extraInstruction: "", imitateContent: false, savedAt: Date()),
            templateId: UUID(), in: url
        )
        try expectTrue(FileManager.default.fileExists(atPath: dir.path))
    }

    s.test("load gracefully returns nil on malformed JSON (no crash)") {
        let url = makeTempProject()
        defer { try? FileManager.default.removeItem(at: url) }
        let templateId = UUID()
        let dir = url.appendingPathComponent("template-gen-state")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(templateId.uuidString).json")
        try "{not valid json".write(to: file, atomically: true, encoding: .utf8)
        try expectNil(TemplateGenStateStore.load(templateId: templateId, in: url))
    }

    return s
}

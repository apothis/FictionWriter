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

    s.test("loadOrBackfill falls back to generation-log when no sidecar exists") {
        // The 2026-05-15 smoke surfaced this: state-saving landed
        // AFTER several real generations had already run. Opening the
        // menu after the rebuild showed empty fields because the
        // sidecar had never been written. Backfill: scan
        // generation-log/*.json for the most recent entry whose
        // templateGenerationInfo.templateId matches; synthesize a
        // TemplateGenState from its castMapping (+ imitateContent
        // and extraInstruction if those newer fields are present).
        let url = makeTempProject()
        defer { try? FileManager.default.removeItem(at: url) }
        let templateId = UUID()
        // Write a generation-log entry the way TemplateGenerationCoordinator
        // would have, with the new optional fields populated.
        let info = TemplateGenerationInfo(
            templateId: templateId, templateName: "Scene 1",
            castMapping: "Emily, 16 and Maya, 17 are lesbian lovers.",
            beatCount: 10, beatModalitySequence: [],
            voiceDescriptor: nil,
            imitateContent: true,
            extraInstruction: "Lean into the tension."
        )
        let entry = GenerationLogEntry(
            sceneId: UUID(),
            timestamp: Date(),
            mode: .continueProse,
            promptAssembly: PromptAssembly(
                contextChiclets: [], fullPrompt: "",
                promptTokens: 0, aboveCacheTokens: 0, belowCacheTokens: 0,
                evictedLayers: [], template: .gemma4
            ),
            response: GenerationResponse(rawText: "", completionTokens: 0, refusalDetected: false, elapsedMs: 0),
            templateGenerationInfo: info
        )
        try GenerationLogStore().write(entry, in: url)

        let restored = try expectNotNil(
            TemplateGenStateStore.loadOrBackfill(templateId: templateId, in: url)
        )
        try expectEqual(restored.castMapping, "Emily, 16 and Maya, 17 are lesbian lovers.")
        try expectEqual(restored.imitateContent, true)
        try expectEqual(restored.extraInstruction, "Lean into the tension.")
    }

    s.test("loadOrBackfill prefers the sidecar over the gen-log when both exist") {
        let url = makeTempProject()
        defer { try? FileManager.default.removeItem(at: url) }
        let templateId = UUID()
        // Older gen-log entry…
        let info = TemplateGenerationInfo(
            templateId: templateId, templateName: "T",
            castMapping: "OLD cast from gen-log",
            beatCount: 5, beatModalitySequence: [],
            voiceDescriptor: nil,
            imitateContent: false, extraInstruction: nil
        )
        let entry = GenerationLogEntry(
            sceneId: UUID(),
            timestamp: Date(timeIntervalSinceNow: -3600),
            mode: .continueProse,
            promptAssembly: PromptAssembly(
                contextChiclets: [], fullPrompt: "",
                promptTokens: 0, aboveCacheTokens: 0, belowCacheTokens: 0,
                evictedLayers: [], template: .gemma4
            ),
            response: GenerationResponse(rawText: "", completionTokens: 0, refusalDetected: false, elapsedMs: 0),
            templateGenerationInfo: info
        )
        try GenerationLogStore().write(entry, in: url)
        // …and a newer sidecar (the authoritative state).
        try TemplateGenStateStore.save(
            TemplateGenState(
                castMapping: "NEW cast from sidecar",
                extraInstruction: "Newer hint.", imitateContent: true,
                savedAt: Date()
            ),
            templateId: templateId, in: url
        )

        let restored = try expectNotNil(
            TemplateGenStateStore.loadOrBackfill(templateId: templateId, in: url)
        )
        try expectEqual(restored.castMapping, "NEW cast from sidecar")
        try expectEqual(restored.extraInstruction, "Newer hint.")
        try expectEqual(restored.imitateContent, true)
    }

    s.test("loadOrBackfill picks the most-recent matching gen-log entry") {
        let url = makeTempProject()
        defer { try? FileManager.default.removeItem(at: url) }
        let templateId = UUID()
        let store = GenerationLogStore()
        for (i, label) in ["oldest", "middle", "newest"].enumerated() {
            let info = TemplateGenerationInfo(
                templateId: templateId, templateName: "T",
                castMapping: "cast: \(label)",
                beatCount: 1, beatModalitySequence: [],
                voiceDescriptor: nil, imitateContent: nil, extraInstruction: nil
            )
            let entry = GenerationLogEntry(
                sceneId: UUID(),
                timestamp: Date(timeIntervalSinceNow: TimeInterval(-3600 * (3 - i))),
                mode: .continueProse,
                promptAssembly: PromptAssembly(
                    contextChiclets: [], fullPrompt: "",
                    promptTokens: 0, aboveCacheTokens: 0, belowCacheTokens: 0,
                    evictedLayers: [], template: .gemma4
                ),
                response: GenerationResponse(rawText: "", completionTokens: 0, refusalDetected: false, elapsedMs: 0),
                templateGenerationInfo: info
            )
            try store.write(entry, in: url)
        }
        let restored = try expectNotNil(
            TemplateGenStateStore.loadOrBackfill(templateId: templateId, in: url)
        )
        try expectEqual(restored.castMapping, "cast: newest")
    }

    s.test("loadOrBackfill returns nil when neither sidecar nor matching gen-log exists") {
        let url = makeTempProject()
        defer { try? FileManager.default.removeItem(at: url) }
        try expectNil(TemplateGenStateStore.loadOrBackfill(templateId: UUID(), in: url))
    }

    return s
}

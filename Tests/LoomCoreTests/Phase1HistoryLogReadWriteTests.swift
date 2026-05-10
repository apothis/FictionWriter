import Foundation
@testable import LoomCore

/// Sub-step 1.k — generation log Codable round-trip + store I/O.
/// Pure tests against synthetic GenerationLogEntry values; the
/// coordinator-level wiring smoke-tests itself via the live launch.
func phase1HistoryLogReadWriteTests() -> TestSuite {
    let s = TestSuite("Phase1HistoryLogReadWrite")

    s.test("GenerationLogEntry Codable round-trips") {
        let entry = makeSampleEntry()
        let data = try JSONEncoder.loomPretty.encode(entry)
        let back = try JSONDecoder.loom.decode(GenerationLogEntry.self, from: data)
        try expectEqual(back, entry)
    }

    s.test("write + list round-trips a single entry") {
        let dir = makeTempProjectDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = GenerationLogStore()
        let entry = makeSampleEntry()
        let path = try store.write(entry, in: dir)
        try expectTrue(FileManager.default.fileExists(atPath: path.path))

        let entries = store.list(in: dir)
        try expectEqual(entries.count, 1)
        try expectEqual(entries[0], entry)
    }

    s.test("list sorts descending by timestamp (newest first)") {
        let dir = makeTempProjectDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = GenerationLogStore()
        let earlier = makeSampleEntry(timestamp: Date(timeIntervalSinceReferenceDate: 100_000))
        let later = makeSampleEntry(timestamp: Date(timeIntervalSinceReferenceDate: 200_000))
        _ = try store.write(earlier, in: dir)
        _ = try store.write(later, in: dir)

        let listed = store.list(in: dir)
        try expectEqual(listed.count, 2)
        try expectEqual(listed[0].id, later.id)
        try expectEqual(listed[1].id, earlier.id)
    }

    s.test("list of an empty / missing directory returns empty array") {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("loom-history-missing-\(UUID().uuidString).loom")
        let store = GenerationLogStore()
        try expectEqual(store.list(in: dir).count, 0)
    }

    s.test("list skips corrupt JSON files (best-effort recovery)") {
        let dir = makeTempProjectDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = GenerationLogStore()
        // Write one valid entry.
        _ = try store.write(makeSampleEntry(), in: dir)
        // Drop a corrupt file alongside it.
        let logDir = dir.appendingPathComponent("generation-log", isDirectory: true)
        let corrupt = logDir.appendingPathComponent("99999999-corrupt.json")
        try Data("{ this is not json }".utf8).write(to: corrupt)

        let listed = store.list(in: dir)
        try expectEqual(listed.count, 1, "corrupt entry should be skipped, valid entry preserved")
    }

    return s
}

// MARK: - helpers

private func makeTempProjectDir() -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("loom-history-\(UUID().uuidString).loom")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func makeSampleEntry(timestamp: Date = Date()) -> GenerationLogEntry {
    let chiclet = ContextChiclet(
        label: "System",
        sourceKind: .system,
        sourceId: nil,
        contentExcerpt: "You are a fiction writer...",
        fullContent: "You are a fiction writer continuing a manuscript.",
        tokenCount: 12
    )
    return GenerationLogEntry(
        id: UUID(),
        sceneId: UUID(),
        timestamp: timestamp,
        mode: .continueProse,
        model: "qwen3-30B-instruct",
        serverProfileId: nil,
        promptAssembly: PromptAssembly(
            contextChiclets: [chiclet],
            fullPrompt: "<|im_start|>system\n...\n<|im_end|>",
            promptTokens: 1234,
            aboveCacheTokens: 800,
            belowCacheTokens: 434,
            evictedLayers: [],
            template: .chatml
        ),
        response: GenerationResponse(
            rawText: "She glanced up from her book.",
            completionTokens: 7,
            stopReason: "stop_sequence",
            refusalDetected: false,
            elapsedMs: 1450
        )
    )
}

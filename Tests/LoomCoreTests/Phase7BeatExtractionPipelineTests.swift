import Foundation
@testable import LoomCore

/// Phase 7.b.2 — beat extraction pipeline.
///
/// `BeatExtractionPipeline` loads a `TemplateScene` from disk, runs
/// Pass A via the injected `BeatExtractor`, and persists the resulting
/// `ExtractedSceneSkeleton` as the `.beats.json` sidecar. Production
/// uses `OllamaBeatExtractor` (gemma4_2b with the schema from
/// `BeatExtraction.jsonSchema`); tests inject a stub.
///
/// Mirrors `ReferenceIngestPipeline` shape and the Phase 4 ledger-
/// extractor async-callback pattern. Per the
/// [`feedback_tdd_async_callbacks`](memory/feedback_tdd_async_callbacks.md)
/// memory, the stub MUST defer its completion call — synchronous
/// completion masks lifetime / `[weak self]` bugs that only manifest
/// against a real async URLSession callback.
func phase7BeatExtractionPipelineTests() -> TestSuite {
    let s = TestSuite("Phase7BeatExtractionPipeline")

    func makeTempProject() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("loom-extract-pipeline-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Stub extractor that records the prompt it was given and
    /// returns a canned skeleton on a deferred main-queue hop.
    final class StubBeatExtractor: BeatExtractor {
        var capturedProse: String?
        let cannedResult: Result<ExtractedSceneSkeleton, Error>
        private var pending: [(Result<ExtractedSceneSkeleton, Error>, (Result<ExtractedSceneSkeleton, Error>) -> Void)] = []

        init(returns result: Result<ExtractedSceneSkeleton, Error>) {
            self.cannedResult = result
        }

        func extractSkeleton(
            from sourceProse: String,
            completion: @escaping (Result<ExtractedSceneSkeleton, Error>) -> Void
        ) {
            self.capturedProse = sourceProse
            // Defer the completion to model real async behaviour.
            pending.append((cannedResult, completion))
        }

        /// Drain pending completions. Tests call this after invoking
        /// the pipeline so they run in a deterministic order.
        func flush() {
            for (r, c) in pending { c(r) }
            pending.removeAll()
        }
    }

    func sampleSkeleton() -> ExtractedSceneSkeleton {
        ExtractedSceneSkeleton(
            beats: [
                SceneBeat(
                    index: 0, summary: "{PROTAGONIST} arrives.",
                    modality: .action, function: .arrival,
                    targetWords: 80, wordRangeStart: 0, wordRangeEnd: 80,
                    beatTensionChange: 1
                ),
                SceneBeat(
                    index: 1, summary: "{PROTAGONIST} discovers the truth.",
                    modality: .interiority, function: .reveal,
                    targetWords: 120, wordRangeStart: 80, wordRangeEnd: 200,
                    beatTensionChange: 2
                ),
            ],
            sourceCharacters: ["Alex"],
            sourceSettingMarkers: ["forest"]
        )
    }

    s.test("BeatExtractionPipeline.extractAndPersist writes the .beats.json sidecar on success") {
        let projectURL = makeTempProject()
        defer { try? FileManager.default.removeItem(at: projectURL) }
        let template = TemplateScene(id: UUID(), name: "test", body: "She walked into the forest.")
        try TemplateSceneStorage.saveTemplate(template, in: projectURL)

        let stub = StubBeatExtractor(returns: .success(sampleSkeleton()))
        let pipeline = BeatExtractionPipeline(projectURL: projectURL, extractor: stub)

        var receivedResult: Result<ExtractedSceneSkeleton, Error>? = nil
        pipeline.extractAndPersist(templateId: template.id) { result in
            receivedResult = result
        }
        // Completion deferred; not yet called.
        try expectTrue(receivedResult == nil)
        // Verify the extractor saw the template body.
        try expectEqual(stub.capturedProse, "She walked into the forest.")
        // Flush the deferred completion.
        stub.flush()
        try expectNotNil(receivedResult)

        // Sidecar written on disk.
        let onDisk = TemplateSceneStorage.loadSkeleton(for: template.id, in: projectURL)
        try expectNotNil(onDisk)
        try expectEqual(onDisk?.beats.count, 2)
        try expectEqual(onDisk?.sourceCharacters, ["Alex"])
    }

    s.test("BeatExtractionPipeline propagates extractor errors without writing sidecar") {
        let projectURL = makeTempProject()
        defer { try? FileManager.default.removeItem(at: projectURL) }
        let template = TemplateScene(id: UUID(), name: "test", body: "body")
        try TemplateSceneStorage.saveTemplate(template, in: projectURL)

        struct CannedError: Error, Equatable { let msg: String }
        let stub = StubBeatExtractor(returns: .failure(CannedError(msg: "ollama timeout")))
        let pipeline = BeatExtractionPipeline(projectURL: projectURL, extractor: stub)

        var receivedResult: Result<ExtractedSceneSkeleton, Error>? = nil
        pipeline.extractAndPersist(templateId: template.id) { result in
            receivedResult = result
        }
        stub.flush()

        // Error propagated.
        if case .failure(let err) = receivedResult {
            try expectTrue(String(describing: err).contains("ollama timeout"))
        } else {
            try expectFalse(true, "expected failure, got success")
        }
        // Sidecar NOT written.
        try expectTrue(TemplateSceneStorage.loadSkeleton(for: template.id, in: projectURL) == nil)
    }

    s.test("BeatExtractionPipeline returns failure when template id is stale") {
        let projectURL = makeTempProject()
        defer { try? FileManager.default.removeItem(at: projectURL) }
        let stub = StubBeatExtractor(returns: .success(sampleSkeleton()))
        let pipeline = BeatExtractionPipeline(projectURL: projectURL, extractor: stub)

        var receivedResult: Result<ExtractedSceneSkeleton, Error>? = nil
        pipeline.extractAndPersist(templateId: UUID()) { result in
            receivedResult = result
        }
        // No deferred work — failed synchronously at template-load step.
        try expectNotNil(receivedResult)
        if case .success = receivedResult {
            try expectFalse(true, "expected failure for stale template id")
        }
    }

    return s
}

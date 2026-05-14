import Foundation
@testable import LoomCore

/// Disk + composition tests for Phase 5 production's query-side
/// retrieval. RetrievalService mirrors ReferenceIngestPipeline:
/// ingest writes (.md + .index sidecars), retrieval reads them.
///
/// Operation per query:
/// 1. Embed query via injected D EmbeddingClient (production:
///    `PythonEmbeddingClient` running Wegmann per Phase 8.a §6.1).
/// 2. Re-fit FuncwordZ across all project chunks (cheap; corpus is
///    small) and transform the query.
/// 3. Per-path rank chunks by cosine.
/// 4. RRF-merge per [`LOOM_RAG_SPIKE.md`](LOOM_RAG_SPIKE.md) §13.8 —
///    `k=10`, equal weights.
/// 5. Optionally filter by modality before retrieval.
///
/// Tests use stubbed D EmbeddingClient + a tiny on-disk corpus.
func phase5RetrievalServiceTests() -> TestSuite {
    let s = TestSuite("Phase5RetrievalService")

    func makeTempProject() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("loom-retrieval-test-\(UUID().uuidString).loom")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Deterministic stub embedder — emits a length-based vector
    /// per text (3-d). Lengths of "She walked the long road" and
    /// "She walked the long road and looked at the sea" differ, so
    /// query embedded the same as a stored chunk will cosine-match
    /// it. Tests assert ordering, not absolute values.
    struct StubD: EmbeddingClient {
        let modelId: String = "stub/D"
        let dim: Int = 3
        func embed(_ text: String) -> EmbeddingVector? {
            let words = text.split(whereSeparator: { $0.isWhitespace }).count
            return EmbeddingVector(values: [
                Float(words),
                Float(text.count),
                Float(text.filter { $0.isLetter }.count)
            ])
        }
    }

    let stubLLM: (String) -> NarrativeMode? = { _ in .action }

    func bootstrapProject() throws -> (URL, UUID, UUID) {
        let projectURL = makeTempProject()
        let id1 = UUID(), id2 = UUID()
        try ReferenceStorage.saveReference(
            ReferenceText(id: id1, name: "ref-1",
                          body: "She walked into the kitchen and looked at the cat.\nThe cat looked back."),
            in: projectURL
        )
        try ReferenceStorage.saveReference(
            ReferenceText(id: id2, name: "ref-2",
                          body: "He stepped onto the boat.\nThe water was rough.\nHe held the rail."),
            in: projectURL
        )
        let pipeline = ReferenceIngestPipeline(
            projectURL: projectURL,
            chunkSize: 100, chunkOverlap: 0,
            dClient: StubD(),
            modalityLLM: stubLLM
        )
        try pipeline.chunkAndEmbedD(referenceId: id1)
        try pipeline.chunkAndEmbedD(referenceId: id2)
        try pipeline.refitAllEVectors()
        return (projectURL, id1, id2)
    }

    // MARK: - Basic retrieval

    s.test("retrieve returns top-K StyleExemplars with reference metadata") {
        let (projectURL, _, _) = try bootstrapProject()
        defer { try? FileManager.default.removeItem(at: projectURL) }

        let service = RetrievalService(projectURL: projectURL, dClient: StubD())
        let results = try service.retrieve(query: "She walked into the kitchen.", topK: 2)
        try expectEqual(results.count, 2)
        for r in results {
            try expectFalse(r.text.isEmpty)
            try expectFalse(r.referenceName.isEmpty)
            // Modality is set by the pipeline; stubLLM returns
            // .action and there are no quotes → action.
            try expectEqual(r.modality, .action)
        }
    }

    s.test("retrieve on an empty project returns empty (no error)") {
        let projectURL = makeTempProject()
        defer { try? FileManager.default.removeItem(at: projectURL) }
        let service = RetrievalService(projectURL: projectURL, dClient: StubD())
        let results = try service.retrieve(query: "anything", topK: 3)
        try expectEqual(results.count, 0)
    }

    s.test("retrieve with topK larger than corpus returns all chunks") {
        let (projectURL, _, _) = try bootstrapProject()
        defer { try? FileManager.default.removeItem(at: projectURL) }

        let service = RetrievalService(projectURL: projectURL, dClient: StubD())
        let allResults = try service.retrieve(query: "anything", topK: 1000)
        // Both refs together: 2 chunks + 3 chunks = 5 (depends on chunker).
        try expectTrue(allResults.count >= 2 && allResults.count <= 10)
    }

    // MARK: - Modality filter

    s.test("retrieve(modalityFilter:) restricts to chunks matching the modality") {
        // Bootstrap a project where some chunks are dialogue and some
        // are action. Dialogue-only retrieval should return only
        // dialogue chunks.
        let projectURL = makeTempProject()
        defer { try? FileManager.default.removeItem(at: projectURL) }

        let dialogueId = UUID()
        try ReferenceStorage.saveReference(
            ReferenceText(id: dialogueId, name: "all dialogue",
                          body: "\"Stop,\" she said.\n\n\"I will not.\"\n\n\"Then leave.\""),
            in: projectURL
        )
        let actionId = UUID()
        try ReferenceStorage.saveReference(
            ReferenceText(id: actionId, name: "all action",
                          body: "She walked the road. He stood in the door. They moved together."),
            in: projectURL
        )
        let pipeline = ReferenceIngestPipeline(
            projectURL: projectURL,
            chunkSize: 100, chunkOverlap: 0,
            dClient: StubD(),
            modalityLLM: stubLLM
        )
        try pipeline.chunkAndEmbedD(referenceId: dialogueId)
        try pipeline.chunkAndEmbedD(referenceId: actionId)
        try pipeline.refitAllEVectors()

        let service = RetrievalService(projectURL: projectURL, dClient: StubD())

        let dialogueResults = try service.retrieve(
            query: "anything", modalityFilter: .dialogue, topK: 10
        )
        try expectTrue(dialogueResults.count > 0)
        for r in dialogueResults {
            try expectEqual(r.modality, .dialogue)
        }

        let actionResults = try service.retrieve(
            query: "anything", modalityFilter: .action, topK: 10
        )
        try expectTrue(actionResults.count > 0)
        for r in actionResults {
            try expectEqual(r.modality, .action)
        }
    }

    s.test("retrieve(modalityFilter: .mixed) does NOT filter (mixed = wildcard)") {
        // Per the LOOM_NARRATIVE_MODE_SPIKE.md §2 schema decision,
        // `mixed` means "the classifier was uncertain". Treating it
        // as a queryable category at retrieval time would surface
        // these as preferred matches, which is wrong — they should
        // remain available but not preferentially retrieved.
        // Production semantics: modalityFilter: .mixed is a no-op
        // (returns all chunks).
        let (projectURL, _, _) = try bootstrapProject()
        defer { try? FileManager.default.removeItem(at: projectURL) }

        let service = RetrievalService(projectURL: projectURL, dClient: StubD())
        let mixedAll = try service.retrieve(query: "anything", modalityFilter: .mixed, topK: 100)
        let unfiltered = try service.retrieve(query: "anything", modalityFilter: nil, topK: 100)
        try expectEqual(mixedAll.count, unfiltered.count)
    }

    // MARK: - Robustness

    s.test("retrieve on references missing .index sidecars skips them gracefully") {
        // Edge case: user saved a reference (.md) but ingest hasn't
        // run yet — no sidecar. Retrieval should return results from
        // the references that DO have sidecars, not crash.
        let (projectURL, _, _) = try bootstrapProject()
        defer { try? FileManager.default.removeItem(at: projectURL) }

        let orphanId = UUID()
        try ReferenceStorage.saveReference(
            ReferenceText(id: orphanId, name: "no-index-yet", body: "Some body."),
            in: projectURL
        )
        // No chunkAndEmbedD for orphanId — sidecar missing.

        let service = RetrievalService(projectURL: projectURL, dClient: StubD())
        let results = try service.retrieve(query: "anything", topK: 100)
        // No orphanId in the results (it has no chunks indexed).
        try expectFalse(results.contains { $0.referenceId == orphanId })
    }

    s.test("retrieve gracefully proceeds when D embedding for the query fails") {
        // Production: MLX model load failure or transient error.
        // Service should still attempt E-only retrieval — the
        // hybrid degrades to single-path.
        let (projectURL, _, _) = try bootstrapProject()
        defer { try? FileManager.default.removeItem(at: projectURL) }

        struct FailingD: EmbeddingClient {
            let modelId: String = "fail/D"
            let dim: Int = 3
            func embed(_ text: String) -> EmbeddingVector? { nil }
        }

        let service = RetrievalService(projectURL: projectURL, dClient: FailingD())
        let results = try service.retrieve(query: "anything", topK: 3)
        // E-only retrieval still works.
        try expectTrue(results.count > 0)
    }

    s.test("retrieve gracefully proceeds when refs have no eVec yet (E pending)") {
        // Edge case: chunkAndEmbedD ran but refitAllEVectors hasn't.
        // The hybrid degrades to D-only.
        let projectURL = makeTempProject()
        defer { try? FileManager.default.removeItem(at: projectURL) }

        let id1 = UUID()
        try ReferenceStorage.saveReference(
            ReferenceText(id: id1, name: "x",
                          body: "She walked the road. He stood in the door."),
            in: projectURL
        )
        let pipeline = ReferenceIngestPipeline(
            projectURL: projectURL,
            chunkSize: 100, chunkOverlap: 0,
            dClient: StubD(),
            modalityLLM: stubLLM
        )
        try pipeline.chunkAndEmbedD(referenceId: id1)
        // No refitAllEVectors — eVec is nil throughout.

        let service = RetrievalService(projectURL: projectURL, dClient: StubD())
        let results = try service.retrieve(query: "She walked", topK: 3)
        try expectTrue(results.count > 0)
    }

    return s
}

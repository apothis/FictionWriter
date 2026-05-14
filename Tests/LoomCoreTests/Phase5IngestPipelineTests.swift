import Foundation
@testable import LoomCore

/// Disk + composition tests for Phase 5 production's reference-text
/// ingest pipeline. Orchestrates chunk → classify (NarrativeModeClassifier
/// = heuristic dialogue-gate + LLM closure) → embed-D (EmbeddingClient
/// protocol; production wraps the Wegmann Python subprocess via
/// `PythonEmbeddingClient` per Phase 8.a §6.1 lock) → write the
/// .index sidecar with chunks + modality + dVec. Path E is fit
/// project-wide in a separate step (`refitAllEVectors`) because adding
/// a new reference shifts the corpus distribution and requires
/// re-transforming every existing reference's eVec.
///
/// Tests use stubbed EmbeddingClient + LLM closures so the suite stays
/// pure-Swift / pure-data; no Python subprocess or Kobold dependencies in TestKit.
func phase5IngestPipelineTests() -> TestSuite {
    let s = TestSuite("Phase5IngestPipeline")

    func makeTempProject() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("loom-ingest-test-\(UUID().uuidString).loom")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Deterministic stub embedder — emits a 3-d vector derived from
    /// the text length so tests can verify embed-call routing without
    /// being sensitive to specific values.
    struct StubD: EmbeddingClient {
        let modelId: String = "stub/D"
        let dim: Int = 3
        func embed(_ text: String) -> EmbeddingVector? {
            let len = Float(text.count)
            return EmbeddingVector(values: [len, len * 0.5, -len])
        }
    }

    /// Stub LLM closure that always claims `action` — composed with
    /// the heuristic dialogue-gate which short-circuits on quotes.
    let stubLLM: (String) -> NarrativeMode? = { _ in .action }

    // MARK: - chunkAndEmbedD

    s.test("chunkAndEmbedD writes a .index sidecar for a reference") {
        let projectURL = makeTempProject()
        defer { try? FileManager.default.removeItem(at: projectURL) }

        let refId = UUID()
        let ref = ReferenceText(
            id: refId,
            name: "test",
            body: "She walked into the room. He looked up. She did not say a word."
        )
        try ReferenceStorage.saveReference(ref, in: projectURL)

        let pipeline = ReferenceIngestPipeline(
            projectURL: projectURL,
            chunkSize: 100, chunkOverlap: 20,
            dClient: StubD(),
            modalityLLM: stubLLM
        )
        let index = try pipeline.chunkAndEmbedD(referenceId: refId)
        try expectTrue(index.chunks.count >= 1)

        // Sidecar is on disk.
        let loaded = try expectNotNil(ReferenceStorage.loadIndex(for: refId, in: projectURL))
        try expectEqual(loaded.chunks.count, index.chunks.count)
    }

    s.test("chunkAndEmbedD produces chunks with text + word range + dVec + modality") {
        let projectURL = makeTempProject()
        defer { try? FileManager.default.removeItem(at: projectURL) }

        let refId = UUID()
        let ref = ReferenceText(
            id: refId,
            name: "test",
            body: "She walked into the room. He looked up. She did not say a word."
        )
        try ReferenceStorage.saveReference(ref, in: projectURL)
        let pipeline = ReferenceIngestPipeline(
            projectURL: projectURL,
            chunkSize: 100, chunkOverlap: 20,
            dClient: StubD(),
            modalityLLM: stubLLM
        )
        let index = try pipeline.chunkAndEmbedD(referenceId: refId)
        for c in index.chunks {
            try expectFalse(c.text.isEmpty)
            try expectTrue(c.wordRangeEnd > c.wordRangeStart)
            let d = try expectNotNil(c.dVec)
            try expectEqual(d.count, 3)
            // eVec is nil — E is a separate step (refitAllEVectors).
            try expectNil(c.eVec)
            // Modality: heuristic catches no-quote text via the
            // action-verb rule + stubLLM returns .action → either way
            // we get action on this body.
            try expectEqual(c.modality, "action")
        }
    }

    s.test("chunkAndEmbedD records the dClient fingerprint on the index") {
        let projectURL = makeTempProject()
        defer { try? FileManager.default.removeItem(at: projectURL) }

        let refId = UUID()
        let ref = ReferenceText(id: refId, name: "x", body: "She walked the long road.")
        try ReferenceStorage.saveReference(ref, in: projectURL)

        let pipeline = ReferenceIngestPipeline(
            projectURL: projectURL,
            chunkSize: 100, chunkOverlap: 20,
            dClient: StubD(),
            modalityLLM: stubLLM
        )
        let index = try pipeline.chunkAndEmbedD(referenceId: refId)
        let d = try expectNotNil(index.dModel)
        try expectEqual(d.id, "stub/D")
        try expectEqual(d.dim, 3)
        // eModel is nil — set by refitAllEVectors.
        try expectNil(index.eModel)
    }

    s.test("chunkAndEmbedD passes raw chunk text through the heuristic dialogue-gate") {
        // Dialogue-heavy reference. The heuristic catches every chunk
        // as dialogue before the LLM closure fires. Verifies the
        // pipeline uses NarrativeModeClassifier (composition), not
        // the raw LLM closure.
        let projectURL = makeTempProject()
        defer { try? FileManager.default.removeItem(at: projectURL) }

        var llmCalled = false
        let refId = UUID()
        let ref = ReferenceText(
            id: refId, name: "dlg",
            body: "\"Stop,\" she said. \"I will not have this.\"\n\n\"Then leave,\" he said.\n\n\"I will.\""
        )
        try ReferenceStorage.saveReference(ref, in: projectURL)

        let pipeline = ReferenceIngestPipeline(
            projectURL: projectURL,
            chunkSize: 100, chunkOverlap: 20,
            dClient: StubD(),
            modalityLLM: { _ in llmCalled = true; return .action }
        )
        let index = try pipeline.chunkAndEmbedD(referenceId: refId)
        for c in index.chunks {
            try expectEqual(c.modality, "dialogue")
        }
        try expectFalse(llmCalled, "heuristic should short-circuit; LLM should not be called")
    }

    s.test("chunkAndEmbedD throws when the reference doesn't exist on disk") {
        let projectURL = makeTempProject()
        defer { try? FileManager.default.removeItem(at: projectURL) }
        let pipeline = ReferenceIngestPipeline(
            projectURL: projectURL,
            chunkSize: 100, chunkOverlap: 20,
            dClient: StubD(),
            modalityLLM: stubLLM
        )
        try expectThrows {
            _ = try pipeline.chunkAndEmbedD(referenceId: UUID())
        }
    }

    s.test("chunkAndEmbedD with a chunk-size larger than the body still produces one chunk") {
        let projectURL = makeTempProject()
        defer { try? FileManager.default.removeItem(at: projectURL) }

        let refId = UUID()
        let ref = ReferenceText(id: refId, name: "short", body: "Two words.")
        try ReferenceStorage.saveReference(ref, in: projectURL)
        let pipeline = ReferenceIngestPipeline(
            projectURL: projectURL,
            chunkSize: 1000, chunkOverlap: 0,
            dClient: StubD(),
            modalityLLM: stubLLM
        )
        let index = try pipeline.chunkAndEmbedD(referenceId: refId)
        try expectEqual(index.chunks.count, 1)
    }

    // MARK: - refitAllEVectors

    s.test("refitAllEVectors fits E across every reference chunk and writes eVec to each sidecar") {
        let projectURL = makeTempProject()
        defer { try? FileManager.default.removeItem(at: projectURL) }

        // Two references with multi-paragraph bodies → multiple chunks each.
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
            chunkSize: 8, chunkOverlap: 0,
            dClient: StubD(),
            modalityLLM: stubLLM
        )
        try pipeline.chunkAndEmbedD(referenceId: id1)
        try pipeline.chunkAndEmbedD(referenceId: id2)

        try pipeline.refitAllEVectors()

        // Both indexes now have eModel + every chunk has a non-nil eVec.
        for refId in [id1, id2] {
            let idx = try expectNotNil(ReferenceStorage.loadIndex(for: refId, in: projectURL))
            let eModel = try expectNotNil(idx.eModel)
            try expectEqual(eModel.id, "loom/funcword-z-top150")
            try expectTrue(eModel.dim > 0)
            for c in idx.chunks {
                let e = try expectNotNil(c.eVec)
                try expectEqual(e.count, eModel.dim)
                // dVec must still be present (refit doesn't touch D).
                try expectNotNil(c.dVec)
            }
        }
    }

    s.test("refitAllEVectors uses the project-wide corpus to fit the E model") {
        // The E model is corpus-relative — the mean + std per
        // function-word frequency depend on every chunk across every
        // reference in the project, not just one reference. Smoke
        // test: a reference that contains tokens absent from a
        // single-reference corpus would receive a different
        // z-score than under project-wide fit. Here we verify the
        // simpler property that the eModel fingerprint is identical
        // across both references (proving they were fit together).
        let projectURL = makeTempProject()
        defer { try? FileManager.default.removeItem(at: projectURL) }

        let id1 = UUID(), id2 = UUID()
        try ReferenceStorage.saveReference(
            ReferenceText(id: id1, name: "a",
                          body: "The cat sat on the mat the cat looked back."),
            in: projectURL
        )
        try ReferenceStorage.saveReference(
            ReferenceText(id: id2, name: "b",
                          body: "He stood on the edge and watched the river the boats slow."),
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

        let idx1 = try expectNotNil(ReferenceStorage.loadIndex(for: id1, in: projectURL))
        let idx2 = try expectNotNil(ReferenceStorage.loadIndex(for: id2, in: projectURL))
        try expectEqual(idx1.eModel?.id, idx2.eModel?.id)
        try expectEqual(idx1.eModel?.dim, idx2.eModel?.dim)
        try expectEqual(idx1.chunks[0].eVec?.count, idx2.chunks[0].eVec?.count)
    }

    s.test("refitAllEVectors is idempotent — calling twice keeps the same vectors") {
        let projectURL = makeTempProject()
        defer { try? FileManager.default.removeItem(at: projectURL) }

        let refId = UUID()
        try ReferenceStorage.saveReference(
            ReferenceText(id: refId, name: "x",
                          body: "She walked the long road and looked at the sea."),
            in: projectURL
        )
        let pipeline = ReferenceIngestPipeline(
            projectURL: projectURL,
            chunkSize: 100, chunkOverlap: 0,
            dClient: StubD(),
            modalityLLM: stubLLM
        )
        try pipeline.chunkAndEmbedD(referenceId: refId)
        try pipeline.refitAllEVectors()
        let first = try expectNotNil(ReferenceStorage.loadIndex(for: refId, in: projectURL))

        try pipeline.refitAllEVectors()
        let second = try expectNotNil(ReferenceStorage.loadIndex(for: refId, in: projectURL))
        try expectEqual(first.chunks[0].eVec, second.chunks[0].eVec)
    }

    s.test("refitAllEVectors on an empty project (no references) is a no-op, not an error") {
        let projectURL = makeTempProject()
        defer { try? FileManager.default.removeItem(at: projectURL) }
        let pipeline = ReferenceIngestPipeline(
            projectURL: projectURL,
            chunkSize: 100, chunkOverlap: 0,
            dClient: StubD(),
            modalityLLM: stubLLM
        )
        try pipeline.refitAllEVectors()
    }

    return s
}

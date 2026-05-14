import Foundation
@testable import LoomCore

// Phase 8.b.5 — modality-filter fallback. Per design §6.3:
//
//   "Different modality → fall-back candidate (only if no better
//    matches). Test the fallback: when zero chunks match modality,
//    the filter degenerates to unfiltered top-K."
//
// The hard-filter behaviour from Phase 5 stays the dominant path —
// when at least one chunk matches the preferred modality, only
// matching chunks are returned. When NO chunks match, retrieval
// gracefully degrades to unfiltered top-K rather than returning [].

private final class StubD: EmbeddingClient {
    var modelId: String { "stub-d" }
    var dim: Int { 4 }
    func embed(_ text: String) -> EmbeddingVector? {
        let hash = abs(text.hashValue)
        return EmbeddingVector(values: [
            Float((hash >> 0) & 0xFF), Float((hash >> 8) & 0xFF),
            Float((hash >> 16) & 0xFF), Float((hash >> 24) & 0xFF),
        ])
    }
}

private func stubLLM(_ text: String) -> NarrativeMode? { nil }

func phase8RetrievalModalityFallbackTests() -> TestSuite {
    let s = TestSuite("Phase8RetrievalModalityFallback")

    s.test("retrieve(modalityFilter:) falls back to unfiltered when zero chunks match") {
        // Project has ONLY action chunks. Filter by .dialogue should
        // produce zero strict matches → fallback returns all action
        // chunks rather than [].
        let projectURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("loom-mod-fallback-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: projectURL) }

        let refId = UUID()
        try ReferenceStorage.saveReference(
            ReferenceText(id: refId, name: "all-action",
                          body: "She walked the road. He stood in the door. They moved together."),
            in: projectURL
        )
        let pipeline = ReferenceIngestPipeline(
            projectURL: projectURL, chunkSize: 100, chunkOverlap: 0,
            dClient: StubD(), modalityLLM: stubLLM
        )
        try pipeline.chunkAndEmbedD(referenceId: refId)
        try pipeline.refitAllEVectors()

        let service = RetrievalService(projectURL: projectURL, dClient: StubD())

        // Confirm action chunks exist (sanity).
        let actionResults = try service.retrieve(
            query: "anything", modalityFilter: .action, topK: 10
        )
        try expectTrue(actionResults.count > 0)

        // Now filter by dialogue. Without fallback, expect []. With
        // fallback (Phase 8.b.5 behaviour), expect the action chunks.
        let fallbackResults = try service.retrieve(
            query: "anything", modalityFilter: .dialogue, topK: 10
        )
        try expectTrue(fallbackResults.count > 0,
                       "fallback should yield action chunks when dialogue is unavailable")
    }

    s.test("when chunks DO match modality, fallback is NOT invoked (strict-filter behaviour preserved)") {
        let projectURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("loom-mod-strict-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: projectURL) }

        let dialogueId = UUID()
        try ReferenceStorage.saveReference(
            ReferenceText(id: dialogueId, name: "dialogue",
                          body: "\"Stop,\" she said.\n\n\"I will not.\"\n\n\"Then leave.\""),
            in: projectURL
        )
        let actionId = UUID()
        try ReferenceStorage.saveReference(
            ReferenceText(id: actionId, name: "action",
                          body: "She walked the road. He stood. They moved."),
            in: projectURL
        )
        let pipeline = ReferenceIngestPipeline(
            projectURL: projectURL, chunkSize: 100, chunkOverlap: 0,
            dClient: StubD(), modalityLLM: stubLLM
        )
        try pipeline.chunkAndEmbedD(referenceId: dialogueId)
        try pipeline.chunkAndEmbedD(referenceId: actionId)
        try pipeline.refitAllEVectors()

        let service = RetrievalService(projectURL: projectURL, dClient: StubD())
        let dialogueOnly = try service.retrieve(
            query: "anything", modalityFilter: .dialogue, topK: 10
        )
        // Action chunks must NOT appear when dialogue chunks are
        // available — strict-filter wins over fallback.
        try expectTrue(dialogueOnly.count > 0)
        for r in dialogueOnly {
            try expectEqual(r.modality, .dialogue)
        }
    }

    return s
}

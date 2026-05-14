import Foundation
@testable import LoomCore

// Phase 8.a §6.1 — orchestrator that wraps an arbitrary `SpikeEmbedder`,
// iterates the fixtures, builds the cosine matrix, and computes the
// register-axis and style-axis separation scores. Pure-data over the
// embedder protocol: the production embedders (Python subprocess for
// sentence-transformers models, HTTP for Ollama) plug in via the
// protocol, but here we test against a stub.

private struct StubEmbedder: SpikeEmbedder {
    let id: String
    let vectors: [String: EmbeddingVector]
    func embed(_ text: String) -> EmbeddingVector? {
        // The stub keys by text prefix so test fixtures can use distinctive bodies.
        for (key, vec) in vectors where text.hasPrefix(key) {
            return vec
        }
        return nil
    }
}

private func fixture(_ id: String, nsfw: Bool, register: String, styleAxis: String, body: String) -> SceneExemplarFixture {
    return SceneExemplarFixture(
        id: id, title: id, nsfw: nsfw,
        register: register, styleAxis: styleAxis,
        body: body
    )
}

func phase8SpikeOrchestratorTests() -> TestSuite {
    let s = TestSuite("Phase8SpikeOrchestrator")

    s.test("cosineMatrix returns matrix in fixture-id order") {
        let fixtures = [
            fixture("a1", nsfw: true, register: "explicit-direct", styleAxis: "explicit-direct", body: "A1 body"),
            fixture("a2", nsfw: true, register: "explicit-direct", styleAxis: "explicit-direct", body: "A2 body"),
            fixture("b1", nsfw: true, register: "clinical", styleAxis: "clinical", body: "B1 body"),
        ]
        let stub = StubEmbedder(id: "stub", vectors: [
            "A1 body": EmbeddingVector(values: [1, 0]),
            "A2 body": EmbeddingVector(values: [1, 0]),
            "B1 body": EmbeddingVector(values: [0, 1]),
        ])

        let result = try SpikeOrchestrator.cosineMatrix(
            fixtures: fixtures, embedder: stub
        )
        try expectEqual(result.matrix.labels, ["a1", "a2", "b1"])
        try expectEqual(result.matrix.values.count, 3)
        // (a1, a2) same direction → 1.0
        try expectTrue(abs(result.matrix.values[0][1] - 1.0) < 1e-5)
        // (a1, b1) orthogonal → 0.0
        try expectTrue(abs(result.matrix.values[0][2]) < 1e-6)
    }

    s.test("cosineMatrix computes register-axis and style-axis separation scores") {
        // 4 fixtures: 2 explicit-direct (same axis), 2 clinical (same axis).
        // Vectors set up so register-axis separation = 1.0.
        let fixtures = [
            fixture("ed1", nsfw: true, register: "explicit-direct", styleAxis: "explicit-direct", body: "ED1"),
            fixture("ed2", nsfw: true, register: "explicit-direct", styleAxis: "explicit-direct", body: "ED2"),
            fixture("cl1", nsfw: true, register: "clinical", styleAxis: "clinical", body: "CL1"),
            fixture("cl2", nsfw: true, register: "clinical", styleAxis: "clinical", body: "CL2"),
        ]
        let stub = StubEmbedder(id: "stub", vectors: [
            "ED1": EmbeddingVector(values: [1, 0]),
            "ED2": EmbeddingVector(values: [1, 0]),
            "CL1": EmbeddingVector(values: [0, 1]),
            "CL2": EmbeddingVector(values: [0, 1]),
        ])
        let result = try SpikeOrchestrator.cosineMatrix(
            fixtures: fixtures, embedder: stub
        )
        try expectTrue(abs(result.registerScore.separation - 1.0) < 1e-5,
                       "register separation = \(result.registerScore.separation)")
        try expectTrue(abs(result.styleAxisScore.separation - 1.0) < 1e-5,
                       "style_axis separation = \(result.styleAxisScore.separation)")
    }

    s.test("cosineMatrix throws when embedder returns nil for any fixture") {
        let fixtures = [
            fixture("ok", nsfw: true, register: "explicit-direct", styleAxis: "explicit-direct", body: "OK body"),
            fixture("bad", nsfw: true, register: "clinical", styleAxis: "clinical", body: "BAD body"),
        ]
        let stub = StubEmbedder(id: "stub", vectors: [
            "OK body": EmbeddingVector(values: [1, 0]),
            // "BAD body" intentionally absent → embedder returns nil
        ])
        try expectThrows {
            _ = try SpikeOrchestrator.cosineMatrix(
                fixtures: fixtures, embedder: stub
            )
        }
    }

    return s
}

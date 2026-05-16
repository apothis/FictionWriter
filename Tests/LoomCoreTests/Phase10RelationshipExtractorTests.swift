import Foundation
@testable import LoomCore

/// `OllamaRelationshipDiscoveryExtractor` — two-stage pairwise
/// classification: one bounded LLM call per co-occurring character
/// pair. Deferred-stub provider (per feedback_tdd_async_callbacks):
/// the stub queues completions, the test flushes them.
func phase10RelationshipExtractorTests() -> TestSuite {
    let s = TestSuite("Phase10RelationshipExtractor")

    final class StubProvider: OllamaCallProvider {
        struct Call {
            let prompt: String
            let options: OllamaChatOptions
            let completion: (Result<String, OllamaError>) -> Void
        }
        var queued: [Call] = []
        var cannedResponses: [Result<String, OllamaError>] = []

        func call(
            prompt: String,
            schema: [String: Any],
            options: OllamaChatOptions,
            completion: @escaping (Result<String, OllamaError>) -> Void
        ) {
            queued.append(Call(prompt: prompt, options: options, completion: completion))
        }

        /// Fire every queued call, in order, against the canned
        /// responses — the extractor fans out all pair calls before
        /// any complete.
        func flushAll() {
            while !queued.isEmpty, !cannedResponses.isEmpty {
                let call = queued.removeFirst()
                call.completion(cannedResponses.removeFirst())
            }
        }
    }

    /// One per-pair answer line: `from | to | kind | status`.
    func pairLine(_ from: String, _ to: String, _ kind: String, _ status: String) -> String {
        "\(from) | \(to) | \(kind) | \(status)"
    }

    let sceneId = UUID()

    s.test("happy path: one pair, one call, one proposal") {
        let stub = StubProvider()
        let extractor = OllamaRelationshipDiscoveryExtractor(provider: stub, votingRounds: 1)

        var captured: Result<[RelationshipDiscovery.ProposedRelationship], Error>?
        extractor.extract(
            scenePose: "Chantal kissed Muriel.",
            sceneId: sceneId,
            characterNames: ["Chantal", "Muriel"]
        ) { captured = $0 }

        try expectEqual(stub.queued.count, 1)
        stub.cannedResponses = [.success(pairLine("Chantal", "Muriel", "girlfriend", "current"))]
        stub.flushAll()

        let result = try expectNotNil(captured)
        guard case .success(let rels) = result else {
            throw TestFailure(message: "expected success, got \(result)", file: #file, line: #line)
        }
        try expectEqual(rels.count, 1)
        try expectEqual(rels[0].fromName, "Chantal")
        try expectEqual(rels[0].kind, "girlfriend")
    }

    s.test("three co-occurring characters fan out to three pair calls") {
        let stub = StubProvider()
        let extractor = OllamaRelationshipDiscoveryExtractor(provider: stub, votingRounds: 1)

        var captured: Result<[RelationshipDiscovery.ProposedRelationship], Error>?
        extractor.extract(
            scenePose: "Chantal, Muriel and Jacob were on the beach.",
            sceneId: sceneId,
            characterNames: ["Chantal", "Muriel", "Jacob"]
        ) { captured = $0 }

        // 3 pairs → 3 calls. Only the first finds a relationship.
        try expectEqual(stub.queued.count, 3)
        stub.cannedResponses = [
            .success(pairLine("Chantal", "Muriel", "girlfriend", "current")),
            .success("none"),
            .success("none"),
        ]
        stub.flushAll()

        let result = try expectNotNil(captured)
        guard case .success(let rels) = result else {
            throw TestFailure(message: "expected success", file: #file, line: #line)
        }
        try expectEqual(rels.count, 1)
        try expectEqual(rels[0].toName, "Muriel")
    }

    s.test("a pair answered 'none' contributes no edge") {
        let stub = StubProvider()
        let extractor = OllamaRelationshipDiscoveryExtractor(provider: stub, votingRounds: 1)

        var captured: Result<[RelationshipDiscovery.ProposedRelationship], Error>?
        extractor.extract(
            scenePose: "Chantal and Muriel passed on the street.",
            sceneId: sceneId,
            characterNames: ["Chantal", "Muriel"]
        ) { captured = $0 }

        stub.cannedResponses = [.success("none")]
        stub.flushAll()

        let result = try expectNotNil(captured)
        guard case .success(let rels) = result else {
            throw TestFailure(message: "expected success", file: #file, line: #line)
        }
        try expectEqual(rels.count, 0)
    }

    s.test("fewer than two characters → empty success, no Ollama call") {
        let stub = StubProvider()
        let extractor = OllamaRelationshipDiscoveryExtractor(provider: stub, votingRounds: 1)

        var captured: Result<[RelationshipDiscovery.ProposedRelationship], Error>?
        extractor.extract(
            scenePose: "Chantal was alone.", sceneId: sceneId, characterNames: ["Chantal"]
        ) { captured = $0 }

        try expectEqual(stub.queued.count, 0)
        let result = try expectNotNil(captured)
        guard case .success(let rels) = result, rels.isEmpty else {
            throw TestFailure(message: "expected empty success", file: #file, line: #line)
        }
    }

    s.test("no character pair co-occurs in the scene → empty success, no call") {
        let stub = StubProvider()
        let extractor = OllamaRelationshipDiscoveryExtractor(provider: stub, votingRounds: 1)

        var captured: Result<[RelationshipDiscovery.ProposedRelationship], Error>?
        // Both are bible characters but only one appears in this scene.
        extractor.extract(
            scenePose: "Chantal walked home alone.",
            sceneId: sceneId,
            characterNames: ["Chantal", "Muriel"]
        ) { captured = $0 }

        try expectEqual(stub.queued.count, 0)
        let result = try expectNotNil(captured)
        guard case .success(let rels) = result, rels.isEmpty else {
            throw TestFailure(message: "expected empty success", file: #file, line: #line)
        }
    }

    s.test("each pair call uses num_predict 2048 (preamble headroom)") {
        let stub = StubProvider()
        let extractor = OllamaRelationshipDiscoveryExtractor(provider: stub, votingRounds: 1)
        extractor.extract(
            scenePose: "Chantal and Muriel.", sceneId: sceneId,
            characterNames: ["Chantal", "Muriel"]
        ) { _ in }
        try expectEqual(stub.queued.count, 1)
        try expectEqual(stub.queued[0].options.numPredict, 2048)
    }

    s.test("duplicate edges within a pair answer collapse to one proposal") {
        let stub = StubProvider()
        let extractor = OllamaRelationshipDiscoveryExtractor(provider: stub, votingRounds: 1)

        var captured: Result<[RelationshipDiscovery.ProposedRelationship], Error>?
        extractor.extract(
            scenePose: "Chantal and Muriel.", sceneId: sceneId,
            characterNames: ["Chantal", "Muriel"]
        ) { captured = $0 }

        stub.cannedResponses = [.success(
            pairLine("Chantal", "Muriel", "girlfriend", "current") + "\n"
                + pairLine("Chantal", "Muriel", "girlfriend", "past")
        )]
        stub.flushAll()

        let result = try expectNotNil(captured)
        guard case .success(let rels) = result else {
            throw TestFailure(message: "expected success", file: #file, line: #line)
        }
        try expectEqual(rels.count, 1)
    }

    s.test("a partial transport failure still reports the pairs that succeeded") {
        let stub = StubProvider()
        let extractor = OllamaRelationshipDiscoveryExtractor(provider: stub, votingRounds: 1)

        var captured: Result<[RelationshipDiscovery.ProposedRelationship], Error>?
        extractor.extract(
            scenePose: "Chantal, Muriel and Jacob.",
            sceneId: sceneId,
            characterNames: ["Chantal", "Muriel", "Jacob"]
        ) { captured = $0 }

        // 3 pairs: one succeeds, two fail — the success still lands.
        stub.cannedResponses = [
            .success(pairLine("Chantal", "Muriel", "friend", "current")),
            .failure(OllamaError.unexpectedShape),
            .failure(OllamaError.unexpectedShape),
        ]
        stub.flushAll()

        let result = try expectNotNil(captured)
        guard case .success(let rels) = result else {
            throw TestFailure(message: "expected success despite partial failure", file: #file, line: #line)
        }
        try expectEqual(rels.count, 1)
    }

    // MARK: - self-consistency voting

    s.test("default votingRounds fires three calls per pair") {
        let stub = StubProvider()
        let extractor = OllamaRelationshipDiscoveryExtractor(provider: stub)
        extractor.extract(
            scenePose: "Chantal and Muriel.", sceneId: sceneId,
            characterNames: ["Chantal", "Muriel"]
        ) { _ in }
        try expectEqual(stub.queued.count, 3)
    }

    s.test("an edge a majority of rounds agree on survives the vote") {
        let stub = StubProvider()
        let extractor = OllamaRelationshipDiscoveryExtractor(provider: stub, votingRounds: 3)

        var captured: Result<[RelationshipDiscovery.ProposedRelationship], Error>?
        extractor.extract(
            scenePose: "Chantal kissed Muriel.", sceneId: sceneId,
            characterNames: ["Chantal", "Muriel"]
        ) { captured = $0 }

        try expectEqual(stub.queued.count, 3)
        stub.cannedResponses = [
            .success(pairLine("Chantal", "Muriel", "girlfriend", "current")),
            .success(pairLine("Chantal", "Muriel", "girlfriend", "current")),
            .success("none"),
        ]
        stub.flushAll()

        let result = try expectNotNil(captured)
        guard case .success(let rels) = result else {
            throw TestFailure(message: "expected success", file: #file, line: #line)
        }
        try expectEqual(rels.count, 1)
        try expectEqual(rels[0].kind, "girlfriend")
    }

    s.test("an edge only a minority of rounds find is voted out") {
        let stub = StubProvider()
        let extractor = OllamaRelationshipDiscoveryExtractor(provider: stub, votingRounds: 3)

        var captured: Result<[RelationshipDiscovery.ProposedRelationship], Error>?
        extractor.extract(
            scenePose: "Chantal passed Muriel.", sceneId: sceneId,
            characterNames: ["Chantal", "Muriel"]
        ) { captured = $0 }

        // gemma hallucinates an edge on one of three rounds — dropped.
        stub.cannedResponses = [
            .success(pairLine("Chantal", "Muriel", "sister", "current")),
            .success("none"),
            .success("none"),
        ]
        stub.flushAll()

        let result = try expectNotNil(captured)
        guard case .success(let rels) = result else {
            throw TestFailure(message: "expected success", file: #file, line: #line)
        }
        try expectEqual(rels.count, 0)
    }

    s.test("a total transport failure surfaces as a failure") {
        let stub = StubProvider()
        let extractor = OllamaRelationshipDiscoveryExtractor(provider: stub, votingRounds: 1)

        var captured: Result<[RelationshipDiscovery.ProposedRelationship], Error>?
        extractor.extract(
            scenePose: "Chantal and Muriel.", sceneId: sceneId,
            characterNames: ["Chantal", "Muriel"]
        ) { captured = $0 }

        stub.cannedResponses = [.failure(OllamaError.unexpectedShape)]
        stub.flushAll()

        let result = try expectNotNil(captured)
        if case .success = result {
            throw TestFailure(message: "expected failure on total outage", file: #file, line: #line)
        }
    }

    return s
}

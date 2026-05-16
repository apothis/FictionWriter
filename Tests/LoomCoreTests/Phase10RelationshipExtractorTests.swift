import Foundation
@testable import LoomCore

/// Phase 10 step 3 — `OllamaRelationshipDiscoveryExtractor`.
/// Deferred-stub provider (per feedback_tdd_async_callbacks): the
/// stub queues completions, the test flushes them.
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

        func flushNext() {
            guard !queued.isEmpty, !cannedResponses.isEmpty else { return }
            let call = queued.removeFirst()
            call.completion(cannedResponses.removeFirst())
        }
    }

    func relResponse(_ rels: [(String, String, String, String)]) -> String {
        let items = rels.map { r in
            "{\"from\":\"\(r.0)\",\"to\":\"\(r.1)\",\"kind\":\"\(r.2)\",\"status\":\"\(r.3)\",\"evidence_quote\":\"q\"}"
        }.joined(separator: ",")
        return "[\(items)]"
    }

    let sceneId = UUID()

    s.test("happy path: parses edges and reports them") {
        let stub = StubProvider()
        let extractor = OllamaRelationshipDiscoveryExtractor(provider: stub)

        var captured: Result<[RelationshipDiscovery.ProposedRelationship], Error>?
        extractor.extract(
            scenePose: "Chantal and Muriel and Jacob.",
            sceneId: sceneId,
            characterNames: ["Chantal", "Muriel", "Jacob"]
        ) { captured = $0 }

        stub.cannedResponses.append(.success(relResponse([
            ("Chantal", "Muriel", "girlfriend", "current"),
            ("Chantal", "Jacob", "ex-boyfriend", "past"),
        ])))
        stub.flushNext()

        let result = try expectNotNil(captured)
        guard case .success(let rels) = result else {
            throw TestFailure(message: "expected success, got \(result)", file: #file, line: #line)
        }
        try expectEqual(rels.count, 2)
        try expectEqual(rels[0].toName, "Muriel")
        try expectEqual(rels[0].status, .current)
        try expectEqual(rels[1].status, .past)
    }

    s.test("calls Ollama with num_predict 2048 (JSON-schema length-cap floor)") {
        let stub = StubProvider()
        let extractor = OllamaRelationshipDiscoveryExtractor(provider: stub)
        extractor.extract(
            scenePose: "x", sceneId: sceneId, characterNames: ["A", "B"]
        ) { _ in }
        try expectEqual(stub.queued.count, 1)
        try expectEqual(stub.queued[0].options.numPredict, 2048)
    }

    s.test("duplicate edges collapse to one proposal") {
        let stub = StubProvider()
        let extractor = OllamaRelationshipDiscoveryExtractor(provider: stub)

        var captured: Result<[RelationshipDiscovery.ProposedRelationship], Error>?
        extractor.extract(
            scenePose: "x", sceneId: sceneId, characterNames: ["Chantal", "Muriel"]
        ) { captured = $0 }

        stub.cannedResponses.append(.success(relResponse([
            ("Chantal", "Muriel", "girlfriend", "current"),
            ("Chantal", "Muriel", "girlfriend", "current"),
            ("Chantal", "Muriel", "girlfriend", "past"),
        ])))
        stub.flushNext()

        let result = try expectNotNil(captured)
        guard case .success(let rels) = result else {
            throw TestFailure(message: "expected success", file: #file, line: #line)
        }
        try expectEqual(rels.count, 1)
    }

    s.test("fewer than two characters → empty success, no Ollama call") {
        let stub = StubProvider()
        let extractor = OllamaRelationshipDiscoveryExtractor(provider: stub)

        var captured: Result<[RelationshipDiscovery.ProposedRelationship], Error>?
        extractor.extract(
            scenePose: "Solo scene.", sceneId: sceneId, characterNames: ["Chantal"]
        ) { captured = $0 }

        try expectEqual(stub.queued.count, 0)
        let result = try expectNotNil(captured)
        guard case .success(let rels) = result else {
            throw TestFailure(message: "expected success", file: #file, line: #line)
        }
        try expectEqual(rels.count, 0)
    }

    s.test("parse failure retries once, then recovers on clean retry") {
        let stub = StubProvider()
        let extractor = OllamaRelationshipDiscoveryExtractor(provider: stub)

        var captured: Result<[RelationshipDiscovery.ProposedRelationship], Error>?
        extractor.extract(
            scenePose: "x", sceneId: sceneId, characterNames: ["A", "B"]
        ) { captured = $0 }

        stub.cannedResponses.append(.success("no json array here"))
        stub.flushNext()
        // Retry fires automatically.
        stub.cannedResponses.append(.success(relResponse([("A", "B", "friend", "current")])))
        stub.flushNext()

        let result = try expectNotNil(captured)
        guard case .success(let rels) = result else {
            throw TestFailure(message: "expected success after retry", file: #file, line: #line)
        }
        try expectEqual(rels.count, 1)
    }

    s.test("transport error surfaces as failure") {
        let stub = StubProvider()
        let extractor = OllamaRelationshipDiscoveryExtractor(provider: stub)

        var captured: Result<[RelationshipDiscovery.ProposedRelationship], Error>?
        extractor.extract(
            scenePose: "x", sceneId: sceneId, characterNames: ["A", "B"]
        ) { captured = $0 }

        stub.cannedResponses.append(.failure(OllamaError.unexpectedShape))
        stub.flushNext()

        let result = try expectNotNil(captured)
        if case .success = result {
            throw TestFailure(message: "expected failure", file: #file, line: #line)
        }
    }

    return s
}

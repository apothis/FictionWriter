import Foundation
@testable import LoomCore

/// Phase 5 — `GLiNEREntityDiscoveryExtractor` orchestration: GLiNER
/// detection → shared filter + Stage D pipeline. Tests use deferred
/// stubs (per feedback_tdd_async_callbacks) — completions are queued
/// and flushed, never fired synchronously inside the stub.
func glinerEntityDiscoveryExtractorTests() -> TestSuite {
    let s = TestSuite("GLiNEREntityDiscoveryExtractor")

    final class StubDetector: EntityCandidateDetecting {
        var queued: [(Result<[EntityDiscovery.Candidate], Error>) -> Void] = []
        var canned: [Result<[EntityDiscovery.Candidate], Error>] = []
        var sceneCount = 0

        func detectCandidates(
            in scenePose: String,
            completion: @escaping (Result<[EntityDiscovery.Candidate], Error>) -> Void
        ) {
            sceneCount += 1
            queued.append(completion)
        }

        func flush() {
            while !queued.isEmpty, !canned.isEmpty {
                queued.removeFirst()(canned.removeFirst())
            }
        }
    }

    final class StubProvider: OllamaCallProvider {
        var queued: [(Result<String, OllamaError>) -> Void] = []
        var canned: [Result<String, OllamaError>] = []
        var callCount = 0
        var schemas: [[String: Any]] = []

        func call(
            prompt: String,
            schema: [String: Any],
            options: OllamaChatOptions,
            completion: @escaping (Result<String, OllamaError>) -> Void
        ) {
            callCount += 1
            schemas.append(schema)
            queued.append(completion)
        }

        func flush() {
            while !queued.isEmpty, !canned.isEmpty {
                queued.removeFirst()(canned.removeFirst())
            }
        }
    }

    func dResponse(kind: String, canonical: String) -> String {
        "{\"kind\":\"\(kind)\",\"canonical_name\":\"\(canonical)\","
            + "\"aliases\":[],\"one_line\":\"x\",\"evidence_quote\":\"x\"}"
    }

    let sceneId = UUID()

    s.test("happy path: GLiNER candidate → Stage D normalises → ProposedEntity") {
        let detector = StubDetector()
        let provider = StubProvider()
        let extractor = GLiNEREntityDiscoveryExtractor(detector: detector, provider: provider)

        var captured: Result<[EntityDiscovery.ProposedEntity], Error>?
        extractor.extract(
            scenePose: "Marek drew the dagger.",
            sceneId: sceneId,
            knownEntityNames: [],
            existingEntities: [],
            embedder: nil
        ) { captured = $0 }

        detector.canned = [.success([
            EntityDiscovery.Candidate(
                surface: "Marek", kind: .character,
                firstSeenQuote: "Marek drew the dagger."
            ),
        ])]
        detector.flush()
        provider.canned = [.success(dResponse(kind: "character", canonical: "Marek"))]
        provider.flush()

        let result = try expectNotNil(captured)
        guard case .success(let proposals) = result else {
            throw TestFailure(message: "expected success, got \(result)", file: #file, line: #line)
        }
        try expectEqual(proposals.count, 1)
        try expectEqual(proposals[0].canonicalName, "Marek")
        try expectEqual(proposals[0].kind, .character)
        try expectEqual(provider.callCount, 1)
    }

    s.test("Stage D call runs unconstrained — no format schema") {
        // Ollama's format-constrained sampling intermittently
        // degenerates on gemma4_2b — a truncated JSON object that
        // won't parse, and the survivor silently vanishes. Stage D
        // opts out (schema [:]) and pins the shape in-prompt instead.
        let detector = StubDetector()
        let provider = StubProvider()
        let extractor = GLiNEREntityDiscoveryExtractor(detector: detector, provider: provider)

        extractor.extract(
            scenePose: "Marek drew the dagger.",
            sceneId: sceneId,
            knownEntityNames: [],
            existingEntities: [],
            embedder: nil
        ) { _ in }

        detector.canned = [.success([
            EntityDiscovery.Candidate(
                surface: "Marek", kind: .character,
                firstSeenQuote: "Marek drew the dagger."
            ),
        ])]
        detector.flush()
        provider.canned = [.success(dResponse(kind: "character", canonical: "Marek"))]
        provider.flush()

        try expectEqual(provider.schemas.count, 1)
        try expectTrue(provider.schemas[0].isEmpty)
    }

    s.test("detector failure propagates to the caller, no Stage D call") {
        let detector = StubDetector()
        let provider = StubProvider()
        let extractor = GLiNEREntityDiscoveryExtractor(detector: detector, provider: provider)

        var captured: Result<[EntityDiscovery.ProposedEntity], Error>?
        extractor.extract(
            scenePose: "x", sceneId: sceneId, knownEntityNames: [],
            existingEntities: [], embedder: nil
        ) { captured = $0 }

        detector.canned = [.failure(GLiNERRuntime.RuntimeError.modelBundleMissing)]
        detector.flush()

        let result = try expectNotNil(captured)
        guard case .failure = result else {
            throw TestFailure(message: "expected failure", file: #file, line: #line)
        }
        try expectEqual(provider.callCount, 0)
    }

    s.test("zero candidates → empty proposals, no Stage D call") {
        let detector = StubDetector()
        let provider = StubProvider()
        let extractor = GLiNEREntityDiscoveryExtractor(detector: detector, provider: provider)

        var captured: Result<[EntityDiscovery.ProposedEntity], Error>?
        extractor.extract(
            scenePose: "x", sceneId: sceneId, knownEntityNames: [],
            existingEntities: [], embedder: nil
        ) { captured = $0 }

        detector.canned = [.success([])]
        detector.flush()

        let result = try expectNotNil(captured)
        guard case .success(let proposals) = result else {
            throw TestFailure(message: "expected success", file: #file, line: #line)
        }
        try expectEqual(proposals.count, 0)
        try expectEqual(provider.callCount, 0)
    }

    return s
}

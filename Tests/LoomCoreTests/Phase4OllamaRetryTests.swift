import Foundation
@testable import LoomCore

/// Phase 4 #7 reliability fix — when Ollama returns empty content
/// (the model hit immediate-EOS under JSON-Schema constraint), the
/// extractor adapter should retry once before surfacing the failure.
/// One retry is enough to clear transient sampling rolls without
/// adding meaningful latency to the happy path.
///
/// Tests use a stub OllamaCallProvider so the retry behaviour is
/// pinned without an HTTP round-trip.
func phase4OllamaRetryTests() -> TestSuite {
    let s = TestSuite("Phase4OllamaRetry")

    final class StubProvider: OllamaCallProvider {
        var responses: [Result<String, OllamaError>]
        var calls = 0
        init(responses: [Result<String, OllamaError>]) {
            self.responses = responses
        }
        func call(prompt: String, schema: [String: Any], completion: @escaping (Result<String, OllamaError>) -> Void) {
            let response = responses[calls]
            calls += 1
            completion(response)
        }
    }

    let chars = [LedgerExtraction.CharacterRef(name: "Mia", aliases: [])]

    s.test("non-empty response returns directly without a retry") {
        let stub = StubProvider(responses: [
            .success("[{\"character_id\":\"Mia\",\"fact\":\"x\",\"certainty\":\"asserted\",\"evidence_quote\":\"x\"}]")
        ])
        let extractor = OllamaLedgerExtractor(provider: stub)
        var captured: Result<[LedgerExtraction.ExtractedFact], Error>?
        extractor.extract(scenePose: "Mia walked.", characters: chars) { captured = $0 }
        try expectEqual(stub.calls, 1)
        switch try expectNotNil(captured) {
        case .success(let facts): try expectEqual(facts.count, 1)
        case .failure: try expectTrue(false, "expected success")
        }
    }

    s.test("empty response triggers one retry; second non-empty response wins") {
        let stub = StubProvider(responses: [
            .success(""),
            .success("[{\"character_id\":\"Mia\",\"fact\":\"x\",\"certainty\":\"asserted\",\"evidence_quote\":\"x\"}]"),
        ])
        let extractor = OllamaLedgerExtractor(provider: stub)
        var captured: Result<[LedgerExtraction.ExtractedFact], Error>?
        extractor.extract(scenePose: "Mia walked.", characters: chars) { captured = $0 }
        try expectEqual(stub.calls, 2)
        switch try expectNotNil(captured) {
        case .success(let facts): try expectEqual(facts.count, 1)
        case .failure: try expectTrue(false, "expected success after retry")
        }
    }

    s.test("two consecutive empty responses surface the parse error") {
        let stub = StubProvider(responses: [.success(""), .success("")])
        let extractor = OllamaLedgerExtractor(provider: stub)
        var captured: Result<[LedgerExtraction.ExtractedFact], Error>?
        extractor.extract(scenePose: "x", characters: chars) { captured = $0 }
        try expectEqual(stub.calls, 2)
        switch try expectNotNil(captured) {
        case .success: try expectTrue(false, "expected failure")
        case .failure: ()  // expected
        }
    }

    s.test("transport failure on first attempt does NOT trigger a retry") {
        // Retry is specifically for "model returned empty content"
        // (sampling/cold-load issue). Transport failures (network down,
        // server unreachable) should surface immediately so the
        // coordinator can put the right state on the queue's
        // onExtractionComplete callback.
        let stub = StubProvider(responses: [
            .failure(.transport("connection refused"))
        ])
        let extractor = OllamaLedgerExtractor(provider: stub)
        var captured: Result<[LedgerExtraction.ExtractedFact], Error>?
        extractor.extract(scenePose: "x", characters: chars) { captured = $0 }
        try expectEqual(stub.calls, 1)
        switch try expectNotNil(captured) {
        case .success: try expectTrue(false, "expected failure")
        case .failure: ()
        }
    }

    return s
}

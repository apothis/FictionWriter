import Foundation
@testable import LoomCore

/// Phase 4 #7 reliability fix — when Ollama returns empty content
/// (the model hit immediate-EOS under JSON-Schema constraint, or
/// the `num_predict` ceiling cut off the schema-constrained buffer
/// before it could close a valid array), the extractor adapter
/// should retry once with a doubled `num_predict` budget before
/// surfacing the failure. One retry is enough to clear transient
/// sampling rolls AND to cover the case where the initial budget
/// was undersized for the scene's emission count.
///
/// Tests use a stub `OllamaCallProvider` that records the options
/// it was called with so the budget-bump behaviour is pinned
/// without an HTTP round-trip.
func phase4OllamaRetryTests() -> TestSuite {
    let s = TestSuite("Phase4OllamaRetry")

    final class StubProvider: OllamaCallProvider {
        var responses: [Result<String, OllamaError>]
        var observedOptions: [OllamaChatOptions] = []
        var calls = 0
        init(responses: [Result<String, OllamaError>]) {
            self.responses = responses
        }
        func call(
            prompt: String,
            schema: [String: Any],
            options: OllamaChatOptions,
            completion: @escaping (Result<String, OllamaError>) -> Void
        ) {
            observedOptions.append(options)
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

    s.test("first call uses the scene-aware auto-budget") {
        let stub = StubProvider(responses: [
            .success("[{\"character_id\":\"Mia\",\"fact\":\"x\",\"certainty\":\"asserted\",\"evidence_quote\":\"x\"}]")
        ])
        let extractor = OllamaLedgerExtractor(provider: stub)
        // 312-word stand-in (just count separator-delimited tokens — the
        // production path goes through `WordCount.count`).
        let prose = Array(repeating: "word", count: 312).joined(separator: " ")
        extractor.extract(scenePose: prose, characters: chars) { _ in }
        try expectEqual(stub.observedOptions.count, 1)
        try expectEqual(stub.observedOptions[0].numPredict, 2496)
    }

    s.test("empty response triggers one retry with DOUBLED num_predict") {
        let stub = StubProvider(responses: [
            .success(""),
            .success("[{\"character_id\":\"Mia\",\"fact\":\"x\",\"certainty\":\"asserted\",\"evidence_quote\":\"x\"}]"),
        ])
        let extractor = OllamaLedgerExtractor(provider: stub)
        let prose = Array(repeating: "word", count: 312).joined(separator: " ")
        var captured: Result<[LedgerExtraction.ExtractedFact], Error>?
        extractor.extract(scenePose: prose, characters: chars) { captured = $0 }
        try expectEqual(stub.calls, 2)
        try expectEqual(stub.observedOptions[0].numPredict, 2496)
        try expectEqual(stub.observedOptions[1].numPredict, 4992)
        switch try expectNotNil(captured) {
        case .success(let facts): try expectEqual(facts.count, 1)
        case .failure: try expectTrue(false, "expected success after retry")
        }
    }

    s.test("retry budget bump is capped at 8192") {
        let stub = StubProvider(responses: [
            .success(""),
            .success("[{\"character_id\":\"Mia\",\"fact\":\"x\",\"certainty\":\"asserted\",\"evidence_quote\":\"x\"}]"),
        ])
        let extractor = OllamaLedgerExtractor(provider: stub)
        // 800-word scene → first call 6400. Retry would naively jump to
        // 12800 but the cap clamps to 8192.
        let prose = Array(repeating: "word", count: 800).joined(separator: " ")
        extractor.extract(scenePose: prose, characters: chars) { _ in }
        try expectEqual(stub.observedOptions[0].numPredict, 6400)
        try expectEqual(stub.observedOptions[1].numPredict, 8192)
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
        // (sampling/cold-load issue OR num_predict cut-off). Transport
        // failures (network down, server unreachable) should surface
        // immediately so the coordinator can put the right state on
        // the queue's onExtractionComplete callback.
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

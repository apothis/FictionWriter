import Foundation
@testable import LoomCore

/// Phase 4 #7 regression — `OllamaLedgerExtractor` is constructed
/// fresh per fire by `LedgerExtractionCoordinator`'s extractorProvider
/// closure and assigned to a local that goes out of scope when
/// `fire()` returns. The earlier retry-refactor's `[weak self]`
/// closure made the extract path silently no-op when this happened:
/// URLSession's callback ran, `guard let self = self else { return }`
/// took the bail path, and the coordinator's completion never fired.
///
/// Production fix: the closure strong-captures `self` so the
/// extractor lives until its single call completes. This suite pins
/// the contract — an extractor that's the ONLY strong reference at
/// fire time still delivers its completion when the call resolves.
func phase4OllamaExtractorLifetimeTests() -> TestSuite {
    let s = TestSuite("Phase4OllamaExtractorLifetime")

    final class DeferredProvider: OllamaCallProvider {
        var pending: ((Result<String, OllamaError>) -> Void)?
        func call(prompt: String, schema: [String: Any], options: OllamaChatOptions, completion: @escaping (Result<String, OllamaError>) -> Void) {
            pending = completion  // hold the completion; caller flushes later
        }
        func flush(_ result: Result<String, OllamaError>) {
            let p = pending
            pending = nil
            p?(result)
        }
    }

    let chars = [LedgerExtraction.CharacterRef(name: "Mia", aliases: [])]
    let raw = "[{\"character_id\":\"Mia\",\"fact\":\"x\",\"certainty\":\"asserted\",\"evidence_quote\":\"x\"}]"

    s.test("extractor whose owning local goes out of scope still delivers its completion when the call resolves") {
        let provider = DeferredProvider()
        var captured: Result<[LedgerExtraction.ExtractedFact], Error>?

        // Construct the extractor in an inner scope so it has no
        // external strong reference; only the in-flight URLSession-
        // style callback (held by `provider.pending`) keeps the
        // closure alive. The extractor itself MUST still resolve.
        do {
            let extractor = OllamaLedgerExtractor(provider: provider)
            extractor.extract(scenePose: "x", characters: chars) { captured = $0 }
            // `extractor` goes out of scope here. In the buggy
            // version, the extractor was deallocated and the
            // [weak self] guard in the retry callback took the bail
            // path, so `captured` stayed nil.
        }

        // Simulate URLSession's late delivery of the response.
        provider.flush(.success(raw))

        switch try expectNotNil(captured) {
        case .success(let facts): try expectEqual(facts.count, 1)
        case .failure(let e): try expectTrue(false, "expected success, got \(e)")
        }
    }

    return s
}

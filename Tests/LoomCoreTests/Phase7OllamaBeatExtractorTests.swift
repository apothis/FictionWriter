import Foundation
@testable import LoomCore

/// Phase 7.b.3 — production `BeatExtractor` adapter wrapping
/// `OllamaCallProvider`. Mirrors `OllamaLedgerExtractor` shape:
/// the integration glue is honest-smoke (covered by the spike
/// runner against a live server); these tests pin the prompt-
/// + schema-flow and the parse + retry semantics with a stub
/// provider.
func phase7OllamaBeatExtractorTests() -> TestSuite {
    let s = TestSuite("Phase7OllamaBeatExtractor")

    /// Stub provider — records what the extractor sent and returns
    /// canned responses on a deferred main-queue hop (per the
    /// async-callback memory).
    final class StubOllamaProvider: OllamaCallProvider {
        var capturedPrompt: String?
        var capturedSchema: [String: Any]?
        var capturedOptions: OllamaChatOptions?
        var responses: [Result<String, OllamaError>]
        private var pending: [(Result<String, OllamaError>, (Result<String, OllamaError>) -> Void)] = []

        init(responses: [Result<String, OllamaError>]) {
            self.responses = responses
        }

        func call(
            prompt: String,
            schema: [String: Any],
            options: OllamaChatOptions,
            completion: @escaping (Result<String, OllamaError>) -> Void
        ) {
            capturedPrompt = prompt
            capturedSchema = schema
            capturedOptions = options
            let response = responses.isEmpty
                ? .failure(OllamaError.unexpectedShape)
                : responses.removeFirst()
            pending.append((response, completion))
        }

        /// Snapshot + clear before firing, so completions that
        /// enqueue MORE work during iteration (e.g. the extractor's
        /// retry path) land in the freshly-cleared `pending` ready
        /// for the next flush call rather than being dropped.
        func flush() {
            let snapshot = pending
            pending.removeAll()
            for (r, c) in snapshot { c(r) }
        }
    }

    let cannedSkeleton = """
        {
          "beats": [
            {"index": 0, "function": "setup", "modality": "description", "summary": "{PROTAGONIST} arrives.", "targetWords": 80, "wordRangeStart": 0, "wordRangeEnd": 80, "beatTensionChange": 0}
          ],
          "sourceCharacters": ["Hadley"],
          "sourceSettingMarkers": ["kitchen"]
        }
        """

    s.test("OllamaBeatExtractor sends Pass-A prompt + schema; parses successful response") {
        let stub = StubOllamaProvider(responses: [.success(cannedSkeleton)])
        let extractor = OllamaBeatExtractor(provider: stub)

        var result: Result<ExtractedSceneSkeleton, Error>? = nil
        extractor.extractSkeleton(from: "She walked into the kitchen.") { r in result = r }
        // Captured before completion fires.
        try expectTrue(stub.capturedPrompt?.contains("She walked into the kitchen.") == true)
        try expectNotNil(stub.capturedSchema)
        stub.flush()
        try expectNotNil(result)
        if case .success(let skeleton) = result {
            try expectEqual(skeleton.beats.count, 1)
            try expectEqual(skeleton.sourceCharacters, ["Hadley"])
        } else {
            try expectFalse(true, "expected success")
        }
    }

    s.test("OllamaBeatExtractor retries-on-empty once with doubled num_predict") {
        // First response: empty content (deterministic budget cap or
        // sampling roll). Second response: valid skeleton.
        let stub = StubOllamaProvider(responses: [
            .success(""), .success(cannedSkeleton)
        ])
        let extractor = OllamaBeatExtractor(provider: stub)

        var result: Result<ExtractedSceneSkeleton, Error>? = nil
        extractor.extractSkeleton(from: "x") { r in result = r }
        // First completion fires — empty content triggers retry.
        let initialBudget = stub.capturedOptions?.numPredict
        try expectNotNil(initialBudget)
        stub.flush()
        // Retry budget should be doubled (subject to the 8192 cap).
        let retryBudget = stub.capturedOptions?.numPredict
        try expectTrue((retryBudget ?? 0) > (initialBudget ?? Int.max))
        stub.flush()
        // Result from the retry.
        if case .success(let skel) = result {
            try expectEqual(skel.beats.count, 1)
        } else {
            try expectFalse(true, "expected success on retry")
        }
    }

    s.test("OllamaBeatExtractor surfaces parse errors when response is malformed JSON") {
        let stub = StubOllamaProvider(responses: [.success("not json at all")])
        let extractor = OllamaBeatExtractor(provider: stub)
        var result: Result<ExtractedSceneSkeleton, Error>? = nil
        extractor.extractSkeleton(from: "x") { r in result = r }
        stub.flush()
        if case .failure = result {
            // pass
        } else {
            try expectFalse(true, "expected parse failure")
        }
    }

    s.test("OllamaBeatExtractor surfaces transport errors without retry") {
        // Transport failures (network down) should NOT be retried —
        // they need higher-level intervention, not budget tweaks.
        let stub = StubOllamaProvider(responses: [
            .failure(OllamaError.transport("network unreachable")),
            .success(cannedSkeleton),  // would be a retry; should not be consumed
        ])
        let extractor = OllamaBeatExtractor(provider: stub)
        var result: Result<ExtractedSceneSkeleton, Error>? = nil
        extractor.extractSkeleton(from: "x") { r in result = r }
        stub.flush()
        if case .failure = result {
            // pass
        } else {
            try expectFalse(true, "expected transport failure")
        }
        // The second canned response should be untouched — no retry on transport.
        try expectEqual(stub.responses.count, 1)
    }

    s.test("OllamaBeatExtractor.budgetForProse scales with source length") {
        // Short prose: floor at 2048. Long prose: scaled up. Cap at 8192.
        let short = OllamaBeatExtractor.budgetForProse("hello")
        let mid = OllamaBeatExtractor.budgetForProse(String(repeating: "word ", count: 300))
        let long = OllamaBeatExtractor.budgetForProse(String(repeating: "word ", count: 5000))
        try expectTrue(short >= 2048)
        try expectTrue(mid >= short)
        try expectTrue(long <= 8192)
        try expectTrue(long >= mid)
    }

    return s
}

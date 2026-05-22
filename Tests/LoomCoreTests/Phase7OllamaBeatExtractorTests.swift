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

    // Flat structure-of-arrays — the production Pass-A shape.
    let cannedSkeleton = """
        {"sentenceCadence":"shortClipped","dialogueDensity":"balanced","rhetoricalFlourish":"minimal","register":"noir","distinctiveTechniques":["fragments"],"characters":["Hadley"],"settings":["kitchen"],"beatFunctions":["setup"],"beatModalities":["description"],"beatSummaries":["{PROTAGONIST} arrives."],"beatTargetWords":[80]}
        """

    s.test("OllamaBeatExtractor sends the flat prompt + flat format schema; parses success") {
        let stub = StubOllamaProvider(responses: [.success(cannedSkeleton)])
        let extractor = OllamaBeatExtractor(provider: stub)

        var result: Result<ExtractedSceneSkeleton, Error>? = nil
        extractor.extractSkeleton(from: "She walked into the kitchen.") { r in result = r }
        // Captured before completion fires.
        try expectTrue(stub.capturedPrompt?.contains("She walked into the kitchen.") == true)
        // The FLAT format-schema constrains the keys (the flake was the
        // nested array-of-objects; this flat schema is shallow).
        try expectTrue(stub.capturedSchema?["properties"] != nil)
        let props = stub.capturedSchema?["properties"] as? [String: Any]
        try expectNotNil(props?["beatSummaries"])
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

    s.test("OllamaBeatExtractor retries on noJSONObjectFound and recovers if second attempt succeeds") {
        // HANDOFF §15.16 follow-up #1 — Pass-A on NSFW shows ~30%
        // transient JSON-parse failures. The retry budget already
        // covers empty content; extending it to noJSONObjectFound
        // (preamble noise that ate the open-brace, etc.) means the
        // user no longer has to hit "Re-ingest" on the first failure.
        let stub = StubOllamaProvider(responses: [
            .success("preamble: {malformed missing braces"),
            .success(cannedSkeleton),
        ])
        let extractor = OllamaBeatExtractor(provider: stub)
        var result: Result<ExtractedSceneSkeleton, Error>? = nil
        extractor.extractSkeleton(from: "x") { r in result = r }
        stub.flush()  // first attempt: parse-fail → retry triggers
        stub.flush()  // retry attempt: success
        if case .success(let skel) = result {
            try expectEqual(skel.beats.count, 1)
        } else {
            try expectFalse(true, "expected success on retry after parse failure")
        }
    }

    s.test("OllamaBeatExtractor retries when a roll yields zero parseable beats, and recovers") {
        // JSONL parse is per-line tolerant: a malformed / off-schema
        // roll yields no beat lines → noJSONObjectFound → retry. (Pre-
        // JSONL this surfaced as decodingFailed on a nested object; the
        // retry set covers any ParseError so both recover.)
        let stub = StubOllamaProvider(responses: [
            .success("{ \"title\": \"wrong schema\", \"plot\": [] }"),  // no beat lines
            .success(cannedSkeleton),
        ])
        let extractor = OllamaBeatExtractor(provider: stub)
        var result: Result<ExtractedSceneSkeleton, Error>? = nil
        extractor.extractSkeleton(from: "x") { r in result = r }
        stub.flush()  // first attempt: zero beats → must retry
        stub.flush()  // retry attempt: success
        if case .success(let skel) = result {
            try expectEqual(skel.beats.count, 1)
        } else {
            try expectFalse(true, "expected success on retry after a no-beats roll")
        }
    }

    s.test("OllamaBeatExtractor surfaces parse errors after retry exhausts") {
        // Both attempts malformed → final result is failure.
        let stub = StubOllamaProvider(responses: [
            .success("not json at all"),
            .success("still not json"),
        ])
        let extractor = OllamaBeatExtractor(provider: stub)
        var result: Result<ExtractedSceneSkeleton, Error>? = nil
        extractor.extractSkeleton(from: "x") { r in result = r }
        stub.flush()
        stub.flush()
        if case .failure = result {
            // pass
        } else {
            try expectFalse(true, "expected parse failure after retry exhausts")
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

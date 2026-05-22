import Foundation
@testable import LoomCore

/// Kobold-writer + GBNF Pass-A beat extraction. Replaces the flaky
/// Ollama `format`-schema path (live 2026-05-22: 97KB off-schema body).
/// Pins the grammar-passing, think-strip, parse, and retry semantics
/// with a stub `KoboldGenerating`.
func phase7KoboldBeatExtractorTests() -> TestSuite {
    let s = TestSuite("Phase7KoboldBeatExtractor")

    /// Stub writer client. Captures the grammar + wrapped prompt and
    /// returns canned responses on a deferred flush (per the
    /// async-callback memory: never complete synchronously inside the
    /// stub — defer + flush so retry re-enqueues land correctly).
    final class StubKoboldClient: KoboldGenerating {
        var capturedGrammar: String?
        var capturedPrompt: String?
        var capturedMaxLengths: [Int] = []
        var responses: [Result<String, Error>]
        private var pending: [(Result<String, Error>, (Result<String, Error>) -> Void)] = []

        init(responses: [Result<String, Error>]) { self.responses = responses }

        // Base required method — unused by the extractor (it calls the
        // grammar variant), but the protocol requires it.
        func generate(
            prompt: String,
            stopSequences: [String],
            params: SamplerParams,
            maxContextLength: Int,
            completion: @escaping (Result<String, Error>) -> Void
        ) {
            enqueue(prompt: prompt, params: params, grammar: nil, completion: completion)
        }

        // Grammar variant — what the extractor calls.
        func generate(
            prompt: String,
            stopSequences: [String],
            params: SamplerParams,
            maxContextLength: Int,
            grammar: String?,
            completion: @escaping (Result<String, Error>) -> Void
        ) {
            enqueue(prompt: prompt, params: params, grammar: grammar, completion: completion)
        }

        private func enqueue(
            prompt: String, params: SamplerParams, grammar: String?,
            completion: @escaping (Result<String, Error>) -> Void
        ) {
            capturedPrompt = prompt
            capturedGrammar = grammar
            capturedMaxLengths.append(params.maxLength)
            let response = responses.isEmpty
                ? .failure(KoboldError.unexpectedShape)
                : responses.removeFirst()
            pending.append((response, completion))
        }

        func flush() {
            let snapshot = pending
            pending.removeAll()
            for (r, c) in snapshot { c(r) }
        }
    }

    let canned = """
        {"beats": [{"index": 0, "function": "setup", "modality": "description", "summary": "{PROTAGONIST} arrives.", "targetWords": 80, "wordRangeStart": 0, "wordRangeEnd": 80, "beatTensionChange": 0}], "sourceCharacters": ["Hadley"], "sourceSettingMarkers": ["kitchen"], "voiceDescriptor": {"sentenceCadence": "shortClipped", "dialogueDensity": "balanced", "rhetoricalFlourish": "minimal", "register": "noir", "distinctiveTechniques": ["fragments"]}}
        """

    s.test("KoboldBeatExtractor is unconstrained by default (no grammar) but instruct-wraps; parses success") {
        let stub = StubKoboldClient(responses: [.success(canned)])
        let extractor = KoboldBeatExtractor(client: stub)
        var result: Result<ExtractedSceneSkeleton, Error>? = nil
        extractor.extractSkeleton(from: "She walked into the kitchen.") { r in result = r }
        // Default path: NO grammar (let a Thinking writer reason first),
        // but the prompt is still instruct-wrapped + carries the source.
        try expectNil(stub.capturedGrammar)
        try expectTrue(stub.capturedPrompt?.contains("She walked into the kitchen.") == true)
        stub.flush()
        if case .success(let skel) = result {
            try expectEqual(skel.beats.count, 1)
            try expectEqual(skel.sourceCharacters, ["Hadley"])
            try expectNotNil(skel.voiceDescriptor)
        } else {
            try expectFalse(true, "expected success")
        }
    }

    s.test("KoboldBeatExtractor sends the GBNF grammar when useGrammar: true (non-thinking writers)") {
        let stub = StubKoboldClient(responses: [.success(canned)])
        let extractor = KoboldBeatExtractor(client: stub, useGrammar: true)
        var result: Result<ExtractedSceneSkeleton, Error>? = nil
        extractor.extractSkeleton(from: "x") { r in result = r }
        try expectNotNil(stub.capturedGrammar)
        try expectTrue(stub.capturedGrammar?.contains("root ::=") == true)
        stub.flush()
        if case .success = result {} else { try expectFalse(true, "expected success") }
    }

    s.test("KoboldBeatExtractor retries on decodingFailed (malformed roll) and recovers") {
        let stub = StubKoboldClient(responses: [
            .success("{ \"beats\": [ : ] }"),   // balanced braces, invalid JSON
            .success(canned),
        ])
        let extractor = KoboldBeatExtractor(client: stub)
        var result: Result<ExtractedSceneSkeleton, Error>? = nil
        extractor.extractSkeleton(from: "x") { r in result = r }
        stub.flush()  // malformed → retry
        stub.flush()  // retry → success
        if case .success(let skel) = result {
            try expectEqual(skel.beats.count, 1)
        } else {
            try expectFalse(true, "expected success on retry after decodingFailed")
        }
    }

    s.test("KoboldBeatExtractor strips a <think> block before parsing") {
        let withThink = "<think>Let me analyze the beats…</think>\n" + canned
        let stub = StubKoboldClient(responses: [.success(withThink)])
        let extractor = KoboldBeatExtractor(client: stub)
        var result: Result<ExtractedSceneSkeleton, Error>? = nil
        extractor.extractSkeleton(from: "x") { r in result = r }
        stub.flush()
        if case .success(let skel) = result {
            try expectEqual(skel.beats.count, 1)
        } else {
            try expectFalse(true, "expected the think block to be stripped + the JSON parsed")
        }
    }

    s.test("KoboldBeatExtractor retries on empty with a bumped budget") {
        let stub = StubKoboldClient(responses: [.success(""), .success(canned)])
        let extractor = KoboldBeatExtractor(client: stub)
        var result: Result<ExtractedSceneSkeleton, Error>? = nil
        extractor.extractSkeleton(from: "x") { r in result = r }
        stub.flush()  // empty → retry with bumped budget
        stub.flush()  // success
        try expectEqual(stub.capturedMaxLengths.count, 2)
        try expectTrue(stub.capturedMaxLengths[1] > stub.capturedMaxLengths[0], "retry budget should be bumped")
        if case .success = result {} else { try expectFalse(true, "expected success on retry") }
    }

    s.test("KoboldBeatExtractor surfaces transport failure without retry") {
        let stub = StubKoboldClient(responses: [
            .failure(KoboldError.http(500, "down")),
            .success(canned),  // must NOT be consumed
        ])
        let extractor = KoboldBeatExtractor(client: stub)
        var result: Result<ExtractedSceneSkeleton, Error>? = nil
        extractor.extractSkeleton(from: "x") { r in result = r }
        stub.flush()
        if case .failure = result {} else { try expectFalse(true, "expected transport failure") }
        try expectEqual(stub.responses.count, 1)  // second response untouched
    }

    return s
}

import Foundation
@testable import LoomCore

/// Continuity Audit (L10) — Phase B, the production claim extractor.
/// Runs **unconstrained** (no `format` schema — the gemma4_2b schema
/// flake, HANDOFF §15.19) and re-rolls once on any degenerate result.
/// The stub provider defers every completion so retry / lifetime
/// behaviour is actually exercised (per the async-callback TDD memory).
func ollamaContinuityExtractorTests() -> TestSuite {
    let s = TestSuite("OllamaContinuityExtractor")

    final class StubProvider: OllamaCallProvider {
        struct Call {
            let prompt: String
            let schema: [String: Any]
            let options: OllamaChatOptions
            let completion: (Result<String, OllamaError>) -> Void
        }
        var calls: [Call] = []
        func call(
            prompt: String, schema: [String: Any], options: OllamaChatOptions,
            completion: @escaping (Result<String, OllamaError>) -> Void
        ) {
            calls.append(Call(prompt: prompt, schema: schema, options: options, completion: completion))
        }
        func respond(_ i: Int, _ r: Result<String, OllamaError>) { calls[i].completion(r) }
    }

    // JSONL — the production output format (one object per line, no array).
    let claimsJSONL = """
    {"type":"attribute","subject":"Mara","attribute_key":"eye colour","value":"green","source":"narration","evidence_quote":"her green eyes"}
    {"type":"temporal","subject":"the village","attribute_key":"","value":"autumn","source":"narration","evidence_quote":"the autumn wind"}
    """

    s.test("extract parses JSONL claims and stamps the scene id") {
        let stub = StubProvider()
        let extractor = OllamaContinuityExtractor(provider: stub)
        var result: Result<[ContinuityAudit.Claim], Error>?
        extractor.extract(scenePose: "A scene.", sceneId: "scene-9") { result = $0 }
        stub.respond(0, .success(claimsJSONL))
        let claims = try expectNotNil(try result?.get())
        try expectEqual(claims.count, 2)
        try expectTrue(claims.allSatisfy { $0.sourceSceneId == "scene-9" })
    }

    s.test("the extractor runs unconstrained — no format schema is sent") {
        let stub = StubProvider()
        OllamaContinuityExtractor(provider: stub).extract(scenePose: "A scene.", sceneId: "s1") { _ in }
        try expectTrue(stub.calls[0].schema.isEmpty,
                       "Ollama's format schema flakes ~50% on gemma4_2b — extraction must be unconstrained")
    }

    s.test("the extraction prompt carries the scene prose") {
        let stub = StubProvider()
        OllamaContinuityExtractor(provider: stub).extract(
            scenePose: "MARKERWORD on the cliff.", sceneId: "s1") { _ in }
        try expectTrue(stub.calls[0].prompt.contains("MARKERWORD"))
    }

    s.test("an empty response is re-rolled once with a doubled budget") {
        let stub = StubProvider()
        let extractor = OllamaContinuityExtractor(provider: stub)
        var result: Result<[ContinuityAudit.Claim], Error>?
        extractor.extract(scenePose: "A scene.", sceneId: "s1") { result = $0 }
        try expectEqual(stub.calls.count, 1)
        let firstBudget = stub.calls[0].options.numPredict
        stub.respond(0, .success(""))
        try expectEqual(stub.calls.count, 2)
        try expectEqual(stub.calls[1].options.numPredict, firstBudget * 2)
        stub.respond(1, .success(claimsJSONL))
        try expectEqual(try result?.get().count, 2)
    }

    s.test("an unparseable (no-JSON) response is re-rolled") {
        let stub = StubProvider()
        let extractor = OllamaContinuityExtractor(provider: stub)
        var result: Result<[ContinuityAudit.Claim], Error>?
        extractor.extract(scenePose: "A scene.", sceneId: "s1") { result = $0 }
        stub.respond(0, .success("I'm sorry, I can't help with that."))
        try expectEqual(stub.calls.count, 2)
        stub.respond(1, .success(claimsJSONL))
        try expectEqual(try result?.get().count, 2)
    }

    s.test("a degenerate result that persists yields an empty claim list, not an error") {
        let stub = StubProvider()
        let extractor = OllamaContinuityExtractor(provider: stub)
        var result: Result<[ContinuityAudit.Claim], Error>?
        extractor.extract(scenePose: "A scene.", sceneId: "s1") { result = $0 }
        stub.respond(0, .success(""))
        stub.respond(1, .success(""))
        try expectEqual(try result?.get().count, 0)
    }

    s.test("a provider transport failure propagates") {
        let stub = StubProvider()
        let extractor = OllamaContinuityExtractor(provider: stub)
        var result: Result<[ContinuityAudit.Claim], Error>?
        extractor.extract(scenePose: "A scene.", sceneId: "s1") { result = $0 }
        stub.respond(0, .failure(.transport("boom")))
        var threw = false
        do { _ = try result?.get() } catch { threw = true }
        try expectTrue(threw)
    }

    return s
}

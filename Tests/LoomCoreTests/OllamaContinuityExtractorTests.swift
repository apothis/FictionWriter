import Foundation
@testable import LoomCore

/// Continuity Audit (L10) — Phase B, the production claim extractor.
/// Mirrors `OllamaLedgerExtractor`: scene-aware token budget +
/// retry-on-empty (the schema empty-content guard the spike runner
/// lacked). The stub provider defers every completion so lifetime /
/// retry behaviour is actually exercised (per the async-callback TDD
/// memory).
func ollamaContinuityExtractorTests() -> TestSuite {
    let s = TestSuite("OllamaContinuityExtractor")

    final class StubProvider: OllamaCallProvider {
        struct Call {
            let prompt: String
            let options: OllamaChatOptions
            let completion: (Result<String, OllamaError>) -> Void
        }
        var calls: [Call] = []
        func call(
            prompt: String, schema: [String: Any], options: OllamaChatOptions,
            completion: @escaping (Result<String, OllamaError>) -> Void
        ) {
            calls.append(Call(prompt: prompt, options: options, completion: completion))
        }
        func respond(_ i: Int, _ r: Result<String, OllamaError>) { calls[i].completion(r) }
    }

    let claimsJSON = """
    [{"type":"attribute","subject":"Mara","attribute_key":"eye colour",
      "value":"green","source":"narration","evidence_quote":"her green eyes"}]
    """

    s.test("extract parses claims and stamps the scene id") {
        let stub = StubProvider()
        let extractor = OllamaContinuityExtractor(provider: stub)
        var result: Result<[ContinuityAudit.Claim], Error>?
        extractor.extract(scenePose: "A scene.", sceneId: "scene-9") { result = $0 }
        stub.respond(0, .success(claimsJSON))
        let claims = try expectNotNil(try result?.get())
        try expectEqual(claims.count, 1)
        try expectEqual(claims[0].sourceSceneId, "scene-9")
    }

    s.test("the extraction prompt carries the scene prose") {
        let stub = StubProvider()
        OllamaContinuityExtractor(provider: stub).extract(
            scenePose: "MARKERWORD on the cliff.", sceneId: "s1") { _ in }
        try expectTrue(stub.calls[0].prompt.contains("MARKERWORD"))
    }

    s.test("an empty response triggers one retry with a doubled budget") {
        let stub = StubProvider()
        let extractor = OllamaContinuityExtractor(provider: stub)
        var result: Result<[ContinuityAudit.Claim], Error>?
        extractor.extract(scenePose: "A scene.", sceneId: "s1") { result = $0 }
        try expectEqual(stub.calls.count, 1)
        let firstBudget = stub.calls[0].options.numPredict
        stub.respond(0, .success(""))   // deterministic empty-content
        try expectEqual(stub.calls.count, 2)
        try expectEqual(stub.calls[1].options.numPredict, firstBudget * 2)
        stub.respond(1, .success(claimsJSON))
        try expectEqual(try result?.get().count, 1)
    }

    s.test("an empty response that persists through the retry surfaces a failure") {
        let stub = StubProvider()
        let extractor = OllamaContinuityExtractor(provider: stub)
        var result: Result<[ContinuityAudit.Claim], Error>?
        extractor.extract(scenePose: "A scene.", sceneId: "s1") { result = $0 }
        stub.respond(0, .success(""))
        stub.respond(1, .success(""))
        var threw = false
        do { _ = try result?.get() } catch { threw = true }
        try expectTrue(threw)
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

import Foundation
@testable import LoomCore

/// Continuity Audit (L10) — Phase B, the production claim extractor.
/// Two stages, both unconstrained (no `format` schema — the gemma4_2b
/// schema flake, HANDOFF §15.19): stage 1 extracts claims, stage 2
/// re-classifies each claim's type in a focused scene-scoped call. The
/// stub provider defers every completion (per the async-callback TDD
/// memory); a `drive` helper pumps the two-call chain.
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
        var hasPending = false
        func call(
            prompt: String, schema: [String: Any], options: OllamaChatOptions,
            completion: @escaping (Result<String, OllamaError>) -> Void
        ) {
            calls.append(Call(prompt: prompt, schema: schema, options: options, completion: completion))
        }
        func respond(_ i: Int, _ r: Result<String, OllamaError>) { calls[i].completion(r) }
    }

    // JSONL — the stage-1 output format (one object per line, no array).
    let claimsJSONL = """
    {"type":"event","subject":"Mara","attribute_key":"eye colour","value":"Mara has green eyes","source":"narration","evidence_quote":"her green eyes"}
    {"type":"event","subject":"the village","attribute_key":"","value":"it is autumn","source":"narration","evidence_quote":"the autumn wind"}
    """
    // Stage-2 typing output — overrides the stage-1 types above.
    let typingLines = "1. attribute\n2. temporal"

    s.test("two-stage extract: stage 1 claims, stage 2 re-types, scene id stamped") {
        let stub = StubProvider()
        let extractor = OllamaContinuityExtractor(provider: stub)
        var result: Result<[ContinuityAudit.Claim], Error>?
        extractor.extract(scenePose: "A scene.", sceneId: "scene-9") { result = $0 }
        stub.respond(0, .success(claimsJSONL))   // stage 1
        stub.respond(1, .success(typingLines))   // stage 2
        let claims = try expectNotNil(try result?.get())
        try expectEqual(claims.count, 2)
        try expectEqual(claims[0].type, .attribute)   // re-typed from event
        try expectEqual(claims[1].type, .temporal)    // re-typed from event
        try expectTrue(claims.allSatisfy { $0.sourceSceneId == "scene-9" })
    }

    s.test("the typing stage sees the scene and the extracted claim values") {
        let stub = StubProvider()
        OllamaContinuityExtractor(provider: stub).extract(
            scenePose: "CLIFFMARKER prose.", sceneId: "s1") { _ in }
        stub.respond(0, .success(claimsJSONL))
        try expectEqual(stub.calls.count, 2)
        try expectTrue(stub.calls[1].prompt.contains("CLIFFMARKER"))
        try expectTrue(stub.calls[1].prompt.contains("Mara has green eyes"))
    }

    s.test("both stages run unconstrained — no format schema is sent") {
        let stub = StubProvider()
        OllamaContinuityExtractor(provider: stub).extract(scenePose: "A scene.", sceneId: "s1") { _ in }
        stub.respond(0, .success(claimsJSONL))
        try expectTrue(stub.calls[0].schema.isEmpty)
        try expectTrue(stub.calls[1].schema.isEmpty)
    }

    s.test("a failed typing stage falls open — stage-1 claims survive with their own types") {
        let stub = StubProvider()
        let extractor = OllamaContinuityExtractor(provider: stub)
        var result: Result<[ContinuityAudit.Claim], Error>?
        extractor.extract(scenePose: "A scene.", sceneId: "s1") { result = $0 }
        stub.respond(0, .success(claimsJSONL))
        stub.respond(1, .failure(.transport("typing boom")))
        let claims = try expectNotNil(try result?.get())
        try expectEqual(claims.count, 2)
        try expectEqual(claims[0].type, .event)   // stage-1 type kept
    }

    s.test("an empty stage-1 response is re-rolled once with a doubled budget") {
        let stub = StubProvider()
        let extractor = OllamaContinuityExtractor(provider: stub)
        var result: Result<[ContinuityAudit.Claim], Error>?
        extractor.extract(scenePose: "A scene.", sceneId: "s1") { result = $0 }
        let firstBudget = stub.calls[0].options.numPredict
        stub.respond(0, .success(""))
        try expectEqual(stub.calls.count, 2)
        try expectEqual(stub.calls[1].options.numPredict, firstBudget * 2)
        stub.respond(1, .success(claimsJSONL))   // stage-1 retry succeeds
        stub.respond(2, .success(typingLines))   // stage 2
        try expectEqual(try result?.get().count, 2)
    }

    s.test("a stage-1 result that stays degenerate yields an empty list, no typing call") {
        let stub = StubProvider()
        let extractor = OllamaContinuityExtractor(provider: stub)
        var result: Result<[ContinuityAudit.Claim], Error>?
        extractor.extract(scenePose: "A scene.", sceneId: "s1") { result = $0 }
        stub.respond(0, .success(""))
        stub.respond(1, .success(""))
        try expectEqual(stub.calls.count, 2)   // no stage-2 call on empty
        try expectEqual(try result?.get().count, 0)
    }

    s.test("a stage-1 transport failure propagates") {
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

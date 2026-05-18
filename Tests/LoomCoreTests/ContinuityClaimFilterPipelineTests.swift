import Foundation
@testable import LoomCore

/// Continuity Audit (L10) — Phase B, the claim-filter pipeline. The
/// async orchestrator that batches one embed call behind
/// `ContinuityClaimFilter` (dedup + per-scene evidence validation),
/// mirroring `LedgerFilterPipeline`. Fail-soft.
func continuityClaimFilterPipelineTests() -> TestSuite {
    let s = TestSuite("ContinuityClaimFilterPipeline")

    struct StubError: Error {}

    // Embedder: maps a text to a one-hot vector by a marker concept.
    final class StubEmbedder: KoboldEmbedding {
        var fail = false
        var concept: (String) -> Int = { _ in 0 }
        func embed(texts: [String], completion: @escaping (Result<[[Float]], Error>) -> Void) {
            if fail { completion(.failure(StubError())); return }
            completion(.success(texts.map { text in
                var v = [Float](repeating: 0, count: 16)
                v[concept(text)] = 1
                return v
            }))
        }
    }

    func claim(
        subject: String, value: String, scene: String, quote: String = ""
    ) -> ContinuityAudit.Claim {
        ContinuityAudit.Claim(
            type: .attribute, subject: subject, attributeKey: "eye colour", value: value,
            sourceSceneId: scene, source: .narration, evidenceQuote: quote)
    }

    s.test("the pipeline embeds, then dedups paraphrases in one scene+dimension") {
        let claims = [
            claim(subject: "Mara", value: "Mara has green eyes", scene: "s1"),
            claim(subject: "Mara", value: "Mara's eyes are green", scene: "s1"),
        ]
        let embedder = StubEmbedder()
        // both claim values map to the same concept → cosine 1 → dupes
        embedder.concept = { _ in 3 }
        var result: ContinuityClaimFilterPipeline.Result?
        ContinuityClaimFilterPipeline.apply(
            embedder: embedder, claims: claims, sceneSentencesByScene: [:]) { result = $0 }
        let r = try expectNotNil(result)
        try expectEqual(r.claims.count, 1)
        try expectEqual(r.dedupDropped, 1)
    }

    s.test("evidence validation is scoped per scene") {
        // claim in s1 with an evidence quote; s1 has a matching sentence,
        // s2 has an unrelated one. The claim must validate against s1 only.
        let claims = [claim(subject: "Mara", value: "v1", scene: "s1", quote: "her green eyes")]
        let embedder = StubEmbedder()
        embedder.concept = { text in
            // "her green eyes" and s1's sentence share concept 5; s2's is 9
            (text == "her green eyes" || text == "She had her green eyes.") ? 5 : 9
        }
        var result: ContinuityClaimFilterPipeline.Result?
        ContinuityClaimFilterPipeline.apply(
            embedder: embedder, claims: claims,
            sceneSentencesByScene: ["s1": ["She had her green eyes."], "s2": ["A different line."]]
        ) { result = $0 }
        try expectEqual(try expectNotNil(result).claims.count, 1)
    }

    s.test("a claim whose evidence matches no sentence in its own scene is dropped") {
        let claims = [claim(subject: "Mara", value: "v1", scene: "s1", quote: "her violet eyes")]
        let embedder = StubEmbedder()
        embedder.concept = { text in text == "her violet eyes" ? 7 : 9 }
        var result: ContinuityClaimFilterPipeline.Result?
        ContinuityClaimFilterPipeline.apply(
            embedder: embedder, claims: claims,
            sceneSentencesByScene: ["s1": ["An unrelated sentence."]]) { result = $0 }
        let r = try expectNotNil(result)
        try expectEqual(r.claims.count, 0)
        try expectEqual(r.evidenceDropped, 1)
    }

    s.test("the result exposes the embedding of every claim value") {
        let claims = [claim(subject: "Mara", value: "Mara has green eyes", scene: "s1")]
        let embedder = StubEmbedder()
        var result: ContinuityClaimFilterPipeline.Result?
        ContinuityClaimFilterPipeline.apply(
            embedder: embedder, claims: claims, sceneSentencesByScene: [:]) { result = $0 }
        _ = try expectNotNil(try expectNotNil(result).embeddings["Mara has green eyes"])
    }

    s.test("an embed failure is fail-soft — claims pass through unchanged") {
        let claims = [
            claim(subject: "Mara", value: "Mara has green eyes", scene: "s1"),
            claim(subject: "Mara", value: "Mara's eyes are green", scene: "s1"),
        ]
        let embedder = StubEmbedder()
        embedder.fail = true
        var result: ContinuityClaimFilterPipeline.Result?
        ContinuityClaimFilterPipeline.apply(
            embedder: embedder, claims: claims, sceneSentencesByScene: [:]) { result = $0 }
        let r = try expectNotNil(result)
        try expectEqual(r.claims.count, 2)
        try expectEqual(r.dedupDropped, 0)
        try expectTrue(r.embeddings.isEmpty)
    }

    s.test("an empty claim list short-circuits to an empty result") {
        var result: ContinuityClaimFilterPipeline.Result?
        ContinuityClaimFilterPipeline.apply(
            embedder: StubEmbedder(), claims: [], sceneSentencesByScene: [:]) { result = $0 }
        try expectEqual(try expectNotNil(result).claims.count, 0)
    }

    return s
}

import Foundation
@testable import LoomCore

/// Continuity Audit (L10) — Phase B, the claim-filter pass. Mirrors
/// `LedgerFilters`: cosine paraphrase dedup (per scene + dimension) and
/// evidence-quote validation against the scene's sentences. Both are
/// pure-data passes over pre-computed embeddings, fail-open on a
/// missing vector.
func continuityClaimFilterTests() -> TestSuite {
    let s = TestSuite("ContinuityClaimFilter")

    // One-hot vectors: same concept index -> cosine 1, different -> 0.
    func vec(_ i: Int) -> [Float] {
        var v = [Float](repeating: 0, count: 12); v[i] = 1; return v
    }

    func claim(
        subject: String, key: String = "eye colour", value: String,
        scene: String, quote: String = ""
    ) -> ContinuityAudit.Claim {
        ContinuityAudit.Claim(
            type: .attribute, subject: subject, attributeKey: key, value: value,
            sourceSceneId: scene, source: .narration, evidenceQuote: quote)
    }

    // MARK: - deduplicate

    s.test("two paraphrase claims in one scene+dimension collapse to one") {
        let claims = [
            claim(subject: "Mara", value: "Mara has green eyes", scene: "s1"),
            claim(subject: "Mara", value: "Mara's eyes are green", scene: "s1"),
        ]
        let embeddings = [
            "Mara has green eyes": vec(0),
            "Mara's eyes are green": vec(0),
        ]
        let kept = ContinuityClaimFilter.deduplicate(claims: claims, embeddings: embeddings)
        try expectEqual(kept.count, 1)
        try expectEqual(kept[0].value, "Mara has green eyes")
    }

    s.test("paraphrases about different subjects are both kept") {
        let claims = [
            claim(subject: "Mara", value: "green eyes A", scene: "s1"),
            claim(subject: "Cole", value: "green eyes B", scene: "s1"),
        ]
        let embeddings = ["green eyes A": vec(0), "green eyes B": vec(0)]
        try expectEqual(
            ContinuityClaimFilter.deduplicate(claims: claims, embeddings: embeddings).count, 2)
    }

    s.test("the same claim in two different scenes is kept — separate observations") {
        let claims = [
            claim(subject: "Mara", value: "green eyes A", scene: "s1"),
            claim(subject: "Mara", value: "green eyes B", scene: "s2"),
        ]
        let embeddings = ["green eyes A": vec(0), "green eyes B": vec(0)]
        try expectEqual(
            ContinuityClaimFilter.deduplicate(claims: claims, embeddings: embeddings).count, 2)
    }

    s.test("dedup is fail-open on a missing embedding") {
        let claims = [
            claim(subject: "Mara", value: "green eyes A", scene: "s1"),
            claim(subject: "Mara", value: "green eyes B", scene: "s1"),
        ]
        try expectEqual(
            ContinuityClaimFilter.deduplicate(claims: claims, embeddings: [:]).count, 2)
    }

    // MARK: - validateEvidence

    s.test("a claim whose evidence matches a scene sentence is kept") {
        let claims = [claim(subject: "Mara", value: "v", scene: "s1", quote: "her green eyes")]
        let embeddings = ["her green eyes": vec(1), "She turned, her green eyes bright.": vec(1)]
        let kept = ContinuityClaimFilter.validateEvidence(
            claims: claims, sceneSentences: ["She turned, her green eyes bright."], embeddings: embeddings)
        try expectEqual(kept.count, 1)
    }

    s.test("a claim whose evidence matches no scene sentence is dropped") {
        let claims = [claim(subject: "Mara", value: "v", scene: "s1", quote: "her violet eyes")]
        let embeddings = ["her violet eyes": vec(2), "She turned, her green eyes bright.": vec(1)]
        let kept = ContinuityClaimFilter.validateEvidence(
            claims: claims, sceneSentences: ["She turned, her green eyes bright."], embeddings: embeddings)
        try expectEqual(kept.count, 0)
    }

    s.test("a claim with an empty evidence quote is kept — fail-open") {
        let claims = [claim(subject: "Mara", value: "v", scene: "s1", quote: "")]
        try expectEqual(
            ContinuityClaimFilter.validateEvidence(
                claims: claims, sceneSentences: ["anything"], embeddings: [:]).count, 1)
    }

    s.test("a claim whose evidence has no embedding is kept — fail-open") {
        let claims = [claim(subject: "Mara", value: "v", scene: "s1", quote: "some quote")]
        try expectEqual(
            ContinuityClaimFilter.validateEvidence(
                claims: claims, sceneSentences: ["a sentence"], embeddings: [:]).count, 1)
    }

    return s
}

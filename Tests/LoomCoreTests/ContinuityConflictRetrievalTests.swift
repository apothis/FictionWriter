import Foundation
@testable import LoomCore

/// Continuity Audit (L10) — conflict-candidate retrieval.
///
/// Retrieval clusters claims by **value similarity** (near-paraphrase
/// propositions that disagree on one point) rather than an exact
/// `(type, subject)` key. The engine baseline (LOOM_CONTINUITY_AUDIT
/// §21) showed exact keying lost ~67 points of recall to subject drift
/// and type-misclassification: a contradiction's two claims were both
/// extracted but never paired. Value-similarity clustering is
/// type-tolerant and drift-tolerant. Source-routing is unchanged: only
/// `narration` claims enter world-fact pairs.
func continuityConflictRetrievalTests() -> TestSuite {
    let s = TestSuite("ContinuityConflictRetrieval")

    func claim(
        _ type: ContinuityAudit.ClaimType,
        subject: String = "x",
        value: String,
        scene: String,
        source: ContinuityAudit.ClaimSource = .narration
    ) -> ContinuityAudit.Claim {
        ContinuityAudit.Claim(
            type: type, subject: subject, attributeKey: "", value: value,
            sourceSceneId: scene, source: source, evidenceQuote: "q")
    }

    let order = ["s1", "s2", "s3"]

    s.test("two narration claims with near-paraphrase values form one ordered pair") {
        let claims = [
            claim(.attribute, value: "Mara has green eyes", scene: "s1"),
            claim(.attribute, value: "Mara has brown eyes", scene: "s3"),
        ]
        let pairs = ContinuityConflictRetrieval.candidatePairs(claims: claims, sceneOrder: order)
        try expectEqual(pairs.count, 1)
        try expectEqual(pairs[0].earlier.sourceSceneId, "s1")
        try expectEqual(pairs[0].later.sourceSceneId, "s3")
    }

    s.test("a dialogue-sourced claim is excluded from world-fact pairs") {
        let claims = [
            claim(.attribute, value: "Cole was inside the church", scene: "s1", source: .narration),
            claim(.attribute, value: "Cole was never inside the church", scene: "s2", source: .dialogue),
        ]
        try expectEqual(
            ContinuityConflictRetrieval.candidatePairs(claims: claims, sceneOrder: order).count, 0)
    }

    s.test("a thought-sourced claim is also excluded") {
        let claims = [
            claim(.attribute, value: "Mara feels calm and steady", scene: "s1", source: .narration),
            claim(.attribute, value: "Mara feels calm and afraid", scene: "s2", source: .thought),
        ]
        try expectEqual(
            ContinuityConflictRetrieval.candidatePairs(claims: claims, sceneOrder: order).count, 0)
    }

    s.test("knowledge_state claims are not paired here — handled by the knowledge check") {
        let claims = [
            claim(.knowledgeState, value: "Mara knows the keeper lost a brother", scene: "s1"),
            claim(.knowledgeState, value: "Mara knows the keeper lost a brother", scene: "s2"),
        ]
        try expectEqual(
            ContinuityConflictRetrieval.candidatePairs(claims: claims, sceneOrder: order).count, 0)
    }

    s.test("event claims now pair when their values are near-paraphrases") {
        let claims = [
            claim(.event, value: "the supply ship came eight months ago", scene: "s1"),
            claim(.event, value: "the supply ship came three months ago", scene: "s2"),
        ]
        try expectEqual(
            ContinuityConflictRetrieval.candidatePairs(claims: claims, sceneOrder: order).count, 1)
    }

    s.test("pairing is type-tolerant — an attribute and an event claim with matching values pair") {
        let claims = [
            claim(.spatial, value: "the lighthouse stands north of the village", scene: "s1"),
            claim(.event, value: "the lighthouse stands south of the village", scene: "s3"),
        ]
        try expectEqual(
            ContinuityConflictRetrieval.candidatePairs(claims: claims, sceneOrder: order).count, 1)
    }

    s.test("claims with dissimilar values do not pair, even on the same subject") {
        let claims = [
            claim(.attribute, value: "Mara has green eyes", scene: "s1"),
            claim(.attribute, value: "Mara wears a silver ring of office", scene: "s2"),
        ]
        try expectEqual(
            ContinuityConflictRetrieval.candidatePairs(claims: claims, sceneOrder: order).count, 0)
    }

    s.test("claims about different subjects do not pair") {
        let claims = [
            claim(.attribute, value: "Mara has green eyes", scene: "s1"),
            claim(.attribute, value: "Cole has blue eyes", scene: "s2"),
        ]
        try expectEqual(
            ContinuityConflictRetrieval.candidatePairs(claims: claims, sceneOrder: order).count, 0)
    }

    s.test("temporal and spatial claims pair on near-paraphrase values") {
        let temporal = [
            claim(.temporal, value: "the storm struck last week", scene: "s1"),
            claim(.temporal, value: "the storm struck a month ago", scene: "s2"),
        ]
        let spatial = [
            claim(.spatial, value: "the lighthouse stands north of the village", scene: "s1"),
            claim(.spatial, value: "the lighthouse stands south of the village", scene: "s2"),
        ]
        try expectEqual(
            ContinuityConflictRetrieval.candidatePairs(claims: temporal, sceneOrder: order).count, 1)
        try expectEqual(
            ContinuityConflictRetrieval.candidatePairs(claims: spatial, sceneOrder: order).count, 1)
    }

    s.test("three near-paraphrase claims in one cluster yield three pairs") {
        let claims = [
            claim(.attribute, value: "Mara has green eyes", scene: "s1"),
            claim(.attribute, value: "Mara has brown eyes", scene: "s2"),
            claim(.attribute, value: "Mara has grey eyes", scene: "s3"),
        ]
        try expectEqual(
            ContinuityConflictRetrieval.candidatePairs(claims: claims, sceneOrder: order).count, 3)
    }

    s.test("two claims in the same scene are not paired — the audit is cross-scene") {
        let claims = [
            claim(.attribute, value: "the wind smelled of salt", scene: "s1"),
            claim(.attribute, value: "the wind smelled of woodsmoke", scene: "s1"),
        ]
        try expectEqual(
            ContinuityConflictRetrieval.candidatePairs(claims: claims, sceneOrder: order).count, 0)
    }

    s.test("a claim in a scene outside the order is skipped") {
        let claims = [
            claim(.attribute, value: "Mara has green eyes", scene: "s1"),
            claim(.attribute, value: "Mara has brown eyes", scene: "s99"),
        ]
        try expectEqual(
            ContinuityConflictRetrieval.candidatePairs(claims: claims, sceneOrder: order).count, 0)
    }

    s.test("a custom similarity closure overrides the default clustering") {
        // Values that share no words — the default would never pair them.
        let claims = [
            claim(.attribute, value: "alpha", scene: "s1"),
            claim(.attribute, value: "omega", scene: "s2"),
        ]
        try expectEqual(
            ContinuityConflictRetrieval.candidatePairs(claims: claims, sceneOrder: order).count, 0)
        // A closure that calls everything similar pairs them.
        let pairs = ContinuityConflictRetrieval.candidatePairs(
            claims: claims, sceneOrder: order, similarity: { _, _ in 1.0 }, threshold: 0.5)
        try expectEqual(pairs.count, 1)
    }

    return s
}

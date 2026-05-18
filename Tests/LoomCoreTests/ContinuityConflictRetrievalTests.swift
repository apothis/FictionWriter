import Foundation
@testable import LoomCore

/// Continuity Audit (L10) — Phase B, conflict-candidate retrieval.
/// Narrows the O(n²) claim space to same-subject/same-dimension pairs
/// worth adjudicating, with deterministic source-routing: only
/// `narration` claims enter world-fact conflict pairs, so a lying
/// character (dialogue) is never adjudicated as a world contradiction.
func continuityConflictRetrievalTests() -> TestSuite {
    let s = TestSuite("ContinuityConflictRetrieval")

    func claim(
        _ type: ContinuityAudit.ClaimType,
        subject: String,
        key: String = "",
        value: String,
        scene: String,
        source: ContinuityAudit.ClaimSource = .narration
    ) -> ContinuityAudit.Claim {
        ContinuityAudit.Claim(
            type: type, subject: subject, attributeKey: key, value: value,
            sourceSceneId: scene, source: source, evidenceQuote: "q"
        )
    }

    let order = ["s1", "s2", "s3"]

    s.test("two narration attribute claims on the same subject and key form one ordered pair") {
        let claims = [
            claim(.attribute, subject: "Mara", key: "eye colour", value: "green", scene: "s1"),
            claim(.attribute, subject: "Mara", key: "eye colour", value: "brown", scene: "s3"),
        ]
        let pairs = ContinuityConflictRetrieval.candidatePairs(claims: claims, sceneOrder: order)
        try expectEqual(pairs.count, 1)
        try expectEqual(pairs[0].earlier.sourceSceneId, "s1")
        try expectEqual(pairs[0].later.sourceSceneId, "s3")
    }

    s.test("a dialogue-sourced claim is excluded from world-fact pairs") {
        let claims = [
            claim(.attribute, subject: "Cole", key: "location", value: "in the church", scene: "s1", source: .narration),
            claim(.attribute, subject: "Cole", key: "location", value: "never in the church", scene: "s2", source: .dialogue),
        ]
        let pairs = ContinuityConflictRetrieval.candidatePairs(claims: claims, sceneOrder: order)
        try expectEqual(pairs.count, 0)
    }

    s.test("a thought-sourced claim is also excluded") {
        let claims = [
            claim(.attribute, subject: "Mara", key: "mood", value: "calm", scene: "s1", source: .narration),
            claim(.attribute, subject: "Mara", key: "mood", value: "afraid", scene: "s2", source: .thought),
        ]
        try expectEqual(
            ContinuityConflictRetrieval.candidatePairs(claims: claims, sceneOrder: order).count, 0)
    }

    s.test("event claims are not paired — too noisy, not a drift dimension") {
        let claims = [
            claim(.event, subject: "Mara", value: "Mara opened the door", scene: "s1"),
            claim(.event, subject: "Mara", value: "Mara closed the door", scene: "s2"),
        ]
        try expectEqual(
            ContinuityConflictRetrieval.candidatePairs(claims: claims, sceneOrder: order).count, 0)
    }

    s.test("knowledge_state claims are not paired here — handled by the knowledge check") {
        let claims = [
            claim(.knowledgeState, subject: "Mara", value: "Mara knows the secret", scene: "s1"),
            claim(.knowledgeState, subject: "Mara", value: "Mara knows the secret", scene: "s2"),
        ]
        try expectEqual(
            ContinuityConflictRetrieval.candidatePairs(claims: claims, sceneOrder: order).count, 0)
    }

    s.test("attribute claims with different keys do not pair") {
        let claims = [
            claim(.attribute, subject: "Mara", key: "eye colour", value: "green", scene: "s1"),
            claim(.attribute, subject: "Mara", key: "hair colour", value: "black", scene: "s2"),
        ]
        try expectEqual(
            ContinuityConflictRetrieval.candidatePairs(claims: claims, sceneOrder: order).count, 0)
    }

    s.test("claims about different subjects do not pair") {
        let claims = [
            claim(.attribute, subject: "Mara", key: "eye colour", value: "green", scene: "s1"),
            claim(.attribute, subject: "Cole", key: "eye colour", value: "blue", scene: "s2"),
        ]
        try expectEqual(
            ContinuityConflictRetrieval.candidatePairs(claims: claims, sceneOrder: order).count, 0)
    }

    s.test("temporal and spatial claims on the same subject do pair") {
        let temporal = [
            claim(.temporal, subject: "the storm", value: "last week", scene: "s1"),
            claim(.temporal, subject: "the storm", value: "a month ago", scene: "s2"),
        ]
        let spatial = [
            claim(.spatial, subject: "the lighthouse", value: "north", scene: "s1"),
            claim(.spatial, subject: "the lighthouse", value: "south", scene: "s2"),
        ]
        try expectEqual(
            ContinuityConflictRetrieval.candidatePairs(claims: temporal, sceneOrder: order).count, 1)
        try expectEqual(
            ContinuityConflictRetrieval.candidatePairs(claims: spatial, sceneOrder: order).count, 1)
    }

    s.test("subject matching is normalised — 'the Lighthouse' equals 'lighthouse'") {
        let claims = [
            claim(.spatial, subject: "the Lighthouse", value: "north", scene: "s1"),
            claim(.spatial, subject: "lighthouse", value: "south", scene: "s2"),
        ]
        try expectEqual(
            ContinuityConflictRetrieval.candidatePairs(claims: claims, sceneOrder: order).count, 1)
    }

    s.test("three claims in one group yield three pairs") {
        let claims = [
            claim(.attribute, subject: "Mara", key: "eye colour", value: "green", scene: "s1"),
            claim(.attribute, subject: "Mara", key: "eye colour", value: "brown", scene: "s2"),
            claim(.attribute, subject: "Mara", key: "eye colour", value: "grey", scene: "s3"),
        ]
        try expectEqual(
            ContinuityConflictRetrieval.candidatePairs(claims: claims, sceneOrder: order).count, 3)
    }

    s.test("two claims in the same scene are not paired — the audit is cross-scene") {
        // "a wind that smelled of salt and woodsmoke" — a conjunction
        // the writer wrote as a unit, not a continuity error.
        let claims = [
            claim(.attribute, subject: "the wind", key: "smell", value: "salt", scene: "s1"),
            claim(.attribute, subject: "the wind", key: "smell", value: "woodsmoke", scene: "s1"),
        ]
        try expectEqual(
            ContinuityConflictRetrieval.candidatePairs(claims: claims, sceneOrder: order).count, 0)
    }

    s.test("a claim in a scene outside the order is skipped") {
        let claims = [
            claim(.attribute, subject: "Mara", key: "eye colour", value: "green", scene: "s1"),
            claim(.attribute, subject: "Mara", key: "eye colour", value: "brown", scene: "s99"),
        ]
        try expectEqual(
            ContinuityConflictRetrieval.candidatePairs(claims: claims, sceneOrder: order).count, 0)
    }

    return s
}

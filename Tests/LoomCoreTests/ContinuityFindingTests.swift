import Foundation
@testable import LoomCore

/// Continuity Audit (L10) — Phase B, the `ContinuityFinding` type and
/// finding assembly. An adjudicated `contradiction` pair or a
/// knowledge-state violation becomes a reviewable finding; `consistent`
/// and `evolution` verdicts produce nothing.
func continuityFindingTests() -> TestSuite {
    let s = TestSuite("ContinuityFinding")

    func claim(
        _ type: ContinuityAudit.ClaimType, subject: String = "Mara",
        value: String, scene: String
    ) -> ContinuityAudit.Claim {
        ContinuityAudit.Claim(
            type: type, subject: subject, attributeKey: "k", value: value,
            sourceSceneId: scene, source: .narration, evidenceQuote: "q")
    }

    func pair(_ type: ContinuityAudit.ClaimType) -> ContinuityConflictRetrieval.CandidatePair {
        ContinuityConflictRetrieval.CandidatePair(
            earlier: claim(type, value: "A", scene: "s1"),
            later: claim(type, value: "B", scene: "s3"))
    }

    func adj(_ verdict: ContinuityAudit.Verdict, _ conf: Double) -> ContinuityAudit.Adjudication {
        ContinuityAudit.Adjudication(verdict: verdict, confidence: conf, explanation: "because")
    }

    // MARK: - Type

    s.test("ContinuityFinding round-trips through Codable") {
        let f = ContinuityFinding(
            kind: .attributeDrift, severity: .high,
            claimA: claim(.attribute, value: "green", scene: "s1"),
            claimB: claim(.attribute, value: "brown", scene: "s3"),
            explanation: "green then brown", confidence: 0.9, status: .open)
        let data = try JSONEncoder().encode(f)
        let decoded = try JSONDecoder().decode(ContinuityFinding.self, from: data)
        try expectEqual(decoded, f)
    }

    s.test("the finding kinds and statuses cover the four classes and three states") {
        try expectEqual(Set(ContinuityFinding.Kind.allCases.map(\.rawValue)),
                        ["attribute_drift", "knowledge_violation", "timeline_conflict", "spatial_conflict"])
        try expectEqual(Set(ContinuityFinding.Status.allCases.map(\.rawValue)),
                        ["open", "dismissed", "resolved"])
    }

    // MARK: - Assembly from adjudication

    s.test("a contradiction verdict becomes an open finding carrying both claims") {
        let f = ContinuityFindingAssembly.finding(pair: pair(.attribute), adjudication: adj(.contradiction, 0.9))
        let finding = try expectNotNil(f)
        try expectEqual(finding.claimA.value, "A")
        try expectEqual(finding.claimB.value, "B")
        try expectEqual(finding.explanation, "because")
        try expectEqual(finding.status, .open)
    }

    s.test("a consistent verdict produces no finding") {
        try expectNil(ContinuityFindingAssembly.finding(pair: pair(.attribute), adjudication: adj(.consistent, 0.9)))
    }

    s.test("an evolution verdict produces no finding") {
        try expectNil(ContinuityFindingAssembly.finding(pair: pair(.attribute), adjudication: adj(.evolution, 0.9)))
    }

    s.test("the finding kind follows the claim type") {
        try expectEqual(
            ContinuityFindingAssembly.finding(pair: pair(.attribute), adjudication: adj(.contradiction, 0.9))?.kind,
            .attributeDrift)
        try expectEqual(
            ContinuityFindingAssembly.finding(pair: pair(.spatial), adjudication: adj(.contradiction, 0.9))?.kind,
            .spatialConflict)
        try expectEqual(
            ContinuityFindingAssembly.finding(pair: pair(.temporal), adjudication: adj(.contradiction, 0.9))?.kind,
            .timelineConflict)
    }

    s.test("severity tiers track adjudication confidence") {
        try expectEqual(
            ContinuityFindingAssembly.finding(pair: pair(.attribute), adjudication: adj(.contradiction, 0.95))?.severity,
            .high)
        try expectEqual(
            ContinuityFindingAssembly.finding(pair: pair(.attribute), adjudication: adj(.contradiction, 0.7))?.severity,
            .medium)
        try expectEqual(
            ContinuityFindingAssembly.finding(pair: pair(.attribute), adjudication: adj(.contradiction, 0.4))?.severity,
            .low)
    }

    // MARK: - Assembly from a knowledge violation

    s.test("a knowledge violation becomes a high-severity knowledge_violation finding") {
        let violation = ContinuityKnowledgeCheck.Violation(
            knowledgeClaim: claim(.knowledgeState, value: "Mara knows the secret", scene: "s2"),
            revealClaim: claim(.event, subject: "x", value: "the secret revealed", scene: "s4"))
        let f = ContinuityFindingAssembly.finding(knowledgeViolation: violation)
        try expectEqual(f.kind, .knowledgeViolation)
        try expectEqual(f.severity, .high)
        try expectEqual(f.claimA.sourceSceneId, "s2")
        try expectEqual(f.claimB.sourceSceneId, "s4")
        try expectEqual(f.status, .open)
    }

    s.test("a knowledge violation can take the adjudicator's explanation and confidence") {
        let violation = ContinuityKnowledgeCheck.Violation(
            knowledgeClaim: claim(.knowledgeState, value: "Mara knows the secret", scene: "s2"),
            revealClaim: claim(.event, subject: "x", value: "the secret revealed", scene: "s4"))
        let f = ContinuityFindingAssembly.finding(
            knowledgeViolation: violation,
            explanation: "Mara cannot know the vault is empty before scene 4.",
            confidence: 0.75)
        try expectEqual(f.explanation, "Mara cannot know the vault is empty before scene 4.")
        try expectEqual(f.confidence, 0.75)
    }

    return s
}

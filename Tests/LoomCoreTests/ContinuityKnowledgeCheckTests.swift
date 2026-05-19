import Foundation
@testable import LoomCore

/// Continuity Audit (L10) — Phase B, the deterministic knowledge-state
/// violation check. A `knowledgeState` claim (a character references
/// proposition P in scene S) is a violation when P's earliest reveal
/// is a scene *after* S. Proposition matching is delegated to an
/// injected `similarity` closure so the check stays pure-data.
func continuityKnowledgeCheckTests() -> TestSuite {
    let s = TestSuite("ContinuityKnowledgeCheck")

    // Synthetic similarity: two texts match iff they share a `#TAG`.
    func sim(_ a: String, _ b: String) -> Double {
        func tags(_ t: String) -> Set<String> {
            Set(t.split(separator: " ").map(String.init).filter { $0.hasPrefix("#") })
        }
        return tags(a).isDisjoint(with: tags(b)) ? 0.0 : 1.0
    }

    func knows(_ subject: String, _ value: String, scene: String) -> ContinuityAudit.Claim {
        ContinuityAudit.Claim(
            type: .knowledgeState, subject: subject, attributeKey: "", value: value,
            sourceSceneId: scene, source: .dialogue, evidenceQuote: "q")
    }
    func reveal(_ subject: String, _ value: String, scene: String) -> ContinuityAudit.Claim {
        ContinuityAudit.Claim(
            type: .event, subject: subject, attributeKey: "", value: value,
            sourceSceneId: scene, source: .narration, evidenceQuote: "q")
    }

    let order = ["s1", "s2", "s3", "s4", "s5"]

    s.test("referencing a proposition before its reveal is a violation") {
        let claims = [
            knows("Mara", "Mara knows the money is missing #MONEY", scene: "s2"),
            reveal("fund", "the money is missing #MONEY", scene: "s4"),
        ]
        let v = ContinuityKnowledgeCheck.violations(claims: claims, sceneOrder: order, similarity: sim)
        try expectEqual(v.count, 1)
        try expectEqual(v[0].knowledgeClaim.sourceSceneId, "s2")
        try expectEqual(v[0].revealClaim.sourceSceneId, "s4")
    }

    s.test("referencing a proposition after its reveal is not a violation") {
        let claims = [
            reveal("Cole", "Cole's brother drowned #DROWN", scene: "s2"),
            knows("Mara", "Mara knows the brother drowned #DROWN", scene: "s3"),
        ]
        try expectEqual(
            ContinuityKnowledgeCheck.violations(claims: claims, sceneOrder: order, similarity: sim).count, 0)
    }

    s.test("a reveal in the same scene as the reference is not a violation") {
        let claims = [
            knows("Mara", "Mara knows the secret #SECRET", scene: "s3"),
            reveal("x", "the secret #SECRET", scene: "s3"),
        ]
        try expectEqual(
            ContinuityKnowledgeCheck.violations(claims: claims, sceneOrder: order, similarity: sim).count, 0)
    }

    s.test("a knowledge claim with no matching reveal yields no violation") {
        let claims = [
            knows("Mara", "Mara knows something #ALONE", scene: "s2"),
            reveal("x", "an unrelated event #OTHER", scene: "s4"),
        ]
        try expectEqual(
            ContinuityKnowledgeCheck.violations(claims: claims, sceneOrder: order, similarity: sim).count, 0)
    }

    s.test("an earlier reveal does not suppress a later one — adjudication decides legitimacy") {
        // A reveal before the reference scene is ignored, not used to
        // clear the violation: embedding similarity matches topic, not
        // proposition identity, so a fuzzy early match must never veto
        // a real later reveal. The adjudicator is the precision gate.
        let claims = [
            reveal("x", "the truth #T", scene: "s1"),
            knows("Mara", "Mara knows the truth #T", scene: "s3"),
            reveal("x", "the truth restated #T", scene: "s5"),
        ]
        let v = ContinuityKnowledgeCheck.violations(claims: claims, sceneOrder: order, similarity: sim)
        try expectEqual(v.count, 1)
        try expectEqual(v[0].revealClaim.sourceSceneId, "s5")
    }

    s.test("the earliest reveal after the reference scene is the candidate") {
        let claims = [
            knows("Mara", "Mara knows P #P", scene: "s2"),
            reveal("x", "P revealed #P", scene: "s5"),
            reveal("x", "P revealed earlier #P", scene: "s3"),
        ]
        let v = ContinuityKnowledgeCheck.violations(claims: claims, sceneOrder: order, similarity: sim)
        try expectEqual(v.count, 1)
        try expectEqual(v[0].revealClaim.sourceSceneId, "s3")
    }

    s.test("within the earliest reveal scene the strongest match is the candidate") {
        func gradedSim(_ a: String, _ b: String) -> Double {
            b.contains("strong") ? 0.95 : 0.75
        }
        let claims = [
            knows("Mara", "Mara knows P", scene: "s2"),
            reveal("x", "a weak match", scene: "s4"),
            reveal("y", "a strong match", scene: "s4"),
        ]
        let v = ContinuityKnowledgeCheck.violations(
            claims: claims, sceneOrder: order, similarity: gradedSim)
        try expectEqual(v.count, 1)
        try expectEqual(v[0].revealClaim.value, "a strong match")
    }

    s.test("the default threshold rejects a weak (~0.65) match, accepts a strong (~0.75) one") {
        // The default is tuned to ~0.70: measured real reveals sit at
        // 0.73–0.94, unrelated junk below 0.70 (LOOM_CONTINUITY_AUDIT §24).
        func sim2(_ a: String, _ b: String) -> Double { b.contains("strong") ? 0.75 : 0.65 }
        let weak = [
            knows("Mara", "Mara knows P", scene: "s2"),
            reveal("x", "a weak match", scene: "s4"),
        ]
        try expectEqual(
            ContinuityKnowledgeCheck.violations(claims: weak, sceneOrder: order, similarity: sim2).count, 0)
        let strong = [
            knows("Mara", "Mara knows P", scene: "s2"),
            reveal("x", "a strong match", scene: "s4"),
        ]
        try expectEqual(
            ContinuityKnowledgeCheck.violations(claims: strong, sceneOrder: order, similarity: sim2).count, 1)
    }

    s.test("a sub-threshold similarity does not count as a reveal of the proposition") {
        let claims = [
            knows("Mara", "Mara knows the plan #PLAN", scene: "s2"),
            reveal("x", "the plan #PLAN", scene: "s4"),
        ]
        // threshold 1.1 is unreachable by the 0/1 synthetic similarity.
        try expectEqual(
            ContinuityKnowledgeCheck.violations(
                claims: claims, sceneOrder: order, similarity: sim, threshold: 1.1).count, 0)
    }

    s.test("a reveal mistyped as attribute is still matched (type-tolerant)") {
        let attrReveal = ContinuityAudit.Claim(
            type: .attribute, subject: "x", attributeKey: "", value: "the truth #T",
            sourceSceneId: "s4", source: .narration, evidenceQuote: "q")
        let claims = [
            knows("Mara", "Mara knows the truth #T", scene: "s2"),
            attrReveal,
        ]
        let v = ContinuityKnowledgeCheck.violations(claims: claims, sceneOrder: order, similarity: sim)
        try expectEqual(v.count, 1)
        try expectEqual(v[0].revealClaim.sourceSceneId, "s4")
    }

    s.test("another knowledge_state claim is not itself treated as a reveal") {
        let claims = [
            knows("Mara", "Mara knows the truth #T", scene: "s2"),
            knows("Innes", "Innes knows the truth #T", scene: "s4"),
        ]
        try expectEqual(
            ContinuityKnowledgeCheck.violations(claims: claims, sceneOrder: order, similarity: sim).count, 0)
    }

    s.test("a negated knowledge reference ('does not know') is not an auditable violation") {
        let claims = [
            knows("Marco", "Marco does not know the truth #T", scene: "s2"),
            reveal("x", "the truth #T", scene: "s4"),
        ]
        try expectEqual(
            ContinuityKnowledgeCheck.violations(claims: claims, sceneOrder: order, similarity: sim).count, 0)
    }

    s.test("a bare topic-awareness reference ('knows about the X') is not an auditable violation") {
        let claims = [
            knows("Tomas", "Tomas knows about the lighthouse #LH", scene: "s2"),
            reveal("x", "the lighthouse #LH", scene: "s4"),
        ]
        try expectEqual(
            ContinuityKnowledgeCheck.violations(claims: claims, sceneOrder: order, similarity: sim).count, 0)
    }

    s.test("'knows about' followed by a proposition is still an auditable reference") {
        let claims = [
            knows("Lirien", "Lirien knows about the King's death being a poisoning #P", scene: "s2"),
            reveal("x", "the King was poisoned #P", scene: "s4"),
        ]
        try expectEqual(
            ContinuityKnowledgeCheck.violations(claims: claims, sceneOrder: order, similarity: sim).count, 1)
    }

    s.test("claims in scenes outside the order are skipped") {
        let claims = [
            knows("Mara", "Mara knows it #X", scene: "s99"),
            reveal("x", "it #X", scene: "s4"),
        ]
        try expectEqual(
            ContinuityKnowledgeCheck.violations(claims: claims, sceneOrder: order, similarity: sim).count, 0)
    }

    return s
}

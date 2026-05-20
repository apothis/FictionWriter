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

    // MARK: - §25 Part B (redesigned) — per-knowledge-claim cosine top-K + same-fact verify
    //
    // Replaces the global FactLedger approach. For each knowledge_state
    // claim k, the function cosine-ranks all non-knowledge claims,
    // takes the top-K, walks them in scene order, and asks the
    // same-fact judge. The first same-fact match's scene determines
    // the violation outcome:
    //   - first appearance > k.scene → violation candidate
    //   - first appearance ≤ k.scene → no violation (already established)
    //   - no match in top-K → no violation flagged
    //
    // Cost: O(knowledge_claims × top_K) judge calls — independent of
    // total non-knowledge claim count. Scales to large manuscripts.

    final class StubJudge: SameFactJudging {
        var responder: (ContinuityAudit.Claim, ContinuityAudit.Claim)
            -> ContinuityAudit.SameFactVerdict = { _, _ in .differentFact }
        private var pending: [(ContinuityAudit.Claim, ContinuityAudit.Claim,
                               (Result<ContinuityAudit.SameFactJudgment, Error>) -> Void)] = []
        var calls: [(ContinuityAudit.Claim, ContinuityAudit.Claim)] = []
        var hasPending: Bool { !pending.isEmpty }
        func judge(
            claimA: ContinuityAudit.Claim, claimB: ContinuityAudit.Claim,
            completion: @escaping (Result<ContinuityAudit.SameFactJudgment, Error>) -> Void
        ) {
            calls.append((claimA, claimB))
            pending.append((claimA, claimB, completion))
        }
        func drain() {
            let p = pending; pending = []
            for (a, b, c) in p {
                c(.success(.init(verdict: responder(a, b), confidence: 1.0, explanation: "")))
            }
        }
    }
    func driveJudge(_ j: StubJudge) { while j.hasPending { j.drain() } }

    // "Same fact" iff the two values share a `#TAG`. Used with a
    // matching synthetic embedder: each `#TAG` is one dimension of
    // a one-hot vector, so cosine = 1.0 when tags match and 0.0
    // otherwise — mirrors the real flow where cosine ranks
    // topical candidates and the LLM judges proposition identity.
    let tagJudgeResponder: (ContinuityAudit.Claim, ContinuityAudit.Claim)
        -> ContinuityAudit.SameFactVerdict = { a, b in
        func tags(_ t: String) -> Set<String> {
            Set(t.split(separator: " ").map(String.init).filter { $0.hasPrefix("#") })
        }
        return tags(a.value).isDisjoint(with: tags(b.value)) ? .differentFact : .sameFact
    }

    // Synthetic embedder: one-hot per #TAG. Multiple tags average
    // (after normalisation). Tag → dimension is a simple hash.
    let dim = 16
    func tagEmbedding(_ value: String) -> [Float] {
        var v = [Float](repeating: 0, count: dim)
        let tags = value.split(separator: " ").map(String.init).filter { $0.hasPrefix("#") }
        if tags.isEmpty { return v }
        for t in tags {
            let h = abs(t.hashValue) % dim
            v[h] = 1
        }
        // Normalise so cosineSim works
        let norm = (v.map { $0 * $0 }.reduce(0, +)).squareRoot()
        return norm == 0 ? v : v.map { $0 / norm }
    }
    func embeddingsFor(_ claims: [ContinuityAudit.Claim]) -> [String: [Float]] {
        var out: [String: [Float]] = [:]
        for c in claims { out[c.value] = tagEmbedding(c.value) }
        return out
    }

    s.test("a knowledge claim at scene N with a same-fact candidate at scene > N → violation") {
        let k = knows("Mara", "Mara knows the money is missing #MONEY", scene: "s2")
        let r = reveal("fund", "the money is missing #MONEY", scene: "s4")
        let judge = StubJudge()
        judge.responder = tagJudgeResponder
        var got: [ContinuityKnowledgeCheck.Violation]?
        ContinuityKnowledgeCheck.violations(
            knowledgeClaims: [k], candidateClaims: [r],
            embeddings: embeddingsFor([k, r]),
            sceneOrder: order, judge: judge, topK: 5
        ) { got = $0 }
        driveJudge(judge)
        let v = try expectNotNil(got)
        try expectEqual(v.count, 1)
        try expectEqual(v[0].knowledgeClaim.sourceSceneId, "s2")
        try expectEqual(v[0].revealClaim.sourceSceneId, "s4")
    }

    s.test("a knowledge claim whose same-fact candidate is in an earlier scene → no violation") {
        let r = reveal("Cole", "Cole's brother drowned #DROWN", scene: "s2")
        let k = knows("Mara", "Mara knows Cole's brother drowned #DROWN", scene: "s3")
        let judge = StubJudge()
        judge.responder = tagJudgeResponder
        var got: [ContinuityKnowledgeCheck.Violation]?
        ContinuityKnowledgeCheck.violations(
            knowledgeClaims: [k], candidateClaims: [r],
            embeddings: embeddingsFor([k, r]),
            sceneOrder: order, judge: judge, topK: 5
        ) { got = $0 }
        driveJudge(judge)
        try expectEqual(try expectNotNil(got).count, 0)
    }

    s.test("a knowledge claim with no same-fact candidate yields no violation") {
        let k = knows("Mara", "Mara knows it #X", scene: "s2")
        let other = reveal("y", "something else #Y", scene: "s4")
        let judge = StubJudge()
        judge.responder = tagJudgeResponder
        var got: [ContinuityKnowledgeCheck.Violation]?
        ContinuityKnowledgeCheck.violations(
            knowledgeClaims: [k], candidateClaims: [other],
            embeddings: embeddingsFor([k, other]),
            sceneOrder: order, judge: judge, topK: 5
        ) { got = $0 }
        driveJudge(judge)
        try expectEqual(try expectNotNil(got).count, 0)
    }

    s.test("a same-scene candidate is not a violation (first appearance ≤ reference scene)") {
        let r = reveal("x", "the fact #X", scene: "s3")
        let k = knows("Mara", "Mara knows it #X", scene: "s3")
        let judge = StubJudge()
        judge.responder = tagJudgeResponder
        var got: [ContinuityKnowledgeCheck.Violation]?
        ContinuityKnowledgeCheck.violations(
            knowledgeClaims: [k], candidateClaims: [r],
            embeddings: embeddingsFor([k, r]),
            sceneOrder: order, judge: judge, topK: 5
        ) { got = $0 }
        driveJudge(judge)
        try expectEqual(try expectNotNil(got).count, 0)
    }

    s.test("a negated knowledge reference is not auditable — judge never called") {
        let k = knows("Mara", "Mara does not know the fact #X", scene: "s2")
        let r = reveal("x", "the fact #X", scene: "s4")
        let judge = StubJudge()
        judge.responder = tagJudgeResponder
        var got: [ContinuityKnowledgeCheck.Violation]?
        ContinuityKnowledgeCheck.violations(
            knowledgeClaims: [k], candidateClaims: [r],
            embeddings: embeddingsFor([k, r]),
            sceneOrder: order, judge: judge, topK: 5
        ) { got = $0 }
        driveJudge(judge)
        try expectEqual(try expectNotNil(got).count, 0)
        try expectEqual(judge.calls.count, 0,
                        "trivial references are filtered before the judge is asked")
    }

    s.test("knowledge claim with no embedding is skipped — judge never called") {
        let k = knows("Mara", "Mara knows X #X", scene: "s2")
        let r = reveal("x", "the fact #X", scene: "s4")
        let judge = StubJudge()
        judge.responder = tagJudgeResponder
        var got: [ContinuityKnowledgeCheck.Violation]?
        // Only embed `r`, not `k`. The check must gracefully skip k.
        ContinuityKnowledgeCheck.violations(
            knowledgeClaims: [k], candidateClaims: [r],
            embeddings: embeddingsFor([r]),
            sceneOrder: order, judge: judge, topK: 5
        ) { got = $0 }
        driveJudge(judge)
        try expectEqual(try expectNotNil(got).count, 0)
        try expectEqual(judge.calls.count, 0)
    }

    s.test("top-K is respected — only the closest candidates are sent to the judge") {
        // 8 candidates topically distinct from k by cosine. With
        // topK=3 the judge sees at most 3 — the 3 closest by cosine.
        // Because the synthetic embedder one-hots per tag, only the
        // candidate sharing #X has nonzero similarity; the others all
        // have cosine=0. The top-K cut means the judge sees at most
        // top-K candidates regardless of how many score zero.
        let k = knows("Mara", "Mara knows X #X", scene: "s2")
        let r = reveal("x", "the fact #X", scene: "s4")
        let distractors = (0..<7).map {
            reveal("d\($0)", "distractor \($0) #D\($0)", scene: "s5")
        }
        let judge = StubJudge()
        judge.responder = tagJudgeResponder
        var got: [ContinuityKnowledgeCheck.Violation]?
        ContinuityKnowledgeCheck.violations(
            knowledgeClaims: [k], candidateClaims: [r] + distractors,
            embeddings: embeddingsFor([k, r] + distractors),
            sceneOrder: order, judge: judge, topK: 3
        ) { got = $0 }
        driveJudge(judge)
        try expectEqual(try expectNotNil(got).count, 1)
        try expectTrue(judge.calls.count <= 3,
                       "the judge must see at most top_K candidates per knowledge claim")
    }

    s.test("walks candidates in scene order — first same-fact match wins") {
        // Two same-fact candidates, one at scene s3 and one at s5.
        // The scene-order walk should ask about s3 first; once a
        // match lands, walking stops. Since both are at scene > k
        // (s2), either match yields a violation, but the reveal is
        // the EARLIEST scene's candidate.
        let k = knows("Mara", "Mara knows X #X", scene: "s2")
        let r1 = reveal("a", "X happened #X", scene: "s5")  // input order: s5 first
        let r2 = reveal("b", "X is the case #X", scene: "s3")
        let judge = StubJudge()
        judge.responder = tagJudgeResponder
        var got: [ContinuityKnowledgeCheck.Violation]?
        ContinuityKnowledgeCheck.violations(
            knowledgeClaims: [k], candidateClaims: [r1, r2],
            embeddings: embeddingsFor([k, r1, r2]),
            sceneOrder: order, judge: judge, topK: 5
        ) { got = $0 }
        driveJudge(judge)
        let v = try expectNotNil(got)
        try expectEqual(v.count, 1)
        try expectEqual(v[0].revealClaim, r2,
                        "the earliest-scene same-fact candidate must be the reveal")
    }

    s.test("mixed knowledge claims — independent results per claim") {
        let early = knows("Mara", "Mara knows the money is missing #MONEY", scene: "s2")
        let late = knows("Cole", "Cole knows the brother drowned #DROWN", scene: "s5")
        let r1 = reveal("fund", "the money is missing #MONEY", scene: "s4")
        let r2 = reveal("Cole", "Cole's brother drowned #DROWN", scene: "s3")
        let judge = StubJudge()
        judge.responder = tagJudgeResponder
        var got: [ContinuityKnowledgeCheck.Violation]?
        ContinuityKnowledgeCheck.violations(
            knowledgeClaims: [early, late], candidateClaims: [r1, r2],
            embeddings: embeddingsFor([early, late, r1, r2]),
            sceneOrder: order, judge: judge, topK: 5
        ) { got = $0 }
        driveJudge(judge)
        let v = try expectNotNil(got)
        try expectEqual(v.count, 1)
        try expectEqual(v[0].knowledgeClaim, early,
                        "only the early reference is a violation (its reveal is in a later scene)")
        try expectEqual(v[0].revealClaim, r1)
    }

    s.test("violations completes on N=2000 candidates without stack overflow") {
        // Regression — async state-machine shape (post-2026-05-20).
        // Stack depth is bounded by 1 per outstanding judge call,
        // independent of the candidate count.
        let k = knows("Mara", "Mara knows X #X", scene: "s2")
        let candidates = (0..<2000).map { i in
            reveal("subj-\(i)", "irrelevant-\(i) #D\(i)", scene: "s4")
        }
        let judge = StubJudge()
        var got: [ContinuityKnowledgeCheck.Violation]?
        ContinuityKnowledgeCheck.violations(
            knowledgeClaims: [k], candidateClaims: candidates,
            embeddings: embeddingsFor([k] + candidates),
            sceneOrder: order, judge: judge, topK: 10
        ) { got = $0 }
        driveJudge(judge)
        try expectEqual(try expectNotNil(got).count, 0,
                        "no violations when no candidate shares a tag with k")
    }

    return s
}

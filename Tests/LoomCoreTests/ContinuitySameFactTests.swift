import Foundation
@testable import LoomCore

/// Continuity Audit (L10) — §25 Part B probe scaffolding. Same-fact
/// judgment is the proposition-identity primitive Part B's world-state
/// fact ledger needs in order to cluster claims into canonical fact
/// nodes. It is a sibling of `KnowledgeVerdict` (§24) — different
/// question ("do these assert the same proposition?" rather than
/// "knowledge before reveal?") but the same vocabulary/schema/parser
/// shape, which is what makes it cheap to probe before committing to
/// build Part B around it.
func continuitySameFactTests() -> TestSuite {
    let s = TestSuite("ContinuitySameFact")

    func claim(
        _ type: ContinuityAudit.ClaimType,
        subject: String,
        key: String = "",
        value: String,
        scene: String,
        source: ContinuityAudit.ClaimSource = .narration,
        quote: String
    ) -> ContinuityAudit.Claim {
        ContinuityAudit.Claim(
            type: type, subject: subject, attributeKey: key, value: value,
            sourceSceneId: scene, source: source, evidenceQuote: quote
        )
    }

    let a = claim(.attribute, subject: "the vault", key: "floor",
                  value: "the vault is on the fourteenth floor",
                  scene: "scene-1", quote: "fourteenth floor vault")
    let b = claim(.attribute, subject: "the vault", key: "floor",
                  value: "the fourteenth-floor vault",
                  scene: "scene-3", quote: "up to the fourteenth")

    s.test("the same-fact verdict vocabulary is {same_fact, different_fact}") {
        try expectEqual(Set(ContinuityAudit.SameFactVerdict.allCases.map(\.rawValue)),
                        ["same_fact", "different_fact"])
    }

    s.test("SameFactJudgment round-trips through Codable") {
        let j = ContinuityAudit.SameFactJudgment(
            verdict: .sameFact, confidence: 0.8,
            explanation: "same proposition, paraphrased"
        )
        let data = try JSONEncoder().encode(j)
        let decoded = try JSONDecoder().decode(ContinuityAudit.SameFactJudgment.self, from: data)
        try expectEqual(decoded, j)
    }

    s.test("the same-fact prompt carries both claim values") {
        let prompt = ContinuityAudit.buildSameFactPrompt(claimA: a, claimB: b)
        try expectTrue(prompt.contains("the vault is on the fourteenth floor"))
        try expectTrue(prompt.contains("the fourteenth-floor vault"))
    }

    s.test("the same-fact prompt judges proposition identity, not shared topic") {
        // The §24 lesson: two claims about the same subject can be
        // *different* propositions. The prompt must steer the model to
        // compare the specific assertion, not the shared topic — and
        // explicitly offer the "different fact, same topic" verdict.
        let prompt = ContinuityAudit.buildSameFactPrompt(claimA: a, claimB: b).lowercased()
        try expectTrue(prompt.contains("proposition") || prompt.contains("specific"),
                       "the prompt must direct the model to the specific proposition")
        try expectTrue(prompt.contains("topic"),
                       "the prompt must offer the same-topic-different-fact case explicitly")
    }

    s.test("the same-fact prompt names the same_fact and different_fact verdicts") {
        let prompt = ContinuityAudit.buildSameFactPrompt(claimA: a, claimB: b)
        try expectTrue(prompt.contains("same_fact"))
        try expectTrue(prompt.contains("different_fact"))
    }

    s.test("the same-fact JSON schema constrains the verdict to its enum") {
        let schema = ContinuityAudit.sameFactJSONSchema()
        let props = schema["properties"] as? [String: Any]
        let verdictEnum = (props?["verdict"] as? [String: Any])?["enum"] as? [String]
        try expectEqual(Set(verdictEnum ?? []), ["same_fact", "different_fact"])
    }

    s.test("parseSameFact decodes same_fact and different_fact") {
        let s1 = try ContinuityAudit.parseSameFact(
            #"{"verdict":"same_fact","confidence":0.9,"explanation":"paraphrase"}"#)
        try expectEqual(s1.verdict, .sameFact)
        try expectEqual(s1.confidence, 0.9)
        try expectEqual(s1.explanation, "paraphrase")
        let s2 = try ContinuityAudit.parseSameFact(
            #"prose {"verdict":"different_fact","confidence":0.3,"explanation":"different proposition"}"#)
        try expectEqual(s2.verdict, .differentFact)
    }

    s.test("parseSameFact clamps confidence into 0...1") {
        let high = try ContinuityAudit.parseSameFact(
            #"{"verdict":"same_fact","confidence":1.4,"explanation":"x"}"#)
        try expectEqual(high.confidence, 1.0)
        let low = try ContinuityAudit.parseSameFact(
            #"{"verdict":"different_fact","confidence":-0.2,"explanation":"x"}"#)
        try expectEqual(low.confidence, 0.0)
    }

    s.test("parseSameFact throws on a non-same-fact verdict word") {
        do {
            _ = try ContinuityAudit.parseSameFact(
                #"{"verdict":"contradiction","confidence":0.5,"explanation":"x"}"#)
            try expectFalse(true, "expected a throw for a non-same-fact verdict word")
        } catch {}
    }

    s.test("parseSameFact throws when there is no JSON object") {
        do {
            _ = try ContinuityAudit.parseSameFact("no json here")
            try expectFalse(true, "expected a throw on missing JSON")
        } catch {}
    }

    return s
}

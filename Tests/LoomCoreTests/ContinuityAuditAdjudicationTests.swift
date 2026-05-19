import Foundation
@testable import LoomCore

/// Continuity Audit (L10) — Phase A spike, the pairwise adjudication
/// layer. Given two same-subject claims, the LLM judges whether the
/// later one contradicts the earlier. Localized pair judgment, not
/// whole-document — the ContraDoc lesson.
func continuityAuditAdjudicationTests() -> TestSuite {
    let s = TestSuite("ContinuityAuditAdjudication")

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

    let earlier = claim(.attribute, subject: "Mara", key: "eye colour",
                        value: "Mara's eyes are green", scene: "scene-1",
                        quote: "her green eyes")
    let later = claim(.attribute, subject: "Mara", key: "eye colour",
                      value: "Mara's eyes are brown", scene: "scene-3",
                      quote: "his brown-eyed gaze")

    // MARK: - Types

    s.test("Adjudication round-trips through Codable") {
        let adj = ContinuityAudit.Adjudication(
            verdict: .contradiction, confidence: 0.9,
            explanation: "green then brown"
        )
        let data = try JSONEncoder().encode(adj)
        let decoded = try JSONDecoder().decode(ContinuityAudit.Adjudication.self, from: data)
        try expectEqual(decoded, adj)
    }

    s.test("the three verdicts are all present") {
        try expectEqual(Set(ContinuityAudit.Verdict.allCases.map(\.rawValue)),
                        ["contradiction", "consistent", "evolution"])
    }

    // MARK: - Prompt + schema

    s.test("the adjudication prompt carries both claims and their evidence") {
        let prompt = ContinuityAudit.buildAdjudicationPrompt(earlier: earlier, later: later)
        try expectTrue(prompt.contains("Mara's eyes are green"))
        try expectTrue(prompt.contains("Mara's eyes are brown"))
        try expectTrue(prompt.contains("her green eyes"))
        try expectTrue(prompt.contains("his brown-eyed gaze"))
    }

    s.test("the adjudication prompt explains the dialogue-source precision rule") {
        let prompt = ContinuityAudit.buildAdjudicationPrompt(earlier: earlier, later: later).lowercased()
        try expectTrue(prompt.contains("dialogue"),
                       "the prompt must tell the model a spoken claim is the character's assertion")
    }

    s.test("the adjudication prompt offers the evolution verdict for legitimate change") {
        let prompt = ContinuityAudit.buildAdjudicationPrompt(earlier: earlier, later: later).lowercased()
        try expectTrue(prompt.contains("evolution"))
    }

    s.test("the knowledge-adjudication prompt carries the reference and the reveal") {
        let reference = claim(.knowledgeState, subject: "Mara", value: "Mara knows the vault is empty",
                              scene: "scene-2", source: .dialogue, quote: "the vault's empty")
        let reveal = claim(.event, subject: "the vault", value: "The empty vault is discovered",
                           scene: "scene-5", quote: "they found the vault bare")
        let prompt = ContinuityAudit.buildKnowledgeAdjudicationPrompt(
            reference: reference, reveal: reveal,
            referenceContext: "ref scene", revealContext: "reveal scene")
        try expectTrue(prompt.contains("Mara knows the vault is empty"))
        try expectTrue(prompt.contains("The empty vault is discovered"))
        // it must offer the non-error way out
        try expectTrue(prompt.lowercased().contains("not_a_violation"))
    }

    s.test("the knowledge-adjudication prompt says agreement is not a reason to clear the error") {
        let reference = claim(.knowledgeState, subject: "Mara", value: "Mara knows the vault is empty",
                              scene: "scene-2", source: .dialogue, quote: "the vault's empty")
        let reveal = claim(.event, subject: "the vault", value: "The empty vault is discovered",
                           scene: "scene-5", quote: "they found the vault bare")
        let prompt = ContinuityAudit.buildKnowledgeAdjudicationPrompt(
            reference: reference, reveal: reveal,
            referenceContext: "ref scene", revealContext: "reveal scene").lowercased()
        // The two claims agreeing about the fact IS the violation — the
        // model must not read agreement as "consistent / no error" (§24).
        try expectTrue(prompt.contains("agree"),
                       "the prompt must address that the two claims agreeing is expected, not a clear")
    }

    s.test("parseKnowledgeAdjudication decodes violation and not_a_violation") {
        let v = try ContinuityAudit.parseKnowledgeAdjudication(
            #"{"verdict":"violation","confidence":0.9,"explanation":"same fact"}"#)
        try expectEqual(v.verdict, .violation)
        try expectEqual(v.confidence, 0.9)
        let n = try ContinuityAudit.parseKnowledgeAdjudication(
            #"prose {"verdict":"not_a_violation","confidence":0.4,"explanation":"different facts"}"#)
        try expectEqual(n.verdict, .notAViolation)
    }

    s.test("parseKnowledgeAdjudication throws on a non-knowledge verdict") {
        do {
            _ = try ContinuityAudit.parseKnowledgeAdjudication(
                #"{"verdict":"contradiction","confidence":1,"explanation":"x"}"#)
            try expectFalse(true, "expected a throw for a non-knowledge verdict word")
        } catch {}
    }

    s.test("evidenceContextWindow returns the quote framed by surrounding prose") {
        let prose = String(repeating: "a ", count: 400) + "THE QUOTE HERE "
            + String(repeating: "b ", count: 400)
        let w = ContinuityAudit.evidenceContextWindow(quote: "THE QUOTE HERE", in: prose, radius: 120)
        try expectTrue(w.contains("THE QUOTE HERE"))
        try expectTrue(w.count < prose.count, "the window must be smaller than the full prose")
        try expectTrue(w.contains("…"), "a window cut from longer prose is ellipsis-marked")
    }

    s.test("evidenceContextWindow falls back to the prose when the quote is absent") {
        let w = ContinuityAudit.evidenceContextWindow(
            quote: "not present", in: "a short scene of prose", radius: 120)
        try expectTrue(w.contains("a short scene of prose"))
    }

    s.test("the knowledge-adjudication prompt carries the scene-context windows") {
        let reference = claim(.knowledgeState, subject: "Mara", value: "Mara knows the vault is empty",
                              scene: "scene-2", source: .dialogue, quote: "the vault's empty")
        let reveal = claim(.event, subject: "the vault", value: "The empty vault is discovered",
                           scene: "scene-5", quote: "they found the vault bare")
        let prompt = ContinuityAudit.buildKnowledgeAdjudicationPrompt(
            reference: reference, reveal: reveal,
            referenceContext: "Mara whispered that the vault's empty, eyes down.",
            revealContext: "They cracked the door and found the vault bare.")
        try expectTrue(prompt.contains("Mara whispered that the vault's empty, eyes down."))
        try expectTrue(prompt.contains("They cracked the door and found the vault bare."))
    }

    s.test("the knowledge-adjudication JSON schema constrains the verdict to violation / not_a_violation") {
        let schema = ContinuityAudit.knowledgeAdjudicationJSONSchema()
        let props = schema["properties"] as? [String: Any]
        let verdictEnum = (props?["verdict"] as? [String: Any])?["enum"] as? [String]
        try expectEqual(Set(verdictEnum ?? []), ["violation", "not_a_violation"])
    }

    s.test("the knowledge-adjudication prompt judges proposition identity, not shared topic") {
        let reference = claim(.knowledgeState, subject: "Mara", value: "Mara knows the vault is empty",
                              scene: "scene-2", source: .dialogue, quote: "the vault's empty")
        let reveal = claim(.event, subject: "the vault", value: "The empty vault is discovered",
                           scene: "scene-5", quote: "they found the vault bare")
        let prompt = ContinuityAudit.buildKnowledgeAdjudicationPrompt(
            reference: reference, reveal: reveal,
            referenceContext: "ref scene", revealContext: "reveal scene").lowercased()
        // It must steer the model to compare the specific proposition, not
        // merely the shared subject/topic — and to read the scene text
        // rather than trust the imprecise one-line claims.
        try expectTrue(prompt.contains("specific"),
                       "the prompt must tell the model to compare the specific fact, not the topic")
        try expectTrue(prompt.contains("imprecise"),
                       "the prompt must say the one-line claims are imprecise — read the scene text")
    }

    s.test("the adjudication JSON schema constrains the verdict to its enum") {
        let schema = ContinuityAudit.adjudicationJSONSchema()
        let props = schema["properties"] as? [String: Any]
        let verdictEnum = (props?["verdict"] as? [String: Any])?["enum"] as? [String]
        try expectEqual(Set(verdictEnum ?? []), ["contradiction", "consistent", "evolution"])
    }

    // MARK: - Parser

    s.test("parseAdjudication decodes a clean object") {
        let raw = """
        {"verdict":"contradiction","confidence":0.85,"explanation":"green vs brown"}
        """
        let adj = try ContinuityAudit.parseAdjudication(raw)
        try expectEqual(adj.verdict, .contradiction)
        try expectEqual(adj.confidence, 0.85)
        try expectEqual(adj.explanation, "green vs brown")
    }

    s.test("parseAdjudication tolerates chatty preamble") {
        let raw = """
        Here is my judgment:
        {"verdict":"consistent","confidence":0.4,"explanation":"no conflict"}
        """
        let adj = try ContinuityAudit.parseAdjudication(raw)
        try expectEqual(adj.verdict, .consistent)
    }

    s.test("parseAdjudication clamps confidence into 0...1") {
        let high = try ContinuityAudit.parseAdjudication(
            #"{"verdict":"evolution","confidence":1.7,"explanation":"x"}"#)
        try expectEqual(high.confidence, 1.0)
        let low = try ContinuityAudit.parseAdjudication(
            #"{"verdict":"evolution","confidence":-0.5,"explanation":"x"}"#)
        try expectEqual(low.confidence, 0.0)
    }

    s.test("parseAdjudication throws on an unknown verdict") {
        do {
            _ = try ContinuityAudit.parseAdjudication(
                #"{"verdict":"maybe","confidence":0.5,"explanation":"x"}"#)
            try expectTrue(false, "expected a throw")
        } catch {
            // expected
        }
    }

    s.test("parseAdjudication throws when there is no JSON object") {
        do {
            _ = try ContinuityAudit.parseAdjudication("no json")
            try expectTrue(false, "expected a throw")
        } catch {
            // expected
        }
    }

    return s
}

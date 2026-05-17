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

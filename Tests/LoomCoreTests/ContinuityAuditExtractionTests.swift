import Foundation
@testable import LoomCore

/// Continuity Audit (L10) — Phase A spike, the per-scene typed-claim
/// extraction layer (pure data). `ContinuityAudit.Claim` is the atomic
/// decontextualised unit; `buildExtractionPrompt` / `parseClaims`
/// mirror the proven `LedgerExtraction` shape.
func continuityAuditExtractionTests() -> TestSuite {
    let s = TestSuite("ContinuityAuditExtraction")

    // MARK: - Types

    s.test("Claim round-trips through Codable") {
        let claim = ContinuityAudit.Claim(
            id: UUID(),
            type: .attribute,
            subject: "Mara",
            attributeKey: "eye colour",
            value: "green",
            sourceSceneId: "scene-1",
            source: .narration,
            evidenceQuote: "her green eyes caught the light"
        )
        let data = try JSONEncoder().encode(claim)
        let decoded = try JSONDecoder().decode(ContinuityAudit.Claim.self, from: data)
        try expectEqual(decoded, claim)
    }

    s.test("ClaimType knowledgeState uses a snake_case wire value") {
        try expectEqual(ContinuityAudit.ClaimType.knowledgeState.rawValue, "knowledge_state")
    }

    s.test("the five claim types are all present") {
        try expectEqual(Set(ContinuityAudit.ClaimType.allCases.map(\.rawValue)),
                        ["attribute", "event", "knowledge_state", "temporal", "spatial"])
    }

    // MARK: - Prompt + schema

    s.test("the extraction prompt carries the scene prose") {
        let prompt = ContinuityAudit.buildExtractionPrompt(
            scenePose: "Mara walked the SENTINELQUOTE cliff path at dawn."
        )
        try expectTrue(prompt.contains("SENTINELQUOTE"))
    }

    s.test("the extraction prompt names every claim type for the model") {
        let prompt = ContinuityAudit.buildExtractionPrompt(scenePose: "A scene.").lowercased()
        for t in ["attribute", "event", "knowledge", "temporal", "spatial"] {
            try expectTrue(prompt.contains(t), "prompt should describe the \(t) claim type")
        }
    }


    // MARK: - Parser

    s.test("parseClaims decodes a clean array and stamps the scene id") {
        let raw = """
        [
          {"type":"attribute","subject":"Mara","attribute_key":"eye colour",
           "value":"green","source":"narration","evidence_quote":"her green eyes"},
          {"type":"temporal","subject":"the village","attribute_key":"",
           "value":"autumn","source":"narration","evidence_quote":"the autumn wind"}
        ]
        """
        let claims = try ContinuityAudit.parseClaims(raw, sourceSceneId: "scene-7")
        try expectEqual(claims.count, 2)
        try expectEqual(claims[0].type, .attribute)
        try expectEqual(claims[0].value, "green")
        try expectEqual(claims[1].type, .temporal)
        try expectTrue(claims.allSatisfy { $0.sourceSceneId == "scene-7" })
        try expectTrue(claims[0].id != claims[1].id)
    }

    s.test("parseClaims tolerates chatty preamble and postamble") {
        let raw = """
        Sure, here are the claims I found:
        [{"type":"event","subject":"Cole","attribute_key":"",
          "value":"Cole's brother drowned","source":"dialogue","evidence_quote":"my brother drowned"}]
        Let me know if you need more.
        """
        let claims = try ContinuityAudit.parseClaims(raw, sourceSceneId: "s1")
        try expectEqual(claims.count, 1)
        try expectEqual(claims[0].source, .dialogue)
    }

    s.test("parseClaims recovers per-object from an unclosed array") {
        let raw = """
        [{"type":"spatial","subject":"the lighthouse","attribute_key":"position",
          "value":"north of the village","source":"narration","evidence_quote":"the lighthouse north of town"},
         {"type":"attribute","subject":"Mara","attribute_key":"eye colour",
          "value":"green","source":"narration","evidence_quote":"green eyes"
        """
        let claims = try ContinuityAudit.parseClaims(raw, sourceSceneId: "s1")
        try expectEqual(claims.count, 1)
        try expectEqual(claims[0].type, .spatial)
    }

    s.test("parseClaims drops an entry with an unknown claim type but keeps siblings") {
        let raw = """
        [{"type":"vibe","subject":"x","attribute_key":"","value":"y","source":"narration","evidence_quote":"q"},
         {"type":"event","subject":"Mara","attribute_key":"","value":"Mara left","source":"narration","evidence_quote":"she left"}]
        """
        let claims = try ContinuityAudit.parseClaims(raw, sourceSceneId: "s1")
        try expectEqual(claims.count, 1)
        try expectEqual(claims[0].type, .event)
    }

    s.test("parseClaims decodes JSONL — one object per line, no array") {
        let raw = """
        {"type":"attribute","subject":"Mara","attribute_key":"eye colour","value":"green","source":"narration","evidence_quote":"green eyes"}
        {"type":"event","subject":"Cole","attribute_key":"","value":"Cole left","source":"narration","evidence_quote":"he left"}
        """
        let claims = try ContinuityAudit.parseClaims(raw, sourceSceneId: "s4")
        try expectEqual(claims.count, 2)
        try expectEqual(claims[0].type, .attribute)
        try expectEqual(claims[1].type, .event)
        try expectTrue(claims.allSatisfy { $0.sourceSceneId == "s4" })
    }

    s.test("parseClaims throws when there is no JSON object at all") {
        do {
            _ = try ContinuityAudit.parseClaims("no json here", sourceSceneId: "s1")
            try expectTrue(false, "expected a throw")
        } catch {
            // expected
        }
    }

    s.test("the extraction prompt pins the JSONL format and the six field names") {
        let prompt = ContinuityAudit.buildExtractionPrompt(scenePose: "A scene.")
        try expectTrue(prompt.lowercased().contains("one json object per line"))
        for field in ["type", "subject", "attribute_key", "value", "source", "evidence_quote"] {
            try expectTrue(prompt.contains("\"\(field)\""), "prompt must pin the \(field) key")
        }
    }

    return s
}

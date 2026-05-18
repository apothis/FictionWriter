import Foundation
@testable import LoomCore

/// Continuity Audit (L10) — Phase B, the type-classification stage.
/// The Goetia/gemma A/B showed a 24B model finds *more* facts but is
/// no better at typing them — typing is overloaded when one call does
/// recall + typing + JSON + quoting at once (the Claimify lesson). So
/// extraction's type is re-decided by a focused, scene-scoped pass.
func continuityTypingTests() -> TestSuite {
    let s = TestSuite("ContinuityTyping")

    func claim(_ value: String) -> ContinuityAudit.Claim {
        ContinuityAudit.Claim(
            type: .event, subject: "x", attributeKey: "", value: value,
            sourceSceneId: "s1", source: .narration, evidenceQuote: "q")
    }

    s.test("the typing prompt carries the scene and a numbered claim list") {
        let prompt = ContinuityAudit.buildTypingPrompt(
            scenePose: "SCENEMARKER prose.",
            claims: [claim("Mara has green eyes"), claim("Cole left the room")])
        try expectTrue(prompt.contains("SCENEMARKER"))
        try expectTrue(prompt.contains("1."))
        try expectTrue(prompt.contains("Mara has green eyes"))
        try expectTrue(prompt.contains("2."))
        try expectTrue(prompt.contains("Cole left the room"))
    }

    s.test("the typing prompt defines all five types") {
        let prompt = ContinuityAudit.buildTypingPrompt(scenePose: "x", claims: [claim("c")]).lowercased()
        for t in ["attribute", "event", "knowledge", "temporal", "spatial"] {
            try expectTrue(prompt.contains(t))
        }
    }

    s.test("parseTypes maps numbered lines to claim indices, zero-based") {
        let raw = """
        1. attribute
        2. event
        3. spatial
        """
        let types = ContinuityAudit.parseTypes(raw, count: 3)
        try expectEqual(types[0], .attribute)
        try expectEqual(types[1], .event)
        try expectEqual(types[2], .spatial)
    }

    s.test("parseTypes tolerates assorted separators and preamble") {
        let raw = """
        Here are the types:
        1) knowledge_state
        2: temporal
        """
        let types = ContinuityAudit.parseTypes(raw, count: 2)
        try expectEqual(types[0], .knowledgeState)
        try expectEqual(types[1], .temporal)
    }

    s.test("parseTypes ignores an unknown type and an out-of-range index") {
        let raw = """
        1. vibes
        2. attribute
        9. event
        """
        let types = ContinuityAudit.parseTypes(raw, count: 2)
        try expectNil(types[0])
        try expectEqual(types[1], .attribute)
        try expectNil(types[8])
    }

    return s
}

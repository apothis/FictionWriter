import Foundation
@testable import LoomCore

/// Pure-data tests for the production Kobold→NarrativeMode wiring.
/// Mirrors the patterns in
/// [`Sources/LoomCore/Retrieval/EmbeddingClients.swift`](Sources/LoomCore/Retrieval/EmbeddingClients.swift)
/// (KoboldEmbeddingsRequest / Response): build the request body in a
/// pure-data layer, parse the response in a pure-data layer, leave
/// the URLSession glue to the call site / synchronous wrapper.
func phase5KoboldNarrativeModeTests() -> TestSuite {
    let s = TestSuite("Phase5KoboldNarrativeMode")

    // MARK: - Prompt template

    s.test("zero-shot prompt embeds the passage and names all six categories") {
        let prompt = KoboldNarrativeModeRequest.zeroShotPrompt(
            passage: "She walked into the room."
        )
        try expectTrue(prompt.contains("She walked into the room."))
        try expectTrue(prompt.contains("action"))
        try expectTrue(prompt.contains("dialogue"))
        try expectTrue(prompt.contains("interiority"))
        try expectTrue(prompt.contains("description"))
        try expectTrue(prompt.contains("summary"))
        try expectTrue(prompt.contains("mixed"))
    }

    s.test("prompt ends with 'Mode:' anchor so generation completes after a single label") {
        let prompt = KoboldNarrativeModeRequest.zeroShotPrompt(passage: "x")
        try expectTrue(prompt.hasSuffix("Mode:"))
    }

    // MARK: - Grammar

    s.test("grammar is a flat enum alternation (Lost-in-Space failure-mode fix)") {
        // Per LOOM_NARRATIVE_MODE_SPIKE §3.2(b): the GBNF MUST be a
        // flat alternation of bare labels — no JSON wrapper, no
        // nested structure. Nested JSON triggers the gemma-31B
        // collapse failure mode (Bastan et al. 2025).
        let g = KoboldNarrativeModeRequest.grammar
        try expectTrue(g.contains("root"))
        try expectTrue(g.contains("\"action\""))
        try expectTrue(g.contains("\"dialogue\""))
        try expectTrue(g.contains("\"mixed\""))
        try expectTrue(g.contains("|"))
        try expectFalse(g.contains("{"))
        try expectFalse(g.contains("["))
    }

    // MARK: - Request body

    s.test("body encodes prompt + grammar + low-temperature + tight max_length") {
        let data = KoboldNarrativeModeRequest.body(passage: "Test passage.")
        let parsed = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        _ = try expectNotNil(parsed["prompt"] as? String)
        _ = try expectNotNil(parsed["grammar"] as? String)
        try expectEqual(parsed["max_length"] as? Int, 8)
        try expectEqual(parsed["temperature"] as? Double, 0.0)
        try expectEqual(parsed["rep_pen"] as? Double, 1.0)
    }

    // MARK: - Response parser

    s.test("response parser decodes a valid label from the kobold shape") {
        let data = """
        {"results": [{"text": "action"}]}
        """.data(using: .utf8)!
        try expectEqual(KoboldNarrativeModeRequest.parse(data), .action)
    }

    s.test("response parser trims whitespace around the label") {
        // gemma occasionally emits leading or trailing whitespace
        // even with grammar — the "Lost in Space" 2025 paper
        // recommends explicit leading-whitespace tolerance.
        let data = """
        {"results": [{"text": "  dialogue\\n"}]}
        """.data(using: .utf8)!
        try expectEqual(KoboldNarrativeModeRequest.parse(data), .dialogue)
    }

    s.test("response parser returns nil for non-enum text (out-of-grammar output)") {
        let data = """
        {"results": [{"text": "narrative"}]}
        """.data(using: .utf8)!
        try expectNil(KoboldNarrativeModeRequest.parse(data))
    }

    s.test("response parser returns nil for malformed JSON") {
        try expectNil(KoboldNarrativeModeRequest.parse(Data("not json".utf8)))
    }

    s.test("response parser returns nil for empty results array") {
        let data = """
        {"results": []}
        """.data(using: .utf8)!
        try expectNil(KoboldNarrativeModeRequest.parse(data))
    }

    return s
}

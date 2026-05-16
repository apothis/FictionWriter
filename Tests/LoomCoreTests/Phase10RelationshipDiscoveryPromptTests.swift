import Foundation
@testable import LoomCore

/// Phase 10 step 2 — relationship-discovery prompt, schema, parser.
/// Sibling of Phase 9's `EntityDiscovery` grammar/prompt tests.
func phase10RelationshipDiscoveryPromptTests() -> TestSuite {
    let s = TestSuite("Phase10RelationshipDiscoveryPrompt")

    // MARK: - Prompt

    s.test("prompt includes the scene prose verbatim") {
        let prose = "Chantal kissed Muriel. Jacob was forgotten."
        let prompt = RelationshipDiscovery.buildDiscoveryPrompt(
            scenePose: prose, characterNames: ["Chantal", "Muriel", "Jacob"]
        )
        try expectTrue(prompt.contains(prose))
    }

    s.test("prompt enumerates the known character names") {
        let prompt = RelationshipDiscovery.buildDiscoveryPrompt(
            scenePose: "...", characterNames: ["Chantal", "Muriel", "Jacob"]
        )
        try expectTrue(prompt.contains("Chantal"))
        try expectTrue(prompt.contains("Muriel"))
        try expectTrue(prompt.contains("Jacob"))
    }

    s.test("prompt instructs the current-vs-past distinction") {
        let instr = RelationshipDiscovery.promptInstruction.lowercased()
        try expectTrue(instr.contains("current"))
        try expectTrue(instr.contains("past"))
    }

    // MARK: - Schema

    s.test("schema is an array of objects with status enum + required keys") {
        let schema = RelationshipDiscovery.discoveryJSONSchema()
        try expectEqual(schema["type"] as? String, "array")
        let items = try expectNotNil(schema["items"] as? [String: Any])
        let required = try expectNotNil(items["required"] as? [String])
        try expectEqual(Set(required), Set(["from", "to", "kind", "status", "evidence_quote"]))
        let props = try expectNotNil(items["properties"] as? [String: Any])
        let status = try expectNotNil(props["status"] as? [String: Any])
        try expectEqual(Set(status["enum"] as? [String] ?? []), Set(["current", "past"]))
    }

    // MARK: - Parser

    s.test("clean JSON array decodes into ProposedRelationship values") {
        let raw = """
        [
          {"from":"Chantal","to":"Muriel","kind":"girlfriend","status":"current","evidence_quote":"Chantal kissed Muriel."},
          {"from":"Chantal","to":"Jacob","kind":"ex-boyfriend","status":"past","evidence_quote":"He wasn't really my type."}
        ]
        """
        let rels = try RelationshipDiscovery.parseRelationships(raw)
        try expectEqual(rels.count, 2)
        try expectEqual(rels[0].fromName, "Chantal")
        try expectEqual(rels[0].toName, "Muriel")
        try expectEqual(rels[0].kind, "girlfriend")
        try expectEqual(rels[0].status, .current)
        try expectEqual(rels[1].status, .past)
    }

    s.test("unrecognised status falls back to .current") {
        let raw = """
        [{"from":"A","to":"B","kind":"friend","status":"banana","evidence_quote":"q"}]
        """
        let rels = try RelationshipDiscovery.parseRelationships(raw)
        try expectEqual(rels.count, 1)
        try expectEqual(rels[0].status, .current)
    }

    s.test("parser tolerates preamble and postamble around the array") {
        let raw = "Sure! Here you go:\n[{\"from\":\"A\",\"to\":\"B\",\"kind\":\"friend\",\"status\":\"current\",\"evidence_quote\":\"q\"}]\nHope that helps."
        let rels = try RelationshipDiscovery.parseRelationships(raw)
        try expectEqual(rels.count, 1)
        try expectEqual(rels[0].fromName, "A")
    }

    s.test("no array at all → throws noJSONArrayFound") {
        try expectThrows {
            _ = try RelationshipDiscovery.parseRelationships("there is no json here")
        }
    }

    s.test("per-object recovery salvages a truncated array") {
        // Array never closes (model hit a cap mid-stream); the first
        // complete object should still be recovered.
        let raw = "[{\"from\":\"A\",\"to\":\"B\",\"kind\":\"friend\",\"status\":\"current\",\"evidence_quote\":\"q\"},{\"from\":\"A\",\"to\":"
        let rels = try RelationshipDiscovery.parseRelationships(raw)
        try expectEqual(rels.count, 1)
        try expectEqual(rels[0].toName, "B")
    }

    s.test("entries missing required fields are dropped") {
        let raw = """
        [
          {"from":"A","to":"B","kind":"friend","status":"current","evidence_quote":"q"},
          {"from":"A","kind":"friend","status":"current","evidence_quote":"q"}
        ]
        """
        let rels = try RelationshipDiscovery.parseRelationships(raw)
        try expectEqual(rels.count, 1)
    }

    // MARK: - dedup

    func rel(_ from: String, _ to: String, _ kind: String, _ status: RelationshipStatus = .current) -> RelationshipDiscovery.ProposedRelationship {
        RelationshipDiscovery.ProposedRelationship(
            fromName: from, toName: to, kind: kind, status: status, evidenceQuote: "q"
        )
    }

    s.test("dedup collapses same direction + kind, case-insensitively") {
        let out = RelationshipDiscovery.dedupRelationships([
            rel("Chantal", "Muriel", "girlfriend"),
            rel("chantal", "  MURIEL ", "Girlfriend"),
        ])
        try expectEqual(out.count, 1)
    }

    s.test("dedup ignores status — first contradictory edge wins") {
        let out = RelationshipDiscovery.dedupRelationships([
            rel("A", "B", "partner", .current),
            rel("A", "B", "partner", .past),
        ])
        try expectEqual(out.count, 1)
        try expectEqual(out[0].status, .current)
    }

    s.test("dedup keeps distinct directions and distinct kinds") {
        let out = RelationshipDiscovery.dedupRelationships([
            rel("A", "B", "mentor"),   // A -> B
            rel("B", "A", "student"),  // reverse direction
            rel("A", "B", "friend"),   // same direction, different kind
        ])
        try expectEqual(out.count, 3)
    }

    return s
}

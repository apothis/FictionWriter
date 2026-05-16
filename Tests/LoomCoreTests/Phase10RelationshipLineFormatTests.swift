import Foundation
@testable import LoomCore

/// Phase 10 follow-up (2026-05-16) — relationship discovery line
/// output. Like Stage A2, the relationship extractor now asks for a
/// delimited line list (`from | to | kind | status | quote`) rather
/// than a JSON array, which small models emit far more reliably.
func phase10RelationshipLineFormatTests() -> TestSuite {
    let s = TestSuite("Phase10RelationshipLineFormat")

    // MARK: - parseRelationshipLines

    s.test("clean lines decode into ProposedRelationship values") {
        let raw = """
        Chantal | Muriel | girlfriend | current | Chantal kissed Muriel.
        Chantal | Jacob | ex-boyfriend | past | He wasn't really my type.
        """
        let rels = RelationshipDiscovery.parseRelationshipLines(raw)
        try expectEqual(rels.count, 2)
        try expectEqual(rels[0].fromName, "Chantal")
        try expectEqual(rels[0].toName, "Muriel")
        try expectEqual(rels[0].kind, "girlfriend")
        try expectEqual(rels[0].status, .current)
        try expectEqual(rels[1].status, .past)
    }

    s.test("blank lines and header noise are skipped") {
        let raw = """
        Here are the relationships:

        A | B | friend | current | They laughed together.
        """
        let rels = RelationshipDiscovery.parseRelationshipLines(raw)
        try expectEqual(rels.count, 1)
        try expectEqual(rels[0].fromName, "A")
    }

    s.test("leading bullet markers are tolerated") {
        let raw = """
        - Chantal | Muriel | girlfriend | current | q
        2. Jacob | Chantal | ex | past | q
        """
        let rels = RelationshipDiscovery.parseRelationshipLines(raw)
        try expectEqual(rels.count, 2)
        try expectEqual(rels[1].fromName, "Jacob")
    }

    s.test("unrecognised status falls back to .current") {
        let raw = "A | B | friend | banana | q"
        let rels = RelationshipDiscovery.parseRelationshipLines(raw)
        try expectEqual(rels.count, 1)
        try expectEqual(rels[0].status, .current)
    }

    s.test("a pipe inside the quote is preserved (maxSplits)") {
        let raw = "A | B | rival | current | She hissed \"you | me\" at him."
        let rels = RelationshipDiscovery.parseRelationshipLines(raw)
        try expectEqual(rels.count, 1)
        try expectEqual(rels[0].evidenceQuote, "She hissed \"you | me\" at him.")
    }

    s.test("lines missing fields are skipped") {
        let raw = """
        A | B | friend | current | q
        A | B | friend
        """
        let rels = RelationshipDiscovery.parseRelationshipLines(raw)
        try expectEqual(rels.count, 1)
    }

    s.test("empty input → empty result") {
        try expectEqual(RelationshipDiscovery.parseRelationshipLines("").count, 0)
    }

    // MARK: - buildDiscoveryListPrompt

    s.test("prompt includes the scene prose verbatim") {
        let prose = "Chantal kissed Muriel."
        let prompt = RelationshipDiscovery.buildDiscoveryListPrompt(
            scenePose: prose, characterNames: ["Chantal", "Muriel"]
        )
        try expectTrue(prompt.contains(prose))
    }

    s.test("prompt enumerates the character names") {
        let prompt = RelationshipDiscovery.buildDiscoveryListPrompt(
            scenePose: "...", characterNames: ["Chantal", "Muriel", "Jacob"]
        )
        try expectTrue(prompt.contains("Chantal"))
        try expectTrue(prompt.contains("Jacob"))
    }

    s.test("prompt specifies the line format and current/past distinction") {
        let prompt = RelationshipDiscovery.buildDiscoveryListPrompt(
            scenePose: "...", characterNames: ["A", "B"]
        )
        try expectTrue(prompt.contains("|"))
        try expectTrue(prompt.lowercased().contains("per line"))
        try expectTrue(prompt.lowercased().contains("current"))
        try expectTrue(prompt.lowercased().contains("past"))
    }

    return s
}

import Foundation
@testable import LoomCore

/// Relationship discovery — two-stage pairwise classification: pure
/// functions for pair enumeration, the per-pair prompt, the per-pair
/// answer parser, plus dedup and the known-character filter.
func phase10RelationshipDiscoveryPromptTests() -> TestSuite {
    let s = TestSuite("Phase10RelationshipDiscoveryPrompt")

    // MARK: - candidatePairs (stage 1)

    s.test("candidatePairs enumerates every pair of co-occurring characters") {
        let pairs = RelationshipDiscovery.candidatePairs(
            characterNames: ["Chantal", "Muriel", "Jacob"],
            scenePose: "Chantal kissed Muriel while Jacob watched."
        )
        try expectEqual(pairs.count, 3)
        let asSets = pairs.map { Set($0) }
        try expectTrue(asSets.contains(Set(["Chantal", "Muriel"])))
        try expectTrue(asSets.contains(Set(["Chantal", "Jacob"])))
        try expectTrue(asSets.contains(Set(["Muriel", "Jacob"])))
    }

    s.test("candidatePairs drops characters absent from the scene") {
        // Karim is in the bible but not in this scene.
        let pairs = RelationshipDiscovery.candidatePairs(
            characterNames: ["Chantal", "Muriel", "Karim"],
            scenePose: "Chantal kissed Muriel."
        )
        try expectEqual(pairs.count, 1)
        try expectEqual(Set(pairs[0]), Set(["Chantal", "Muriel"]))
    }

    s.test("candidatePairs matches scene presence case-insensitively, dedups names") {
        let pairs = RelationshipDiscovery.candidatePairs(
            characterNames: ["chantal", "Chantal", "Muriel"],
            scenePose: "CHANTAL and muriel walked."
        )
        try expectEqual(pairs.count, 1)
    }

    s.test("candidatePairs with fewer than two present → no pairs") {
        try expectEqual(
            RelationshipDiscovery.candidatePairs(
                characterNames: ["Chantal", "Muriel"], scenePose: "Chantal was alone."
            ).count,
            0
        )
    }

    // MARK: - buildPairClassificationPrompt (stage 2)

    s.test("pair prompt names both characters, the scene, and a worked example") {
        let prompt = RelationshipDiscovery.buildPairClassificationPrompt(
            characterA: "Chantal", characterB: "Muriel",
            scenePose: "Chantal kissed Muriel."
        )
        try expectTrue(prompt.contains("Chantal"))
        try expectTrue(prompt.contains("Muriel"))
        try expectTrue(prompt.contains("Chantal kissed Muriel."))
        // The worked example uses the real names — so the model
        // substitutes them rather than echoing literal "from | to".
        try expectTrue(prompt.contains("Chantal | Muriel | mentor | current"))
        // The bounded escape hatch.
        try expectTrue(prompt.lowercased().contains("none"))
        try expectTrue(prompt.lowercased().contains("past"))
    }

    // MARK: - parsePairClassification (stage 2 answer)

    s.test("pair parser decodes a clean four-field line") {
        let rels = RelationshipDiscovery.parsePairClassification(
            "Chantal | Muriel | girlfriend | current",
            characterA: "Chantal", characterB: "Muriel"
        )
        try expectEqual(rels.count, 1)
        try expectEqual(rels[0].fromName, "Chantal")
        try expectEqual(rels[0].toName, "Muriel")
        try expectEqual(rels[0].kind, "girlfriend")
        try expectEqual(rels[0].status, .current)
    }

    s.test("pair parser treats 'none' as no relationship") {
        try expectEqual(
            RelationshipDiscovery.parsePairClassification(
                "none", characterA: "A", characterB: "B"
            ).count,
            0
        )
    }

    s.test("pair parser drops a line naming a character other than the asked pair") {
        // The model hallucinated a third name — not in the asked pair.
        let rels = RelationshipDiscovery.parsePairClassification(
            "Chantal | Narrator | friend | current",
            characterA: "Chantal", characterB: "Muriel"
        )
        try expectEqual(rels.count, 0)
    }

    s.test("pair parser tolerates a leading bullet and an unknown status") {
        let rels = RelationshipDiscovery.parsePairClassification(
            "- Judy | Allie | sister | banana",
            characterA: "Judy", characterB: "Allie"
        )
        try expectEqual(rels.count, 1)
        try expectEqual(rels[0].status, .current)
    }

    // MARK: - dedupRelationships

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
            rel("A", "B", "mentor"),
            rel("B", "A", "student"),
            rel("A", "B", "friend"),
        ])
        try expectEqual(out.count, 3)
    }

    // MARK: - filterToKnownCharacters

    s.test("filterToKnownCharacters drops edges to an invented character") {
        let kept = RelationshipDiscovery.filterToKnownCharacters(
            [
                rel("Megan", "Abby", "lover"),
                rel("Lucas", "Narrator", "spouse"),
            ],
            characterNames: ["Abby", "Megan", "Lucas"]
        )
        try expectEqual(kept.count, 1)
        try expectEqual(kept[0].fromName, "Megan")
    }

    s.test("filterToKnownCharacters matches names case-insensitively") {
        let kept = RelationshipDiscovery.filterToKnownCharacters(
            [rel(" chantal ", "MURIEL", "lover")],
            characterNames: ["Chantal", "Muriel"]
        )
        try expectEqual(kept.count, 1)
    }

    return s
}

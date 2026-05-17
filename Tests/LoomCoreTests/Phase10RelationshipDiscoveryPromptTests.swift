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

    // MARK: - voteOnPair (self-consistency)

    s.test("voteOnPair keeps an edge a strict majority of runs agree on") {
        let out = RelationshipDiscovery.voteOnPair([
            [rel("Abby", "Judy", "mother")],
            [rel("Abby", "Judy", "mother")],
            [],
        ])
        try expectEqual(out.count, 1)
        try expectEqual(out[0].kind, "mother")
    }

    s.test("voteOnPair drops an edge only a minority of runs found") {
        // The hallucination case: gemma invents an edge on 1 of 3 runs.
        let out = RelationshipDiscovery.voteOnPair([
            [rel("Megan", "Judy", "sister")],
            [],
            [],
        ])
        try expectEqual(out.count, 0)
    }

    s.test("voteOnPair returns the modal edge when runs disagree on kind") {
        let out = RelationshipDiscovery.voteOnPair([
            [rel("Abby", "Judy", "mother")],
            [rel("Abby", "Judy", "mother")],
            [rel("Abby", "Judy", "parent")],
        ])
        try expectEqual(out.count, 1)
        try expectEqual(out[0].kind, "mother")
    }

    s.test("voteOnPair breaks a kind tie toward the first run") {
        let out = RelationshipDiscovery.voteOnPair([
            [rel("Abby", "Judy", "mother")],
            [rel("Abby", "Judy", "parent")],
            [],
        ])
        try expectEqual(out.count, 1)
        try expectEqual(out[0].kind, "mother")
    }

    s.test("voteOnPair with a single round keeps any edge found") {
        let out = RelationshipDiscovery.voteOnPair([[rel("A", "B", "friend")]])
        try expectEqual(out.count, 1)
    }

    s.test("voteOnPair on all-none runs returns nothing") {
        try expectEqual(RelationshipDiscovery.voteOnPair([[], [], []]).count, 0)
    }

    // MARK: - relationship gate (binary evidence pre-filter)

    let gateScene = "Judy was Allie's sister. They walked to the shop. Megan watched them go."

    s.test("gate prompt names both characters, the scene, and the no escape") {
        let prompt = RelationshipDiscovery.buildRelationshipGatePrompt(
            characterA: "Judy", characterB: "Megan", scenePose: gateScene
        )
        try expectTrue(prompt.contains("Judy"))
        try expectTrue(prompt.contains("Megan"))
        try expectTrue(prompt.contains(gateScene))
        try expectTrue(prompt.contains("RELATED"))
        try expectTrue(prompt.lowercased().contains("no"))
    }

    s.test("gate parser returns a verbatim evidence quote on a grounded yes") {
        let evidence = RelationshipDiscovery.parseGateResponse(
            "RELATED: yes\nEVIDENCE: Judy was Allie's sister.",
            scenePose: gateScene
        )
        try expectEqual(evidence, "Judy was Allie's sister.")
    }

    s.test("gate parser returns nil on a 'no'") {
        try expectNil(RelationshipDiscovery.parseGateResponse(
            "RELATED: no", scenePose: gateScene
        ))
    }

    s.test("gate parser rejects a 'yes' whose evidence is not in the scene") {
        // Ungrounded "yes" — the cited sentence was fabricated.
        try expectNil(RelationshipDiscovery.parseGateResponse(
            "RELATED: yes\nEVIDENCE: Judy married Allie last spring.",
            scenePose: gateScene
        ))
    }

    s.test("gate parser rejects a 'yes' with no evidence line at all") {
        try expectNil(RelationshipDiscovery.parseGateResponse(
            "RELATED: yes", scenePose: gateScene
        ))
    }

    s.test("gate parser tolerates a reasoning preamble before RELATED") {
        let evidence = RelationshipDiscovery.parseGateResponse(
            "Let me check the scene.\n\nRELATED: yes\nEVIDENCE: Judy was Allie's sister.",
            scenePose: gateScene
        )
        try expectEqual(evidence, "Judy was Allie's sister.")
    }

    s.test("gate parser matches evidence past whitespace and case differences") {
        let evidence = RelationshipDiscovery.parseGateResponse(
            "RELATED: yes\nEVIDENCE:   judy WAS   allie's SISTER.  ",
            scenePose: gateScene
        )
        try expectNotNil(evidence)
    }

    s.test("gate parser rejects a too-short evidence fragment") {
        // "Judy." is in the scene but too short to ground a claim.
        try expectNil(RelationshipDiscovery.parseGateResponse(
            "RELATED: yes\nEVIDENCE: Judy.", scenePose: gateScene
        ))
    }

    return s
}

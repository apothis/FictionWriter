import Foundation
@testable import LoomCore

/// Phase 9 entity-discovery spike — precision/recall/F1 scorer.
/// LOOM_ENTITY_DISCOVERY_SPIKE §6.3: closes the live-eval loop.
/// Given the pipeline's proposals + the fixture's gold entities,
/// grade precision (proposals matching gold) and recall (gold
/// entities the pipeline found). Match predicate is set-intersect
/// on normalised name+aliases AND kind agreement — same person
/// under two surface forms ("Marius Thorn" vs "Dr Thorn") matches
/// if either side's alias list bridges them.
///
/// Convention follows LedgerExtraction.ScoreReport: denominator-
/// zero precision = 1.0 (vacuously precise on no proposals).
func phase9ScorerTests() -> TestSuite {
    let s = TestSuite("Phase9Scorer")

    func proposal(_ name: String, kind: EntityDiscovery.Kind = .character, aliases: [String] = []) -> EntityDiscoveryScorer.ProposedSurface {
        EntityDiscoveryScorer.ProposedSurface(canonicalName: name, aliases: aliases, kind: kind)
    }
    func gold(_ name: String, kind: EntityDiscovery.Kind = .character, aliases: [String] = []) -> EntityDiscoveryScorer.GoldSurface {
        EntityDiscoveryScorer.GoldSurface(canonicalName: name, aliases: aliases, kind: kind)
    }

    s.test("empty proposals + empty gold → vacuous precision=1, recall=1, F1=1") {
        let report = EntityDiscoveryScorer.score(inputs: [])
        try expectEqual(report.truePositives, 0)
        try expectEqual(report.falsePositives, 0)
        try expectEqual(report.falseNegatives, 0)
        try expectEqual(report.precision, 1.0)
        try expectEqual(report.recall, 1.0)
        try expectEqual(report.f1, 1.0)
    }

    s.test("empty proposals + 1 gold → precision=1, recall=0") {
        let report = EntityDiscoveryScorer.score(inputs: [
            EntityDiscoveryScorer.ScoreInput(
                sceneId: "eds-00",
                proposed: [],
                gold: [gold("Anders")]
            )
        ])
        try expectEqual(report.truePositives, 0)
        try expectEqual(report.falsePositives, 0)
        try expectEqual(report.falseNegatives, 1)
        try expectEqual(report.precision, 1.0)
        try expectEqual(report.recall, 0.0)
        try expectEqual(report.f1, 0.0)
    }

    s.test("perfect match (exact canonical name) → TP=1") {
        let report = EntityDiscoveryScorer.score(inputs: [
            EntityDiscoveryScorer.ScoreInput(
                sceneId: "eds-00",
                proposed: [proposal("Anders")],
                gold: [gold("Anders")]
            )
        ])
        try expectEqual(report.truePositives, 1)
        try expectEqual(report.falsePositives, 0)
        try expectEqual(report.falseNegatives, 0)
        try expectEqual(report.precision, 1.0)
        try expectEqual(report.recall, 1.0)
        try expectEqual(report.f1, 1.0)
    }

    s.test("match via gold alias (proposal's canonical is in gold's aliases)") {
        // The pipeline proposes "Dr Thorn"; gold has canonical
        // "Marius Thorn" with alias "Dr Thorn" — match.
        let report = EntityDiscoveryScorer.score(inputs: [
            EntityDiscoveryScorer.ScoreInput(
                sceneId: "eds-06",
                proposed: [proposal("Dr Thorn")],
                gold: [gold("Marius Thorn", aliases: ["Dr Thorn", "Thorn", "Marius"])]
            )
        ])
        try expectEqual(report.truePositives, 1)
        try expectEqual(report.falseNegatives, 0)
    }

    s.test("match via proposal alias (gold's canonical is in proposal's aliases)") {
        // Inverse: pipeline emits canonical "Dr Thorn" but
        // includes "Marius Thorn" as an alias — still matches gold.
        let report = EntityDiscoveryScorer.score(inputs: [
            EntityDiscoveryScorer.ScoreInput(
                sceneId: "eds-06",
                proposed: [proposal("Dr Thorn", aliases: ["Marius Thorn"])],
                gold: [gold("Marius Thorn")]
            )
        ])
        try expectEqual(report.truePositives, 1)
    }

    s.test("case-insensitive matching") {
        let report = EntityDiscoveryScorer.score(inputs: [
            EntityDiscoveryScorer.ScoreInput(
                sceneId: "eds-00",
                proposed: [proposal("ANDERS")],
                gold: [gold("anders")]
            )
        ])
        try expectEqual(report.truePositives, 1)
    }

    s.test("FP: proposal with no matching gold (distractor leak)") {
        let report = EntityDiscoveryScorer.score(inputs: [
            EntityDiscoveryScorer.ScoreInput(
                sceneId: "eds-07",
                proposed: [proposal("Brussels", kind: .place)],
                gold: [gold("Theo")]
            )
        ])
        try expectEqual(report.truePositives, 0)
        try expectEqual(report.falsePositives, 1)
        try expectEqual(report.falseNegatives, 1)
    }

    s.test("kind mismatch is NOT a match (Anders the character vs Anders the place)") {
        // Defensive: if the pipeline proposes a place named
        // "Anders" but gold has Anders the character, this should
        // count as FP + FN, not TP. Kind agreement matters.
        let report = EntityDiscoveryScorer.score(inputs: [
            EntityDiscoveryScorer.ScoreInput(
                sceneId: "eds-00",
                proposed: [proposal("Anders", kind: .place)],
                gold: [gold("Anders", kind: .character)]
            )
        ])
        try expectEqual(report.truePositives, 0)
        try expectEqual(report.falsePositives, 1)
        try expectEqual(report.falseNegatives, 1)
    }

    s.test("duplicate proposals matching same gold: one TP, rest FP") {
        // Pipeline proposes Anders twice (once as "Anders", once
        // as "the stranger"). One should TP, the duplicate is a
        // FP since you only get credit once per gold entity.
        let report = EntityDiscoveryScorer.score(inputs: [
            EntityDiscoveryScorer.ScoreInput(
                sceneId: "eds-00",
                proposed: [
                    proposal("Anders"),
                    proposal("the stranger"),
                ],
                gold: [gold("Anders", aliases: ["the stranger"])]
            )
        ])
        try expectEqual(report.truePositives, 1)
        try expectEqual(report.falsePositives, 1)
        try expectEqual(report.falseNegatives, 0)
    }

    s.test("multi-scene aggregate sums TP/FP/FN") {
        let inputs: [EntityDiscoveryScorer.ScoreInput] = [
            // Scene 1: 1 perfect TP
            .init(sceneId: "a", proposed: [proposal("Anders")], gold: [gold("Anders")]),
            // Scene 2: 1 FP + 1 FN
            .init(sceneId: "b", proposed: [proposal("Brussels", kind: .place)], gold: [gold("Karim")]),
            // Scene 3: 1 TP + 1 FP + 1 FN (proposed two, only one matches)
            .init(sceneId: "c", proposed: [proposal("Velka"), proposal("Random")],
                  gold: [gold("Velka"), gold("The Quay", kind: .place)]),
        ]
        let report = EntityDiscoveryScorer.score(inputs: inputs)
        try expectEqual(report.truePositives, 2)   // Anders + Velka
        try expectEqual(report.falsePositives, 2)  // Brussels + Random
        try expectEqual(report.falseNegatives, 2)  // Karim + The Quay
        // precision = 2/4 = 0.5, recall = 2/4 = 0.5, F1 = 0.5
        try expectEqual(report.precision, 0.5)
        try expectEqual(report.recall, 0.5)
        try expectEqual(report.f1, 0.5)
    }

    s.test("F1 formula: 2*p*r / (p+r)") {
        // p = 1, r = 0.5 → F1 = 2*1*0.5 / 1.5 = 0.666…
        let inputs: [EntityDiscoveryScorer.ScoreInput] = [
            .init(sceneId: "a",
                  proposed: [proposal("Anders")],
                  gold: [gold("Anders"), gold("Karim")]),
        ]
        let report = EntityDiscoveryScorer.score(inputs: inputs)
        try expectEqual(report.truePositives, 1)
        try expectEqual(report.falsePositives, 0)
        try expectEqual(report.falseNegatives, 1)
        try expectEqual(report.precision, 1.0)
        try expectEqual(report.recall, 0.5)
        try expectTrue(abs(report.f1 - 2.0/3.0) < 1e-9)
    }

    s.test("per-scene breakdown is exposed for failure analysis") {
        let inputs: [EntityDiscoveryScorer.ScoreInput] = [
            .init(sceneId: "a", proposed: [proposal("Anders")], gold: [gold("Anders")]),
            .init(sceneId: "b", proposed: [], gold: [gold("Karim")]),
        ]
        let report = EntityDiscoveryScorer.score(inputs: inputs)
        try expectEqual(report.perScene.count, 2)
        try expectEqual(report.perScene["a"]?.truePositives, 1)
        try expectEqual(report.perScene["b"]?.falseNegatives, 1)
    }

    return s
}

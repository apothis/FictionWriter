import Foundation
@testable import LoomCore

/// Phase 4 §14.1 #8 — pure-data formatter for the rewritePOV
/// descriptor (lands on `PromptContext.perCallInstruction`).
///
/// Layout mirrors the `[KNOWLEDGE-LEDGER]` prompt layer shipped in
/// sub-task 7 (LOOM_GENERATION_MODES.md §11): leading "Target POV"
/// line, then a KNOWS bullet list, then a DOES NOT KNOW bullet list.
/// Empty buckets omit their sub-block. Source POV is omitted from
/// the descriptor — it's already implicit in the surrounding
/// manuscript prose the model sees via the recent-prose layer.
func phase4RewritePOVDescriptorTests() -> TestSuite {
    let s = TestSuite("Phase4RewritePOVDescriptor")

    func makeFact(_ text: String, sceneId: UUID = UUID()) -> KnownFact {
        KnownFact(
            id: UUID(),
            fact: text,
            sourceSceneId: sceneId,
            certainty: .asserted,
            addedAt: Date()
        )
    }

    s.test("formatter leads with the target POV line including default person/limited") {
        let result = LedgerKnowledge.Result(knows: [], unknowns: [])
        let descriptor = RewritePOVDescriptor.build(targetName: "Iris", knowledge: result)
        try expectTrue(
            descriptor.contains("Target POV: Iris"),
            "descriptor should declare target POV by name; got: \(descriptor)"
        )
        try expectTrue(
            descriptor.lowercased().contains("third-person") ||
            descriptor.lowercased().contains("third person"),
            "default person treatment should be third-person limited"
        )
    }

    s.test("formatter emits KNOWS section when knowledge.knows is non-empty") {
        let result = LedgerKnowledge.Result(
            knows: [
                makeFact("Daniel is married to Cora"),
                makeFact("Daniel smoked on the balcony"),
            ],
            unknowns: []
        )
        let descriptor = RewritePOVDescriptor.build(targetName: "Iris", knowledge: result)
        try expectTrue(descriptor.uppercased().contains("KNOWS"))
        try expectTrue(descriptor.contains("Daniel is married to Cora"))
        try expectTrue(descriptor.contains("Daniel smoked on the balcony"))
    }

    s.test("formatter emits DOES NOT KNOW section when knowledge.unknowns is non-empty") {
        let result = LedgerKnowledge.Result(
            knows: [],
            unknowns: [makeFact("Anders proposed to Mia")]
        )
        let descriptor = RewritePOVDescriptor.build(targetName: "Iris", knowledge: result)
        try expectTrue(
            descriptor.uppercased().contains("NOT KNOW") ||
            descriptor.uppercased().contains("DOES NOT")
        )
        try expectTrue(descriptor.contains("Anders proposed to Mia"))
    }

    s.test("empty KNOWS bucket omits its sub-block") {
        let result = LedgerKnowledge.Result(
            knows: [],
            unknowns: [makeFact("Anders proposed to Mia")]
        )
        let descriptor = RewritePOVDescriptor.build(targetName: "Iris", knowledge: result)
        try expectFalse(
            descriptor.uppercased().contains("KNOWS"),
            "no KNOWS sub-block when knows is empty; got: \(descriptor)"
        )
    }

    s.test("empty DOES NOT KNOW bucket omits its sub-block") {
        let result = LedgerKnowledge.Result(
            knows: [makeFact("Daniel is married to Cora")],
            unknowns: []
        )
        let descriptor = RewritePOVDescriptor.build(targetName: "Iris", knowledge: result)
        try expectFalse(
            descriptor.uppercased().contains("NOT KNOW"),
            "no DOES NOT KNOW sub-block when unknowns is empty; got: \(descriptor)"
        )
    }

    s.test("both buckets empty still produces the target POV line") {
        let result = LedgerKnowledge.Result(knows: [], unknowns: [])
        let descriptor = RewritePOVDescriptor.build(targetName: "Iris", knowledge: result)
        try expectTrue(descriptor.contains("Target POV: Iris"))
        // No bullet lines at all.
        try expectFalse(descriptor.contains("- "),
            "no bullet rows expected when both buckets are empty; got: \(descriptor)")
    }

    s.test("facts are rendered as one bullet line per entry, in input order") {
        let result = LedgerKnowledge.Result(
            knows: [
                makeFact("alpha-fact"),
                makeFact("beta-fact"),
                makeFact("gamma-fact"),
            ],
            unknowns: []
        )
        let descriptor = RewritePOVDescriptor.build(targetName: "Iris", knowledge: result)
        let alphaIdx = try expectNotNil(descriptor.range(of: "alpha-fact")?.lowerBound)
        let betaIdx = try expectNotNil(descriptor.range(of: "beta-fact")?.lowerBound)
        let gammaIdx = try expectNotNil(descriptor.range(of: "gamma-fact")?.lowerBound)
        try expectTrue(alphaIdx < betaIdx)
        try expectTrue(betaIdx < gammaIdx)
    }

    return s
}

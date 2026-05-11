import Foundation
@testable import LoomCore

/// Phase 4 #7 sub-task 7 — `PromptBuilder` adds a `.knowledgeLedger`
/// layer below the cache when the active scene has a POV character
/// with extracted facts in scope. Renders the LOOM_GENERATION_MODES
/// §11 format:
///
/// ```
/// [KNOWLEDGE-LEDGER]
/// {POV} knows the following as of this scene:
/// - fact 1
/// - fact 2
///
/// {POV} does NOT know:
/// - fact A
/// ```
///
/// Each block is omitted when its bucket is empty (don't render
/// "knows: (none)" — wastes tokens and confuses the model).
/// Layer is below cache so it doesn't bust prompt caching when the
/// ledger changes between generations.
func phase4KnowledgeLedgerLayerTests() -> TestSuite {
    let s = TestSuite("Phase4KnowledgeLedgerLayer")

    let miaId = UUID()
    let andersId = UUID()
    let scene1Id = UUID()
    let scene2Id = UUID()

    func fact(_ text: String, source: UUID) -> KnownFact {
        KnownFact(id: UUID(), fact: text, sourceSceneId: source, certainty: .asserted)
    }

    /// Two scenes [s1, s2], Mia + Anders in the bible. Caller wires
    /// facts + POV per scene; this returns a PromptContext targeting
    /// scene 2 as the current scene.
    func makeContext(
        proseS1: String = "", povS1: UUID? = nil,
        proseS2: String = "She turned the page slowly.", povS2: UUID? = nil,
        miaFacts: [UUID: [KnownFact]] = [:],
        andersFacts: [UUID: [KnownFact]] = [:]
    ) -> PromptContext {
        var mia = Character(id: miaId, name: "Mia", aliases: [])
        mia.knownFactsBySceneId = miaFacts
        var anders = Character(id: andersId, name: "Anders", aliases: [])
        anders.knownFactsBySceneId = andersFacts

        var bible = Bible()
        bible.characters = [mia, anders]

        var s1 = Scene.empty(id: scene1Id, title: "S1"); s1.prose = proseS1; s1.pov = povS1
        var s2 = Scene.empty(id: scene2Id, title: "S2"); s2.prose = proseS2; s2.pov = povS2

        var project = Project(title: "T")
        project.bible = bible
        project.manuscript.orphanedSceneIds = [scene1Id, scene2Id]

        return PromptContext(
            mode: .continueProse,
            project: project,
            scenes: [scene1Id: s1, scene2Id: s2],
            currentSceneId: scene2Id,
            cursorOffset: s2.prose.count,
            selectionRange: nil,
            modelName: nil,
            contextBudgetTokens: 8192,
            replyBudgetTokens: 1024
        )
    }

    s.test("no POV on the current scene → no knowledge-ledger layer is added") {
        let ctx = makeContext(
            povS1: miaId,
            povS2: nil,  // no POV
            miaFacts: [scene1Id: [fact("Mia opened the door.", source: scene1Id)]]
        )
        let assembled = PromptBuilder.build(ctx)
        let ledgerChiclets = assembled.chiclets.filter { $0.sourceKind == .knowledgeLedger }
        try expectEqual(ledgerChiclets.count, 0)
    }

    s.test("POV character with NO facts (knows + unknowns both empty) → no layer added") {
        let ctx = makeContext(povS2: miaId)
        let assembled = PromptBuilder.build(ctx)
        let ledgerChiclets = assembled.chiclets.filter { $0.sourceKind == .knowledgeLedger }
        try expectEqual(ledgerChiclets.count, 0)
    }

    s.test("POV with only knows-bucket → renders KNOWS block, no DOES NOT KNOW block") {
        // Mia POV in scene 1 → Mia knows scene-1 facts.
        // Mia POV in scene 2 (current) — still knows them.
        let ctx = makeContext(
            povS1: miaId,
            povS2: miaId,
            miaFacts: [scene1Id: [fact("Mia opened the door.", source: scene1Id)]]
        )
        let assembled = PromptBuilder.build(ctx)
        let chiclet = try expectNotNil(
            assembled.chiclets.first { $0.sourceKind == .knowledgeLedger }
        )
        try expectTrue(chiclet.fullContent.contains("[KNOWLEDGE-LEDGER]"))
        try expectTrue(chiclet.fullContent.contains("Mia knows"))
        try expectTrue(chiclet.fullContent.contains("Mia opened the door."))
        try expectFalse(chiclet.fullContent.contains("does NOT know"))
    }

    s.test("POV with only unknown-bucket → renders DOES NOT KNOW block, no KNOWS block") {
        // Anders POV in scene 1 with a fact about him; Mia not present.
        // Mia POV in scene 2 (current) — she doesn't know scene-1 fact.
        let ctx = makeContext(
            proseS1: "Anders walked away through the rain.",
            povS1: andersId,
            povS2: miaId,
            andersFacts: [scene1Id: [fact("Anders walked away.", source: scene1Id)]]
        )
        let assembled = PromptBuilder.build(ctx)
        let chiclet = try expectNotNil(
            assembled.chiclets.first { $0.sourceKind == .knowledgeLedger }
        )
        try expectTrue(chiclet.fullContent.contains("Mia does NOT know"))
        try expectTrue(chiclet.fullContent.contains("Anders walked away."))
        try expectFalse(chiclet.fullContent.contains("Mia knows"))
    }

    s.test("POV with both knows + unknowns → renders both blocks") {
        // Scene 1 (Anders POV, Mia absent): Anders fact → Mia unknown.
        // Scene 2 (Mia POV, current): Mia fact → Mia knows.
        let ctx = makeContext(
            povS1: andersId,
            povS2: miaId,
            miaFacts: [scene2Id: [fact("Mia turned the page.", source: scene2Id)]],
            andersFacts: [scene1Id: [fact("Anders left.", source: scene1Id)]]
        )
        let assembled = PromptBuilder.build(ctx)
        let chiclet = try expectNotNil(
            assembled.chiclets.first { $0.sourceKind == .knowledgeLedger }
        )
        try expectTrue(chiclet.fullContent.contains("Mia knows"))
        try expectTrue(chiclet.fullContent.contains("Mia turned the page."))
        try expectTrue(chiclet.fullContent.contains("Mia does NOT know"))
        try expectTrue(chiclet.fullContent.contains("Anders left."))
    }

    s.test("knowledge-ledger layer is rendered below the cache boundary (counts against belowCacheTokens)") {
        let ctx = makeContext(
            povS1: miaId,
            povS2: miaId,
            miaFacts: [scene1Id: [fact("Mia opened the door.", source: scene1Id)]]
        )
        let assembled = PromptBuilder.build(ctx)
        // The chiclet exists and contributes to belowCacheTokens.
        let chiclet = try expectNotNil(
            assembled.chiclets.first { $0.sourceKind == .knowledgeLedger }
        )
        try expectTrue(chiclet.tokenCount > 0)
        // It's in the user-block (below cache), not the system-block.
        try expectTrue(assembled.userBlock.contains("[KNOWLEDGE-LEDGER]"))
        try expectFalse(assembled.systemBlock.contains("[KNOWLEDGE-LEDGER]"))
    }

    s.test("layer carries the POV character id as sourceId for the History tab") {
        let ctx = makeContext(
            povS1: miaId,
            povS2: miaId,
            miaFacts: [scene1Id: [fact("Mia opened the door.", source: scene1Id)]]
        )
        let assembled = PromptBuilder.build(ctx)
        let chiclet = try expectNotNil(
            assembled.chiclets.first { $0.sourceKind == .knowledgeLedger }
        )
        try expectEqual(chiclet.sourceId, miaId)
    }

    return s
}

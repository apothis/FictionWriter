import Foundation
@testable import LoomCore

/// Phase 4 #7 sub-task 6 — `LedgerKnowledge` is the pure-data query
/// that derives KNOWS / DOES NOT KNOW per character at a given
/// chronological position. Implements the SymbolicToM-style
/// scene-exposure derivation (LOOM_STORY_BIBLE §3.5 + spike §8.3):
/// `unknown` is NOT extracted — it's set-differenced from per-scene
/// exposure at query time.
///
/// Algorithm:
/// 1. Walk `manuscript.flatSceneIds` truncated at `asOfSceneId`
///    inclusive (the doc says "chronologically ≤ N").
/// 2. For each scene S in that prefix, check if the queried
///    character was present (via `ScenePresence`).
/// 3. Collect ALL facts from ALL characters' `knownFactsBySceneId[S]`
///    (facts about anyone, extracted from S):
///    - present in S → KNOWS bucket
///    - not present in S → DOES NOT KNOW bucket
func phase4LedgerKnowledgeTests() -> TestSuite {
    let s = TestSuite("Phase4LedgerKnowledge")

    let miaId = UUID()
    let andersId = UUID()
    let scene1Id = UUID()
    let scene2Id = UUID()
    let scene3Id = UUID()

    func fact(_ text: String, source: UUID) -> KnownFact {
        KnownFact(id: UUID(), fact: text, sourceSceneId: source, certainty: .asserted)
    }

    /// Build a tiny project: 3 scenes in narrative order [s1, s2, s3],
    /// Mia + Anders in the bible. Caller supplies prose + POV + facts
    /// per scene to set up the test case.
    func makeFixture(
        proseS1: String = "", povS1: UUID? = nil,
        proseS2: String = "", povS2: UUID? = nil,
        proseS3: String = "", povS3: UUID? = nil,
        miaFacts: [UUID: [KnownFact]] = [:],
        andersFacts: [UUID: [KnownFact]] = [:]
    ) -> (Project, [UUID: Scene]) {
        var mia = Character(id: miaId, name: "Mia", aliases: ["Miss Vance"])
        mia.knownFactsBySceneId = miaFacts
        var anders = Character(id: andersId, name: "Anders", aliases: [])
        anders.knownFactsBySceneId = andersFacts

        var bible = Bible()
        bible.characters = [mia, anders]

        var s1 = Scene.empty(id: scene1Id, title: "S1"); s1.prose = proseS1; s1.pov = povS1
        var s2 = Scene.empty(id: scene2Id, title: "S2"); s2.prose = proseS2; s2.pov = povS2
        var s3 = Scene.empty(id: scene3Id, title: "S3"); s3.prose = proseS3; s3.pov = povS3

        var project = Project(title: "T")
        project.bible = bible
        project.manuscript.orphanedSceneIds = [scene1Id, scene2Id, scene3Id]

        return (project, [scene1Id: s1, scene2Id: s2, scene3Id: s3])
    }

    s.test("empty project → empty knows + empty unknowns") {
        let (project, scenes) = makeFixture()
        let result = LedgerKnowledge.compute(
            characterId: miaId,
            asOfSceneId: scene3Id,
            in: project,
            scenes: scenes
        )
        try expectEqual(result.knows.count, 0)
        try expectEqual(result.unknowns.count, 0)
    }

    s.test("fact extracted in a scene where C was present (POV) → knows") {
        let f = fact("Mia opened the door.", source: scene1Id)
        let (project, scenes) = makeFixture(
            povS1: miaId,
            miaFacts: [scene1Id: [f]]
        )
        let result = LedgerKnowledge.compute(
            characterId: miaId,
            asOfSceneId: scene3Id,
            in: project,
            scenes: scenes
        )
        try expectEqual(result.knows.count, 1)
        try expectEqual(result.knows[0].fact, "Mia opened the door.")
        try expectEqual(result.unknowns.count, 0)
    }

    s.test("fact extracted in a scene where C was NOT present → unknown") {
        // Scene 1: Anders POV, no Mia mention. A fact is extracted
        // about Anders. Mia doesn't know it.
        let f = fact("Anders fled to the city.", source: scene1Id)
        let (project, scenes) = makeFixture(
            proseS1: "Anders walked away from her house.",
            povS1: andersId,
            andersFacts: [scene1Id: [f]]
        )
        let result = LedgerKnowledge.compute(
            characterId: miaId,
            asOfSceneId: scene3Id,
            in: project,
            scenes: scenes
        )
        try expectEqual(result.knows.count, 0)
        try expectEqual(result.unknowns.count, 1)
        try expectEqual(result.unknowns[0].fact, "Anders fled to the city.")
    }

    s.test("facts from a scene AFTER asOfSceneId are excluded from both buckets") {
        // Scene 3 has a fact; asOfSceneId = scene2 → scene 3 is
        // out of scope.
        let f = fact("Mia learned the truth.", source: scene3Id)
        let (project, scenes) = makeFixture(
            povS3: miaId,
            miaFacts: [scene3Id: [f]]
        )
        let result = LedgerKnowledge.compute(
            characterId: miaId,
            asOfSceneId: scene2Id,
            in: project,
            scenes: scenes
        )
        try expectEqual(result.knows.count, 0)
        try expectEqual(result.unknowns.count, 0)
    }

    s.test("facts in the asOfSceneId itself ARE in scope (chronologically ≤ N)") {
        // Scene 2 has a fact and Mia is its POV. Query asOfSceneId=scene2.
        let f = fact("Mia drank wine.", source: scene2Id)
        let (project, scenes) = makeFixture(
            povS2: miaId,
            miaFacts: [scene2Id: [f]]
        )
        let result = LedgerKnowledge.compute(
            characterId: miaId,
            asOfSceneId: scene2Id,
            in: project,
            scenes: scenes
        )
        try expectEqual(result.knows.count, 1)
        try expectEqual(result.knows[0].fact, "Mia drank wine.")
    }

    s.test("facts about ANY character are walked, not just the queried character's own ledger") {
        // Anders POV scene 1, Anders extracted fact. Mia POV scene 2,
        // Mia extracted fact. Query Mia as of scene 3:
        //   - Anders's scene-1 fact: Mia was not present → unknown
        //   - Mia's scene-2 fact: Mia was POV → knows
        let andersFact = fact("Anders walked alone.", source: scene1Id)
        let miaFact = fact("Mia opened the door.", source: scene2Id)
        let (project, scenes) = makeFixture(
            povS1: andersId,
            povS2: miaId,
            miaFacts: [scene2Id: [miaFact]],
            andersFacts: [scene1Id: [andersFact]]
        )
        let result = LedgerKnowledge.compute(
            characterId: miaId,
            asOfSceneId: scene3Id,
            in: project,
            scenes: scenes
        )
        try expectEqual(result.knows.count, 1)
        try expectEqual(result.knows[0].fact, "Mia opened the door.")
        try expectEqual(result.unknowns.count, 1)
        try expectEqual(result.unknowns[0].fact, "Anders walked alone.")
    }

    s.test("name appearing in prose (free-text, no @-mention) marks the character present in that scene") {
        // Anders POV scene 1. Mia mentioned by name in scene 1's prose.
        // A fact extracted in scene 1 → Mia counts as present → knows.
        let f = fact("Anders saw Mia at the door.", source: scene1Id)
        let (project, scenes) = makeFixture(
            proseS1: "Anders saw Mia waiting at the door.",
            povS1: andersId,
            andersFacts: [scene1Id: [f]]
        )
        let result = LedgerKnowledge.compute(
            characterId: miaId,
            asOfSceneId: scene3Id,
            in: project,
            scenes: scenes
        )
        try expectEqual(result.knows.count, 1)
        try expectEqual(result.unknowns.count, 0)
    }

    s.test("multiple scenes mix knows + unknowns correctly") {
        // Scene 1: Anders alone → Anders fact lands in Mia's unknowns
        // Scene 2: Mia + Anders both present → Anders fact lands in Mia's knows
        let s1Fact = fact("Anders walked alone.", source: scene1Id)
        let s2Fact = fact("Anders confessed.", source: scene2Id)
        let (project, scenes) = makeFixture(
            povS1: andersId,
            proseS2: "Mia and Anders sat together.",
            povS2: andersId,
            andersFacts: [scene1Id: [s1Fact], scene2Id: [s2Fact]]
        )
        let result = LedgerKnowledge.compute(
            characterId: miaId,
            asOfSceneId: scene3Id,
            in: project,
            scenes: scenes
        )
        try expectEqual(result.knows.count, 1)
        try expectEqual(result.knows[0].fact, "Anders confessed.")
        try expectEqual(result.unknowns.count, 1)
        try expectEqual(result.unknowns[0].fact, "Anders walked alone.")
    }

    s.test("asOfSceneId not in manuscript (orphan/unknown) falls back to ALL scenes in scope") {
        // Defensive: a draft scene that hasn't been placed yet.
        let f = fact("Some fact.", source: scene1Id)
        let (project, scenes) = makeFixture(
            povS1: miaId,
            miaFacts: [scene1Id: [f]]
        )
        let strangerSceneId = UUID()
        let result = LedgerKnowledge.compute(
            characterId: miaId,
            asOfSceneId: strangerSceneId,
            in: project,
            scenes: scenes
        )
        try expectEqual(result.knows.count, 1)
    }

    return s
}

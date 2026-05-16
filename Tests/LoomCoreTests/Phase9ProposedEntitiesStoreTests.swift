import Foundation
@testable import LoomCore

/// Phase 9 entity-discovery — `ProposedEntitiesStore`: on-disk sidecar
/// holding the pending entity-discovery proposals + their attached
/// facts. Per LOOM_ENTITY_DISCOVERY_SPIKE §3.2 + §6.5 productionisation.
/// Single file per project (proposals are scene-anchored but few
/// enough that a per-file index would be over-engineering at v1).
///
/// File layout: `<project>/proposed-entities/proposed-entities.json`
/// containing `{ entities: [...], facts: [...], updatedAt: ISO8601 }`.
func phase9ProposedEntitiesStoreTests() -> TestSuite {
    let s = TestSuite("Phase9ProposedEntitiesStore")

    func tempProjectURL() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("loom-pe-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func proposal(_ name: String, kind: EntityDiscovery.Kind = .character) -> EntityDiscovery.ProposedEntity {
        EntityDiscovery.ProposedEntity(
            id: UUID(),
            kind: kind,
            canonicalName: name,
            aliases: [],
            oneLine: "test",
            evidenceQuote: "x",
            sourceSceneId: UUID(),
            confidence: 0.8
        )
    }

    s.test("load on absent project → nil (no error)") {
        let project = tempProjectURL()
        defer { try? FileManager.default.removeItem(at: project) }
        try expectNil(ProposedEntitiesStore.load(in: project))
    }

    s.test("save then load round-trips") {
        let project = tempProjectURL()
        defer { try? FileManager.default.removeItem(at: project) }
        let p = proposal("Anders")
        let payload = ProposedEntitiesPayload(
            entities: [p],
            facts: [],
            updatedAt: Date()
        )
        try ProposedEntitiesStore.save(payload, in: project)
        let back = try expectNotNil(ProposedEntitiesStore.load(in: project))
        try expectEqual(back.entities.count, 1)
        try expectEqual(back.entities[0].canonicalName, "Anders")
    }

    s.test("save creates the sidecar directory if missing") {
        let project = tempProjectURL()
        defer { try? FileManager.default.removeItem(at: project) }
        // Don't pre-create proposed-entities/ — store should mkdir
        let payload = ProposedEntitiesPayload(entities: [proposal("Anders")], facts: [], updatedAt: Date())
        try ProposedEntitiesStore.save(payload, in: project)
        try expectTrue(FileManager.default.fileExists(
            atPath: project.appendingPathComponent("proposed-entities/proposed-entities.json").path
        ))
    }

    s.test("append adds entities + facts to existing payload") {
        let project = tempProjectURL()
        defer { try? FileManager.default.removeItem(at: project) }
        try ProposedEntitiesStore.save(
            ProposedEntitiesPayload(entities: [proposal("Anders")], facts: [], updatedAt: Date()),
            in: project
        )
        let newEntity = proposal("Karim")
        let newFact = EntityDiscovery.ProposedEntityFacts(
            proposedEntityId: newEntity.id,
            facts: [LedgerExtraction.ExtractedFact(
                characterId: newEntity.id.uuidString,
                fact: "is Mia's brother",
                certainty: .asserted,
                evidenceQuote: "x"
            )]
        )
        try ProposedEntitiesStore.append(entities: [newEntity], facts: [newFact], in: project)
        let back = try expectNotNil(ProposedEntitiesStore.load(in: project))
        try expectEqual(back.entities.count, 2)
        try expectEqual(back.facts.count, 1)
    }

    s.test("append on absent project starts fresh (no error)") {
        let project = tempProjectURL()
        defer { try? FileManager.default.removeItem(at: project) }
        let p = proposal("Anders")
        try ProposedEntitiesStore.append(entities: [p], facts: [], in: project)
        let back = try expectNotNil(ProposedEntitiesStore.load(in: project))
        try expectEqual(back.entities.count, 1)
    }

    s.test("remove drops proposal by id and its attached facts") {
        let project = tempProjectURL()
        defer { try? FileManager.default.removeItem(at: project) }
        let a = proposal("Anders")
        let k = proposal("Karim")
        let kFact = EntityDiscovery.ProposedEntityFacts(
            proposedEntityId: k.id,
            facts: [LedgerExtraction.ExtractedFact(
                characterId: k.id.uuidString,
                fact: "x", certainty: .asserted, evidenceQuote: "x"
            )]
        )
        try ProposedEntitiesStore.save(
            ProposedEntitiesPayload(entities: [a, k], facts: [kFact], updatedAt: Date()),
            in: project
        )
        try ProposedEntitiesStore.remove(proposalId: k.id, in: project)
        let back = try expectNotNil(ProposedEntitiesStore.load(in: project))
        try expectEqual(back.entities.count, 1)
        try expectEqual(back.entities[0].id, a.id)
        try expectEqual(back.facts.count, 0)  // k's facts dropped too
    }

    s.test("remove on absent project is a no-op (not an error)") {
        let project = tempProjectURL()
        defer { try? FileManager.default.removeItem(at: project) }
        try ProposedEntitiesStore.remove(proposalId: UUID(), in: project)
        try expectNil(ProposedEntitiesStore.load(in: project))
    }

    s.test("remove on unknown id is a no-op") {
        let project = tempProjectURL()
        defer { try? FileManager.default.removeItem(at: project) }
        let a = proposal("Anders")
        try ProposedEntitiesStore.save(
            ProposedEntitiesPayload(entities: [a], facts: [], updatedAt: Date()),
            in: project
        )
        try ProposedEntitiesStore.remove(proposalId: UUID(), in: project)
        let back = try expectNotNil(ProposedEntitiesStore.load(in: project))
        try expectEqual(back.entities.count, 1)
    }

    s.test("malformed JSON on disk → load returns nil (defensive)") {
        let project = tempProjectURL()
        defer { try? FileManager.default.removeItem(at: project) }
        let dir = project.appendingPathComponent("proposed-entities", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("proposed-entities.json")
        try "{ not json".write(to: file, atomically: true, encoding: .utf8)
        try expectNil(ProposedEntitiesStore.load(in: project))
    }

    func sceneProposal(_ name: String, scene: UUID, kind: EntityDiscovery.Kind = .character) -> EntityDiscovery.ProposedEntity {
        EntityDiscovery.ProposedEntity(
            id: UUID(),
            kind: kind,
            canonicalName: name,
            aliases: [],
            oneLine: "test",
            evidenceQuote: "x",
            sourceSceneId: scene,
            confidence: 0.8
        )
    }

    s.test("replaceProposals supersedes prior proposals for the same scene") {
        // Live-smoke: re-running discovery on a scene used to APPEND,
        // so each run stacked duplicate Chantal/Muriel/Jacob entries
        // (plus stale leftovers from earlier scene drafts). Re-running
        // must give a fresh set for that scene, not an accumulation.
        let project = tempProjectURL()
        defer { try? FileManager.default.removeItem(at: project) }
        let sceneA = UUID()
        let sceneB = UUID()
        try ProposedEntitiesStore.save(
            ProposedEntitiesPayload(
                entities: [
                    sceneProposal("StaleJacob", scene: sceneA),
                    sceneProposal("StaleKey", scene: sceneA, kind: .object),
                    sceneProposal("OtherSceneEntity", scene: sceneB),
                ],
                facts: [],
                updatedAt: Date()
            ),
            in: project
        )
        try ProposedEntitiesStore.replaceProposals(
            forSceneId: sceneA,
            entities: [sceneProposal("Chantal", scene: sceneA), sceneProposal("Muriel", scene: sceneA)],
            facts: [],
            in: project
        )
        let back = try expectNotNil(ProposedEntitiesStore.load(in: project))
        let names = Set(back.entities.map(\.canonicalName))
        // sceneA's old proposals gone, fresh ones present.
        try expectEqual(names, Set(["Chantal", "Muriel", "OtherSceneEntity"]))
    }

    s.test("replaceProposals drops facts attached to superseded proposals") {
        let project = tempProjectURL()
        defer { try? FileManager.default.removeItem(at: project) }
        let sceneA = UUID()
        let stale = sceneProposal("StaleJacob", scene: sceneA)
        let staleFact = EntityDiscovery.ProposedEntityFacts(
            proposedEntityId: stale.id,
            facts: [LedgerExtraction.ExtractedFact(
                characterId: stale.id.uuidString, fact: "stale", certainty: .asserted, evidenceQuote: "x"
            )]
        )
        try ProposedEntitiesStore.save(
            ProposedEntitiesPayload(entities: [stale], facts: [staleFact], updatedAt: Date()),
            in: project
        )
        try ProposedEntitiesStore.replaceProposals(
            forSceneId: sceneA,
            entities: [sceneProposal("Chantal", scene: sceneA)],
            facts: [],
            in: project
        )
        let back = try expectNotNil(ProposedEntitiesStore.load(in: project))
        try expectEqual(back.facts.count, 0, "stale fact should be dropped with its proposal")
        try expectEqual(back.entities.count, 1)
    }

    s.test("replaceProposals on absent project starts fresh (no error)") {
        let project = tempProjectURL()
        defer { try? FileManager.default.removeItem(at: project) }
        let sceneA = UUID()
        try ProposedEntitiesStore.replaceProposals(
            forSceneId: sceneA,
            entities: [sceneProposal("Chantal", scene: sceneA)],
            facts: [],
            in: project
        )
        let back = try expectNotNil(ProposedEntitiesStore.load(in: project))
        try expectEqual(back.entities.count, 1)
    }

    return s
}

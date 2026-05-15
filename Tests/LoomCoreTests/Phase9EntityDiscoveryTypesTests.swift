import Foundation
@testable import LoomCore

/// Phase 9 entity-discovery spike — pure-data types.
/// LOOM_ENTITY_DISCOVERY_SPIKE §3.2 / §6.2: `ProposedEntity` /
/// `ProposedEntityFacts` are the wire shape between Stage D (GBNF
/// normalisation) and Stage F (suggestion queue). They round-trip
/// through Codable so they can be persisted as a sidecar on disk
/// (queue state) and serialised over the BibleWorkspace bridge.
func phase9EntityDiscoveryTypesTests() -> TestSuite {
    let s = TestSuite("Phase9EntityDiscoveryTypes")

    s.test("Kind decodes from the two valid raw values") {
        try expectEqual(EntityDiscovery.Kind(rawValue: "character"), .character)
        try expectEqual(EntityDiscovery.Kind(rawValue: "place"), .place)
        try expectNil(EntityDiscovery.Kind(rawValue: "object"))
    }

    s.test("ProposedEntity round-trips through Codable") {
        let id = UUID()
        let sceneId = UUID()
        let p = EntityDiscovery.ProposedEntity(
            id: id,
            kind: .character,
            canonicalName: "Marius Thorn",
            aliases: ["Marius", "the doctor"],
            oneLine: "A reclusive doctor with a haunted past.",
            evidenceQuote: "Marius pulled the blanket tight around his shoulders.",
            sourceSceneId: sceneId,
            confidence: 0.82
        )
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(EntityDiscovery.ProposedEntity.self, from: data)
        try expectEqual(back, p)
    }

    s.test("ProposedEntity place kind round-trips") {
        let p = EntityDiscovery.ProposedEntity(
            id: UUID(),
            kind: .place,
            canonicalName: "The Hollow",
            aliases: [],
            oneLine: "An abandoned woodland clearing.",
            evidenceQuote: "They reached The Hollow by dusk.",
            sourceSceneId: UUID(),
            confidence: 0.6
        )
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(EntityDiscovery.ProposedEntity.self, from: data)
        try expectEqual(back.kind, .place)
        try expectEqual(back, p)
    }

    s.test("ProposedEntityFacts attaches multiple facts to one proposal") {
        let proposalId = UUID()
        let facts = [
            LedgerExtraction.ExtractedFact(
                characterId: proposalId.uuidString,
                fact: "Cooked breakfast for the others.",
                certainty: .asserted,
                evidenceQuote: "He cracked the eggs into the skillet."
            ),
            LedgerExtraction.ExtractedFact(
                characterId: proposalId.uuidString,
                fact: "Mentioned a sister in passing.",
                certainty: .asserted,
                evidenceQuote: "\"My sister would have laughed,\" he said."
            ),
        ]
        let bundle = EntityDiscovery.ProposedEntityFacts(
            proposedEntityId: proposalId,
            facts: facts
        )
        let data = try JSONEncoder().encode(bundle)
        let back = try JSONDecoder().decode(EntityDiscovery.ProposedEntityFacts.self, from: data)
        try expectEqual(back, bundle)
        try expectEqual(back.facts.count, 2)
    }

    s.test("ProposedEntityFacts handles empty facts (entity proposed, no facts yet)") {
        let bundle = EntityDiscovery.ProposedEntityFacts(
            proposedEntityId: UUID(),
            facts: []
        )
        let data = try JSONEncoder().encode(bundle)
        let back = try JSONDecoder().decode(EntityDiscovery.ProposedEntityFacts.self, from: data)
        try expectEqual(back, bundle)
    }

    s.test("ProposedEntity confidence is clamped to 0...1 at construction") {
        // Confidence is gate-output; out-of-range should clamp not throw
        // (we want the pipeline to never crash on a buggy LLM emit).
        let high = EntityDiscovery.ProposedEntity(
            id: UUID(), kind: .character, canonicalName: "X",
            aliases: [], oneLine: "", evidenceQuote: "",
            sourceSceneId: UUID(), confidence: 1.5
        )
        try expectEqual(high.confidence, 1.0)
        let low = EntityDiscovery.ProposedEntity(
            id: UUID(), kind: .character, canonicalName: "X",
            aliases: [], oneLine: "", evidenceQuote: "",
            sourceSceneId: UUID(), confidence: -0.2
        )
        try expectEqual(low.confidence, 0.0)
    }

    return s
}

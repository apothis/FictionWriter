import Foundation
@testable import LoomCore

/// Phase 9 v2 — object discovery (BibleObject). Additive: same
/// pipeline shape (gate, dedup, scorer) but a third Kind raw value.
/// LOOM_ENTITY_DISCOVERY_SPIKE §5 deferred item.
///
/// Tests pin: Kind enum has .object; promotion gate handles objects
/// identically to characters (proper-noun-or-"The X"); place-
/// recurrence does NOT fire on objects (kind != .place short-
/// circuit); grammars/schemas allow "object" in the kind alternation;
/// SnapshotProposedEntity round-trips with kind: "object".
func phase9ObjectKindTests() -> TestSuite {
    let s = TestSuite("Phase9ObjectKind")

    s.test("Kind.object decodes from raw value") {
        try expectEqual(EntityDiscovery.Kind(rawValue: "object"), .object)
        try expectEqual(EntityDiscovery.Kind.object.rawValue, "object")
    }

    s.test("Kind.allCases includes object") {
        let cases = Set(EntityDiscovery.Kind.allCases.map(\.rawValue))
        try expectTrue(cases.contains("object"))
        try expectTrue(cases.contains("character"))
        try expectTrue(cases.contains("place"))
        try expectEqual(EntityDiscovery.Kind.allCases.count, 3)
    }

    s.test("promotion gate handles single proper-noun objects (Excalibur)") {
        // Named objects without a "The" prefix are still proper
        // nouns — gate passes them like characters.
        try expectEqual(EntityPromotionGate.evaluate(canonicalName: "Excalibur"), .promote)
        try expectEqual(EntityPromotionGate.evaluate(canonicalName: "Mjolnir"), .promote)
    }

    s.test("promotion gate handles 'The X' objects") {
        try expectEqual(EntityPromotionGate.evaluate(canonicalName: "The Necronomicon"), .promote)
        try expectEqual(EntityPromotionGate.evaluate(canonicalName: "The One Ring"), .promote)
    }

    s.test("promotion gate rejects generic objects (lowercase nouns)") {
        try expectEqual(EntityPromotionGate.evaluate(canonicalName: "the cup"), .rejectNoProperNoun)
        try expectEqual(EntityPromotionGate.evaluate(canonicalName: "the knife"), .rejectNoProperNoun)
    }

    s.test("place-recurrence filter does NOT fire on .object kind") {
        // Single-mention named objects must pass — Excalibur in one
        // scene shouldn't be rejected by the place-recurrence gate.
        let prose = "He picked up Excalibur."
        try expectTrue(EntityDiscovery.passesPlaceRecurrence(
            surface: "Excalibur", kind: .object, scenePose: prose
        ))
        // Sanity: same surface as a .place would also pass single-
        // mention proper-noun via the "The"-prefix path (not the
        // single-token uppercase path) — but Excalibur has no
        // "The". This test pins .object's path.
    }

    s.test("ProposedEntity round-trips with kind: .object") {
        let p = EntityDiscovery.ProposedEntity(
            id: UUID(),
            kind: .object,
            canonicalName: "Excalibur",
            aliases: ["the sword"],
            oneLine: "Arthur's legendary blade.",
            evidenceQuote: "He drew Excalibur.",
            sourceSceneId: UUID(),
            confidence: 0.85
        )
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(EntityDiscovery.ProposedEntity.self, from: data)
        try expectEqual(back, p)
        try expectEqual(back.kind, .object)
    }

    s.test("candidate generation JSON schema kind enum includes object") {
        let schema = EntityDiscovery.candidateGenerationJSONSchema()
        let items = try expectNotNil(schema["items"] as? [String: Any])
        let props = try expectNotNil(items["properties"] as? [String: Any])
        let kind = try expectNotNil(props["kind"] as? [String: Any])
        let enum_ = try expectNotNil(kind["enum"] as? [String])
        try expectTrue(enum_.contains("object"))
        try expectEqual(enum_.count, 3)
    }

    s.test("normalisation JSON schema kind enum includes object") {
        let schema = EntityDiscovery.normalisationJSONSchema()
        let props = try expectNotNil(schema["properties"] as? [String: Any])
        let kind = try expectNotNil(props["kind"] as? [String: Any])
        let enum_ = try expectNotNil(kind["enum"] as? [String])
        try expectTrue(enum_.contains("object"))
    }

    s.test("Stage A2 GBNF kind rule includes object") {
        let g = EntityDiscovery.candidateGenerationGBNF()
        try expectTrue(g.contains("object"))
    }

    s.test("parser decodes a candidate with kind=object") {
        let raw = "[{\"surface\": \"Excalibur\", \"kind\": \"object\", \"first_seen_quote\": \"He drew it.\"}]"
        let cands = try EntityDiscovery.parseCandidates(raw)
        try expectEqual(cands.count, 1)
        try expectEqual(cands[0].kind, .object)
    }

    s.test("normalisation parser decodes kind=object") {
        let raw = """
        {"kind": "object", "canonical_name": "The Necronomicon", "aliases": [], "one_line": "x", "evidence_quote": "x"}
        """
        let ent = try EntityDiscovery.parseNormalisedEntity(raw)
        try expectEqual(ent.kind, .object)
    }

    return s
}

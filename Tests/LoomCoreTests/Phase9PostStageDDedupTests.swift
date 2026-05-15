import Foundation
@testable import LoomCore

/// Phase 9 entity-discovery — post-Stage-D canonical-name dedup.
/// LOOM_ENTITY_DISCOVERY_SPIKE §6.4 second-run finding: eds-06
/// emitted "Marius Thorn" twice. The CoreML Wegmann embedder
/// (style-similarity, not semantic) didn't cluster "Marius Thorn"
/// vs "Dr Thorn" tightly enough at Stage C — but **both Stage D
/// outputs ended up with identical canonical_name "Marius Thorn"**.
///
/// Trivial fix: after Stage D completes, walk the normalised
/// entities and merge any sharing a canonical_name (case-insensitive,
/// trimmed). The merged version inherits the union of aliases.
/// This is *post-LLM* dedup, complementary to the embedding-based
/// pre-LLM dedup that runs against the starting bible.
func phase9PostStageDDedupTests() -> TestSuite {
    let s = TestSuite("Phase9PostStageDDedup")

    func e(_ name: String, kind: EntityDiscovery.Kind = .character, aliases: [String] = [], oneLine: String = "x", evidence: String = "x") -> EntityDiscovery.NormalisedEntity {
        EntityDiscovery.NormalisedEntity(kind: kind, canonicalName: name, aliases: aliases, oneLine: oneLine, evidenceQuote: evidence)
    }

    s.test("empty input → empty output") {
        let out = EntityDiscovery.dedupByCanonicalName([])
        try expectEqual(out.count, 0)
    }

    s.test("distinct canonical names → all kept") {
        let out = EntityDiscovery.dedupByCanonicalName([
            e("Mia"), e("Anders"), e("Karim"),
        ])
        try expectEqual(out.count, 3)
    }

    s.test("two with identical canonical → merge, aliases unioned") {
        // The eds-06 case: Stage D emitted Marius Thorn twice with
        // different alias annotations.
        let out = EntityDiscovery.dedupByCanonicalName([
            e("Marius Thorn", aliases: ["Thorn"]),
            e("Marius Thorn", aliases: ["Dr Thorn"]),
        ])
        try expectEqual(out.count, 1)
        let merged = out[0]
        try expectEqual(merged.canonicalName, "Marius Thorn")
        try expectEqual(Set(merged.aliases), Set(["Thorn", "Dr Thorn"]))
    }

    s.test("merge is case-insensitive") {
        let out = EntityDiscovery.dedupByCanonicalName([
            e("Marius Thorn", aliases: ["a"]),
            e("MARIUS THORN", aliases: ["b"]),
            e("marius thorn", aliases: ["c"]),
        ])
        try expectEqual(out.count, 1)
        try expectEqual(Set(out[0].aliases), Set(["a", "b", "c"]))
    }

    s.test("merge preserves first occurrence's canonical-name casing") {
        // First-wins for the canonical string itself so the user-
        // visible name is whatever Stage D emitted first.
        let out = EntityDiscovery.dedupByCanonicalName([
            e("Marius Thorn"),
            e("MARIUS THORN"),
        ])
        try expectEqual(out[0].canonicalName, "Marius Thorn")
    }

    s.test("character + place with same name do NOT merge (kind matters)") {
        // Defensive: if Stage D somehow emits a character "Anders"
        // and a place "Anders", keep them separate.
        let out = EntityDiscovery.dedupByCanonicalName([
            e("Anders", kind: .character),
            e("Anders", kind: .place),
        ])
        try expectEqual(out.count, 2)
    }

    s.test("preserves first occurrence's one_line + evidence_quote") {
        // Merging takes the first non-empty oneLine/evidence to
        // avoid losing context to a later, less informative copy.
        let out = EntityDiscovery.dedupByCanonicalName([
            e("Marius Thorn", oneLine: "doctor", evidence: "Marius Thorn arrived."),
            e("Marius Thorn", oneLine: "intense man", evidence: "he was intense."),
        ])
        try expectEqual(out.count, 1)
        try expectEqual(out[0].oneLine, "doctor")
        try expectEqual(out[0].evidenceQuote, "Marius Thorn arrived.")
    }

    s.test("dedup is order-stable for kept entries") {
        let out = EntityDiscovery.dedupByCanonicalName([
            e("Anders"),
            e("Marius Thorn", aliases: ["a"]),
            e("Karim"),
            e("Marius Thorn", aliases: ["b"]),
        ])
        try expectEqual(out.count, 3)
        try expectEqual(out[0].canonicalName, "Anders")
        try expectEqual(out[1].canonicalName, "Marius Thorn")
        try expectEqual(out[2].canonicalName, "Karim")
    }

    return s
}

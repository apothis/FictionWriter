import Foundation
@testable import LoomCore

/// Phase 9 entity-discovery — pre-Stage-D candidate dedup.
///
/// Live-smoke: the reworded Stage A2 prompt fixed recall (Chantal
/// and Muriel finally surfaced) but gemma4_2b emitted one candidate
/// per *mention* — a 1263-word scene produced 30 candidates for 3
/// entities. Each duplicate fires its own Stage D normalisation
/// call, serialised through Ollama; discovery time ballooned from
/// ~30s to minutes. `dedupCandidatesBySurface` collapses duplicates
/// before the expensive fan-out.
func phase9CandidateDedupTests() -> TestSuite {
    let s = TestSuite("Phase9CandidateDedup")

    func c(_ surface: String, kind: EntityDiscovery.Kind = .character, quote: String = "q") -> EntityDiscovery.Candidate {
        EntityDiscovery.Candidate(surface: surface, kind: kind, firstSeenQuote: quote)
    }

    s.test("empty input → empty output") {
        try expectEqual(EntityDiscovery.dedupCandidatesBySurface([]).count, 0)
    }

    s.test("distinct surfaces → all kept") {
        let out = EntityDiscovery.dedupCandidatesBySurface([
            c("Chantal"), c("Muriel"), c("Jacob"),
        ])
        try expectEqual(out.count, 3)
    }

    s.test("repeated surface collapses to first occurrence (the 30-mention case)") {
        let out = EntityDiscovery.dedupCandidatesBySurface([
            c("Chantal", quote: "first"),
            c("Muriel", quote: "m1"),
            c("Chantal", quote: "second"),
            c("Chantal", quote: "third"),
            c("Muriel", quote: "m2"),
        ])
        try expectEqual(out.count, 2)
        try expectEqual(out[0].surface, "Chantal")
        // First occurrence's quote survives.
        try expectEqual(out[0].firstSeenQuote, "first")
        try expectEqual(out[1].surface, "Muriel")
        try expectEqual(out[1].firstSeenQuote, "m1")
    }

    s.test("dedup is case-insensitive and trims whitespace") {
        let out = EntityDiscovery.dedupCandidatesBySurface([
            c("Chantal"), c("chantal"), c("  CHANTAL  "),
        ])
        try expectEqual(out.count, 1)
    }

    s.test("same surface, different kind → kept separate") {
        // Rare but legitimate — a character and a place could share
        // a surface form. Don't collapse across kinds.
        let out = EntityDiscovery.dedupCandidatesBySurface([
            c("Brussels", kind: .character),
            c("Brussels", kind: .place),
        ])
        try expectEqual(out.count, 2)
    }

    s.test("input order is preserved for kept candidates") {
        let out = EntityDiscovery.dedupCandidatesBySurface([
            c("Jacob"), c("Chantal"), c("Jacob"), c("Muriel"),
        ])
        try expectEqual(out.map(\.surface), ["Jacob", "Chantal", "Muriel"])
    }

    return s
}

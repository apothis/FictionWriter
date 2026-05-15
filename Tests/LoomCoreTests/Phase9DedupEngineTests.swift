import Foundation
@testable import LoomCore

/// Phase 9 entity-discovery spike — Stage C dedup engine.
/// LOOM_ENTITY_DISCOVERY_SPIKE §3.1 Stage C / §4.4: embed
/// (candidate name + evidence quote), nearest-neighbour against
/// existing bible entries (CoreML Wegmann at production time, stub
/// here), threshold-band verdict:
///   ≥ mergeThreshold (default 0.85)     → mergesWith
///   ambiguousThreshold…mergeThreshold   → ambiguous (LLM-judge)
///   <  ambiguousThreshold (default 0.65) → proposeAsNew
///
/// Embedder injected per `EmbeddingClient` protocol so the tests
/// drive a deterministic stub. Production wires the existing
/// `CoreMLEmbeddingClient`.
func phase9DedupEngineTests() -> TestSuite {
    let s = TestSuite("Phase9DedupEngine")

    // MARK: helpers

    /// Deterministic stub embedder — returns vectors from a fixed
    /// map. Anything outside the map yields a constant orthogonal
    /// vector so the un-mapped cases are always "very dissimilar."
    final class StubEmbedder: EmbeddingClient {
        let mapping: [String: EmbeddingVector]
        let fallback: EmbeddingVector
        init(_ mapping: [String: EmbeddingVector]) {
            self.mapping = mapping
            self.fallback = EmbeddingVector(values: [0, 0, 0, 1])
        }
        var modelId: String { "stub" }
        var dim: Int { 4 }
        func embed(_ text: String) -> EmbeddingVector? {
            mapping[text] ?? fallback
        }
    }

    func v(_ a: Float, _ b: Float, _ c: Float, _ d: Float) -> EmbeddingVector {
        EmbeddingVector(values: [a, b, c, d])
    }

    let mariusId = UUID()
    let liaaId = UUID()
    let karimId = UUID()

    // MARK: tests

    s.test("empty existing list → propose as new (no dedup candidate)") {
        let stub = StubEmbedder([
            "Velka — singer at The Quay": v(1, 0, 0, 0)
        ])
        let verdict = EntityDedupEngine.evaluate(
            candidateName: "Velka",
            candidateEvidenceQuote: "singer at The Quay",
            existingEntities: [],
            embedder: stub
        )
        try expectEqual(verdict, .proposeAsNew(closestSimilarity: nil))
    }

    s.test("high cosine → mergesWith existing") {
        // "Dr Thorn" + evidence and "Marius Thorn" + aliases embed
        // to nearly-identical vectors — typical "same person, two
        // surface forms" case.
        let stub = StubEmbedder([
            "Dr Thorn — house call doctor": v(1, 0, 0, 0),
            "Marius Thorn (aka Dr Thorn, Thorn, Marius)": v(0.99, 0.14, 0, 0),
            "Liana — friend": v(0, 1, 0, 0),
        ])
        let existing = [
            EntityDedupEngine.ExistingEntity(id: mariusId, canonicalName: "Marius Thorn", aliases: ["Dr Thorn", "Thorn", "Marius"]),
            EntityDedupEngine.ExistingEntity(id: liaaId, canonicalName: "Liana", aliases: ["friend"]),
        ]
        let verdict = EntityDedupEngine.evaluate(
            candidateName: "Dr Thorn",
            candidateEvidenceQuote: "house call doctor",
            existingEntities: existing,
            embedder: stub
        )
        if case .mergesWith(let id, let sim) = verdict {
            try expectEqual(id, mariusId)
            try expectTrue(sim >= 0.85)
        } else {
            throw TestFailure(message: "expected .mergesWith, got \(verdict)", file: #file, line: #line)
        }
    }

    s.test("mid-band cosine → ambiguous (LLM-judge boundary)") {
        // 0.7 cosine: same broad concept (e.g. "Karim" vs "Kareem"
        // or "Anders" vs "Andres") but not high enough for auto-
        // merge. Production routes to LLM-judge; here we just
        // assert the verdict.
        let stub = StubEmbedder([
            "Andres — coworker": v(1, 0, 0, 0),
            "Anders (aka Anders Voll)": v(0.7, 0.71, 0, 0),  // cos≈0.7
        ])
        let existing = [
            EntityDedupEngine.ExistingEntity(id: karimId, canonicalName: "Anders", aliases: ["Anders Voll"]),
        ]
        let verdict = EntityDedupEngine.evaluate(
            candidateName: "Andres",
            candidateEvidenceQuote: "coworker",
            existingEntities: existing,
            embedder: stub
        )
        if case .ambiguous(let id, let sim) = verdict {
            try expectEqual(id, karimId)
            try expectTrue(sim >= 0.65 && sim < 0.85)
        } else {
            throw TestFailure(message: "expected .ambiguous, got \(verdict)", file: #file, line: #line)
        }
    }

    s.test("low cosine → propose as new (with closest similarity surfaced)") {
        let stub = StubEmbedder([
            "Theo — ex-lover": v(1, 0, 0, 0),
            "Karim (aka Karim Vance)": v(0, 1, 0, 0),
        ])
        let existing = [
            EntityDedupEngine.ExistingEntity(id: karimId, canonicalName: "Karim", aliases: ["Karim Vance"]),
        ]
        let verdict = EntityDedupEngine.evaluate(
            candidateName: "Theo",
            candidateEvidenceQuote: "ex-lover",
            existingEntities: existing,
            embedder: stub
        )
        if case .proposeAsNew(let sim) = verdict {
            // 0 cosine surfaced as the closest-similarity hint.
            let unwrapped = try expectNotNil(sim)
            try expectTrue(unwrapped < 0.65)
        } else {
            throw TestFailure(message: "expected .proposeAsNew, got \(verdict)", file: #file, line: #line)
        }
    }

    s.test("picks the closest of multiple existing entities") {
        let stub = StubEmbedder([
            "Marius — doctor": v(1, 0, 0, 0),
            "Karim (aka Karim Vance)": v(0, 1, 0, 0),
            "Marius Thorn (aka Dr Thorn)": v(0.95, 0.31, 0, 0),
            "Anders (aka Anders Voll)": v(0, 0.5, 0.87, 0),
        ])
        let existing = [
            EntityDedupEngine.ExistingEntity(id: karimId, canonicalName: "Karim", aliases: ["Karim Vance"]),
            EntityDedupEngine.ExistingEntity(id: mariusId, canonicalName: "Marius Thorn", aliases: ["Dr Thorn"]),
            EntityDedupEngine.ExistingEntity(id: liaaId, canonicalName: "Anders", aliases: ["Anders Voll"]),
        ]
        let verdict = EntityDedupEngine.evaluate(
            candidateName: "Marius",
            candidateEvidenceQuote: "doctor",
            existingEntities: existing,
            embedder: stub
        )
        if case .mergesWith(let id, _) = verdict {
            try expectEqual(id, mariusId)
        } else {
            throw TestFailure(message: "expected mergesWith Marius id, got \(verdict)", file: #file, line: #line)
        }
    }

    s.test("custom thresholds override defaults") {
        // Same vectors but lower mergeThreshold to 0.6 — now the
        // 0.7-cosine case auto-merges.
        let stub = StubEmbedder([
            "Andres — coworker": v(1, 0, 0, 0),
            "Anders (aka Anders Voll)": v(0.7, 0.71, 0, 0),
        ])
        let existing = [
            EntityDedupEngine.ExistingEntity(id: karimId, canonicalName: "Anders", aliases: ["Anders Voll"]),
        ]
        let verdict = EntityDedupEngine.evaluate(
            candidateName: "Andres",
            candidateEvidenceQuote: "coworker",
            existingEntities: existing,
            embedder: stub,
            mergeThreshold: 0.6,
            ambiguousThreshold: 0.4
        )
        if case .mergesWith(let id, _) = verdict {
            try expectEqual(id, karimId)
        } else {
            throw TestFailure(message: "expected mergesWith under custom thresholds, got \(verdict)", file: #file, line: #line)
        }
    }

    s.test("embedder failure on candidate → propose as new (defensive)") {
        // Stub that returns nil for everything.
        final class NilEmbedder: EmbeddingClient {
            var modelId: String { "nil" }
            var dim: Int { 4 }
            func embed(_ text: String) -> EmbeddingVector? { nil }
        }
        let existing = [
            EntityDedupEngine.ExistingEntity(id: mariusId, canonicalName: "Marius Thorn", aliases: []),
        ]
        let verdict = EntityDedupEngine.evaluate(
            candidateName: "Anyone",
            candidateEvidenceQuote: "any quote",
            existingEntities: existing,
            embedder: NilEmbedder()
        )
        // Can't compare similarity if we can't embed — safe default
        // is propose-as-new so the user gets to see + judge.
        try expectEqual(verdict, .proposeAsNew(closestSimilarity: nil))
    }

    s.test("nil on one existing entity skips it without affecting verdict") {
        // Stub that returns nil for one specific bible-side text but
        // valid vectors for others.
        final class SkipEmbedder: EmbeddingClient {
            var modelId: String { "skip" }
            var dim: Int { 4 }
            func embed(_ text: String) -> EmbeddingVector? {
                if text == "Karim (aka Karim Vance)" { return nil }
                if text == "Marius Thorn (aka Dr Thorn)" {
                    return EmbeddingVector(values: [0.95, 0.31, 0, 0])
                }
                if text == "Dr Thorn — house call doctor" {
                    return EmbeddingVector(values: [1, 0, 0, 0])
                }
                return EmbeddingVector(values: [0, 0, 0, 1])
            }
        }
        let existing = [
            EntityDedupEngine.ExistingEntity(id: karimId, canonicalName: "Karim", aliases: ["Karim Vance"]),
            EntityDedupEngine.ExistingEntity(id: mariusId, canonicalName: "Marius Thorn", aliases: ["Dr Thorn"]),
        ]
        let verdict = EntityDedupEngine.evaluate(
            candidateName: "Dr Thorn",
            candidateEvidenceQuote: "house call doctor",
            existingEntities: existing,
            embedder: SkipEmbedder()
        )
        if case .mergesWith(let id, _) = verdict {
            try expectEqual(id, mariusId)
        } else {
            throw TestFailure(message: "expected mergesWith Marius, got \(verdict)", file: #file, line: #line)
        }
    }

    return s
}

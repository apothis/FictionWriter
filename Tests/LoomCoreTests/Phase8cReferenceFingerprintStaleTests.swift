import Foundation
@testable import LoomCore

/// Phase 8.c — Wegmann re-ingest UX. HANDOFF §15.16 follow-up #3:
/// References ingested under the old StyleDistance fingerprint are
/// stale relative to the current CoreML Wegmann embedder; without
/// detection RetrievalService silently returns mismatched vectors.
/// Pure-data staleness check + a snapshot field + a UI badge close
/// the loop.
///
/// Test surface: the staleness derivation function (4 cases).
func phase8cReferenceFingerprintStaleTests() -> TestSuite {
    let s = TestSuite("Phase8cReferenceFingerprintStale")

    s.test("nil persisted + nil expected → nil (no info)") {
        try expectNil(SnapshotReference.computeDModelStale(persisted: nil, expectedModelId: nil))
    }

    s.test("nil persisted + expected → nil (not yet ingested, can't be stale)") {
        try expectNil(SnapshotReference.computeDModelStale(
            persisted: nil,
            expectedModelId: "AnnaWegmann/Style-Embedding (CoreML)"
        ))
    }

    s.test("persisted + nil expected → nil (no current embedder, can't compare)") {
        let fp = ReferenceTextIndex.ModelFingerprint(id: "old", dim: 768)
        try expectNil(SnapshotReference.computeDModelStale(
            persisted: fp,
            expectedModelId: nil
        ))
    }

    s.test("persisted matches expected → false (fresh)") {
        let fp = ReferenceTextIndex.ModelFingerprint(
            id: "AnnaWegmann/Style-Embedding (CoreML)", dim: 768
        )
        try expectEqual(
            SnapshotReference.computeDModelStale(
                persisted: fp,
                expectedModelId: "AnnaWegmann/Style-Embedding (CoreML)"
            ),
            false
        )
    }

    s.test("persisted differs from expected → true (stale)") {
        // Phase 5 → Phase 8.c migration: the old ID was the
        // StyleDistance MLX model; new is the CoreML Wegmann.
        let fp = ReferenceTextIndex.ModelFingerprint(
            id: "StyleDistance (MLX)", dim: 768
        )
        try expectEqual(
            SnapshotReference.computeDModelStale(
                persisted: fp,
                expectedModelId: "AnnaWegmann/Style-Embedding (CoreML)"
            ),
            true
        )
    }

    s.test("comparison is case-sensitive (model IDs are exact strings)") {
        let fp = ReferenceTextIndex.ModelFingerprint(id: "annawegmann/style-embedding (coreml)", dim: 768)
        try expectEqual(
            SnapshotReference.computeDModelStale(
                persisted: fp,
                expectedModelId: "AnnaWegmann/Style-Embedding (CoreML)"
            ),
            true
        )
    }

    s.test("CoreMLEmbeddingClient surfaces an expectedModelId static") {
        // Caller (window controller) needs a known constant to pass
        // in without instantiating the client just to read its
        // modelId. Expose it on the type.
        try expectEqual(CoreMLEmbeddingClient.expectedModelId, "AnnaWegmann/Style-Embedding (CoreML)")
    }

    return s
}

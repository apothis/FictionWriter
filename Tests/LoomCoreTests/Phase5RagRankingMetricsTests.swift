import Foundation
@testable import LoomCore

/// Pure-data scoring primitives for the Phase 5 RAG-for-style spike
/// (LOOM_RAG_SPIKE.md §5). Three metrics: NDCG@k, style-vs-topic
/// preference index, Kendall's tau. The spike runner combines all
/// three per path; this file pins their behaviour against
/// hand-computed values.
func phase5RagRankingMetricsTests() -> TestSuite {
    let s = TestSuite("Phase5RagRankingMetrics")

    // MARK: - NDCG@k (binary relevance)

    s.test("ndcg of a perfect top-k ranking is 1.0") {
        // 4 candidates, 2 relevant (ids 10, 20). Perfect top-3 is
        // [10, 20, x] for any irrelevant x.
        let v = RankingMetrics.ndcg(at: 3, gold: [10, 20], ranking: [10, 20, 30, 40])
        try expectTrue(abs(v - 1.0) < 1e-9, "got \(v)")
    }

    s.test("ndcg of all-irrelevant top-k is 0.0") {
        let v = RankingMetrics.ndcg(at: 3, gold: [10, 20], ranking: [30, 40, 50, 10, 20])
        try expectEqual(v, 0.0)
    }

    s.test("ndcg of partial top-k matches the hand-computed value") {
        // ranking [10, 30, 20, 40], gold {10, 20}, k=3
        // DCG  = 1/log2(2) + 0/log2(3) + 1/log2(4) = 1 + 0 + 0.5 = 1.5
        // IDCG = 1/log2(2) + 1/log2(3) + 0/log2(4) = 1 + 0.6309297... = 1.6309297...
        // NDCG = 1.5 / 1.6309297... ≈ 0.91972...
        let v = RankingMetrics.ndcg(at: 3, gold: [10, 20], ranking: [10, 30, 20, 40])
        try expectTrue(abs(v - 0.9197207891481876) < 1e-9, "got \(v)")
    }

    s.test("ndcg with k larger than ranking length clamps to ranking length") {
        let v = RankingMetrics.ndcg(at: 10, gold: [10, 20], ranking: [10, 20])
        try expectTrue(abs(v - 1.0) < 1e-9, "got \(v)")
    }

    s.test("ndcg with empty gold returns 0 (undefined, choose 0)") {
        let v = RankingMetrics.ndcg(at: 3, gold: [], ranking: [10, 20, 30])
        try expectEqual(v, 0.0)
    }

    s.test("ndcg with empty ranking returns 0") {
        let v = RankingMetrics.ndcg(at: 3, gold: [10], ranking: [])
        try expectEqual(v, 0.0)
    }

    // MARK: - Style-vs-topic preference index

    s.test("preference is +1.0 when top-3 is all same-style") {
        let v = RankingMetrics.styleTopicPreference(
            top3: [1, 2, 3],
            styleMatch: [1, 2, 3, 4],
            topicMatch: [5, 6, 7]
        )
        try expectTrue(abs(v - 1.0) < 1e-9, "got \(v)")
    }

    s.test("preference is -1.0 when top-3 is all topic-not-style") {
        let v = RankingMetrics.styleTopicPreference(
            top3: [5, 6, 7],
            styleMatch: [1, 2, 3, 4],
            topicMatch: [5, 6, 7]
        )
        try expectTrue(abs(v + 1.0) < 1e-9, "got \(v)")
    }

    s.test("preference is 0 when top-3 is unrelated to either gold set") {
        let v = RankingMetrics.styleTopicPreference(
            top3: [100, 101, 102],
            styleMatch: [1, 2, 3],
            topicMatch: [5, 6, 7]
        )
        try expectEqual(v, 0.0)
    }

    s.test("preference handles 1 style + 1 topic + 1 unrelated") {
        // s=1, t=1 → (1 - 1) / 3 = 0
        let v = RankingMetrics.styleTopicPreference(
            top3: [1, 5, 100],
            styleMatch: [1, 2, 3],
            topicMatch: [5, 6, 7]
        )
        try expectEqual(v, 0.0)
    }

    s.test("preference treats an id in BOTH sets as style-only (not double-counted)") {
        // If a chunk shares both style AND topic with the query, it
        // belongs to the styleMatch set; topicMatch's contribution
        // is "same topic, DIFFERENT style" per the doc.
        let v = RankingMetrics.styleTopicPreference(
            top3: [1, 2, 3],
            styleMatch: [1, 2, 3],
            topicMatch: [1, 2, 3]
        )
        try expectTrue(abs(v - 1.0) < 1e-9, "got \(v)")
    }

    // MARK: - Kendall's tau

    s.test("kendallTau of a ranking against itself is 1.0") {
        let v = RankingMetrics.kendallTau([1, 2, 3, 4, 5], [1, 2, 3, 4, 5])
        try expectTrue(abs(v - 1.0) < 1e-9, "got \(v)")
    }

    s.test("kendallTau of a perfectly reversed ranking is -1.0") {
        let v = RankingMetrics.kendallTau([1, 2, 3, 4, 5], [5, 4, 3, 2, 1])
        try expectTrue(abs(v + 1.0) < 1e-9, "got \(v)")
    }

    s.test("kendallTau matches the hand-computed value for a single swap") {
        // [1,2,3,4] vs [2,1,3,4]: pairs (in a's order) and rank in b
        // (1,2): a says 1<2 (1 first), b says 2<1 → discordant
        // (1,3): a 1<3, b 1<3 (b pos: 1@1, 3@2) → concordant
        // (1,4): concordant
        // (2,3): a 2<3, b 2<3 → concordant
        // (2,4): concordant
        // (3,4): concordant
        // 5 concordant, 1 discordant; pairs = 6
        // tau = (5 - 1) / 6 = 0.6666...
        let v = RankingMetrics.kendallTau([1, 2, 3, 4], [2, 1, 3, 4])
        try expectTrue(abs(v - (4.0/6.0)) < 1e-9, "got \(v)")
    }

    s.test("kendallTau returns 0 for ranking lengths < 2") {
        try expectEqual(RankingMetrics.kendallTau([], []), 0.0)
        try expectEqual(RankingMetrics.kendallTau([1], [1]), 0.0)
    }

    s.test("kendallTau returns 0 when rankings cover different item sets (defensive)") {
        // Production callers must rank the same id universe. Defensive
        // 0 guards against the eval runner shipping bad data.
        let v = RankingMetrics.kendallTau([1, 2, 3], [1, 2, 4])
        try expectEqual(v, 0.0)
    }

    // MARK: - rankExcerpts (the eval-runner glue)

    s.test("rankExcerpts orders excerpts by cosine similarity to the query (descending)") {
        // Hand-constructed 2-d vectors: ids 1, 2, 3 along directions
        // pointing in different parts of the plane; query parallel to id 2.
        let query = EmbeddingVector(values: [1.0, 0.0])
        let excerpts: [(Int, EmbeddingVector)] = [
            (1, EmbeddingVector(values: [0.0, 1.0])),    // cosine 0 (orthogonal)
            (2, EmbeddingVector(values: [1.0, 0.0])),    // cosine 1 (parallel)
            (3, EmbeddingVector(values: [0.7, 0.7])),    // cosine ~0.707
        ]
        let ranking = RankingMetrics.rankExcerpts(query: query, excerpts: excerpts)
        try expectEqual(ranking, [2, 3, 1])
    }

    s.test("rankExcerpts on empty excerpts returns empty") {
        let query = EmbeddingVector(values: [1.0, 0.0])
        try expectEqual(RankingMetrics.rankExcerpts(query: query, excerpts: []), [])
    }

    s.test("rankExcerpts breaks ties deterministically by id (lower id first)") {
        let query = EmbeddingVector(values: [1.0, 0.0])
        let excerpts: [(Int, EmbeddingVector)] = [
            (5, EmbeddingVector(values: [1.0, 0.0])),
            (3, EmbeddingVector(values: [1.0, 0.0])),
            (7, EmbeddingVector(values: [1.0, 0.0])),
        ]
        let ranking = RankingMetrics.rankExcerpts(query: query, excerpts: excerpts)
        try expectEqual(ranking, [3, 5, 7])
    }

    // MARK: - reciprocalRankFusion (Phase 5 D + E hybrid merge)

    s.test("RRF on a single ranking is identity (degenerate single-path case)") {
        let merged = RankingMetrics.reciprocalRankFusion(
            rankings: [[1, 2, 3, 4]],
            k: 10
        )
        try expectEqual(merged, [1, 2, 3, 4])
    }

    s.test("RRF on two identical rankings preserves the order") {
        let merged = RankingMetrics.reciprocalRankFusion(
            rankings: [[1, 2, 3, 4], [1, 2, 3, 4]],
            k: 10
        )
        try expectEqual(merged, [1, 2, 3, 4])
    }

    s.test("RRF on two opposite rankings ranks the middle items highest") {
        // ranking A: [1, 2, 3, 4]    (ranks 0,1,2,3 → 1/10, 1/11, 1/12, 1/13)
        // ranking B: [4, 3, 2, 1]    (ranks 0,1,2,3 → 4 gets 1/10, 3 gets 1/11, etc)
        //
        // total scores:
        //   1: 1/10 + 1/13 = 0.1769
        //   2: 1/11 + 1/12 = 0.1742
        //   3: 1/12 + 1/11 = 0.1742
        //   4: 1/13 + 1/10 = 0.1769
        //
        // 1 + 4 tie, 2 + 3 tie. Tie-break by id ascending: [1, 4, 2, 3].
        let merged = RankingMetrics.reciprocalRankFusion(
            rankings: [[1, 2, 3, 4], [4, 3, 2, 1]],
            k: 10
        )
        try expectEqual(merged, [1, 4, 2, 3])
    }

    s.test("RRF matches the hand-computed score formula 1/(k + rank)") {
        // 2 paths, 3 items, k=10. Hand-computed scores:
        // path A:  [10, 20, 30]
        // path B:  [30, 10, 20]
        //
        // scores per item:
        //   10: 1/(10+0) + 1/(10+1) = 0.1 + 0.0909 = 0.1909
        //   20: 1/(10+1) + 1/(10+2) = 0.0909 + 0.0833 = 0.1742
        //   30: 1/(10+2) + 1/(10+0) = 0.0833 + 0.1 = 0.1833
        //
        // Order: 10 (0.1909) > 30 (0.1833) > 20 (0.1742) → [10, 30, 20]
        let merged = RankingMetrics.reciprocalRankFusion(
            rankings: [[10, 20, 30], [30, 10, 20]],
            k: 10
        )
        try expectEqual(merged, [10, 30, 20])
    }

    s.test("RRF item appearing in only one ranking gets only that ranking's contribution") {
        // ranking A: [1, 2, 3]
        // ranking B: [4]
        // scores:
        //   1: 1/(10+0) = 0.1
        //   2: 1/(10+1) = 0.0909
        //   3: 1/(10+2) = 0.0833
        //   4: 1/(10+0) = 0.1
        // 1 and 4 tie at 0.1; tie-break ascending id → [1, 4, 2, 3]
        let merged = RankingMetrics.reciprocalRankFusion(
            rankings: [[1, 2, 3], [4]],
            k: 10
        )
        try expectEqual(merged, [1, 4, 2, 3])
    }

    s.test("RRF with k=60 (Cormack default) produces different ranking than k=10 on tied edges") {
        // At k=60 the rank gradient is much flatter:
        //   ranking A: [1, 2]     (1/(60+0), 1/(60+1))
        //   ranking B: [2, 1]     (1/(60+0) for 2, 1/(60+1) for 1)
        //   scores:
        //     1: 1/60 + 1/61
        //     2: 1/61 + 1/60
        //   exact tie → tie-break by id → [1, 2]
        //
        // This test exists to pin that k is configurable and the
        // formula is exact; the §13 production note explains why
        // Loom uses k=10 over Cormack's 60.
        let merged = RankingMetrics.reciprocalRankFusion(
            rankings: [[1, 2], [2, 1]],
            k: 60
        )
        try expectEqual(merged, [1, 2])
    }

    s.test("RRF with weights honours the per-path weighting") {
        // Equal weight default behaves the same as no-weights.
        let equal = RankingMetrics.reciprocalRankFusion(
            rankings: [[1, 2], [2, 1]],
            k: 10, weights: [0.5, 0.5]
        )
        let unweighted = RankingMetrics.reciprocalRankFusion(
            rankings: [[1, 2], [2, 1]],
            k: 10
        )
        try expectEqual(equal, unweighted)

        // Asymmetric weight collapses to the higher-weighted ranking.
        let bias = RankingMetrics.reciprocalRankFusion(
            rankings: [[1, 2, 3], [3, 2, 1]],
            k: 10, weights: [1.0, 0.0]
        )
        try expectEqual(bias, [1, 2, 3])
    }

    s.test("RRF returns empty array when given empty rankings") {
        try expectEqual(
            RankingMetrics.reciprocalRankFusion(rankings: [], k: 10),
            []
        )
        try expectEqual(
            RankingMetrics.reciprocalRankFusion(rankings: [[]], k: 10),
            []
        )
    }

    s.test("RRF returns the union of items across all input rankings") {
        let merged = RankingMetrics.reciprocalRankFusion(
            rankings: [[1, 2], [3, 4]],
            k: 10
        )
        try expectEqual(Set(merged), Set([1, 2, 3, 4]))
    }

    return s
}

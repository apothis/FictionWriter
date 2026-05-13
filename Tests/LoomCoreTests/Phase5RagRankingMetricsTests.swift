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

    return s
}

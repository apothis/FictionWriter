import Foundation

/// Scoring primitives for the Phase 5 RAG-for-style spike
/// (LOOM_RAG_SPIKE.md §5). NDCG@k as the headline binary-relevance
/// metric; style-vs-topic preference index as the corroborating
/// signal that catches paths gaming small fixtures; Kendall's tau
/// for secondary oracle-agreement scoring.

public enum RankingMetrics {
    /// NDCG@k under binary relevance (item is either in `gold` or
    /// not). `ranking` is the ordered list of item ids the embedder
    /// produced; `gold` is the set of relevant ids.
    ///
    /// Returns 0 for any degenerate input (empty gold, empty
    /// ranking, k <= 0) so callers don't need to special-case.
    public static func ndcg(at k: Int, gold: Set<Int>, ranking: [Int]) -> Double {
        guard k > 0, !gold.isEmpty, !ranking.isEmpty else { return 0 }
        let effectiveK = min(k, ranking.count)

        var dcg: Double = 0
        for i in 0..<effectiveK {
            if gold.contains(ranking[i]) {
                dcg += 1.0 / log2(Double(i) + 2.0)
            }
        }

        let idealRelevant = min(effectiveK, gold.count)
        var idcg: Double = 0
        for i in 0..<idealRelevant {
            idcg += 1.0 / log2(Double(i) + 2.0)
        }

        guard idcg > 0 else { return 0 }
        return dcg / idcg
    }

    /// Style-vs-topic preference in [-1, 1]. Counts how many of the
    /// top-3 are same-style as the query vs. how many are
    /// same-topic-but-different-style. A path that hits NDCG@3 ≥ 0.7
    /// but has preference ≤ 0 isn't actually retrieving style — both
    /// must agree.
    ///
    /// Items present in both `styleMatch` and `topicMatch` count as
    /// style-only — the topic-only contribution requires *different
    /// style*, per the LOOM_RAG_SPIKE §5.2 definition.
    public static func styleTopicPreference(
        top3: [Int],
        styleMatch: Set<Int>,
        topicMatch: Set<Int>
    ) -> Double {
        let topicOnly = topicMatch.subtracting(styleMatch)
        var s = 0
        var t = 0
        for id in top3 {
            if styleMatch.contains(id) {
                s += 1
            } else if topicOnly.contains(id) {
                t += 1
            }
        }
        return Double(s - t) / 3.0
    }

    /// Rank a set of (id, vector) excerpts by cosine similarity to a
    /// query vector, descending. Ties are broken by ascending id so the
    /// eval-runner's output is deterministic across runs (same fixture
    /// always produces the same ranking).
    public static func rankExcerpts(
        query: EmbeddingVector,
        excerpts: [(Int, EmbeddingVector)]
    ) -> [Int] {
        let scored = excerpts.map { (id, vec) -> (Int, Float) in
            (id, EmbeddingVector.cosine(query, vec))
        }
        return scored
            .sorted { a, b in
                if a.1 != b.1 { return a.1 > b.1 }
                return a.0 < b.0
            }
            .map { $0.0 }
    }

    /// Reciprocal Rank Fusion — the Phase 5 hybrid merge policy
    /// (LOOM_PLAN.md §5, scope-lock #4).
    ///
    /// Combines multiple per-path rankings into a single merged
    /// ranking by summing `1 / (k + rank_i)` across each path the
    /// item appears in. The merged ordering is descending by this
    /// summed reciprocal-rank score; ties break by ascending item id.
    ///
    /// Defaults to `k = 10` rather than Cormack et al. 2009's `k = 60`
    /// — the original tuning targeted TREC top-1000 deep rankings,
    /// where a flatter rank gradient is appropriate. Loom retrieves
    /// the top-3 over a small (~50-chunk) corpus where rank-1 hits
    /// must dominate; `k = 10` keeps the contribution gap between
    /// rank-1 and rank-10 wide enough to matter.
    ///
    /// `weights` is optional. When provided, each path's contribution
    /// is multiplied by its weight (weighted-RRF). Must have the same
    /// count as `rankings`. Pass `nil` for equal weights — the
    /// Phase 5 default per LOOM_RAG_SPIKE §13 (D and E tie on NDCG
    /// in the spike fixture; no learned weights to overfit on a
    /// 16-decision sample).
    ///
    /// Items absent from a given path's ranking get zero contribution
    /// from that path — they only score on the paths they appear in.
    /// This is the score-blind property that makes RRF preserve E's
    /// NSFW parity without smearing toward D's distribution.
    public static func reciprocalRankFusion(
        rankings: [[Int]],
        k: Int = 10,
        weights: [Double]? = nil
    ) -> [Int] {
        guard !rankings.isEmpty else { return [] }
        let w: [Double] = weights ?? Array(repeating: 1.0, count: rankings.count)

        var scores: [Int: Double] = [:]
        for (pathIdx, ranking) in rankings.enumerated() {
            let weight = pathIdx < w.count ? w[pathIdx] : 1.0
            if weight == 0 { continue }
            for (rank, id) in ranking.enumerated() {
                let contribution = weight / Double(k + rank)
                scores[id, default: 0] += contribution
            }
        }
        return scores.keys
            .sorted { a, b in
                let sa = scores[a] ?? 0
                let sb = scores[b] ?? 0
                if sa != sb { return sa > sb }
                return a < b
            }
    }

    /// Kendall's tau-a in [-1, 1]. Both inputs must be permutations
    /// of the same id universe. Returns 0 for trivial cases (length
    /// < 2) and as a defensive guard when the two rankings cover
    /// different items.
    public static func kendallTau(_ a: [Int], _ b: [Int]) -> Double {
        guard a.count >= 2, a.count == b.count else { return 0 }
        guard Set(a) == Set(b) else { return 0 }

        var rankInB: [Int: Int] = [:]
        for (i, id) in b.enumerated() { rankInB[id] = i }

        var concordant = 0
        var discordant = 0
        for i in 0..<a.count {
            for j in (i + 1)..<a.count {
                let ri = rankInB[a[i]] ?? 0
                let rj = rankInB[a[j]] ?? 0
                if ri < rj { concordant += 1 }
                else if ri > rj { discordant += 1 }
            }
        }
        let pairs = a.count * (a.count - 1) / 2
        return Double(concordant - discordant) / Double(pairs)
    }
}

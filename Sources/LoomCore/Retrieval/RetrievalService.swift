import Foundation

/// A style exemplar — what the retrieval surface returns to callers.
/// Carries enough metadata for the writer-prompt assembler to do its
/// few-shot injection AND for the UI to show provenance ("retrieved
/// from references/hemingway-sample.md, chunk 4 (action)").
public struct StyleExemplar: Equatable {
    public let referenceId: UUID
    public let referenceName: String
    public let chunkIndex: Int
    public let text: String
    public let modality: NarrativeMode?
    /// RRF score; useful for the UI debug "why this chunk?" view.
    public let rrfScore: Double

    public init(
        referenceId: UUID,
        referenceName: String,
        chunkIndex: Int,
        text: String,
        modality: NarrativeMode?,
        rrfScore: Double
    ) {
        self.referenceId = referenceId
        self.referenceName = referenceName
        self.chunkIndex = chunkIndex
        self.text = text
        self.modality = modality
        self.rrfScore = rrfScore
    }
}

/// Query-side composition for Phase 5 style-RAG. Mirror of
/// [`ReferenceIngestPipeline`](ReferenceIngestPipeline.swift) — ingest
/// writes (.md + .index sidecars); RetrievalService reads them.
///
/// Operation per query:
///
/// 1. Load every reference's `.index` sidecar in the project.
///    References missing a sidecar (ingest not yet run) are silently
///    skipped — they'll come online once their ingest finishes.
/// 2. Optionally filter chunks by modality (`.mixed` passed as
///    filter is a no-op — see test for rationale).
/// 3. Embed the query via the injected D `EmbeddingClient`. Refit
///    `FuncwordZEmbedder` across the full project corpus and
///    transform the query. Either step can fail gracefully:
///    - D fails → degrade to E-only retrieval.
///    - All chunks lack eVec → degrade to D-only retrieval.
///    - Both fail → return empty.
/// 4. Per-path rank candidate chunks by cosine similarity (top-K
///    each, where K = `rrfMergeWindow` defaulting to top-10 — the
///    LOOM_RAG_SPIKE §13.8 recommendation).
/// 5. Reciprocal Rank Fusion merge per
///    [`RankingMetrics.reciprocalRankFusion`](RankingMetrics.swift)
///    with k=10, equal weights.
/// 6. Take top-K from the merged ranking, return as StyleExemplars
///    with full provenance metadata.
public final class RetrievalService {
    public let projectURL: URL
    public let dClient: EmbeddingClient
    public let rrfK: Int
    public let rrfMergeWindow: Int

    public init(
        projectURL: URL,
        dClient: EmbeddingClient,
        rrfK: Int = 10,
        rrfMergeWindow: Int = 10
    ) {
        self.projectURL = projectURL
        self.dClient = dClient
        self.rrfK = rrfK
        self.rrfMergeWindow = rrfMergeWindow
    }

    public func retrieve(
        query: String,
        modalityFilter: NarrativeMode? = nil,
        topK: Int = 3
    ) throws -> [StyleExemplar] {
        let allIds = try ReferenceStorage.listReferenceIds(in: projectURL)
        guard !allIds.isEmpty else { return [] }

        // Gather candidate chunks across every reference. Each
        // candidate gets a stable opaque id (we use the index into
        // this array) so RankingMetrics.reciprocalRankFusion's
        // [Int] ranking type stays the same.
        struct Candidate {
            let opaqueId: Int
            let referenceId: UUID
            let referenceName: String
            let chunkIndex: Int
            let chunk: ReferenceTextIndex.Chunk
        }
        var candidates: [Candidate] = []
        for refId in allIds {
            guard let idx = ReferenceStorage.loadIndex(for: refId, in: projectURL),
                  let ref = try? ReferenceStorage.loadReference(id: refId, in: projectURL)
            else { continue }
            for (ci, chunk) in idx.chunks.enumerated() {
                if let f = modalityFilter, f != .mixed {
                    guard let modalityRaw = chunk.modality,
                          NarrativeMode(rawValue: modalityRaw) == f
                    else { continue }
                }
                candidates.append(Candidate(
                    opaqueId: candidates.count,
                    referenceId: refId,
                    referenceName: ref.name,
                    chunkIndex: ci,
                    chunk: chunk
                ))
            }
        }
        guard !candidates.isEmpty else { return [] }

        // Per-path rankings — produce as much as we can; degrade
        // gracefully when either path is unavailable.
        var perPathRankings: [[Int]] = []

        // Path D: query embedding via the injected client, candidate
        // chunks via stored dVec. Skip path if either side is missing.
        if let queryD = dClient.embed(query) {
            let dPairs: [(Int, EmbeddingVector)] = candidates.compactMap { c in
                guard let v = c.chunk.dVec else { return nil }
                return (c.opaqueId, EmbeddingVector(values: v))
            }
            if !dPairs.isEmpty {
                let ranking = RankingMetrics.rankExcerpts(query: queryD, excerpts: dPairs)
                perPathRankings.append(Array(ranking.prefix(rrfMergeWindow)))
            }
        }

        // Path E: fit function-word-z on the project corpus, transform
        // the query, rank against stored eVec. Skip if no eVec stored
        // anywhere yet (refitAllEVectors hasn't run).
        let haveAnyE = candidates.contains { $0.chunk.eVec != nil }
        if haveAnyE {
            // Refit on the full corpus so the query is on the same
            // distribution as stored eVecs. Cost: O(total chunks);
            // sub-second for typical projects.
            let allChunkTexts = candidates.compactMap { $0.chunk.text }
            let eModel = FuncwordZEmbedder.fit(
                corpus: allChunkTexts,
                topN: ReferenceIngestPipeline.eTopN
            )
            let queryE = FuncwordZEmbedder.transform(query, using: eModel)
            let ePairs: [(Int, EmbeddingVector)] = candidates.compactMap { c in
                guard let v = c.chunk.eVec else { return nil }
                return (c.opaqueId, EmbeddingVector(values: v))
            }
            if !ePairs.isEmpty {
                let ranking = RankingMetrics.rankExcerpts(query: queryE, excerpts: ePairs)
                perPathRankings.append(Array(ranking.prefix(rrfMergeWindow)))
            }
        }

        guard !perPathRankings.isEmpty else { return [] }

        let merged = RankingMetrics.reciprocalRankFusion(
            rankings: perPathRankings, k: rrfK
        )
        let topOpaque = Array(merged.prefix(topK))

        // Compute RRF scores for the top-K (small set; recompute
        // rather than thread-through).
        let scores = scoreMap(rankings: perPathRankings, k: rrfK)

        let byOpaque = Dictionary(uniqueKeysWithValues: candidates.map { ($0.opaqueId, $0) })
        return topOpaque.compactMap { id in
            guard let c = byOpaque[id] else { return nil }
            return StyleExemplar(
                referenceId: c.referenceId,
                referenceName: c.referenceName,
                chunkIndex: c.chunkIndex,
                text: c.chunk.text,
                modality: c.chunk.modality.flatMap(NarrativeMode.init(rawValue:)),
                rrfScore: scores[id] ?? 0
            )
        }
    }

    /// Replicates the RRF score formula. RankingMetrics returns the
    /// merged ranking but not the scores; we recompute here to
    /// surface them on StyleExemplar.
    private func scoreMap(rankings: [[Int]], k: Int) -> [Int: Double] {
        var scores: [Int: Double] = [:]
        for ranking in rankings {
            for (rank, id) in ranking.enumerated() {
                scores[id, default: 0] += 1.0 / Double(k + rank)
            }
        }
        return scores
    }
}

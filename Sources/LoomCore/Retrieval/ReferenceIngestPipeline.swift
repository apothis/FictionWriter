import Foundation

/// Production-shape abstraction for the per-chunk D embedder. Phase 5
/// production wraps the MLX StyleDistance call site (closed in
/// [`LOOM_MLX_PORT_SPIKE.md`](../../LOOM_MLX_PORT_SPIKE.md)) as one
/// concrete `EmbeddingClient`. Test stubs implement the same protocol
/// to keep [`ReferenceIngestPipeline`](#) pure-data testable without
/// MLX wired up.
public protocol EmbeddingClient {
    /// Unique identifier persisted on the index sidecar's
    /// `ModelFingerprint.id`. Used at retrieval time to detect when
    /// a model swap has invalidated existing vectors.
    var modelId: String { get }
    /// Output dimensionality. Persisted on `ModelFingerprint.dim`.
    var dim: Int { get }
    /// Embed a single text. Returns nil on failure (network, model
    /// load error, etc.); the pipeline records nil dVec rather than
    /// failing the whole ingest, so a partial state is recoverable
    /// by re-running ingest after the upstream issue is fixed.
    func embed(_ text: String) -> EmbeddingVector?
}

/// Orchestrates reference-text ingest. Composes the pieces landed
/// across Phase 5 production scope-locks 1-5 into a single pipeline:
///
/// 1. Load `references/<id>.md` via [`ReferenceStorage`](Storage/ReferenceStorage.swift).
/// 2. Chunk via [`RagChunker`](Embeddings.swift).
/// 3. Classify modality via [`NarrativeModeClassifier`](NarrativeModeClassifier.swift)
///    (heuristic dialogue-gate first, caller-supplied LLM closure
///    for the residual; per
///    [LOOM_NARRATIVE_MODE_SPIKE](../../LOOM_NARRATIVE_MODE_SPIKE.md)
///    §10).
/// 4. Embed each chunk via the injected D `EmbeddingClient`
///    (MLX StyleDistance in production).
/// 5. Write the `.index` sidecar with chunks + modality + dVec.
///
/// Path E vectors are filled in a second pass — see
/// `refitAllEVectors()`. They're project-wide and so must re-fit on
/// every new reference; doing it inline at single-reference ingest
/// would re-touch every other reference's sidecar, which is operationally
/// noisy.
public final class ReferenceIngestPipeline {
    public let projectURL: URL
    public let chunkSize: Int
    public let chunkOverlap: Int
    public let dClient: EmbeddingClient
    public let modalityLLM: (String) -> NarrativeMode?

    public init(
        projectURL: URL,
        chunkSize: Int = 100,
        chunkOverlap: Int = 20,
        dClient: EmbeddingClient,
        modalityLLM: @escaping (String) -> NarrativeMode?
    ) {
        self.projectURL = projectURL
        self.chunkSize = chunkSize
        self.chunkOverlap = chunkOverlap
        self.dClient = dClient
        self.modalityLLM = modalityLLM
    }

    public static let eModelIdentifier = "loom/funcword-z-top150"
    public static let eTopN = 150

    /// Fit a project-wide function-word z-score model across every
    /// chunk in every reference, then transform each chunk and write
    /// the resulting eVec back into the sidecar. Idempotent — a
    /// repeat call produces the same vectors as long as the corpus
    /// is unchanged. No-op if there are no references.
    ///
    /// Called after every new-reference ingest in production, since
    /// adding a reference shifts the corpus distribution. Cost scales
    /// with total chunk count (low hundreds typical); takes
    /// milliseconds even with thousands of chunks since the fit and
    /// transform are pure-numpy-equivalent Swift.
    public func refitAllEVectors() throws {
        let allRefIds = try ReferenceStorage.listReferenceIds(in: projectURL)
        guard !allRefIds.isEmpty else { return }

        var indexes: [UUID: ReferenceTextIndex] = [:]
        var allChunkTexts: [String] = []
        var ownership: [(refId: UUID, chunkIndex: Int)] = []

        for refId in allRefIds {
            guard let idx = ReferenceStorage.loadIndex(for: refId, in: projectURL) else { continue }
            indexes[refId] = idx
            for (i, chunk) in idx.chunks.enumerated() {
                allChunkTexts.append(chunk.text)
                ownership.append((refId: refId, chunkIndex: i))
            }
        }
        guard !allChunkTexts.isEmpty else { return }

        let eModel = FuncwordZEmbedder.fit(corpus: allChunkTexts, topN: Self.eTopN)
        let fingerprint = ReferenceTextIndex.ModelFingerprint(
            id: Self.eModelIdentifier,
            dim: eModel.dim
        )

        for (i, text) in allChunkTexts.enumerated() {
            let eVec = FuncwordZEmbedder.transform(text, using: eModel)
            let (refId, chunkIdx) = ownership[i]
            indexes[refId]?.chunks[chunkIdx].eVec = eVec.values
        }
        for refId in indexes.keys {
            indexes[refId]?.eModel = fingerprint
            try ReferenceStorage.saveIndex(indexes[refId]!, for: refId, in: projectURL)
        }
    }

    @discardableResult
    public func chunkAndEmbedD(referenceId: UUID) throws -> ReferenceTextIndex {
        let ref = try ReferenceStorage.loadReference(id: referenceId, in: projectURL)
        let chunks = RagChunker.chunk(ref.body, size: chunkSize, overlap: chunkOverlap)
        let materialChunks = chunks.isEmpty
            ? [RagChunk(text: ref.body, wordRange: 0..<max(1, ref.body.split(whereSeparator: { $0.isWhitespace }).count))]
            : chunks

        var indexChunks: [ReferenceTextIndex.Chunk] = []
        for c in materialChunks {
            let modality = NarrativeModeClassifier.classify(c.text, via: modalityLLM)
            let dVec = dClient.embed(c.text)?.values
            indexChunks.append(
                ReferenceTextIndex.Chunk(
                    text: c.text,
                    wordRangeStart: c.wordRange.lowerBound,
                    wordRangeEnd: c.wordRange.upperBound,
                    modality: modality.rawValue,
                    dVec: dVec,
                    eVec: nil
                )
            )
        }

        let index = ReferenceTextIndex(
            schemaVersion: 1,
            dModel: ReferenceTextIndex.ModelFingerprint(id: dClient.modelId, dim: dClient.dim),
            eModel: nil,
            chunks: indexChunks
        )
        try ReferenceStorage.saveIndex(index, for: referenceId, in: projectURL)
        return index
    }
}

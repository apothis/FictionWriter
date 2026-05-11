import Foundation

/// Single-prompt non-streaming generation. The protocol exists so future
/// side-call call-sites (rolling summary, fact extraction in Phase 2+)
/// can route through a fake during tests. Phase 1 only has one
/// implementation: KoboldClient.
public protocol KoboldGenerating: AnyObject {
    func generate(
        prompt: String,
        stopSequences: [String],
        params: SamplerParams,
        maxContextLength: Int,
        completion: @escaping (Result<String, Error>) -> Void
    )
}

/// Batched text → vector embeddings via KoboldCpp's `/v1/embeddings`
/// endpoint. Requires the server to be launched with
/// `--embeddingsmodel <gguf>` (bge-small-en-v1.5 / nomic-embed-text /
/// similar). Used by the Phase 4 #7 ledger pipeline for fact
/// similarity scoring + deduplication + evidence-quote validation
/// (LOOM_LEDGER_SPIKE §10).
public protocol KoboldEmbedding: AnyObject {
    func embed(
        texts: [String],
        completion: @escaping (Result<[[Float]], Error>) -> Void
    )
}

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

    /// Streaming variant. Each token chunk is delivered via `onToken`
    /// as soon as the writer emits it; `completion` fires once at
    /// the end with the full concatenated text or an error. The
    /// default protocol-extension impl falls back to non-streaming
    /// `generate` and delivers the whole result as a single
    /// `onToken` call — so test stubs that only implement the
    /// non-streaming method still work, but production `KoboldClient`
    /// overrides this to drive `generateStream` directly.
    func generate(
        prompt: String,
        stopSequences: [String],
        params: SamplerParams,
        maxContextLength: Int,
        onToken: @escaping (String) -> Void,
        completion: @escaping (Result<String, Error>) -> Void
    )
}

extension KoboldGenerating {
    public func generate(
        prompt: String,
        stopSequences: [String],
        params: SamplerParams,
        maxContextLength: Int,
        onToken: @escaping (String) -> Void,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        generate(
            prompt: prompt,
            stopSequences: stopSequences,
            params: params,
            maxContextLength: maxContextLength
        ) { result in
            if case .success(let text) = result, !text.isEmpty {
                onToken(text)
            }
            completion(result)
        }
    }
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

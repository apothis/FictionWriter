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

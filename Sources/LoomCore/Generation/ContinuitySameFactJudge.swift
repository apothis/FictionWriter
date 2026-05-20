import Foundation

// Continuity Audit (L10) — §25 Part B. The same-fact judgment
// primitive used by `ContinuityKnowledgeCheck.violations` to decide
// whether two extracted claims assert the same proposition.

/// The async same-fact judgment primitive. Production code calls a
/// `SameFactLLMJudge` (LLM-backed); tests use a deferred stub. The
/// completion is invoked with `.success(judgment)` or `.failure(...)`;
/// on `.failure` the caller treats the pair as `different_fact`
/// (fail-soft — a transient kobold error must not corrupt the audit
/// by accidentally merging two different facts).
public protocol SameFactJudging {
    func judge(
        claimA: ContinuityAudit.Claim,
        claimB: ContinuityAudit.Claim,
        completion: @escaping (Result<ContinuityAudit.SameFactJudgment, Error>) -> Void
    )
}

/// LLM-backed `SameFactJudging` impl — wraps an `OllamaCallProvider`
/// (the abstraction the audit engine already uses for both Ollama and
/// KoboldCpp via `KoboldGenerateProvider`). Builds the same-fact
/// prompt, requests the constrained JSON schema, parses the verdict.
/// A parse failure or transport failure maps to `.failure(_)` — the
/// caller then treats the pair as `different_fact` (fail-soft).
public final class SameFactLLMJudge: SameFactJudging {
    public enum JudgeError: Error { case parse }

    private let provider: OllamaCallProvider
    public init(provider: OllamaCallProvider) {
        self.provider = provider
    }

    public func judge(
        claimA: ContinuityAudit.Claim,
        claimB: ContinuityAudit.Claim,
        completion: @escaping (Result<ContinuityAudit.SameFactJudgment, Error>) -> Void
    ) {
        let prompt = ContinuityAudit.buildSameFactPrompt(claimA: claimA, claimB: claimB)
        provider.call(
            prompt: prompt,
            schema: ContinuityAudit.sameFactJSONSchema(),
            options: OllamaChatOptions(temperature: 0.2)
        ) { result in
            switch result {
            case .success(let raw):
                if let j = try? ContinuityAudit.parseSameFact(raw) {
                    completion(.success(j))
                } else {
                    completion(.failure(JudgeError.parse))
                }
            case .failure(let e):
                completion(.failure(e))
            }
        }
    }
}

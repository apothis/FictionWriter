import Foundation

/// Planned Project mode — Phase 5.1: the async beat-planning pass.
/// Runs one LLM call over a scene's outline summary and turns the
/// response into the beat list the per-beat draft loop consumes. The
/// beat count and word budget are fixed deterministically by
/// `SceneBeatPlanning`; the model only supplies the beat intents.
///
/// `OllamaCallProvider` injection so the orchestration is tested
/// without HTTP — the same shape as `OutlineGenerator`.
public final class SceneBeatPlanner {
    private let provider: OllamaCallProvider

    public init(provider: OllamaCallProvider) {
        self.provider = provider
    }

    public convenience init(client: OllamaClient) {
        self.init(provider: client)
    }

    /// Plan the beats for a scene. The completion always carries a
    /// full beat list on success — `SceneBeatPlanning.parseBeatPlan`
    /// pads or truncates to the deterministic count, so a degenerate
    /// model response still yields a runnable plan. Only a transport
    /// failure surfaces as `.failure`.
    public func planBeats(
        sceneSummary: String,
        targetWordCount: Int,
        completion: @escaping (Result<[SceneBeatPlanning.PlannedBeat], Error>) -> Void
    ) {
        let count = SceneBeatPlanning.beatCount(forTargetWords: targetWordCount)
        let prompt = SceneBeatPlanning.buildBeatPlanPrompt(
            sceneSummary: sceneSummary, beatCount: count
        )
        // num_predict 1024: the answer is a short line list, but small
        // models emit a reasoning preamble first — leave headroom.
        let options = OllamaChatOptions(numPredict: 1024)
        provider.call(prompt: prompt, schema: [:], options: options) { result in
            switch result {
            case .failure(let err):
                completion(.failure(err))
            case .success(let raw):
                let beats = SceneBeatPlanning.parseBeatPlan(
                    raw, beatCount: count, targetWords: targetWordCount
                )
                completion(.success(beats))
            }
        }
    }
}

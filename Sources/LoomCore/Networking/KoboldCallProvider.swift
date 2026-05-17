import Foundation

/// Bridges a `KoboldGenerating` client — the prose-tuned writer model
/// on KoboldCpp — to the `OllamaCallProvider` abstraction, so bounded
/// structured tasks can run on the writer model rather than the small
/// extractor model. Planned Project mode's outline generation uses
/// this (LOOM_PLANNED_PROJECT.md §4): the writer model produces
/// markedly more concrete, scene-ready outlines.
///
/// KoboldCpp's `/api/v1/generate` is raw completion with no
/// server-side chat template, so the prompt is wrapped here in the
/// model family's instruct template (Mistral V7 for the Goetia
/// writer model) and the adapter's stop sequences are passed through.
public final class KoboldCallProvider: OllamaCallProvider {
    private let client: KoboldGenerating
    private let template: InstructTemplate
    private let baseParams: SamplerParams
    private let maxContextLength: Int

    public init(
        client: KoboldGenerating,
        template: InstructTemplate = .mistralV7,
        params: SamplerParams = .phase1Defaults,
        maxContextLength: Int = 8192
    ) {
        self.client = client
        self.template = template
        self.baseParams = params
        self.maxContextLength = maxContextLength
    }

    public func call(
        prompt: String,
        schema: [String: Any],
        options: OllamaChatOptions,
        completion: @escaping (Result<String, OllamaError>) -> Void
    ) {
        let adapter = InstructTemplates.adapter(for: template)
        let wrapped = adapter.wrap(system: "", userBody: prompt, prefill: "")
        // `OllamaChatOptions.numPredict` is the output-token budget;
        // KoboldCpp carries it as the sampler's `maxLength`.
        var params = baseParams
        params.maxLength = options.numPredict
        client.generate(
            prompt: wrapped,
            stopSequences: adapter.stopSequences,
            params: params,
            maxContextLength: maxContextLength
        ) { result in
            switch result {
            case .success(let text):
                completion(.success(text))
            case .failure(let err):
                completion(.failure(.transport("\(err)")))
            }
        }
    }
}

import Foundation

/// Planned Project mode — Phase 2: the async outline-generation
/// orchestrator. Runs the staged pipeline against an LLM provider:
/// Stage 1 (one call) generates the framework's beats; Stage 2 (pure
/// code) maps them to chapters; Stage 3 (one call per chapter)
/// expands each chapter into scenes; Stage 4 assembles a `Manuscript`.
///
/// `OllamaCallProvider` injection so the orchestration is tested
/// without HTTP. The LLM calls run unconstrained (no `format`
/// schema). A Stage 1 failure aborts the generation; a Stage 3
/// chapter that fails or under-delivers degrades to placeholder
/// scenes (`OutlineGeneration.reconcileScenes`) rather than failing
/// the whole outline.
public final class OutlineGenerator {
    private let provider: OllamaCallProvider

    public init(provider: OllamaCallProvider) {
        self.provider = provider
    }

    public convenience init(client: OllamaClient) {
        self.init(provider: client)
    }

    public func generate(
        premise: String,
        characterSketch: String,
        lengthScenario: LengthScenario,
        framework: StoryFramework,
        completion: @escaping (Result<OutlineGeneration.GeneratedOutline, Error>) -> Void
    ) {
        let provider = self.provider
        let sizing = OutlineSizing.plan(for: lengthScenario)
        // num_predict 2048: the answer is a line list, but small
        // models emit a reasoning preamble first (the §15.19/§15.26
        // pathology) — leave headroom.
        let options = OllamaChatOptions(numPredict: 2048)

        let beatPrompt = OutlineGeneration.buildBeatGenerationPrompt(
            premise: premise, characterSketch: characterSketch, framework: framework
        )
        provider.call(prompt: beatPrompt, schema: [:], options: options) { result in
            switch result {
            case .failure(let err):
                completion(.failure(err))
            case .success(let raw):
                let beats = OutlineGeneration.parseGeneratedBeats(raw, framework: framework)
                guard !beats.isEmpty else {
                    completion(.failure(OllamaError.unexpectedShape))
                    return
                }
                let plans = OutlineGeneration.planChapters(beats: beats, sizing: sizing)

                // Stage 3 — one call per chapter, fanned out.
                final class Box {
                    var scenes: [[OutlineGeneration.SceneOutline]]
                    var remaining: Int
                    var fired = false
                    init(count: Int) {
                        scenes = Array(repeating: [], count: count)
                        remaining = count
                    }
                }
                let box = Box(count: plans.count)
                let lock = NSLock()

                for (i, plan) in plans.enumerated() {
                    let scenePrompt = OutlineGeneration.buildSceneGenerationPrompt(
                        chapter: plan, premise: premise, characterSketch: characterSketch
                    )
                    provider.call(prompt: scenePrompt, schema: [:], options: options) { sResult in
                        var parsed: [OutlineGeneration.SceneOutline] = []
                        if case .success(let sRaw) = sResult {
                            parsed = OutlineGeneration.parseGeneratedScenes(sRaw)
                        }
                        lock.lock()
                        box.scenes[i] = parsed
                        box.remaining -= 1
                        let done = box.remaining == 0 && !box.fired
                        if done { box.fired = true }
                        lock.unlock()
                        if done {
                            let outline = OutlineGeneration.assembleOutline(
                                plans: plans,
                                scenesPerChapter: box.scenes,
                                sizing: sizing
                            )
                            completion(.success(outline))
                        }
                    }
                }
            }
        }
    }
}

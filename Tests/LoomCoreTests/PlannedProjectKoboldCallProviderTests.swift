import Foundation
@testable import LoomCore

/// `KoboldCallProvider` — bridges the KoboldCpp writer model to the
/// `OllamaCallProvider` abstraction so outline generation can run on
/// the prose-tuned model. LOOM_PLANNED_PROJECT.md §4.
func plannedProjectKoboldCallProviderTests() -> TestSuite {
    let s = TestSuite("PlannedProjectKoboldCallProvider")

    /// Deferred fake (per feedback_tdd_async_callbacks): stores the
    /// completion; the test flushes it.
    final class FakeKobold: KoboldGenerating {
        var capturedPrompt: String?
        var capturedParams: SamplerParams?
        var pending: ((Result<String, Error>) -> Void)?
        func generate(
            prompt: String, stopSequences: [String], params: SamplerParams,
            maxContextLength: Int,
            completion: @escaping (Result<String, Error>) -> Void
        ) {
            capturedPrompt = prompt
            capturedParams = params
            pending = completion
        }
        func flush(_ result: Result<String, Error>) {
            let p = pending; pending = nil; p?(result)
        }
    }

    let opts = OllamaChatOptions(numPredict: 2048)

    s.test("call wraps the prompt in the instruct template") {
        let fake = FakeKobold()
        let provider = KoboldCallProvider(client: fake, template: .mistralV7)
        provider.call(prompt: "Outline this story.", schema: [:], options: opts) { _ in }
        let wrapped = try expectNotNil(fake.capturedPrompt)
        try expectTrue(wrapped.contains("Outline this story."))
        try expectTrue(wrapped.contains("[INST]"))
    }

    s.test("call maps numPredict onto the sampler maxLength") {
        let fake = FakeKobold()
        let provider = KoboldCallProvider(client: fake)
        provider.call(
            prompt: "x", schema: [:], options: OllamaChatOptions(numPredict: 4096)
        ) { _ in }
        try expectEqual(fake.capturedParams?.maxLength, 4096)
    }

    s.test("a successful generation completes with the text") {
        let fake = FakeKobold()
        let provider = KoboldCallProvider(client: fake)
        var captured: Result<String, OllamaError>?
        provider.call(prompt: "x", schema: [:], options: opts) { captured = $0 }
        fake.flush(.success("the outline"))
        guard case .success(let text)? = captured else {
            throw TestFailure(message: "expected success", file: #file, line: #line)
        }
        try expectEqual(text, "the outline")
    }

    s.test("a failed generation completes with an OllamaError") {
        let fake = FakeKobold()
        let provider = KoboldCallProvider(client: fake)
        var captured: Result<String, OllamaError>?
        provider.call(prompt: "x", schema: [:], options: opts) { captured = $0 }
        fake.flush(.failure(KoboldError.unexpectedShape))
        guard case .failure? = captured else {
            throw TestFailure(message: "expected failure", file: #file, line: #line)
        }
    }

    s.test("the provider outlives the call scope — deferred completion still fires") {
        let fake = FakeKobold()
        var captured: Result<String, OllamaError>?
        do {
            let provider = KoboldCallProvider(client: fake)
            provider.call(prompt: "x", schema: [:], options: opts) { captured = $0 }
        }
        fake.flush(.success("ok"))
        _ = try expectNotNil(captured)
    }

    return s
}

import Foundation
@testable import LoomCore

/// Phase 4 #7 sub-task 8 — async orchestrator that chains the three
/// §10.5 filters behind a single `KoboldEmbedding.embed(...)` batch
/// call. Sits between `LedgerDiff.diff` and
/// `ledgerSuggestionsQueue.add` at the AppState layer; the pipeline
/// itself does NOT hop threads (the AppState wrapper handles
/// main-queue dispatch before touching the queue + notification).
///
/// Tests use a `DeferredStubEmbedder` per the `feedback_tdd_async_callbacks`
/// memory — embed completions are stored and `flush(_:)`-ed by the
/// test, never invoked synchronously inside the stub's `embed(...)`
/// method. Synchronous completion would hide lifetime / dealloc
/// bugs in any [weak self] capture path the pipeline may grow.
func phase4LedgerFilterPipelineTests() -> TestSuite {
    let s = TestSuite("Phase4LedgerFilterPipeline")

    s.test("empty suggestions complete immediately with [] and never call embed") {
        let embedder = DeferredStubEmbedder()
        var result: LedgerFilterPipelineResult?
        LedgerFilterPipeline.apply(
            embedder: embedder,
            suggestions: [],
            existingFactsByCharacter: [:],
            sceneSentences: ["whatever"]
        ) { result = $0 }
        try expectNotNil(result)
        try expectEqual(result?.suggestions.count, 0)
        try expectEqual(result?.dedupDropped, 0)
        try expectEqual(result?.evidenceDropped, 0)
        try expectEqual(result?.leakageDropped, 0)
        try expectNil(embedder.stored)
    }

    s.test("non-empty suggestions: embed is called with fact + evidence + scene-sentence + existing + prompt-instruction") {
        let embedder = DeferredStubEmbedder()
        let mia = UUID()
        let kf = KnownFact(
            id: UUID(),
            fact: "Mia drank wine",
            sourceSceneId: UUID(),
            certainty: .asserted,
            addedAt: Date()
        )
        let suggestion = LedgerSuggestion(
            characterId: mia,
            fact: kf,
            evidenceQuote: "She drank her wine"
        )

        LedgerFilterPipeline.apply(
            embedder: embedder,
            suggestions: [suggestion],
            existingFactsByCharacter: [mia: ["Mia was drinking wine"]],
            sceneSentences: ["Mia drank wine in the kitchen"]
        ) { _ in }

        try expectNotNil(embedder.stored)
        let texts = Set(embedder.stored!.texts)
        try expectTrue(texts.contains("Mia drank wine"))
        try expectTrue(texts.contains("She drank her wine"))
        try expectTrue(texts.contains("Mia was drinking wine"))
        try expectTrue(texts.contains("Mia drank wine in the kitchen"))
        try expectTrue(texts.contains(LedgerExtraction.extractionPromptInstruction))
    }

    s.test("embed failure → completion fires with INPUT suggestions (fail-soft)") {
        let embedder = DeferredStubEmbedder()
        let mia = UUID()
        let suggestion = LedgerSuggestion(
            characterId: mia,
            fact: KnownFact(fact: "Mia drank wine", certainty: .asserted),
            evidenceQuote: ""
        )
        var result: LedgerFilterPipelineResult?
        LedgerFilterPipeline.apply(
            embedder: embedder,
            suggestions: [suggestion],
            existingFactsByCharacter: [:],
            sceneSentences: []
        ) { result = $0 }

        embedder.flush(.failure(NSError(domain: "test", code: 1)))
        try expectEqual(result?.suggestions.count, 1)
        try expectEqual(result?.suggestions.first?.fact.fact, "Mia drank wine")
        // Fail-soft path returns the input list with all zero drops.
        try expectEqual(result?.dedupDropped, 0)
        try expectEqual(result?.evidenceDropped, 0)
        try expectEqual(result?.leakageDropped, 0)
    }

    s.test("embed size mismatch → fail-soft (returns input list)") {
        let embedder = DeferredStubEmbedder()
        let mia = UUID()
        let suggestion = LedgerSuggestion(
            characterId: mia,
            fact: KnownFact(fact: "Mia drank wine", certainty: .asserted),
            evidenceQuote: ""
        )
        var result: LedgerFilterPipelineResult?
        LedgerFilterPipeline.apply(
            embedder: embedder,
            suggestions: [suggestion],
            existingFactsByCharacter: [:],
            sceneSentences: []
        ) { result = $0 }

        // Server returned the wrong number of vectors — pipeline should
        // not assume positional alignment and must fail open.
        embedder.flush(.success([]))
        try expectEqual(result?.suggestions.count, 1)
    }

    s.test("dedup filter fires under the pipeline") {
        let embedder = DeferredStubEmbedder()
        let mia = UUID()
        let suggestion = LedgerSuggestion(
            characterId: mia,
            fact: KnownFact(fact: "Mia drank wine", certainty: .asserted),
            evidenceQuote: ""
        )
        var result: LedgerFilterPipelineResult?
        LedgerFilterPipeline.apply(
            embedder: embedder,
            suggestions: [suggestion],
            existingFactsByCharacter: [mia: ["Mia was drinking wine"]],
            sceneSentences: []
        ) { result = $0 }

        // Vectors keyed by input order — emit near-identical vectors so
        // the cosine ≥ 0.85 dedup fires.
        let texts = embedder.stored!.texts
        let v: [Float] = [1.0, 0.0]
        let vClose: [Float] = [0.95, 0.3122]
        var vectors: [[Float]] = []
        for t in texts {
            switch t {
            case "Mia drank wine": vectors.append(v)
            case "Mia was drinking wine": vectors.append(vClose)
            default: vectors.append([0.0, 1.0])     // orthogonal placeholder
            }
        }
        embedder.flush(.success(vectors))
        try expectEqual(result?.suggestions.count, 0)
        try expectEqual(result?.dedupDropped, 1)
        try expectEqual(result?.evidenceDropped, 0)
        try expectEqual(result?.leakageDropped, 0)
    }

    s.test("evidence-quote validation fires under the pipeline (drops hallucinated quote)") {
        let embedder = DeferredStubEmbedder()
        let mia = UUID()
        let suggestion = LedgerSuggestion(
            characterId: mia,
            fact: KnownFact(fact: "Mia drank wine", certainty: .asserted),
            evidenceQuote: "Mia hallucinated quote"
        )
        var result: LedgerFilterPipelineResult?
        LedgerFilterPipeline.apply(
            embedder: embedder,
            suggestions: [suggestion],
            existingFactsByCharacter: [:],
            sceneSentences: ["Anders looked out the window"]
        ) { result = $0 }

        let texts = embedder.stored!.texts
        let vA: [Float] = [1.0, 0.0]
        let vB: [Float] = [0.0, 1.0]
        var vectors: [[Float]] = []
        for t in texts {
            switch t {
            case "Mia hallucinated quote": vectors.append(vA)
            case "Anders looked out the window": vectors.append(vB)
            case "Mia drank wine": vectors.append(vA)
            default: vectors.append([0.5, 0.5])
            }
        }
        embedder.flush(.success(vectors))
        try expectEqual(result?.suggestions.count, 0)
        try expectEqual(result?.dedupDropped, 0)
        try expectEqual(result?.evidenceDropped, 1)
        try expectEqual(result?.leakageDropped, 0)
    }

    s.test("prompt-leakage filter fires under the pipeline") {
        let embedder = DeferredStubEmbedder()
        let mia = UUID()
        // Fact text echoes the prompt instruction.
        let leakedText = "List one entry per fact the character DID or LEARNED"
        let suggestion = LedgerSuggestion(
            characterId: mia,
            fact: KnownFact(fact: leakedText, certainty: .asserted),
            evidenceQuote: ""
        )
        var result: LedgerFilterPipelineResult?
        LedgerFilterPipeline.apply(
            embedder: embedder,
            suggestions: [suggestion],
            existingFactsByCharacter: [:],
            sceneSentences: []
        ) { result = $0 }

        let texts = embedder.stored!.texts
        let vSame: [Float] = [1.0, 0.0]
        var vectors: [[Float]] = []
        for t in texts {
            if t == leakedText || t == LedgerExtraction.extractionPromptInstruction {
                vectors.append(vSame)
            } else {
                vectors.append([0.0, 1.0])
            }
        }
        embedder.flush(.success(vectors))
        try expectEqual(result?.suggestions.count, 0)
        try expectEqual(result?.dedupDropped, 0)
        try expectEqual(result?.evidenceDropped, 0)
        try expectEqual(result?.leakageDropped, 1)
    }

    s.test("happy path: nothing matches → all suggestions pass through") {
        let embedder = DeferredStubEmbedder()
        let mia = UUID()
        let s1 = LedgerSuggestion(
            characterId: mia,
            fact: KnownFact(fact: "Mia drank wine", certainty: .asserted),
            evidenceQuote: "Mia drank her wine"
        )
        let s2 = LedgerSuggestion(
            characterId: mia,
            fact: KnownFact(fact: "Mia opened the door", certainty: .asserted),
            evidenceQuote: "Mia opened the door"
        )
        var result: LedgerFilterPipelineResult?
        LedgerFilterPipeline.apply(
            embedder: embedder,
            suggestions: [s1, s2],
            existingFactsByCharacter: [:],
            sceneSentences: ["Mia drank wine in the kitchen", "Mia opened the door for Anders"]
        ) { result = $0 }

        let texts = embedder.stored!.texts
        // Hand-construct vectors so each fact matches its own scene
        // sentence but neither matches the other, and neither matches
        // the prompt.
        let vWine: [Float] = [1.0, 0.0]
        let vDoor: [Float] = [0.0, 1.0]
        let vPrompt: [Float] = [0.7071, -0.7071]   // orthogonal to vWine + vDoor cos = 0.7071 / -0.7071, both below 0.85 threshold
        var vectors: [[Float]] = []
        for t in texts {
            switch t {
            case "Mia drank wine", "Mia drank her wine", "Mia drank wine in the kitchen":
                vectors.append(vWine)
            case "Mia opened the door", "Mia opened the door for Anders":
                vectors.append(vDoor)
            case LedgerExtraction.extractionPromptInstruction:
                vectors.append(vPrompt)
            default:
                vectors.append([0.0, 0.0])
            }
        }
        embedder.flush(.success(vectors))
        try expectEqual(result?.suggestions.count, 2)
        try expectEqual(result?.dedupDropped, 0)
        try expectEqual(result?.evidenceDropped, 0)
        try expectEqual(result?.leakageDropped, 0)
    }

    return s
}

// MARK: - Deferred-stub embedder

/// Per `feedback_tdd_async_callbacks`: async-callback APIs must be
/// stubbed with deferred completions, never synchronous ones, so any
/// lifetime / [weak self] race in the system-under-test surfaces in
/// tests rather than only in production.
final class DeferredStubEmbedder: KoboldEmbedding {
    var stored: (texts: [String], completion: (Result<[[Float]], Error>) -> Void)?

    func embed(texts: [String], completion: @escaping (Result<[[Float]], Error>) -> Void) {
        stored = (texts, completion)
    }

    func flush(_ result: Result<[[Float]], Error>) {
        guard let s = stored else { return }
        stored = nil
        s.completion(result)
    }
}

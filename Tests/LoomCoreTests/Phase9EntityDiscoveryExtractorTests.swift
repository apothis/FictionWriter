import Foundation
@testable import LoomCore

/// Phase 9 entity-discovery — `OllamaEntityDiscoveryExtractor`:
/// async wrapper around Stages A2 + B + C + D + post-Stage-D dedup.
/// Mirrors `OllamaLedgerExtractor`'s shape — `OllamaCallProvider`
/// injection so tests pin orchestration behaviour without HTTP.
///
/// Tests use deferred stubs (per feedback_tdd_async_callbacks memory)
/// — never call completion synchronously inside the stub, defer to
/// a manual run-queue and flush at the end of each test.
func phase9EntityDiscoveryExtractorTests() -> TestSuite {
    let s = TestSuite("Phase9EntityDiscoveryExtractor")

    /// Stub that queues completions; tests call `flush()` to fire
    /// each pending call in order. Captures the prompt + schema so
    /// orchestration order can be asserted.
    final class StubProvider: OllamaCallProvider {
        struct Call {
            let prompt: String
            let options: OllamaChatOptions
            let completion: (Result<String, OllamaError>) -> Void
        }
        var queued: [Call] = []
        var cannedResponses: [Result<String, OllamaError>] = []
        var optionsLog: [OllamaChatOptions] = []

        func call(
            prompt: String,
            schema: [String: Any],
            options: OllamaChatOptions,
            completion: @escaping (Result<String, OllamaError>) -> Void
        ) {
            optionsLog.append(options)
            queued.append(Call(prompt: prompt, options: options, completion: completion))
        }

        func flushNext() {
            guard !queued.isEmpty, !cannedResponses.isEmpty else { return }
            let call = queued.removeFirst()
            let resp = cannedResponses.removeFirst()
            call.completion(resp)
        }
        func flushAll() {
            while !queued.isEmpty && !cannedResponses.isEmpty {
                flushNext()
            }
        }
    }

    func a2Response(_ candidates: [(String, String, String)]) -> String {
        // Build a clean JSON array of A2 candidates from a list of
        // (surface, kind, first_seen_quote) tuples.
        let items = candidates.map { c in
            "{\"surface\":\"\(c.0)\",\"kind\":\"\(c.1)\",\"first_seen_quote\":\"\(c.2)\"}"
        }.joined(separator: ",")
        return "[\(items)]"
    }

    func dResponse(kind: String, canonical: String, aliases: [String] = [], oneLine: String = "x", evidence: String = "x") -> String {
        let aliasesJSON = "[" + aliases.map { "\"\($0)\"" }.joined(separator: ",") + "]"
        return "{\"kind\":\"\(kind)\",\"canonical_name\":\"\(canonical)\",\"aliases\":\(aliasesJSON),\"one_line\":\"\(oneLine)\",\"evidence_quote\":\"\(evidence)\"}"
    }

    let sceneId = UUID()

    s.test("happy path: Stage A2 emits 1 candidate, Stage D normalises, ProposedEntity built") {
        let stub = StubProvider()
        let extractor = OllamaEntityDiscoveryExtractor(provider: stub)

        var captured: Result<[EntityDiscovery.ProposedEntity], Error>?
        extractor.extract(
            scenePose: "Anders arrived.",
            sceneId: sceneId,
            knownEntityNames: [],
            existingEntities: [],
            embedder: nil
        ) { result in captured = result }

        // First call is Stage A2 — feed back one candidate.
        stub.cannedResponses.append(.success(a2Response([("Anders", "character", "Anders arrived.")])))
        stub.flushNext()
        // Second call is Stage D for Anders — feed back the
        // normalised tuple.
        stub.cannedResponses.append(.success(dResponse(kind: "character", canonical: "Anders")))
        stub.flushNext()

        let result = try expectNotNil(captured)
        if case .success(let proposals) = result {
            try expectEqual(proposals.count, 1)
            try expectEqual(proposals[0].canonicalName, "Anders")
            try expectEqual(proposals[0].kind, .character)
            try expectEqual(proposals[0].sourceSceneId, sceneId)
        } else {
            throw TestFailure(message: "expected success, got \(result)", file: #file, line: #line)
        }
    }

    s.test("known-entity filter drops known surface before Stage D fires") {
        let stub = StubProvider()
        let extractor = OllamaEntityDiscoveryExtractor(provider: stub)

        var captured: Result<[EntityDiscovery.ProposedEntity], Error>?
        extractor.extract(
            scenePose: "Mia and Anders.",
            sceneId: sceneId,
            knownEntityNames: ["Mia"],
            existingEntities: [],
            embedder: nil
        ) { result in captured = result }

        // Stage A2 returns Mia + Anders. Mia gets filtered.
        stub.cannedResponses.append(.success(a2Response([
            ("Mia", "character", "Mia."),
            ("Anders", "character", "Anders."),
        ])))
        stub.flushNext()
        // Only one Stage D call (for Anders).
        try expectEqual(stub.queued.count, 1)
        stub.cannedResponses.append(.success(dResponse(kind: "character", canonical: "Anders")))
        stub.flushNext()

        let result = try expectNotNil(captured)
        if case .success(let proposals) = result {
            try expectEqual(proposals.count, 1)
            try expectEqual(proposals[0].canonicalName, "Anders")
        } else {
            throw TestFailure(message: "expected success", file: #file, line: #line)
        }
    }

    s.test("promotion gate drops definite-NP candidates before Stage D fires") {
        let stub = StubProvider()
        let extractor = OllamaEntityDiscoveryExtractor(provider: stub)

        var captured: Result<[EntityDiscovery.ProposedEntity], Error>?
        extractor.extract(
            scenePose: "The man and Anders.",
            sceneId: sceneId,
            knownEntityNames: [],
            existingEntities: [],
            embedder: nil
        ) { result in captured = result }

        stub.cannedResponses.append(.success(a2Response([
            ("the man", "character", "the man."),
            ("Anders", "character", "Anders."),
        ])))
        stub.flushNext()
        // Only Anders survives the gate → 1 Stage D call.
        try expectEqual(stub.queued.count, 1)
        stub.cannedResponses.append(.success(dResponse(kind: "character", canonical: "Anders")))
        stub.flushNext()

        let result = try expectNotNil(captured)
        if case .success(let proposals) = result {
            try expectEqual(proposals.count, 1)
        } else {
            throw TestFailure(message: "expected success", file: #file, line: #line)
        }
    }

    s.test("place-recurrence filter drops single-mention non-The places") {
        let stub = StubProvider()
        let extractor = OllamaEntityDiscoveryExtractor(provider: stub)

        var captured: Result<[EntityDiscovery.ProposedEntity], Error>?
        // Brussels appears once — should be dropped.
        extractor.extract(
            scenePose: "Penelope was in Brussels.",
            sceneId: sceneId,
            knownEntityNames: [],
            existingEntities: [],
            embedder: nil
        ) { result in captured = result }

        stub.cannedResponses.append(.success(a2Response([
            ("Brussels", "place", "in Brussels."),
            ("Penelope", "character", "Penelope was."),
        ])))
        stub.flushNext()
        // Only Penelope survives → 1 Stage D.
        try expectEqual(stub.queued.count, 1)
        stub.cannedResponses.append(.success(dResponse(kind: "character", canonical: "Penelope")))
        stub.flushNext()

        let result = try expectNotNil(captured)
        if case .success(let proposals) = result {
            try expectEqual(proposals.count, 1)
            try expectEqual(proposals[0].canonicalName, "Penelope")
        } else {
            throw TestFailure(message: "expected success", file: #file, line: #line)
        }
    }

    s.test("post-Stage-D dedup collapses identical canonical names") {
        let stub = StubProvider()
        let extractor = OllamaEntityDiscoveryExtractor(provider: stub)

        var captured: Result<[EntityDiscovery.ProposedEntity], Error>?
        extractor.extract(
            scenePose: "Marius Thorn arrived. Dr Thorn looked tired.",
            sceneId: sceneId,
            knownEntityNames: [],
            existingEntities: [],
            embedder: nil
        ) { result in captured = result }

        // A2 returns two candidates that are actually the same
        // person. Both pass the gate (proper nouns).
        stub.cannedResponses.append(.success(a2Response([
            ("Marius Thorn", "character", "Marius Thorn arrived."),
            ("Dr Thorn", "character", "Dr Thorn looked tired."),
        ])))
        stub.flushNext()
        // Two Stage D calls — both normalise to "Marius Thorn".
        stub.cannedResponses.append(.success(dResponse(kind: "character", canonical: "Marius Thorn", aliases: ["Thorn"])))
        stub.cannedResponses.append(.success(dResponse(kind: "character", canonical: "Marius Thorn", aliases: ["Dr Thorn"])))
        stub.flushAll()

        let result = try expectNotNil(captured)
        if case .success(let proposals) = result {
            // Post-Stage-D dedup merges them into one.
            try expectEqual(proposals.count, 1)
            try expectEqual(proposals[0].canonicalName, "Marius Thorn")
        } else {
            throw TestFailure(message: "expected success", file: #file, line: #line)
        }
    }

    s.test("Stage A2 retries on noJSONArrayFound and recovers if second attempt succeeds") {
        // Mirrors the OllamaBeatExtractor fix (commit 6b6e714) —
        // gemma4_2b's Pass-A on NSFW prose shows ~30% transient
        // JSON-parse failures (preamble noise eating the open
        // bracket). One retry recovers most of those without
        // costing the user a recall miss.
        let stub = StubProvider()
        let extractor = OllamaEntityDiscoveryExtractor(provider: stub)

        var captured: Result<[EntityDiscovery.ProposedEntity], Error>?
        extractor.extract(
            scenePose: "Anders arrived.",
            sceneId: sceneId,
            knownEntityNames: [],
            existingEntities: [],
            embedder: nil
        ) { result in captured = result }

        // First attempt: preamble eats the open bracket.
        stub.cannedResponses.append(.success("Sure, here you go: malformed without an open bracket"))
        stub.flushNext()
        // Retry fires automatically; provide a clean response.
        stub.cannedResponses.append(.success(a2Response([("Anders", "character", "Anders arrived.")])))
        stub.flushNext()
        // Then Stage D for the recovered candidate.
        stub.cannedResponses.append(.success(dResponse(kind: "character", canonical: "Anders")))
        stub.flushNext()

        let result = try expectNotNil(captured)
        if case .success(let proposals) = result {
            try expectEqual(proposals.count, 1)
            try expectEqual(proposals[0].canonicalName, "Anders")
        } else {
            throw TestFailure(message: "expected success after Stage A2 retry, got \(result)", file: #file, line: #line)
        }
    }

    s.test("Stage A2 retries when output is non-empty but yields zero candidates") {
        // No-format mode (2026-05-16): gemma4_2b occasionally
        // degenerates — emits an open bracket + a partial object,
        // hits the token cap, leaving 0 recoverable candidates. That
        // is distinct from a genuine null-discovery (a bare "[]");
        // re-roll rather than silently report nothing.
        let stub = StubProvider()
        let extractor = OllamaEntityDiscoveryExtractor(provider: stub)

        var captured: Result<[EntityDiscovery.ProposedEntity], Error>?
        extractor.extract(
            scenePose: "Anders arrived.",
            sceneId: sceneId,
            knownEntityNames: [],
            existingEntities: [],
            embedder: nil
        ) { result in captured = result }

        // First attempt: opening bracket + half an object, nothing
        // recoverable — but it is NOT a clean empty array.
        stub.cannedResponses.append(.success("[{\"surface\": \"And"))
        stub.flushNext()
        // Retry fires automatically; clean response this time.
        stub.cannedResponses.append(.success(a2Response([("Anders", "character", "Anders arrived.")])))
        stub.flushNext()
        stub.cannedResponses.append(.success(dResponse(kind: "character", canonical: "Anders")))
        stub.flushNext()

        let result = try expectNotNil(captured)
        if case .success(let proposals) = result {
            try expectEqual(proposals.count, 1)
            try expectEqual(proposals[0].canonicalName, "Anders")
        } else {
            throw TestFailure(message: "expected success after degenerate-empty retry, got \(result)", file: #file, line: #line)
        }
    }

    s.test("Stage A2 surfaces parse failure after retry exhausts (both attempts malformed)") {
        let stub = StubProvider()
        let extractor = OllamaEntityDiscoveryExtractor(provider: stub)

        var captured: Result<[EntityDiscovery.ProposedEntity], Error>?
        extractor.extract(
            scenePose: "...",
            sceneId: sceneId,
            knownEntityNames: [],
            existingEntities: [],
            embedder: nil
        ) { result in captured = result }

        stub.cannedResponses.append(.success("not json"))
        stub.cannedResponses.append(.success("still not json"))
        stub.flushAll()

        let result = try expectNotNil(captured)
        if case .failure = result {
            // ok
        } else {
            throw TestFailure(message: "expected failure after retry exhausts", file: #file, line: #line)
        }
    }

    s.test("Stage A2 transport error → completion fires with error") {
        let stub = StubProvider()
        let extractor = OllamaEntityDiscoveryExtractor(provider: stub)

        var captured: Result<[EntityDiscovery.ProposedEntity], Error>?
        extractor.extract(
            scenePose: "...",
            sceneId: sceneId,
            knownEntityNames: [],
            existingEntities: [],
            embedder: nil
        ) { result in captured = result }

        stub.cannedResponses.append(.failure(OllamaError.unexpectedShape))
        stub.flushNext()

        let result = try expectNotNil(captured)
        if case .failure = result {
            // ok
        } else {
            throw TestFailure(message: "expected failure", file: #file, line: #line)
        }
    }

    s.test("zero A2 candidates → empty success (genuine null-discovery)") {
        let stub = StubProvider()
        let extractor = OllamaEntityDiscoveryExtractor(provider: stub)

        var captured: Result<[EntityDiscovery.ProposedEntity], Error>?
        extractor.extract(
            scenePose: "Nothing new.",
            sceneId: sceneId,
            knownEntityNames: [],
            existingEntities: [],
            embedder: nil
        ) { result in captured = result }

        stub.cannedResponses.append(.success("[]"))
        stub.flushNext()
        // No Stage D calls fire.
        try expectEqual(stub.queued.count, 0)

        let result = try expectNotNil(captured)
        if case .success(let proposals) = result {
            try expectEqual(proposals.count, 0)
        } else {
            throw TestFailure(message: "expected success", file: #file, line: #line)
        }
    }

    s.test("individual Stage D failure does not poison the whole batch") {
        let stub = StubProvider()
        let extractor = OllamaEntityDiscoveryExtractor(provider: stub)

        var captured: Result<[EntityDiscovery.ProposedEntity], Error>?
        extractor.extract(
            scenePose: "A and B.",
            sceneId: sceneId,
            knownEntityNames: [],
            existingEntities: [],
            embedder: nil
        ) { result in captured = result }

        stub.cannedResponses.append(.success(a2Response([
            ("Anders", "character", "A."),
            ("Brusselsboy", "character", "B."),
        ])))
        stub.flushNext()
        // First Stage D succeeds, second fails — overall result
        // still has 1 proposal.
        stub.cannedResponses.append(.success(dResponse(kind: "character", canonical: "Anders")))
        stub.cannedResponses.append(.failure(OllamaError.unexpectedShape))
        stub.flushAll()

        let result = try expectNotNil(captured)
        if case .success(let proposals) = result {
            try expectEqual(proposals.count, 1)
            try expectEqual(proposals[0].canonicalName, "Anders")
        } else {
            throw TestFailure(message: "expected success despite partial Stage D failure", file: #file, line: #line)
        }
    }

    s.test("duplicate A2 candidates collapse to one Stage D call per entity") {
        // Live-smoke: gemma4_2b emitted 30 candidates for 3 entities
        // (one per mention). Without pre-Stage-D dedup that fires 30
        // serialised normalisation calls. Feed 6 candidates spanning
        // 2 entities → exactly 2 Stage D calls.
        let stub = StubProvider()
        let extractor = OllamaEntityDiscoveryExtractor(provider: stub)

        var captured: Result<[EntityDiscovery.ProposedEntity], Error>?
        extractor.extract(
            scenePose: "Chantal and Muriel.",
            sceneId: sceneId,
            knownEntityNames: [],
            existingEntities: [],
            embedder: nil
        ) { result in captured = result }

        stub.cannedResponses.append(.success(a2Response([
            ("Chantal", "character", "q1"),
            ("Muriel", "character", "q2"),
            ("Chantal", "character", "q3"),
            ("Chantal", "character", "q4"),
            ("Muriel", "character", "q5"),
            ("Chantal", "character", "q6"),
        ])))
        stub.flushNext()
        // Only 2 Stage D calls — one per distinct surface.
        try expectEqual(stub.queued.count, 2)
        stub.cannedResponses.append(.success(dResponse(kind: "character", canonical: "Chantal")))
        stub.cannedResponses.append(.success(dResponse(kind: "character", canonical: "Muriel")))
        stub.flushAll()

        let result = try expectNotNil(captured)
        if case .success(let proposals) = result {
            try expectEqual(proposals.count, 2)
        } else {
            throw TestFailure(message: "expected success", file: #file, line: #line)
        }
    }

    s.test("Stage A2 uses num_predict 4096, Stage D 2048 (no-format headroom)") {
        // Stage A2 runs unconstrained (no `format` schema) and the
        // candidate array routinely reaches ~2000 tokens on a dense
        // scene — 4096 gives headroom so the array completes rather
        // than truncating. Stage D emits a single small object and
        // keeps the 2048 floor.
        let stub = StubProvider()
        let extractor = OllamaEntityDiscoveryExtractor(provider: stub)

        extractor.extract(
            scenePose: "Anders arrived.",
            sceneId: sceneId,
            knownEntityNames: [],
            existingEntities: [],
            embedder: nil
        ) { _ in }

        stub.cannedResponses.append(.success(a2Response([("Anders", "character", "Anders arrived.")])))
        stub.flushNext()
        stub.cannedResponses.append(.success(dResponse(kind: "character", canonical: "Anders")))
        stub.flushNext()

        // optionsLog[0] = Stage A2, optionsLog[1] = Stage D for Anders.
        try expectEqual(stub.optionsLog.count, 2)
        try expectEqual(stub.optionsLog[0].numPredict, 4096, "Stage A2 num_predict")
        try expectEqual(stub.optionsLog[1].numPredict, 2048, "Stage D num_predict")
    }

    return s
}

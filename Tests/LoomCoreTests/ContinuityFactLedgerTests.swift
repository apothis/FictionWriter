import Foundation
@testable import LoomCore

/// Continuity Audit (L10) — §25 Part B. The world-state fact ledger
/// for `knowledge_violation`. Each `FactNode` is a cluster of claims
/// that assert the same proposition; `firstAppearanceScene` answers
/// the "by what scene has this fact entered the story?" question the
/// class actually asks (§24 measured this is a state-membership
/// question, not a similarity one — which is why embedding retrieval
/// and pairwise NLI both failed on it).
///
/// This file covers the value types and the deterministic builder.
/// The same-fact judgment is abstracted behind `SameFactJudging` so
/// the build is testable with a deterministic stub (no LLM call in
/// LoomCoreTests).
func continuityFactLedgerTests() -> TestSuite {
    let s = TestSuite("ContinuityFactLedger")

    func claim(
        _ type: ContinuityAudit.ClaimType = .attribute,
        subject: String = "Mara",
        key: String = "",
        value: String,
        scene: String,
        source: ContinuityAudit.ClaimSource = .narration,
        quote: String = ""
    ) -> ContinuityAudit.Claim {
        ContinuityAudit.Claim(
            type: type, subject: subject, attributeKey: key, value: value,
            sourceSceneId: scene, source: source, evidenceQuote: quote
        )
    }

    // MARK: - FactNode + FactLedger value types

    s.test("FactNode round-trips through Codable") {
        let c = claim(value: "Mara's eyes are green", scene: "s1")
        let node = ContinuityAudit.FactNode(
            id: "node-1", representative: c,
            firstAppearanceScene: "s1", members: [c])
        let data = try JSONEncoder().encode(node)
        let decoded = try JSONDecoder().decode(ContinuityAudit.FactNode.self, from: data)
        try expectEqual(decoded, node)
    }

    s.test("FactLedger round-trips through Codable with multiple nodes") {
        let c1 = claim(value: "Mara's eyes are green", scene: "s1")
        let c2 = claim(subject: "the vault", value: "the vault is on the fourteenth floor", scene: "s2")
        let n1 = ContinuityAudit.FactNode(id: "n1", representative: c1, firstAppearanceScene: "s1", members: [c1])
        let n2 = ContinuityAudit.FactNode(id: "n2", representative: c2, firstAppearanceScene: "s2", members: [c2])
        let ledger = ContinuityAudit.FactLedger(nodes: [n1, n2])
        let data = try JSONEncoder().encode(ledger)
        let decoded = try JSONDecoder().decode(ContinuityAudit.FactLedger.self, from: data)
        try expectEqual(decoded, ledger)
    }

    s.test("FactLedger() defaults to an empty node list") {
        let ledger = ContinuityAudit.FactLedger()
        try expectEqual(ledger.nodes.count, 0)
    }

    // MARK: - Builder

    /// Deferred-stub judge — mirrors the §-Engine StubAdjProvider
    /// pattern. The builder kicks calls onto `pending`; the test
    /// drains them, each call's verdict picked by `responder`. Async
    /// lifetime / `[weak self]` bugs surface here because completion
    /// never fires synchronously inside the stub.
    final class StubJudge: SameFactJudging {
        var responder: (ContinuityAudit.Claim, ContinuityAudit.Claim)
            -> ContinuityAudit.SameFactVerdict = { _, _ in .differentFact }
        private var pending: [(ContinuityAudit.Claim, ContinuityAudit.Claim,
                               (Result<ContinuityAudit.SameFactJudgment, Error>) -> Void)] = []
        var calls: [(ContinuityAudit.Claim, ContinuityAudit.Claim)] = []
        var hasPending: Bool { !pending.isEmpty }
        func judge(
            claimA: ContinuityAudit.Claim,
            claimB: ContinuityAudit.Claim,
            completion: @escaping (Result<ContinuityAudit.SameFactJudgment, Error>) -> Void
        ) {
            calls.append((claimA, claimB))
            pending.append((claimA, claimB, completion))
        }
        func drain() {
            let p = pending; pending = []
            for (a, b, c) in p {
                let v = responder(a, b)
                c(.success(ContinuityAudit.SameFactJudgment(
                    verdict: v, confidence: 1.0, explanation: "")))
            }
        }
    }

    func drive(_ judge: StubJudge) {
        while judge.hasPending { judge.drain() }
    }

    s.test("FactLedger.build on no claims yields an empty ledger and never calls the judge") {
        let judge = StubJudge()
        var ledger: ContinuityAudit.FactLedger?
        ContinuityAudit.FactLedger.build(
            claims: [], flatSceneIds: ["s1", "s2"],
            judge: judge, shouldCompare: { _, _ in true }
        ) { ledger = $0 }
        drive(judge)
        try expectEqual(try expectNotNil(ledger).nodes.count, 0)
        try expectEqual(judge.calls.count, 0)
    }

    s.test("FactLedger.build on one claim yields one node and never calls the judge") {
        let c = claim(value: "v", scene: "s1")
        let judge = StubJudge()
        var ledger: ContinuityAudit.FactLedger?
        ContinuityAudit.FactLedger.build(
            claims: [c], flatSceneIds: ["s1", "s2"],
            judge: judge, shouldCompare: { _, _ in true }
        ) { ledger = $0 }
        drive(judge)
        let l = try expectNotNil(ledger)
        try expectEqual(l.nodes.count, 1)
        try expectEqual(l.nodes[0].representative, c)
        try expectEqual(l.nodes[0].firstAppearanceScene, "s1")
        try expectEqual(l.nodes[0].members, [c])
        try expectEqual(judge.calls.count, 0)
    }

    s.test("two claims judged different_fact yield two separate nodes in scene order") {
        let c1 = claim(value: "x", scene: "s1")
        let c2 = claim(value: "y", scene: "s2")
        let judge = StubJudge()
        judge.responder = { _, _ in .differentFact }
        var ledger: ContinuityAudit.FactLedger?
        ContinuityAudit.FactLedger.build(
            claims: [c1, c2], flatSceneIds: ["s1", "s2"],
            judge: judge, shouldCompare: { _, _ in true }
        ) { ledger = $0 }
        drive(judge)
        let l = try expectNotNil(ledger)
        try expectEqual(l.nodes.count, 2)
        try expectEqual(l.nodes[0].representative, c1)
        try expectEqual(l.nodes[1].representative, c2)
        try expectEqual(judge.calls.count, 1)
    }

    s.test("two claims judged same_fact yield one node with both as members") {
        let c1 = claim(value: "v1", scene: "s1")
        let c2 = claim(value: "v2", scene: "s2")
        let judge = StubJudge()
        judge.responder = { _, _ in .sameFact }
        var ledger: ContinuityAudit.FactLedger?
        ContinuityAudit.FactLedger.build(
            claims: [c1, c2], flatSceneIds: ["s1", "s2"],
            judge: judge, shouldCompare: { _, _ in true }
        ) { ledger = $0 }
        drive(judge)
        let l = try expectNotNil(ledger)
        try expectEqual(l.nodes.count, 1)
        try expectEqual(l.nodes[0].representative, c1)
        try expectEqual(l.nodes[0].firstAppearanceScene, "s1")
        try expectEqual(l.nodes[0].members, [c1, c2])
    }

    s.test("the builder walks claims in scene order, not input order") {
        // Inputs are in (s2, s1) order; the builder must process s1
        // first so the s1 claim is the representative of any merged
        // node and firstAppearanceScene is "s1".
        let cLate = claim(value: "v2", scene: "s2")
        let cEarly = claim(value: "v1", scene: "s1")
        let judge = StubJudge()
        judge.responder = { _, _ in .sameFact }
        var ledger: ContinuityAudit.FactLedger?
        ContinuityAudit.FactLedger.build(
            claims: [cLate, cEarly], flatSceneIds: ["s1", "s2"],
            judge: judge, shouldCompare: { _, _ in true }
        ) { ledger = $0 }
        drive(judge)
        let l = try expectNotNil(ledger)
        try expectEqual(l.nodes.count, 1)
        try expectEqual(l.nodes[0].representative, cEarly,
                        "the earliest-scene claim is the cluster representative")
        try expectEqual(l.nodes[0].firstAppearanceScene, "s1")
    }

    s.test("shouldCompare=false skips the judge — every claim becomes its own node") {
        let c1 = claim(value: "v1", scene: "s1")
        let c2 = claim(value: "v2", scene: "s2")
        let c3 = claim(value: "v3", scene: "s3")
        let judge = StubJudge()
        var ledger: ContinuityAudit.FactLedger?
        ContinuityAudit.FactLedger.build(
            claims: [c1, c2, c3], flatSceneIds: ["s1", "s2", "s3"],
            judge: judge, shouldCompare: { _, _ in false }
        ) { ledger = $0 }
        drive(judge)
        let l = try expectNotNil(ledger)
        try expectEqual(l.nodes.count, 3,
                        "claims that fail the prefilter must not be compared, so each is its own node")
        try expectEqual(judge.calls.count, 0,
                        "the judge must never be called when the prefilter rejects every candidate")
    }

    s.test("three same-fact claims fold into one node with three members") {
        let c1 = claim(value: "v1", scene: "s1")
        let c2 = claim(value: "v2", scene: "s2")
        let c3 = claim(value: "v3", scene: "s3")
        let judge = StubJudge()
        judge.responder = { _, _ in .sameFact }
        var ledger: ContinuityAudit.FactLedger?
        ContinuityAudit.FactLedger.build(
            claims: [c1, c2, c3], flatSceneIds: ["s1", "s2", "s3"],
            judge: judge, shouldCompare: { _, _ in true }
        ) { ledger = $0 }
        drive(judge)
        let l = try expectNotNil(ledger)
        try expectEqual(l.nodes.count, 1)
        try expectEqual(l.nodes[0].members.count, 3)
        try expectEqual(l.nodes[0].representative, c1)
        try expectEqual(l.nodes[0].firstAppearanceScene, "s1")
    }

    s.test("a same-fact match attaches to the first matching node; later nodes are not re-evaluated") {
        // c1 (s1) and c3 (s3) are about fact A; c2 (s2) is about
        // fact B. The walk creates a node for c1, c2 separately,
        // then attaches c3 to the c1 node. The judge should NOT be
        // asked about (c2, c3) once a same_fact match is found.
        let c1 = claim(value: "a1", scene: "s1")
        let c2 = claim(value: "b1", scene: "s2")
        let c3 = claim(value: "a2", scene: "s3")
        let judge = StubJudge()
        judge.responder = { rep, cand in
            // s1 ↔ s3 are same fact; s2 is different from everything
            (rep.value.hasPrefix("a") && cand.value.hasPrefix("a")) ? .sameFact : .differentFact
        }
        var ledger: ContinuityAudit.FactLedger?
        ContinuityAudit.FactLedger.build(
            claims: [c1, c2, c3], flatSceneIds: ["s1", "s2", "s3"],
            judge: judge, shouldCompare: { _, _ in true }
        ) { ledger = $0 }
        drive(judge)
        let l = try expectNotNil(ledger)
        try expectEqual(l.nodes.count, 2)
        try expectEqual(l.nodes[0].representative, c1)
        try expectEqual(l.nodes[0].members, [c1, c3])
        try expectEqual(l.nodes[1].representative, c2)
        try expectEqual(l.nodes[1].members, [c2])
    }

    // MARK: - SameFactLLMJudge — production wrapper around an OllamaCallProvider

    final class StubLLM: OllamaCallProvider {
        var responder: (String) -> Result<String, OllamaError> = { _ in .success("") }
        private var pending: [(String, (Result<String, OllamaError>) -> Void)] = []
        var prompts: [String] = []
        var hasPending: Bool { !pending.isEmpty }
        func call(
            prompt: String, schema: [String: Any], options: OllamaChatOptions,
            completion: @escaping (Result<String, OllamaError>) -> Void
        ) {
            prompts.append(prompt)
            pending.append((prompt, completion))
        }
        func drain() {
            let p = pending; pending = []
            for (pr, c) in p { c(responder(pr)) }
        }
    }

    let cA = claim(value: "the vault is empty", scene: "s1")
    let cB = claim(value: "the empty vault", scene: "s2")

    s.test("SameFactLLMJudge builds the same-fact prompt, parses same_fact, completes success") {
        let llm = StubLLM()
        llm.responder = { _ in
            .success(#"{"verdict":"same_fact","confidence":0.9,"explanation":"paraphrase"}"#)
        }
        let j = SameFactLLMJudge(provider: llm)
        var got: ContinuityAudit.SameFactJudgment?
        var err: Error?
        j.judge(claimA: cA, claimB: cB) { result in
            switch result {
            case .success(let v): got = v
            case .failure(let e): err = e
            }
        }
        while llm.hasPending { llm.drain() }
        try expectNil(err)
        let g = try expectNotNil(got)
        try expectEqual(g.verdict, .sameFact)
        try expectEqual(g.confidence, 0.9)
        // sanity — the prompt carried both claim values
        try expectTrue(llm.prompts.first?.contains("the vault is empty") == true)
        try expectTrue(llm.prompts.first?.contains("the empty vault") == true)
    }

    s.test("SameFactLLMJudge parses different_fact and completes success") {
        let llm = StubLLM()
        llm.responder = { _ in
            .success(#"{"verdict":"different_fact","confidence":0.4,"explanation":"unrelated"}"#)
        }
        let j = SameFactLLMJudge(provider: llm)
        var got: ContinuityAudit.SameFactJudgment?
        j.judge(claimA: cA, claimB: cB) { result in got = try? result.get() }
        while llm.hasPending { llm.drain() }
        try expectEqual(try expectNotNil(got).verdict, .differentFact)
    }

    s.test("SameFactLLMJudge maps a parse failure to .failure") {
        let llm = StubLLM()
        llm.responder = { _ in .success("not a json at all") }
        let j = SameFactLLMJudge(provider: llm)
        var got: ContinuityAudit.SameFactJudgment?
        var err: Error?
        j.judge(claimA: cA, claimB: cB) { result in
            switch result { case .success(let v): got = v; case .failure(let e): err = e }
        }
        while llm.hasPending { llm.drain() }
        try expectNil(got)
        try expectNotNil(err)
    }

    s.test("SameFactLLMJudge propagates an LLM transport failure") {
        let llm = StubLLM()
        llm.responder = { _ in .failure(.transport("boom")) }
        let j = SameFactLLMJudge(provider: llm)
        var got: ContinuityAudit.SameFactJudgment?
        var err: Error?
        j.judge(claimA: cA, claimB: cB) { result in
            switch result { case .success(let v): got = v; case .failure(let e): err = e }
        }
        while llm.hasPending { llm.drain() }
        try expectNil(got)
        try expectNotNil(err)
    }

    s.test("FactLedger.build completes on many sync prefilter-rejects without stack overflow") {
        // Regression — the crash report at 2026-05-20 12:25 (k=1 eval
        // on Goetia, lighthouse) showed `matchAgainst` recursing 399
        // frames deep on a thread-6 stack guard. With most claims
        // pre-filtering out, the synchronous recursion across ledger
        // nodes accumulated frames until the 544K thread stack
        // exhausted. The fix trampolines the sync path into a loop.
        // N=2000 — well above any realistic manuscript ledger size
        // (lighthouse averaged 107 per run in the §27 probe, large
        // novels won't exceed a few thousand). The state-machine
        // `advance()` form has bounded stack depth = 1 per
        // outstanding judge call; this test fires zero judge calls
        // and so should complete with constant stack regardless of N.
        // The original recursive form crashed at depth ~9300 here.
        let claims = (0..<2000).map { i in
            claim(value: "fact-\(i)", scene: "s1")
        }
        let judge = StubJudge()
        // Prefilter rejects every pair — forces the worst-case sync walk
        // for every new claim against every existing node.
        var ledger: ContinuityAudit.FactLedger?
        ContinuityAudit.FactLedger.build(
            claims: claims, flatSceneIds: ["s1"],
            judge: judge, shouldCompare: { _, _ in false }
        ) { ledger = $0 }
        drive(judge)
        try expectEqual(try expectNotNil(ledger).nodes.count, 2000,
                        "every prefilter-rejected claim seeds its own node")
        try expectEqual(judge.calls.count, 0,
                        "no judge call should fire — every pair is prefiltered")
    }

    s.test("claims whose scene is not in flatSceneIds are skipped") {
        let kept = claim(value: "v1", scene: "s1")
        let orphan = claim(value: "v2", scene: "scene-removed-from-manuscript")
        let judge = StubJudge()
        var ledger: ContinuityAudit.FactLedger?
        ContinuityAudit.FactLedger.build(
            claims: [kept, orphan], flatSceneIds: ["s1"],
            judge: judge, shouldCompare: { _, _ in true }
        ) { ledger = $0 }
        drive(judge)
        let l = try expectNotNil(ledger)
        try expectEqual(l.nodes.count, 1)
        try expectEqual(l.nodes[0].representative, kept)
    }

    return s
}

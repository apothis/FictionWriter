import Foundation

/// Continuity Audit (L10) — Phase B, the knowledge-state violation
/// check (pure data, deterministic).
///
/// A `knowledgeState` claim says a character references / knows
/// proposition P in scene S. It is a continuity error when P's reveal —
/// a non-knowledge claim asserting P — lands in a scene *after* S: the
/// character knew something the story had not told them yet.
///
/// The check emits *candidates*, not findings: for each knowledge claim
/// it pairs the earliest matching reveal after the reference scene and
/// hands it to the LLM adjudicator, which is the precision gate. It does
/// not try to clear a violation when an *earlier* reveal exists —
/// embedding similarity matches topic, not proposition identity, so a
/// fuzzy early match cannot be trusted to veto a real later reveal
/// (`LOOM_CONTINUITY_AUDIT.md` §23). The reveal side is type-tolerant:
/// any non-knowledge claim is a candidate reveal, since `type` is only
/// ~62% reliable and gating on `event` made most reveals invisible.
///
/// Proposition matching (does this knowledge claim refer to the same
/// fact as this reveal?) is semantic, so it is delegated to an
/// injected `similarity` closure — the engine backs it with the
/// embedding service; tests pass a synthetic one. The check itself
/// stays pure-data and TDD-tractable.
///
/// v1 treats a reveal as global (once P is revealed, anyone may know
/// it). Per-character exposure — a character learning P off-page — is
/// a documented later refinement (`LOOM_CONTINUITY_AUDIT.md` §11).
public enum ContinuityKnowledgeCheck {

    public struct Violation: Equatable {
        /// The claim where a character references the proposition.
        public let knowledgeClaim: ContinuityAudit.Claim
        /// The later claim that first reveals it.
        public let revealClaim: ContinuityAudit.Claim

        public init(knowledgeClaim: ContinuityAudit.Claim, revealClaim: ContinuityAudit.Claim) {
            self.knowledgeClaim = knowledgeClaim
            self.revealClaim = revealClaim
        }
    }

    /// Find knowledge-before-reveal violations. `similarity` returns a
    /// 0…1 score that two proposition texts describe the same fact;
    /// a reveal counts when its score meets `threshold`.
    ///
    /// The reveal side is *type-tolerant*: any claim not typed
    /// `knowledgeState` is a candidate reveal, matched by proposition
    /// similarity alone. Type classification is only ~62% reliable
    /// (`LOOM_CONTINUITY_AUDIT.md` §23), so gating reveals on
    /// `type == .event` made most reveals invisible; the adjudicator is
    /// the precision gate. The default threshold is 0.70: measured real
    /// reference→reveal cosines sit at 0.73–0.94, while unrelated junk
    /// pairs sit below 0.70 — a lower threshold floods the adjudicator
    /// with noise (§24).
    public static func violations(
        claims: [ContinuityAudit.Claim],
        sceneOrder: [String],
        similarity: (String, String) -> Double,
        threshold: Double = 0.70
    ) -> [Violation] {
        var sceneIndex: [String: Int] = [:]
        for (i, id) in sceneOrder.enumerated() { sceneIndex[id] = i }

        let knowledge = claims.filter {
            $0.type == .knowledgeState
                && sceneIndex[$0.sourceSceneId] != nil
                && !isTrivialReference($0.value)
        }
        let reveals = claims.filter {
            $0.type != .knowledgeState && sceneIndex[$0.sourceSceneId] != nil
        }

        var out: [Violation] = []
        for k in knowledge {
            let kIdx = sceneIndex[k.sourceSceneId]!
            // The earliest matching reveal *after* the reference scene.
            // A reveal before the reference is ignored, not used to clear
            // the violation: embedding similarity matches topic, not
            // proposition identity (a claim about the same entity scores
            // as high as a true reveal — §23), so a fuzzy early match
            // must never silently veto a real later reveal. Whether an
            // earlier reveal legitimises the knowledge is left to the
            // adjudicator. Ties on scene break to the strongest match.
            var best: (claim: ContinuityAudit.Claim, idx: Int, sim: Double)? = nil
            for r in reveals {
                let rIdx = sceneIndex[r.sourceSceneId]!
                guard rIdx > kIdx else { continue }
                let sim = similarity(k.value, r.value)
                guard sim >= threshold else { continue }
                if best == nil || rIdx < best!.idx
                    || (rIdx == best!.idx && sim > best!.sim) {
                    best = (r, rIdx, sim)
                }
            }
            if let b = best {
                out.append(Violation(knowledgeClaim: k, revealClaim: b.claim))
            }
        }
        return out
    }

    /// §25 Part B — find violations against a pre-built `FactLedger`.
    ///
    /// The deterministic core: for each knowledge claim at scene N,
    /// ask the same-fact judge whether any fact node's representative
    /// asserts the *same proposition*; a fact node whose
    /// `firstAppearanceScene` falls *after* N is a violation (the
    /// character knows a fact the story has not yet introduced). The
    /// LLM adjudicator can run downstream as a confirmation backstop;
    /// this function returns the candidate set.
    ///
    /// Trivial references (negations, bare topic-awareness) are
    /// dropped before the judge is consulted — same screen as the
    /// legacy `violations(claims:sceneOrder:similarity:)` form.
    ///
    /// `shouldCompare(rep, k)` is the cheap LLM-call prefilter,
    /// mirroring `FactLedger.build`. Pairs it rejects are treated as
    /// `different_fact`. Completion fires once with the full
    /// violation set; the function is fail-soft on judge errors.
    public static func violations(
        knowledgeClaims: [ContinuityAudit.Claim],
        ledger: ContinuityAudit.FactLedger,
        sceneOrder: [String],
        judge: SameFactJudging,
        shouldCompare: @escaping (ContinuityAudit.Claim, ContinuityAudit.Claim) -> Bool,
        completion: @escaping ([Violation]) -> Void
    ) {
        var sceneIndex: [String: Int] = [:]
        for (i, id) in sceneOrder.enumerated() { sceneIndex[id] = i }

        let auditable = knowledgeClaims.filter {
            $0.type == .knowledgeState
                && sceneIndex[$0.sourceSceneId] != nil
                && !isTrivialReference($0.value)
        }

        var out: [Violation] = []

        func step(_ i: Int) {
            if i >= auditable.count { completion(out); return }
            let k = auditable[i]
            let kIdx = sceneIndex[k.sourceSceneId]!
            findMatch(k, kIdx: kIdx, nodeIndex: 0) { matched in
                if let node = matched {
                    out.append(Violation(knowledgeClaim: k, revealClaim: node.representative))
                }
                step(i + 1)
            }
        }

        func findMatch(
            _ k: ContinuityAudit.Claim, kIdx: Int, nodeIndex i: Int,
            completion done: @escaping (ContinuityAudit.FactNode?) -> Void
        ) {
            if i >= ledger.nodes.count { done(nil); return }
            let node = ledger.nodes[i]
            // Only a fact whose *first appearance* is later than the
            // reference scene is a candidate violation. Earlier first
            // appearance means the fact entered the story before the
            // character referenced it — not auditable here.
            guard let nIdx = sceneIndex[node.firstAppearanceScene], nIdx > kIdx else {
                findMatch(k, kIdx: kIdx, nodeIndex: i + 1, completion: done)
                return
            }
            if !shouldCompare(node.representative, k) {
                findMatch(k, kIdx: kIdx, nodeIndex: i + 1, completion: done)
                return
            }
            judge.judge(claimA: node.representative, claimB: k) { result in
                let verdict = (try? result.get())?.verdict ?? .differentFact
                if verdict == .sameFact { done(node); return }
                findMatch(k, kIdx: kIdx, nodeIndex: i + 1, completion: done)
            }
        }

        step(0)
    }

    /// A knowledge_state claim that cannot be a knowledge-before-reveal
    /// violation and so should not become a candidate (§24):
    ///
    /// - **Negated** — "X does not know P" is the *opposite* of the
    ///   error; auditing it only produces false positives.
    /// - **Bare topic-awareness** — "X knows about <a thing>" names a
    ///   topic, not a specific fact. A real reference knows a
    ///   proposition. The tell is a verb in the clause after "about";
    ///   "knows about the lighthouse" has none, "knows about the King's
    ///   death being a poisoning" does, so the latter is kept.
    static func isTrivialReference(_ value: String) -> Bool {
        let v = value.lowercased()
        for negation in ["not know", "n't know", "no idea",
                         "never knew", "no leave to know"] {
            if v.contains(negation) { return true }
        }
        for marker in ["knows about ", "knew about ", "know about "] {
            guard let r = v.range(of: marker) else { continue }
            let rest = " " + v[r.upperBound...] + " "
            let verbSignal = [" is ", " was ", " were ", " be ", " been ",
                              " being ", " has ", " have ", " had ", " will "]
            if !verbSignal.contains(where: { rest.contains($0) }) {
                return true
            }
        }
        return false
    }
}

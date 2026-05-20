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

    /// §25 Part B (redesigned, 2026-05-20) — per-knowledge-claim
    /// cosine top-K + same-fact LLM verification.
    ///
    /// For each `knowledge_state` claim k at scene N:
    ///   1. Cosine-rank all `candidateClaims` against k using the
    ///      provided `embeddings`. Take the top-K closest.
    ///   2. Sort those K candidates by scene order.
    ///   3. Walk in scene order; ask the LLM `judge` whether each
    ///      candidate asserts the same proposition as k.
    ///   4. The first `same_fact` match's scene is the fact's first
    ///      appearance. If first_appearance > k.scene → violation.
    ///      If first_appearance ≤ k.scene → fact was already
    ///      established before the reference, no violation.
    ///      If no `same_fact` match in the top-K → no violation
    ///      flagged.
    ///
    /// Cost: O(knowledge_claims × top_K) LLM calls — independent of
    /// total candidate count. Replaces the global-FactLedger approach
    /// which was both O(N²) in non-knowledge claims AND allowed
    /// spurious clustering to silently suppress real violations
    /// (§28). The per-k lookup carries neither problem.
    ///
    /// §24's measurement makes this safe: real reference↔reveal
    /// cosines sit at 0.73–0.94 and unrelated pairs below 0.7. Top-K
    /// cosine ranking captures real reveals; the LLM same-fact judge
    /// (§27 measured 100% precision on different_fact) drops
    /// topical-but-different-proposition junk.
    ///
    /// Trivial references (negations, bare topic-awareness) are
    /// dropped before any judge call. Claims missing an embedding
    /// are silently skipped (fail-soft — a missing embed is treated
    /// as "no candidates," not as a crash).
    public static func violations(
        knowledgeClaims: [ContinuityAudit.Claim],
        candidateClaims: [ContinuityAudit.Claim],
        embeddings: [String: [Float]],
        sceneOrder: [String],
        judge: SameFactJudging,
        topK: Int = 10,
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

        // Async state machine — between LLM calls everything is
        // iteration. `kIdx` walks `auditable`; `rankedIdx` walks the
        // top-K cosine ranking of `candidateClaims` against the
        // current k. Stack depth is bounded by 1 per outstanding
        // judge call (URLSession completions fire on a fresh stack).
        var kIdx = 0
        var ranked: [ContinuityAudit.Claim] = []
        var rankedIdx = 0
        var initializedForKIdx = -1

        func advance() {
            while kIdx < auditable.count {
                let k = auditable[kIdx]
                if initializedForKIdx != kIdx {
                    // Build the top-K cosine ranking for this k.
                    guard let kEmb = embeddings[k.value] else {
                        // No embedding → skip this k entirely (cannot
                        // determine candidates without one).
                        kIdx += 1
                        continue
                    }
                    let scored = candidateClaims.compactMap { c -> (ContinuityAudit.Claim, Double)? in
                        guard sceneIndex[c.sourceSceneId] != nil else { return nil }
                        guard let cEmb = embeddings[c.value] else { return nil }
                        return (c, LedgerExtraction.cosineSimilarity(kEmb, cEmb))
                    }
                    ranked = Array(scored
                        .sorted { $0.1 > $1.1 }
                        .prefix(topK)
                        .map(\.0))
                        .sorted { lhs, rhs in
                            (sceneIndex[lhs.sourceSceneId] ?? Int.max)
                                < (sceneIndex[rhs.sourceSceneId] ?? Int.max)
                        }
                    rankedIdx = 0
                    initializedForKIdx = kIdx
                }
                while rankedIdx < ranked.count {
                    let c = ranked[rankedIdx]
                    let savedC = c
                    judge.judge(claimA: c, claimB: k) { result in
                        let verdict = (try? result.get())?.verdict ?? .differentFact
                        if verdict == .sameFact {
                            // First match wins. Scene-order walk
                            // means this is the earliest candidate
                            // that asserts the same proposition.
                            let cIdx = sceneIndex[savedC.sourceSceneId] ?? Int.max
                            let kSceneIdx = sceneIndex[k.sourceSceneId] ?? Int.max
                            if cIdx > kSceneIdx {
                                out.append(Violation(
                                    knowledgeClaim: k, revealClaim: savedC))
                            }
                            // Either way, stop this k's walk.
                            kIdx += 1
                            rankedIdx = 0
                        } else {
                            rankedIdx += 1
                        }
                        advance()
                    }
                    return
                }
                // No same-fact match in top-K for this k.
                kIdx += 1
            }
            completion(out)
        }

        advance()
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

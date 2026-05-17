import Foundation

/// Continuity Audit (L10) — Phase B, the knowledge-state violation
/// check (pure data, deterministic).
///
/// A `knowledgeState` claim says a character references / knows
/// proposition P in scene S. It is a continuity error when P's
/// **earliest reveal** — the first `event` claim asserting P — lands
/// in a scene *after* S: the character knew something the story had
/// not told them yet.
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
    public static func violations(
        claims: [ContinuityAudit.Claim],
        sceneOrder: [String],
        similarity: (String, String) -> Double,
        threshold: Double = 0.7
    ) -> [Violation] {
        var sceneIndex: [String: Int] = [:]
        for (i, id) in sceneOrder.enumerated() { sceneIndex[id] = i }

        let knowledge = claims.filter {
            $0.type == .knowledgeState && sceneIndex[$0.sourceSceneId] != nil
        }
        let reveals = claims.filter {
            $0.type == .event && sceneIndex[$0.sourceSceneId] != nil
        }

        var out: [Violation] = []
        for k in knowledge {
            let kIdx = sceneIndex[k.sourceSceneId]!
            // The earliest reveal of this proposition, if any.
            var earliest: (claim: ContinuityAudit.Claim, idx: Int)? = nil
            for r in reveals where similarity(k.value, r.value) >= threshold {
                let rIdx = sceneIndex[r.sourceSceneId]!
                if earliest == nil || rIdx < earliest!.idx {
                    earliest = (r, rIdx)
                }
            }
            if let reveal = earliest, reveal.idx > kIdx {
                out.append(Violation(knowledgeClaim: k, revealClaim: reveal.claim))
            }
        }
        return out
    }
}

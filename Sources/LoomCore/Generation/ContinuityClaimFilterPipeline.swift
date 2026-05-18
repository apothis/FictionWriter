import Foundation

/// Continuity Audit (L10) — Phase B, the claim-filter pipeline.
///
/// Async orchestrator that runs one batched embed call behind
/// `ContinuityClaimFilter`, mirroring `LedgerFilterPipeline`. The
/// batch covers every claim value, every non-empty evidence quote,
/// and every scene sentence; the result dict drives both filter
/// passes. Evidence validation is scoped **per scene** so a claim's
/// quote is checked against its own scene's sentences.
///
/// **Fail-soft:** an embed failure (or a length-mismatched response)
/// returns the claims unchanged with no drops — the audit still runs,
/// just without the dedup/evidence trim. The embeddings dict is also
/// surfaced so the caller can reuse it (the engine builds the
/// knowledge-check similarity from it).
public enum ContinuityClaimFilterPipeline {

    public struct Result {
        /// Survivors after dedup + evidence validation.
        public let claims: [ContinuityAudit.Claim]
        /// `text → vector` for every embedded text (claim values,
        /// quotes, sentences). Empty when the embed call failed.
        public let embeddings: [String: [Float]]
        public let dedupDropped: Int
        public let evidenceDropped: Int

        public init(
            claims: [ContinuityAudit.Claim],
            embeddings: [String: [Float]],
            dedupDropped: Int,
            evidenceDropped: Int
        ) {
            self.claims = claims
            self.embeddings = embeddings
            self.dedupDropped = dedupDropped
            self.evidenceDropped = evidenceDropped
        }
    }

    public static func apply(
        embedder: KoboldEmbedding,
        claims: [ContinuityAudit.Claim],
        sceneProseByScene: [String: String],
        completion: @escaping (Result) -> Void
    ) {
        guard !claims.isEmpty else {
            completion(Result(claims: [], embeddings: [:], dedupDropped: 0, evidenceDropped: 0))
            return
        }

        let sceneSentencesByScene = sceneProseByScene.mapValues { SentenceSplitter.split($0) }
        var texts: Set<String> = []
        for claim in claims {
            texts.insert(claim.value)
            if !claim.evidenceQuote.isEmpty { texts.insert(claim.evidenceQuote) }
        }
        for (_, sentences) in sceneSentencesByScene {
            for sentence in sentences where !sentence.isEmpty { texts.insert(sentence) }
        }
        let textArray = Array(texts)

        embedder.embed(texts: textArray) { embedResult in
            // Fail-soft: any embed problem → input claims, no drops.
            let passthrough = Result(
                claims: claims, embeddings: [:], dedupDropped: 0, evidenceDropped: 0)
            guard case .success(let vectors) = embedResult,
                  vectors.count == textArray.count else {
                DebugLog.shared.write("[continuity-audit] claim-filter embed failed — fail-soft passthrough")
                completion(passthrough)
                return
            }
            let embeddings = Dictionary(uniqueKeysWithValues: zip(textArray, vectors))

            let postDedup = ContinuityClaimFilter.deduplicate(
                claims: claims, embeddings: embeddings)

            // Evidence validation, scoped per scene.
            var postEvidence: [ContinuityAudit.Claim] = []
            for (sceneId, group) in Dictionary(grouping: postDedup, by: { $0.sourceSceneId }) {
                postEvidence += ContinuityClaimFilter.validateEvidence(
                    claims: group,
                    sceneProse: sceneProseByScene[sceneId] ?? "",
                    sceneSentences: sceneSentencesByScene[sceneId] ?? [],
                    embeddings: embeddings)
            }

            completion(Result(
                claims: postEvidence,
                embeddings: embeddings,
                dedupDropped: claims.count - postDedup.count,
                evidenceDropped: postDedup.count - postEvidence.count))
        }
    }
}

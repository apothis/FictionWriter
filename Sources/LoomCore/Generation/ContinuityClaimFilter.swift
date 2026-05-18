import Foundation

/// Continuity Audit (L10) — Phase B, the claim-filter pass (pure data).
///
/// Raw extraction is noisy — the spike saw 11–24 claims/scene, many
/// redundant. This pass mirrors [`LedgerFilters`](LedgerFilters.swift),
/// the proven knowledge-ledger filter, over `ContinuityAudit.Claim`:
///
/// - **deduplicate** — collapse cosine-paraphrase clusters *within one
///   scene and one dimension* (subject + type + attribute key). Two
///   scenes restating the same fact are kept — they are separate
///   observations the audit needs.
/// - **validateEvidence** — drop a claim whose `evidenceQuote` matches
///   no scene sentence (a hallucinated / editorialised quote). This is
///   §4 defense #4 — evidence-grounding — applied at the claim level.
///
/// Both run over pre-computed embeddings and are **fail-open**: a
/// missing vector keeps the claim. The async embed orchestration is an
/// engine-level concern, the same split as `LedgerFilterPipeline`.
public enum ContinuityClaimFilter {

    /// Cosine at/above which two claim values are the same proposition.
    public static let defaultDedupThreshold: Double = 0.85
    /// Cosine at/above which an evidence quote matches a scene sentence.
    public static let defaultEvidenceThreshold: Double = 0.65

    /// Collapse paraphrase clusters. Scoped to one scene and one
    /// dimension — `(sourceSceneId, subject, type, attributeKey)` — so
    /// a restated fact in a *different* scene survives. Order-preserving,
    /// first occurrence wins. Fail-open on a missing value embedding.
    public static func deduplicate(
        claims: [ContinuityAudit.Claim],
        embeddings: [String: [Float]],
        threshold: Double = defaultDedupThreshold
    ) -> [ContinuityAudit.Claim] {
        var keptValuesByGroup: [String: [String]] = [:]
        var out: [ContinuityAudit.Claim] = []

        for claim in claims {
            let group = dedupGroupKey(claim)
            let value = claim.value
            guard let vector = embeddings[value] else {
                out.append(claim)
                keptValuesByGroup[group, default: []].append(value)
                continue
            }
            let kept = keptValuesByGroup[group] ?? []
            let isDupe = kept.contains { other in
                guard let otherVector = embeddings[other] else { return false }
                return LedgerExtraction.cosineSimilarity(vector, otherVector) >= threshold
            }
            if isDupe { continue }
            out.append(claim)
            keptValuesByGroup[group, default: []].append(value)
        }
        return out
    }

    /// Drop claims whose `evidenceQuote` is not grounded in the scene.
    ///
    /// A quote that appears **verbatim** in the scene prose is grounded —
    /// kept directly, no embedding needed. This is the common case: the
    /// extractor is asked for a verbatim span. Only a quote that is *not*
    /// a literal substring (a model paraphrase, or a hallucination) falls
    /// through to the embedding-cosine fallback against the scene's
    /// sentences. The verbatim check is load-bearing: short verbatim
    /// fragments embed far from the long sentences that contain them, so
    /// a cosine-only test silently drops correct claims.
    ///
    /// Fail-open: an empty quote, or a non-verbatim quote with no
    /// embedding, keeps the claim.
    public static func validateEvidence(
        claims: [ContinuityAudit.Claim],
        sceneProse: String,
        sceneSentences: [String],
        embeddings: [String: [Float]],
        threshold: Double = defaultEvidenceThreshold
    ) -> [ContinuityAudit.Claim] {
        let normalizedProse = normalizedSpan(sceneProse)
        var out: [ContinuityAudit.Claim] = []
        for claim in claims {
            let quote = claim.evidenceQuote
            if quote.isEmpty {
                out.append(claim)
                continue
            }
            if normalizedProse.contains(normalizedSpan(quote)) {
                out.append(claim)
                continue
            }
            guard let quoteVector = embeddings[quote] else {
                out.append(claim)
                continue
            }
            let matches = sceneSentences.contains { sentence in
                guard let sentenceVector = embeddings[sentence] else { return false }
                return LedgerExtraction.cosineSimilarity(quoteVector, sentenceVector) >= threshold
            }
            if matches { out.append(claim) }
        }
        return out
    }

    /// Lowercase, normalise quote glyphs, collapse whitespace — so a
    /// verbatim-span check tolerates curly-vs-straight quotes and
    /// whitespace differences without matching across paraphrase.
    private static func normalizedSpan(_ s: String) -> String {
        let lowered = s.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
        return lowered.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func dedupGroupKey(_ c: ContinuityAudit.Claim) -> String {
        let subject = ContinuityConflictRetrieval.normalize(c.subject)
        let key = ContinuityConflictRetrieval.normalize(c.attributeKey)
        return "\(c.sourceSceneId)|\(c.type.rawValue)|\(subject)|\(key)"
    }
}

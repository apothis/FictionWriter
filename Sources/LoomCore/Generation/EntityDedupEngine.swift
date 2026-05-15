import Foundation

/// Phase 9 entity-discovery — Stage C dedup engine.
///
/// LOOM_ENTITY_DISCOVERY_SPIKE §3.1 Stage C / §4.4: embed
/// `(candidate name + evidence quote)`, nearest-neighbour against
/// each existing bible entry embedded as `name (aka aliases…)`,
/// threshold-band verdict. Embedder injected per `EmbeddingClient`
/// — production wires the existing `CoreMLEmbeddingClient` (CoreML
/// Wegmann at native runtime).
///
/// Thresholds: ≥ merge (default 0.85) auto-merge, mid-band routes
/// to LLM-judge, < ambiguous (default 0.65) propose-as-new. Values
/// are spike defaults — the live eval sweeps the band against the
/// dedup-component of the gold fixture.
public enum EntityDedupEngine {

    public struct ExistingEntity: Equatable {
        public let id: UUID
        public let canonicalName: String
        public let aliases: [String]

        public init(id: UUID, canonicalName: String, aliases: [String]) {
            self.id = id
            self.canonicalName = canonicalName
            self.aliases = aliases
        }
    }

    public enum Verdict: Equatable {
        case mergesWith(existingId: UUID, similarity: Float)
        case ambiguous(closestId: UUID, similarity: Float)
        case proposeAsNew(closestSimilarity: Float?)
    }

    public static func evaluate(
        candidateName: String,
        candidateEvidenceQuote: String,
        existingEntities: [ExistingEntity],
        embedder: EmbeddingClient,
        mergeThreshold: Float = 0.85,
        ambiguousThreshold: Float = 0.65
    ) -> Verdict {
        guard !existingEntities.isEmpty else {
            return .proposeAsNew(closestSimilarity: nil)
        }
        let candidateText = candidateText(name: candidateName, quote: candidateEvidenceQuote)
        guard let candidateVec = embedder.embed(candidateText) else {
            // Can't embed → can't compare → safe default is propose-
            // as-new so the user gets to judge manually.
            return .proposeAsNew(closestSimilarity: nil)
        }

        var bestId: UUID?
        var bestSim: Float = -.infinity
        for entity in existingEntities {
            let text = existingText(name: entity.canonicalName, aliases: entity.aliases)
            guard let existingVec = embedder.embed(text) else { continue }
            let sim = EmbeddingVector.cosine(candidateVec, existingVec)
            if sim > bestSim {
                bestSim = sim
                bestId = entity.id
            }
        }
        guard let id = bestId, bestSim > -.infinity else {
            // Every existing-entity embed failed — fall through.
            return .proposeAsNew(closestSimilarity: nil)
        }
        if bestSim >= mergeThreshold {
            return .mergesWith(existingId: id, similarity: bestSim)
        } else if bestSim >= ambiguousThreshold {
            return .ambiguous(closestId: id, similarity: bestSim)
        } else {
            return .proposeAsNew(closestSimilarity: bestSim)
        }
    }

    static func candidateText(name: String, quote: String) -> String {
        "\(name) — \(quote)"
    }

    static func existingText(name: String, aliases: [String]) -> String {
        if aliases.isEmpty {
            return name
        }
        return "\(name) (aka \(aliases.joined(separator: ", ")))"
    }
}

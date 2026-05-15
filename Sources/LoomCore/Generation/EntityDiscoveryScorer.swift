import Foundation

/// Phase 9 entity-discovery — precision/recall/F1 scorer.
///
/// LOOM_ENTITY_DISCOVERY_SPIKE §6.3: closes the live-eval loop.
/// Given the pipeline's proposals + the fixture's gold entities,
/// grade precision (proposals matching gold) and recall (gold
/// entities the pipeline found). Match predicate: kind agreement
/// + non-empty intersection of normalised (lowercased, trimmed)
/// surface-form sets — same person under two surface forms
/// ("Marius Thorn" vs "Dr Thorn") matches if either side's alias
/// list bridges them.
///
/// Convention follows `LedgerExtraction.ScoreReport`: denominator-
/// zero precision and recall = 1.0 (vacuously precise / recallful
/// on empty inputs).
public enum EntityDiscoveryScorer {

    public struct ProposedSurface: Equatable {
        public let canonicalName: String
        public let aliases: [String]
        public let kind: EntityDiscovery.Kind

        public init(canonicalName: String, aliases: [String], kind: EntityDiscovery.Kind) {
            self.canonicalName = canonicalName
            self.aliases = aliases
            self.kind = kind
        }
    }

    public struct GoldSurface: Equatable {
        public let canonicalName: String
        public let aliases: [String]
        public let kind: EntityDiscovery.Kind

        public init(canonicalName: String, aliases: [String], kind: EntityDiscovery.Kind) {
            self.canonicalName = canonicalName
            self.aliases = aliases
            self.kind = kind
        }
    }

    public struct ScoreInput: Equatable {
        public let sceneId: String
        public let proposed: [ProposedSurface]
        public let gold: [GoldSurface]

        public init(sceneId: String, proposed: [ProposedSurface], gold: [GoldSurface]) {
            self.sceneId = sceneId
            self.proposed = proposed
            self.gold = gold
        }
    }

    public struct SceneTally: Equatable {
        public let truePositives: Int
        public let falsePositives: Int
        public let falseNegatives: Int
    }

    public struct Report: Equatable {
        public let truePositives: Int
        public let falsePositives: Int
        public let falseNegatives: Int
        public let perScene: [String: SceneTally]

        public var precision: Double {
            let denom = truePositives + falsePositives
            return denom == 0 ? 1.0 : Double(truePositives) / Double(denom)
        }
        public var recall: Double {
            let denom = truePositives + falseNegatives
            return denom == 0 ? 1.0 : Double(truePositives) / Double(denom)
        }
        public var f1: Double {
            let p = precision, r = recall
            return (p + r) == 0 ? 0 : 2 * p * r / (p + r)
        }
    }

    public static func score(inputs: [ScoreInput]) -> Report {
        var tp = 0, fp = 0, fn = 0
        var perScene: [String: SceneTally] = [:]

        for input in inputs {
            var sceneTp = 0, sceneFp = 0
            // Each gold can match at most one proposal. Track
            // which golds have been claimed so duplicate
            // proposals matching the same gold count as FP.
            var claimedGoldIndices = Set<Int>()

            for prop in input.proposed {
                var matched = false
                for (gi, g) in input.gold.enumerated() where !claimedGoldIndices.contains(gi) {
                    if matches(prop, g) {
                        claimedGoldIndices.insert(gi)
                        matched = true
                        break
                    }
                }
                if matched { sceneTp += 1 } else { sceneFp += 1 }
            }
            let sceneFn = input.gold.count - claimedGoldIndices.count
            tp += sceneTp; fp += sceneFp; fn += sceneFn
            perScene[input.sceneId] = SceneTally(
                truePositives: sceneTp,
                falsePositives: sceneFp,
                falseNegatives: sceneFn
            )
        }
        return Report(
            truePositives: tp,
            falsePositives: fp,
            falseNegatives: fn,
            perScene: perScene
        )
    }

    /// Match iff kind agrees AND the normalised surface-form sets
    /// (canonical + aliases on both sides) intersect.
    public static func matches(_ p: ProposedSurface, _ g: GoldSurface) -> Bool {
        guard p.kind == g.kind else { return false }
        let pSet = normalisedSurfaces(canonical: p.canonicalName, aliases: p.aliases)
        let gSet = normalisedSurfaces(canonical: g.canonicalName, aliases: g.aliases)
        return !pSet.isDisjoint(with: gSet)
    }

    private static func normalisedSurfaces(canonical: String, aliases: [String]) -> Set<String> {
        var out = Set<String>()
        out.insert(canonical.lowercased().trimmingCharacters(in: .whitespaces))
        for a in aliases {
            out.insert(a.lowercased().trimmingCharacters(in: .whitespaces))
        }
        out.remove("")
        return out
    }
}

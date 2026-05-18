import Foundation

/// Continuity Audit (L10 — `LOOM_CONTINUITY_AUDIT.md` §21) — the
/// eval-harness metrics module.
///
/// Tuning the audit's extraction recall and precision needs a
/// stage-attributable, multi-run picture: a single end-to-end run is
/// stochastic and uninterpretable on its own (§19). This module is the
/// pure-data scoring core the `ContinuityAuditSpike` `eval` phase drives.
///
/// It scores three pipeline stages independently — extraction recall,
/// pairwise adjudication, end-to-end findings — so a regression localises
/// to a stage; and it aggregates across runs (mean ± CI, pass@k vs
/// pass^k, and a Chao1 capture-recapture coverage estimate).
public enum ContinuityEvalMetrics {

    // MARK: - Word-set Jaccard

    private static let stopwords: Set<String> = [
        "a", "an", "the", "is", "was", "were", "be", "of", "in", "on", "at",
        "to", "for", "and", "or", "it", "has", "have", "had", "s",
    ]

    private static func contentWords(_ s: String) -> Set<String> {
        Set(s.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !stopwords.contains($0) })
    }

    /// Content-word Jaccard overlap — the fuzzy matcher used to compare a
    /// model claim against a gold claim. Stopwords are dropped so phrasing
    /// differences ("Mara has green eyes" / "Mara's eyes are green") still
    /// score as a match.
    public static func wordJaccard(_ a: String, _ b: String) -> Double {
        let x = contentWords(a), y = contentWords(b)
        if x.isEmpty && y.isEmpty { return 1.0 }
        let union = x.union(y).count
        return union == 0 ? 0.0 : Double(x.intersection(y).count) / Double(union)
    }

    /// Default Jaccard threshold for a claim/value match — the value the
    /// Phase A spike used.
    public static let matchThreshold = 0.34

    // MARK: - Extraction recall

    /// One hand-graded gold claim — the extraction target for a scene.
    public struct GoldClaim: Equatable {
        public var scene: String
        public var type: ContinuityAudit.ClaimType
        public var subject: String
        public var value: String
        public init(scene: String, type: ContinuityAudit.ClaimType,
                    subject: String, value: String) {
            self.scene = scene
            self.type = type
            self.subject = subject
            self.value = value
        }
    }

    /// Recall of planted gold claims. `typed` requires the claim type to
    /// match too; `content` is type-agnostic — the gap between them
    /// isolates a genuine extraction miss from a type-classification
    /// disagreement.
    public struct ExtractionRecall: Equatable {
        public var goldCount: Int
        public var matchedTyped: Int
        public var matchedContent: Int
        public var recallTyped: Double
        public var recallContent: Double
    }

    public static func extractionRecall(
        gold: [GoldClaim], extracted: [ContinuityAudit.Claim],
        threshold: Double = matchThreshold
    ) -> ExtractionRecall {
        var typed = 0, content = 0
        for g in gold {
            if extracted.contains(where: {
                $0.type == g.type && wordJaccard($0.value, g.value) >= threshold
            }) { typed += 1 }
            if extracted.contains(where: {
                wordJaccard($0.value, g.value) >= threshold
            }) { content += 1 }
        }
        let n = gold.count
        return ExtractionRecall(
            goldCount: n, matchedTyped: typed, matchedContent: content,
            recallTyped: n == 0 ? 1.0 : Double(typed) / Double(n),
            recallContent: n == 0 ? 1.0 : Double(content) / Double(n))
    }

    // MARK: - Adjudication

    /// Pairwise-adjudication scoring against gold verdicts — the
    /// contradiction class is the headline (precision/recall/F1), with
    /// overall 3-way accuracy alongside. `predicted` is parallel to
    /// `gold`; a `nil` entry is a parse failure and counts as a miss.
    public struct AdjudicationScore: Equatable {
        public var total: Int
        public var correct: Int
        public var accuracy: Double
        public var contradictionTP: Int
        public var contradictionFP: Int
        public var contradictionFN: Int
        public var precision: Double
        public var recall: Double
        public var f1: Double
    }

    public static func adjudication(
        gold: [ContinuityAudit.Verdict], predicted: [ContinuityAudit.Verdict?]
    ) -> AdjudicationScore {
        var correct = 0, tp = 0, fp = 0, fn = 0
        for (g, p) in zip(gold, predicted) {
            if p == g { correct += 1 }
            let predIsContra = (p == .contradiction)
            let goldIsContra = (g == .contradiction)
            if goldIsContra && predIsContra { tp += 1 }
            if !goldIsContra && predIsContra { fp += 1 }
            if goldIsContra && !predIsContra { fn += 1 }
        }
        let total = min(gold.count, predicted.count)
        let precision = (tp + fp) == 0 ? 1.0 : Double(tp) / Double(tp + fp)
        let recall = (tp + fn) == 0 ? 1.0 : Double(tp) / Double(tp + fn)
        let f1 = (precision + recall) == 0 ? 0.0
            : 2 * precision * recall / (precision + recall)
        return AdjudicationScore(
            total: total, correct: correct,
            accuracy: total == 0 ? 1.0 : Double(correct) / Double(total),
            contradictionTP: tp, contradictionFP: fp, contradictionFN: fn,
            precision: precision, recall: recall, f1: f1)
    }

    // MARK: - End-to-end findings

    /// One hand-graded gold contradiction — what the *whole pipeline* is
    /// expected to surface as a finding. `sceneDistance` (|index gap|
    /// between the two scenes) supports stratified reporting.
    public struct GoldContradiction: Equatable {
        public var id: String
        public var kind: ContinuityFinding.Kind
        public var sceneA: String
        public var sceneB: String
        public var valueA: String
        public var valueB: String
        public var sceneDistance: Int
        public init(id: String, kind: ContinuityFinding.Kind,
                    sceneA: String, sceneB: String,
                    valueA: String, valueB: String, sceneDistance: Int) {
            self.id = id
            self.kind = kind
            self.sceneA = sceneA
            self.sceneB = sceneB
            self.valueA = valueA
            self.valueB = valueB
            self.sceneDistance = sceneDistance
        }
    }

    /// End-to-end finding scoring — produced findings matched against gold
    /// contradictions. `matchedGoldIds` records which contradictions were
    /// caught (for stratified / pass@k reporting).
    public struct FindingScore: Equatable {
        public var truePositives: Int
        public var falsePositives: Int
        public var falseNegatives: Int
        public var precision: Double
        public var recall: Double
        public var f1: Double
        public var matchedGoldIds: [String]
    }

    /// A finding matches a gold contradiction when the kind agrees and the
    /// two claim values align with the gold pair — order-insensitively,
    /// since extraction/retrieval do not preserve a canonical A/B order.
    private static func matches(
        _ finding: ContinuityFinding, _ gold: GoldContradiction,
        threshold: Double
    ) -> Bool {
        guard finding.kind == gold.kind else { return false }
        let fa = finding.claimA.value, fb = finding.claimB.value
        let forward = wordJaccard(fa, gold.valueA) >= threshold
            && wordJaccard(fb, gold.valueB) >= threshold
        let reverse = wordJaccard(fa, gold.valueB) >= threshold
            && wordJaccard(fb, gold.valueA) >= threshold
        return forward || reverse
    }

    public static func findingScore(
        gold: [GoldContradiction], findings: [ContinuityFinding],
        threshold: Double = matchThreshold
    ) -> FindingScore {
        var matchedIds: [String] = []
        for g in gold where findings.contains(where: { matches($0, g, threshold: threshold) }) {
            matchedIds.append(g.id)
        }
        let tp = matchedIds.count
        let fn = gold.count - tp
        let fp = findings.filter { f in
            !gold.contains(where: { matches(f, $0, threshold: threshold) })
        }.count
        let precision = (tp + fp) == 0 ? 1.0 : Double(tp) / Double(tp + fp)
        let recall = (tp + fn) == 0 ? 1.0 : Double(tp) / Double(tp + fn)
        let f1 = (precision + recall) == 0 ? 0.0
            : 2 * precision * recall / (precision + recall)
        return FindingScore(
            truePositives: tp, falsePositives: fp, falseNegatives: fn,
            precision: precision, recall: recall, f1: f1,
            matchedGoldIds: matchedIds)
    }

    // MARK: - Multi-run aggregation

    /// Summary of one metric across k runs — mean with a 95% confidence
    /// interval, so a stochastic pipeline reports a range, not a number.
    public struct Aggregate: Equatable {
        public var n: Int
        public var mean: Double
        public var standardDeviation: Double
        public var ci95Low: Double
        public var ci95High: Double
    }

    public static func aggregate(_ values: [Double]) -> Aggregate {
        let n = values.count
        guard n > 0 else {
            return Aggregate(n: 0, mean: 0, standardDeviation: 0,
                             ci95Low: 0, ci95High: 0)
        }
        let mean = values.reduce(0, +) / Double(n)
        guard n > 1 else {
            return Aggregate(n: 1, mean: mean, standardDeviation: 0,
                             ci95Low: mean, ci95High: mean)
        }
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
            / Double(n - 1)
        let sd = variance.squareRoot()
        let halfWidth = 1.96 * sd / Double(n).squareRoot()
        return Aggregate(n: n, mean: mean, standardDeviation: sd,
                         ci95Low: mean - halfWidth, ci95High: mean + halfWidth)
    }

    /// `pass@k` — a contradiction caught in *at least one* of k runs.
    public static func passAtK(_ detections: [Bool]) -> Bool {
        detections.contains(true)
    }

    /// `pass^k` — caught in *every* run. The gap between `passAtK` and
    /// `passHatK` is the stochasticity tax: contradictions a single audit
    /// will sometimes miss.
    public static func passHatK(_ detections: [Bool]) -> Bool {
        !detections.isEmpty && !detections.contains(false)
    }

    /// Fraction of runs that caught a contradiction.
    public static func detectionRate(_ detections: [Bool]) -> Double {
        guard !detections.isEmpty else { return 0 }
        return Double(detections.filter { $0 }.count) / Double(detections.count)
    }

    // MARK: - Chao1 coverage

    /// Capture-recapture coverage estimate (Chao1) — how complete the
    /// union of k stochastic runs is, computed from the runs alone with no
    /// ground truth. `f1`/`f2` are items seen in exactly one / exactly two
    /// runs; many singletons relative to doubletons ⇒ much still unseen.
    public struct CoverageEstimate: Equatable {
        public var observed: Int
        public var f1: Int
        public var f2: Int
        public var estimatedMissing: Double
        public var estimatedTotal: Double
        public var completeness: Double
    }

    /// `perRunItemKeys` — one array per run of canonical item keys (e.g.
    /// deduped claim keys). An item's run-count is how many runs contain
    /// it; presence within a run is set-valued (repeats in one run count
    /// once).
    public static func chao1(perRunItemKeys: [[String]]) -> CoverageEstimate {
        var runCount: [String: Int] = [:]
        for run in perRunItemKeys {
            for key in Set(run) { runCount[key, default: 0] += 1 }
        }
        let observed = runCount.count
        let f1 = runCount.values.filter { $0 == 1 }.count
        let f2 = runCount.values.filter { $0 == 2 }.count
        let missing: Double
        if f1 == 0 {
            missing = 0
        } else if f2 > 0 {
            missing = Double(f1 * f1) / Double(2 * f2)
        } else {
            missing = Double(f1 * (f1 - 1)) / 2.0
        }
        let total = Double(observed) + missing
        return CoverageEstimate(
            observed: observed, f1: f1, f2: f2,
            estimatedMissing: missing, estimatedTotal: total,
            completeness: total == 0 ? 1.0 : Double(observed) / total)
    }
}

import Foundation
@testable import LoomCore

/// Continuity Audit (L10) — the eval-harness metrics module
/// (`LOOM_CONTINUITY_AUDIT.md` §21, step 1). Pure-data: stage-conditioned
/// scoring (extraction recall → adjudication → end-to-end findings) and
/// multi-run aggregation (mean ± CI, pass@k / pass^k, Chao1 coverage).
func continuityEvalMetricsTests() -> TestSuite {
    let s = TestSuite("ContinuityEvalMetrics")

    func claim(
        _ type: ContinuityAudit.ClaimType, subject: String = "Mara",
        value: String, scene: String = "s1"
    ) -> ContinuityAudit.Claim {
        ContinuityAudit.Claim(
            type: type, subject: subject, attributeKey: "", value: value,
            sourceSceneId: scene, source: .narration, evidenceQuote: "q")
    }
    func gold(
        _ type: ContinuityAudit.ClaimType, subject: String = "Mara",
        value: String, scene: String = "s1"
    ) -> ContinuityEvalMetrics.GoldClaim {
        ContinuityEvalMetrics.GoldClaim(scene: scene, type: type, subject: subject, value: value)
    }

    // MARK: - Word Jaccard

    s.test("wordJaccard ignores stopwords and is 1 for identical strings") {
        try expectEqual(ContinuityEvalMetrics.wordJaccard("the cat sat", "the cat sat"), 1.0)
    }

    s.test("wordJaccard is 0 for fully disjoint content words") {
        try expectEqual(ContinuityEvalMetrics.wordJaccard("green eyes", "stone harbour"), 0.0)
    }

    s.test("wordJaccard scores partial overlap between 0 and 1") {
        let j = ContinuityEvalMetrics.wordJaccard("Mara has green eyes", "Mara has brown eyes")
        try expectTrue(j > 0.0 && j < 1.0)
    }

    s.test("wordJaccard treats inflected verb forms as the same word") {
        // -ed / -ing / 3rd-person -s should not break a match
        let j = ContinuityEvalMetrics.wordJaccard(
            "Lirien knows the King was poisoned",
            "Lirien know the King poisoning")
        try expectEqual(j, 1.0)
    }

    s.test("wordJaccard collapses plurals to the singular stem") {
        let j = ContinuityEvalMetrics.wordJaccard(
            "the keeper lost a brother", "the keepers lost brothers")
        try expectEqual(j, 1.0)
    }

    s.test("extractionRecall matches a gold claim despite inflectional drift") {
        let g = [gold(.knowledgeState, value: "Lirien knows the King was poisoned")]
        let e = [claim(.knowledgeState, value: "Lirien had no leave to know the King's poisoning")]
        let r = ContinuityEvalMetrics.extractionRecall(gold: g, extracted: e)
        try expectEqual(r.matchedContent, 1)
    }

    // MARK: - Extraction recall

    s.test("extractionRecall matches a gold claim by type and value overlap") {
        let g = [gold(.attribute, value: "Mara has green eyes")]
        let e = [claim(.attribute, value: "Mara's eyes are green")]
        let r = ContinuityEvalMetrics.extractionRecall(gold: g, extracted: e)
        try expectEqual(r.matchedTyped, 1)
        try expectEqual(r.matchedContent, 1)
        try expectEqual(r.recallTyped, 1.0)
    }

    s.test("extractionRecall counts a type mismatch as content-only") {
        let g = [gold(.temporal, value: "the storm happened last week")]
        let e = [claim(.event, value: "the storm happened last week")]
        let r = ContinuityEvalMetrics.extractionRecall(gold: g, extracted: e)
        try expectEqual(r.matchedTyped, 0)
        try expectEqual(r.matchedContent, 1)
    }

    s.test("extractionRecall misses a gold claim with no value overlap") {
        let g = [gold(.attribute, value: "Mara has green eyes")]
        let e = [claim(.attribute, value: "Cole keeps the lighthouse")]
        let r = ContinuityEvalMetrics.extractionRecall(gold: g, extracted: e)
        try expectEqual(r.matchedContent, 0)
        try expectEqual(r.recallContent, 0.0)
    }

    s.test("extractionRecall on empty gold is full recall") {
        let r = ContinuityEvalMetrics.extractionRecall(gold: [], extracted: [])
        try expectEqual(r.recallTyped, 1.0)
        try expectEqual(r.recallContent, 1.0)
    }

    // MARK: - Adjudication

    s.test("adjudication scores a perfect run") {
        let g: [ContinuityAudit.Verdict] = [.contradiction, .consistent, .evolution]
        let p: [ContinuityAudit.Verdict?] = [.contradiction, .consistent, .evolution]
        let a = ContinuityEvalMetrics.adjudication(gold: g, predicted: p)
        try expectEqual(a.accuracy, 1.0)
        try expectEqual(a.precision, 1.0)
        try expectEqual(a.recall, 1.0)
        try expectEqual(a.f1, 1.0)
    }

    s.test("adjudication counts a false positive against precision") {
        let g: [ContinuityAudit.Verdict] = [.contradiction, .consistent]
        let p: [ContinuityAudit.Verdict?] = [.contradiction, .contradiction]
        let a = ContinuityEvalMetrics.adjudication(gold: g, predicted: p)
        try expectEqual(a.contradictionTP, 1)
        try expectEqual(a.contradictionFP, 1)
        try expectEqual(a.precision, 0.5)
        try expectEqual(a.recall, 1.0)
    }

    s.test("adjudication counts a miss and a parse error as a false negative") {
        let g: [ContinuityAudit.Verdict] = [.contradiction, .contradiction]
        let p: [ContinuityAudit.Verdict?] = [.consistent, nil]
        let a = ContinuityEvalMetrics.adjudication(gold: g, predicted: p)
        try expectEqual(a.contradictionTP, 0)
        try expectEqual(a.contradictionFN, 2)
        try expectEqual(a.recall, 0.0)
    }

    // MARK: - End-to-end findings

    func goldContra(
        _ id: String, kind: ContinuityFinding.Kind = .attributeDrift,
        valueA: String, valueB: String, distance: Int = 2
    ) -> ContinuityEvalMetrics.GoldContradiction {
        ContinuityEvalMetrics.GoldContradiction(
            id: id, kind: kind, sceneA: "s1", sceneB: "s3",
            valueA: valueA, valueB: valueB, sceneDistance: distance)
    }
    func finding(
        _ kind: ContinuityFinding.Kind = .attributeDrift,
        valueA: String, valueB: String
    ) -> ContinuityFinding {
        ContinuityFinding(
            kind: kind, severity: .high,
            claimA: claim(.attribute, value: valueA, scene: "s1"),
            claimB: claim(.attribute, value: valueB, scene: "s3"),
            explanation: "x", confidence: 0.9)
    }

    s.test("findingScore matches a finding to its gold contradiction") {
        let g = [goldContra("c1", valueA: "Mara has green eyes", valueB: "Mara has brown eyes")]
        let f = [finding(valueA: "Mara's eyes are green", valueB: "Mara's eyes are brown")]
        let r = ContinuityEvalMetrics.findingScore(gold: g, findings: f)
        try expectEqual(r.truePositives, 1)
        try expectEqual(r.falsePositives, 0)
        try expectEqual(r.falseNegatives, 0)
        try expectEqual(r.matchedGoldIds, ["c1"])
    }

    s.test("findingScore matches regardless of claim order") {
        let g = [goldContra("c1", valueA: "Mara has green eyes", valueB: "Mara has brown eyes")]
        let f = [finding(valueA: "Mara has brown eyes", valueB: "Mara has green eyes")]
        let r = ContinuityEvalMetrics.findingScore(gold: g, findings: f)
        try expectEqual(r.truePositives, 1)
    }

    s.test("findingScore counts an unmatched finding as a false positive") {
        let g = [goldContra("c1", valueA: "Mara has green eyes", valueB: "Mara has brown eyes")]
        let f = [finding(valueA: "the lighthouse is north", valueB: "the lighthouse is south")]
        let r = ContinuityEvalMetrics.findingScore(gold: g, findings: f)
        try expectEqual(r.truePositives, 0)
        try expectEqual(r.falsePositives, 1)
        try expectEqual(r.falseNegatives, 1)
        try expectEqual(r.precision, 0.0)
        try expectEqual(r.recall, 0.0)
    }

    s.test("findingScore requires the kind to match") {
        let g = [goldContra("c1", kind: .spatialConflict,
                             valueA: "the lighthouse is north", valueB: "the lighthouse is south")]
        let f = [finding(.attributeDrift,
                         valueA: "the lighthouse is north", valueB: "the lighthouse is south")]
        let r = ContinuityEvalMetrics.findingScore(gold: g, findings: f)
        try expectEqual(r.truePositives, 0)
        try expectEqual(r.falseNegatives, 1)
    }

    // MARK: - Multi-run aggregation

    s.test("aggregate computes mean and standard deviation") {
        let a = ContinuityEvalMetrics.aggregate([0.8, 0.9, 1.0])
        try expectEqual(a.n, 3)
        try expectTrue(abs(a.mean - 0.9) < 1e-9)
        try expectTrue(abs(a.standardDeviation - 0.1) < 1e-9)
    }

    s.test("aggregate of a single value has zero spread") {
        let a = ContinuityEvalMetrics.aggregate([0.83])
        try expectEqual(a.mean, 0.83)
        try expectEqual(a.standardDeviation, 0.0)
        try expectEqual(a.ci95Low, 0.83)
        try expectEqual(a.ci95High, 0.83)
    }

    s.test("aggregate CI widens with variance") {
        let tight = ContinuityEvalMetrics.aggregate([0.9, 0.9, 0.9, 0.91, 0.89])
        let wide = ContinuityEvalMetrics.aggregate([0.5, 1.0, 0.6, 0.95, 0.7])
        try expectTrue((wide.ci95High - wide.ci95Low) > (tight.ci95High - tight.ci95Low))
    }

    s.test("passAtK is true when a contradiction is caught in any run") {
        try expectTrue(ContinuityEvalMetrics.passAtK([false, true, false]))
        try expectFalse(ContinuityEvalMetrics.passAtK([false, false, false]))
    }

    s.test("passHatK is true only when caught in every run") {
        try expectTrue(ContinuityEvalMetrics.passHatK([true, true, true]))
        try expectFalse(ContinuityEvalMetrics.passHatK([true, false, true]))
    }

    s.test("detectionRate is the fraction of runs that caught it") {
        try expectEqual(ContinuityEvalMetrics.detectionRate([true, false, true, true]), 0.75)
    }

    // MARK: - Chao1 coverage

    s.test("chao1 estimates missing items from singletons and doubletons") {
        // a, b seen in all 3 runs; c, d seen once; e, f seen twice.
        let runs = [
            ["a", "b", "c", "e"],
            ["a", "b", "e", "f"],
            ["a", "b", "d", "f"],
        ]
        let cov = ContinuityEvalMetrics.chao1(perRunItemKeys: runs)
        try expectEqual(cov.observed, 6)
        try expectEqual(cov.f1, 2)          // c, d
        try expectEqual(cov.f2, 2)          // e, f
        // estimatedMissing = f1^2 / (2*f2) = 4/4 = 1
        try expectTrue(abs(cov.estimatedMissing - 1.0) < 1e-9)
        try expectTrue(abs(cov.estimatedTotal - 7.0) < 1e-9)
        try expectTrue(cov.completeness > 0.85 && cov.completeness < 0.87)
    }

    s.test("chao1 reports full coverage when every item recurs") {
        let runs = [["a", "b"], ["a", "b"], ["a", "b"]]
        let cov = ContinuityEvalMetrics.chao1(perRunItemKeys: runs)
        try expectEqual(cov.f1, 0)
        try expectEqual(cov.estimatedMissing, 0.0)
        try expectEqual(cov.completeness, 1.0)
    }

    s.test("chao1 uses the bias-corrected form when there are no doubletons") {
        // c, d, e seen once each; no item seen exactly twice.
        let runs = [["a", "a", "c"], ["a", "a", "d"], ["a", "a", "e"]]
        let cov = ContinuityEvalMetrics.chao1(perRunItemKeys: runs)
        try expectEqual(cov.f2, 0)
        // bias-corrected: f1*(f1-1)/2 = 3*2/2 = 3
        try expectTrue(abs(cov.estimatedMissing - 3.0) < 1e-9)
    }

    return s
}

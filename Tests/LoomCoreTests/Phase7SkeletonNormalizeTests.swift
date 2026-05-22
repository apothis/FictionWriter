import Foundation
@testable import LoomCore

/// Pass-A skeleton normalization — a pure post-process applied after
/// extraction (pipeline seam + spike) to curb the two skeleton-quality
/// problems seen on monologue-heavy exemplars (2026-05-22 test5 run):
/// out-of-order beat indices and near-duplicate adjacent beats that
/// Pass-B then re-renders. `normalizeSkeleton` sorts by index, merges
/// adjacent near-identical beats, and re-indexes 0..n-1.
func phase7SkeletonNormalizeTests() -> TestSuite {
    let s = TestSuite("Phase7SkeletonNormalize")

    func beat(_ index: Int, _ summary: String, target: Int = 80) -> SceneBeat {
        SceneBeat(
            index: index, summary: summary, modality: .description,
            function: .escalation, targetWords: target,
            wordRangeStart: 0, wordRangeEnd: 0, beatTensionChange: 0
        )
    }

    s.test("sorts beats by index and re-indexes 0..n-1") {
        let skel = ExtractedSceneSkeleton(
            beats: [beat(2, "Gamma."), beat(0, "Alpha."), beat(1, "Beta.")],
            sourceCharacters: [], sourceSettingMarkers: []
        )
        let out = BeatExtraction.normalizeSkeleton(skel)
        try expectEqual(out.beats.map(\.index), [0, 1, 2])
        try expectEqual(out.beats.map(\.summary), ["Alpha.", "Beta.", "Gamma."])
    }

    s.test("merges adjacent near-identical beats and sums their targetWords") {
        // Jaccard of {the,hero,opens,door} vs {the,hero,opens,door,slowly}
        // = 4/5 = 0.8 → merge.
        let skel = ExtractedSceneSkeleton(
            beats: [
                beat(0, "The hero opens the door.", target: 60),
                beat(1, "The hero opens the door slowly.", target: 50),
                beat(2, "The villain laughs loudly.", target: 70),
            ],
            sourceCharacters: [], sourceSettingMarkers: []
        )
        let out = BeatExtraction.normalizeSkeleton(skel)
        try expectEqual(out.beats.count, 2)
        try expectEqual(out.beats.map(\.index), [0, 1])
        // First (kept) beat absorbs the duplicate's word budget.
        try expectEqual(out.beats[0].targetWords, 110)
        // The distinct third beat survives.
        try expectTrue(out.beats[1].summary.contains("villain"))
    }

    s.test("leaves wholly distinct beats untouched") {
        let skel = ExtractedSceneSkeleton(
            beats: [
                beat(0, "A storm rolls in over the harbour."),
                beat(1, "She reads the telegram twice."),
                beat(2, "The dog will not stop barking."),
            ],
            sourceCharacters: [], sourceSettingMarkers: []
        )
        let out = BeatExtraction.normalizeSkeleton(skel)
        try expectEqual(out.beats.count, 3)
    }

    s.test("clamps non-positive targetWords (GBNF can emit negatives) to a sane default") {
        // Goetia under the GBNF grammar (integer ::= "-"? [0-9]+) emits
        // negative target counts on some beats (2026-05-22 test5 run:
        // -75, -155). They disable the length cap + corrupt budgets;
        // the nested parser doesn't guard them, so normalize does.
        let skel = ExtractedSceneSkeleton(
            beats: [
                beat(0, "Alpha.", target: -75),
                beat(1, "Beta.", target: 0),
                beat(2, "Gamma.", target: 80),
            ],
            sourceCharacters: [], sourceSettingMarkers: []
        )
        let out = BeatExtraction.normalizeSkeleton(skel)
        try expectEqual(out.beats.count, 3)
        try expectTrue(out.beats[0].targetWords > 0)
        try expectTrue(out.beats[1].targetWords > 0)
        try expectEqual(out.beats[2].targetWords, 80)  // valid value untouched
    }

    s.test("preserves voice descriptor + character/setting markers") {
        let voice = VoiceDescriptor(
            sentenceCadence: .shortClipped, dialogueDensity: .balanced,
            rhetoricalFlourish: .minimal, register: "noir",
            distinctiveTechniques: ["fragments"]
        )
        let skel = ExtractedSceneSkeleton(
            beats: [beat(1, "Beta."), beat(0, "Alpha.")],
            sourceCharacters: ["Mara"], sourceSettingMarkers: ["dock"],
            voiceDescriptor: voice
        )
        let out = BeatExtraction.normalizeSkeleton(skel)
        try expectEqual(out.sourceCharacters, ["Mara"])
        try expectEqual(out.sourceSettingMarkers, ["dock"])
        try expectEqual(out.voiceDescriptor?.register, "noir")
    }

    return s
}

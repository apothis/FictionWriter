import Foundation
@testable import LoomCore

/// Planned Project mode — `OutlineSizing`: the deterministic allocator
/// that turns a length target into scene/chapter counts and an act
/// distribution. Computing this in code (not via the LLM) is what
/// eliminates scene-count drift. LOOM_PLANNED_PROJECT.md §4.
func plannedProjectOutlineSizingTests() -> TestSuite {
    let s = TestSuite("PlannedProjectOutlineSizing")

    s.test("each preset sizes to the expected scene + chapter counts") {
        let cases: [(LengthScenario, Int, Int)] = [
            (.flashFiction, 1, 0),
            (.shortStory, 3, 0),
            (.novelette, 8, 2),
            (.novella, 19, 5),
            (.novel, 53, 13),
        ]
        for (scenario, scenes, chapters) in cases {
            let sizing = OutlineSizing.plan(for: scenario)
            try expectEqual(sizing.sceneCount, scenes)
            try expectEqual(sizing.chapterCount, chapters)
        }
    }

    s.test("short formats are flat, longer formats are chaptered") {
        try expectTrue(OutlineSizing.plan(for: .flashFiction).isFlat)
        try expectTrue(OutlineSizing.plan(for: .shortStory).isFlat)
        try expectTrue(!OutlineSizing.plan(for: .novelette).isFlat)
        try expectTrue(!OutlineSizing.plan(for: .novel).isFlat)
    }

    s.test("act scene counts always sum to the total scene count") {
        for scenario in LengthScenario.allCases {
            let z = OutlineSizing.plan(for: scenario)
            try expectEqual(
                z.act1SceneCount + z.act2SceneCount + z.act3SceneCount,
                z.sceneCount
            )
        }
    }

    s.test("the middle act is the largest (25/50/25 budget)") {
        // Novel is large enough that the split is unambiguous.
        let z = OutlineSizing.plan(for: .novel)
        try expectTrue(z.act2SceneCount >= z.act1SceneCount)
        try expectTrue(z.act2SceneCount >= z.act3SceneCount)
    }

    s.test("per-scene word budget is the total divided across scenes") {
        let z = OutlineSizing.plan(for: .novelette)
        try expectEqual(z.perSceneWords, 12_000 / 8)
    }

    s.test("plan accepts an arbitrary word count") {
        let z = OutlineSizing.plan(totalWords: 15_000)
        try expectEqual(z.sceneCount, 10)  // round(15000/1500)
    }

    s.test("a zero / negative word count never produces fewer than one scene") {
        try expectEqual(OutlineSizing.plan(totalWords: 0).sceneCount, 1)
        try expectEqual(OutlineSizing.plan(totalWords: -500).sceneCount, 1)
    }

    return s
}

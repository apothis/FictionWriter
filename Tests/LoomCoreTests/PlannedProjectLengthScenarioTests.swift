import Foundation
@testable import LoomCore

/// Planned Project mode — `LengthScenario`: the format presets that
/// size a generated outline. LOOM_PLANNED_PROJECT.md §3.3 / §5.
func plannedProjectLengthScenarioTests() -> TestSuite {
    let s = TestSuite("PlannedProjectLengthScenario")

    s.test("there are five format presets") {
        try expectEqual(LengthScenario.allCases.count, 5)
    }

    s.test("target word counts increase strictly from flash fiction to novel") {
        let ordered: [LengthScenario] = [
            .flashFiction, .shortStory, .novelette, .novella, .novel,
        ]
        for (a, b) in zip(ordered, ordered.dropFirst()) {
            try expectTrue(
                a.targetWordCount < b.targetWordCount,
                "\(a) (\(a.targetWordCount)) should be < \(b) (\(b.targetWordCount))"
            )
        }
    }

    s.test("each preset's target word count lies within its display band") {
        for scenario in LengthScenario.allCases {
            try expectTrue(
                scenario.wordRange.contains(scenario.targetWordCount),
                "\(scenario) target \(scenario.targetWordCount) outside \(scenario.wordRange)"
            )
        }
    }

    s.test("every preset has a non-empty display name") {
        for scenario in LengthScenario.allCases {
            try expectTrue(!scenario.displayName.isEmpty)
        }
    }

    s.test("LengthScenario round-trips through Codable by stable raw value") {
        for scenario in LengthScenario.allCases {
            let data = try JSONEncoder().encode(scenario)
            let back = try JSONDecoder().decode(LengthScenario.self, from: data)
            try expectEqual(back, scenario)
        }
    }

    return s
}

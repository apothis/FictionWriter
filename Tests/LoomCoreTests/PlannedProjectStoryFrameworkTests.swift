import Foundation
@testable import LoomCore

/// Planned Project mode — `StoryFramework` + `SaveTheCatFramework`.
/// The beat scaffold the outline generator fills. v1 ships only Save
/// the Cat, behind a protocol + registry so further frameworks are
/// additive. LOOM_PLANNED_PROJECT.md §2, §4.
func plannedProjectStoryFrameworkTests() -> TestSuite {
    let s = TestSuite("PlannedProjectStoryFramework")

    let stc = SaveTheCatFramework()

    s.test("Save the Cat has the canonical 15 beats in order") {
        let expected = [
            "Opening Image", "Theme Stated", "Setup", "Catalyst", "Debate",
            "Break into Two", "B Story", "Fun and Games", "Midpoint",
            "Bad Guys Close In", "All Is Lost", "Dark Night of the Soul",
            "Break into Three", "Finale", "Final Image",
        ]
        try expectEqual(stc.beatSlots.map(\.name), expected)
    }

    s.test("every beat slot has a valid 0...1 position range") {
        for beat in stc.beatSlots {
            try expectTrue(beat.actFraction.lowerBound >= 0.0)
            try expectTrue(beat.actFraction.upperBound <= 1.0)
        }
    }

    s.test("beat position ranges advance through the story") {
        let upper = stc.beatSlots.map { $0.actFraction.upperBound }
        for (a, b) in zip(upper, upper.dropFirst()) {
            try expectTrue(a <= b, "beat positions must not move backwards")
        }
    }

    s.test("every beat carries non-empty guidance for the outline prompt") {
        for beat in stc.beatSlots {
            try expectTrue(!beat.guidance.isEmpty)
        }
    }

    s.test("the framework registry resolves Save the Cat by id") {
        try expectEqual(
            StoryFrameworks.framework(id: "save-the-cat")?.id, "save-the-cat"
        )
        try expectNil(StoryFrameworks.framework(id: "no-such-framework"))
    }

    s.test("the default framework is Save the Cat") {
        try expectEqual(StoryFrameworks.default.id, "save-the-cat")
    }

    return s
}

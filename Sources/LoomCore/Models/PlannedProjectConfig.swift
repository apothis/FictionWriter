import Foundation

/// Planned Project mode — the per-project guided-planning record.
///
/// Lands on `Project` as an optional field: nil ⇒ an ordinary blank
/// project; non-nil ⇒ a project created through the guided flow,
/// carrying the premise it was scaffolded from, the chosen length
/// scenario and story framework, and the styles assigned to all of
/// its generation. LOOM_PLANNED_PROJECT.md §5.
public struct PlannedProjectConfig: Codable, Equatable {
    /// The few-sentence plot premise the outline was generated from.
    public var premise: String
    /// The short character sketch; seeds a Bible character at creation.
    public var characterSketch: String
    public var lengthScenario: LengthScenario
    /// Id of the `StoryFramework` used to scaffold the outline.
    public var frameworkId: String
    /// Ids of the `Style` records (in the app style library) assigned
    /// to this project — threaded into every generation call.
    public var assignedStyleIds: [UUID]

    public init(
        premise: String = "",
        characterSketch: String = "",
        lengthScenario: LengthScenario = .shortStory,
        frameworkId: String = StoryFrameworks.default.id,
        assignedStyleIds: [UUID] = []
    ) {
        self.premise = premise
        self.characterSketch = characterSketch
        self.lengthScenario = lengthScenario
        self.frameworkId = frameworkId
        self.assignedStyleIds = assignedStyleIds
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.premise = try c.decodeIfPresent(String.self, forKey: .premise) ?? ""
        self.characterSketch = try c.decodeIfPresent(String.self, forKey: .characterSketch) ?? ""
        self.lengthScenario = try c.decodeIfPresent(LengthScenario.self, forKey: .lengthScenario) ?? .shortStory
        self.frameworkId = try c.decodeIfPresent(String.self, forKey: .frameworkId) ?? StoryFrameworks.default.id
        self.assignedStyleIds = try c.decodeIfPresent([UUID].self, forKey: .assignedStyleIds) ?? []
    }
}

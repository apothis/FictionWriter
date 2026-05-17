import Foundation

/// Planned Project mode — one slot in a story-structure scaffold.
///
/// `actFraction` is the beat's position in the story as a 0...1
/// fraction of total length (point beats use a narrow range, span
/// beats a wide one). `guidance` is the one-sentence description fed
/// to the outline generator's beat-expansion prompt.
public struct BeatSlot: Equatable {
    public let name: String
    public let actFraction: ClosedRange<Double>
    public let guidance: String

    public init(name: String, actFraction: ClosedRange<Double>, guidance: String) {
        self.name = name
        self.actFraction = actFraction
        self.guidance = guidance
    }
}

/// A story-structure framework — an ordered set of named beat slots
/// the outline generator fills from a premise. v1 ships only Save the
/// Cat; the protocol + `StoryFrameworks` registry exist so further
/// frameworks (Hero's Journey, seven-point, …) are additive.
public protocol StoryFramework {
    var id: String { get }
    var displayName: String { get }
    var beatSlots: [BeatSlot] { get }
}

/// The Save the Cat! 15-beat sheet — a fixed, named, ordered slot
/// list. Fixed slots turn open-ended ideation into a fill-in task,
/// which small models handle far more reliably (LOOM_PLANNED_PROJECT
/// §3.2). Beat positions follow the canonical Save the Cat
/// percentages; act 1 ≈ beats 1–6, act 2 ≈ 7–13, act 3 ≈ 14–15.
public struct SaveTheCatFramework: StoryFramework {
    public let id = "save-the-cat"
    public let displayName = "Save the Cat"

    public let beatSlots: [BeatSlot] = [
        BeatSlot(
            name: "Opening Image", actFraction: 0.00...0.01,
            guidance: "A snapshot of the protagonist's world and tone before the story changes them."
        ),
        BeatSlot(
            name: "Theme Stated", actFraction: 0.04...0.06,
            guidance: "Someone states, often in passing, what the story is really about — the lesson the protagonist must learn."
        ),
        BeatSlot(
            name: "Setup", actFraction: 0.00...0.10,
            guidance: "Establish the protagonist's ordinary life, what is missing from it, and the stakes."
        ),
        BeatSlot(
            name: "Catalyst", actFraction: 0.10...0.12,
            guidance: "The inciting incident: an event that disrupts the ordinary world and sets the story in motion."
        ),
        BeatSlot(
            name: "Debate", actFraction: 0.12...0.20,
            guidance: "The protagonist hesitates, weighing whether to act — the last of the old world."
        ),
        BeatSlot(
            name: "Break into Two", actFraction: 0.20...0.22,
            guidance: "The protagonist makes a choice and commits, leaving the ordinary world for the new one."
        ),
        BeatSlot(
            name: "B Story", actFraction: 0.22...0.25,
            guidance: "A secondary thread — often a relationship — that carries the story's theme."
        ),
        BeatSlot(
            name: "Fun and Games", actFraction: 0.20...0.50,
            guidance: "The promise of the premise: the protagonist explores the new world and the story delivers what it advertised."
        ),
        BeatSlot(
            name: "Midpoint", actFraction: 0.50...0.52,
            guidance: "A false victory or false defeat that raises the stakes and turns the story toward its second half."
        ),
        BeatSlot(
            name: "Bad Guys Close In", actFraction: 0.52...0.75,
            guidance: "Pressure mounts as external antagonists and internal doubts tighten around the protagonist."
        ),
        BeatSlot(
            name: "All Is Lost", actFraction: 0.75...0.77,
            guidance: "The lowest point: the protagonist's plan collapses, often with a loss that echoes death."
        ),
        BeatSlot(
            name: "Dark Night of the Soul", actFraction: 0.77...0.80,
            guidance: "The protagonist sits in defeat, processing the loss, before finding the insight to go on."
        ),
        BeatSlot(
            name: "Break into Three", actFraction: 0.80...0.82,
            guidance: "The realisation: the protagonist finds the solution by fusing the A and B stories, and acts on it."
        ),
        BeatSlot(
            name: "Finale", actFraction: 0.82...0.99,
            guidance: "The protagonist executes the new plan, confronts the antagonist, and the world is set right on new terms."
        ),
        BeatSlot(
            name: "Final Image", actFraction: 0.99...1.00,
            guidance: "A closing snapshot mirroring the opening image, showing how far the protagonist has changed."
        ),
    ]

    public init() {}
}

/// Registry of available story frameworks. Adding a framework is a
/// one-line change here — the only extensibility seam Planned Project
/// mode needs for the "more frameworks later" decision.
public enum StoryFrameworks {
    public static let all: [StoryFramework] = [SaveTheCatFramework()]

    public static let `default`: StoryFramework = SaveTheCatFramework()

    public static func framework(id: String) -> StoryFramework? {
        all.first { $0.id == id }
    }
}

import Foundation

/// Project-level narrative POV style (Novelcrafter pill-picker
/// convention, LOOM_UI_RESEARCH.md §B.2). Distinct from `Scene.pov`,
/// which references a character — POVStyle is the *grammatical*
/// posture of the narration (first / second / third-limited /
/// third-omniscient), not who the camera follows.
///
/// Per-scene Scene-level overrides land in a later phase; this is
/// the project default the prompt assembler reads when no scene-
/// level override is present.
public enum POVStyle: String, Codable, Equatable, CaseIterable {
    case firstPerson
    case secondPerson
    case thirdPersonLimited
    case thirdPersonOmniscient
}

/// Project-level narrative tense (Novelcrafter pill-picker
/// convention). Past + present cover ~99% of long-form fiction;
/// future-tense narration is rare enough to defer until requested.
public enum NarrativeTense: String, Codable, Equatable, CaseIterable {
    case past
    case present
}

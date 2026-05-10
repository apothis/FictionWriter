import Foundation

/// The Bible — the canonical reference data the prompt assembler injects
/// into context. Phase 1 surfaces only `characters`; settings, objects,
/// factions, timeline, lorebook, styleSheets land additively in Phase 2+
/// (their absence in 1.b's persisted form is the lazy-versioning posture
/// — a Phase 1 project.json doesn't need a migration when those fields
/// arrive).
public struct Bible: Codable, Equatable {
    public var characters: [Character]
    /// Phase 2 #5 — settings (places). Same shape pattern as Character;
    /// see LOOM_DATA_MODEL.md §3.2.
    public var settings: [Setting]
    /// Phase 2 #5 — objects (significant artefacts). Same shape
    /// pattern as Character; see LOOM_DATA_MODEL.md §3.3.
    public var objects: [BibleObject]

    public init(
        characters: [Character] = [],
        settings: [Setting] = [],
        objects: [BibleObject] = []
    ) {
        self.characters = characters
        self.settings = settings
        self.objects = objects
    }

    public static let empty = Bible()

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.characters = try c.decodeIfPresent([Character].self, forKey: .characters) ?? []
        self.settings = try c.decodeIfPresent([Setting].self, forKey: .settings) ?? []
        self.objects = try c.decodeIfPresent([BibleObject].self, forKey: .objects) ?? []
    }
}

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
    /// Phase 2 #8 — lorebook entries. NovelAI / KoboldAI / SillyTavern
    /// trichotomy (LOOM_DATA_MODEL.md §3.6). UI editing lands Phase 4
    /// when the Sphiratrioth active-scenario pattern becomes
    /// user-facing; schema + prompt-injection plumbing here.
    public var lorebook: [LorebookEntry]
    /// P2b — per-relationship Dynamic Sheets. Structured roles / wants
    /// / limits / safeword / arc specs fed to the writer model.
    public var dynamics: [DynamicSheet]

    public init(
        characters: [Character] = [],
        settings: [Setting] = [],
        objects: [BibleObject] = [],
        lorebook: [LorebookEntry] = [],
        dynamics: [DynamicSheet] = []
    ) {
        self.characters = characters
        self.settings = settings
        self.objects = objects
        self.lorebook = lorebook
        self.dynamics = dynamics
    }

    public static let empty = Bible()

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.characters = try c.decodeIfPresent([Character].self, forKey: .characters) ?? []
        self.settings = try c.decodeIfPresent([Setting].self, forKey: .settings) ?? []
        self.objects = try c.decodeIfPresent([BibleObject].self, forKey: .objects) ?? []
        self.lorebook = try c.decodeIfPresent([LorebookEntry].self, forKey: .lorebook) ?? []
        self.dynamics = try c.decodeIfPresent([DynamicSheet].self, forKey: .dynamics) ?? []
    }
}

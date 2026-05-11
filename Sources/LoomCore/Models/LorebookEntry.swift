import Foundation

/// Lorebook entry — NovelAI / KoboldAI / SillyTavern trichotomy
/// (LOOM_DATA_MODEL.md §3.6, LOOM_MEMORY.md §A2.4). Phase 2 ships
/// the schema + the prompt-injection plumbing (reuses BibleInjector's
/// regex-word-boundary matcher); the editing UI lands Phase 4 when
/// the Sphiratrioth active-scenario pattern becomes user-facing.
///
/// `group`, `weight`, and `sticky` are the Phase 2 #8 additions for
/// the Sphiratrioth pattern (LOOM_NSFW.md §2.5):
///   - `group`: rolls a single winner from a labelled bucket
///     ("kink_outcome") at generation time.
///   - `weight`: bias inside a group (1..100).
///   - `sticky`: persists across scene-shifts so a chosen scenario
///     remains in force across multiple generations.
public struct LorebookEntry: Codable, Equatable {
    public let id: UUID
    public var name: String
    public var content: String
    public var activationMode: LorebookActivationMode
    public var keys: [String]
    public var secondaryKeys: [String]
    public var enabled: Bool
    public var priority: Int
    public var positionMode: LorebookPositionMode
    public var depth: Int?
    public var maxRecentScenesScanned: Int
    public var group: String?
    public var weight: Int?
    public var sticky: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        content: String = "",
        activationMode: LorebookActivationMode = .keyed,
        keys: [String] = [],
        secondaryKeys: [String] = [],
        enabled: Bool = true,
        priority: Int = 0,
        positionMode: LorebookPositionMode = .top,
        depth: Int? = nil,
        maxRecentScenesScanned: Int = 3,
        group: String? = nil,
        weight: Int? = nil,
        sticky: Bool = false
    ) {
        self.id = id
        self.name = name
        self.content = content
        self.activationMode = activationMode
        self.keys = keys
        self.secondaryKeys = secondaryKeys
        self.enabled = enabled
        self.priority = priority
        self.positionMode = positionMode
        self.depth = depth
        self.maxRecentScenesScanned = maxRecentScenesScanned
        self.group = group
        self.weight = weight
        self.sticky = sticky
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        self.activationMode = try c.decodeIfPresent(LorebookActivationMode.self, forKey: .activationMode) ?? .keyed
        self.keys = try c.decodeIfPresent([String].self, forKey: .keys) ?? []
        self.secondaryKeys = try c.decodeIfPresent([String].self, forKey: .secondaryKeys) ?? []
        self.enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        self.priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 0
        self.positionMode = try c.decodeIfPresent(LorebookPositionMode.self, forKey: .positionMode) ?? .top
        self.depth = try c.decodeIfPresent(Int.self, forKey: .depth)
        self.maxRecentScenesScanned = try c.decodeIfPresent(Int.self, forKey: .maxRecentScenesScanned) ?? 3
        self.group = try c.decodeIfPresent(String.self, forKey: .group)
        self.weight = try c.decodeIfPresent(Int.self, forKey: .weight)
        self.sticky = try c.decodeIfPresent(Bool.self, forKey: .sticky) ?? false
    }
}

public enum LorebookActivationMode: String, Codable, Equatable, CaseIterable {
    case constant     // always inject
    case keyed        // matches in recent prose trigger injection
    case vectorised   // Phase 5 R&D — semantic-similarity injection
}

public enum LorebookPositionMode: String, Codable, Equatable, CaseIterable {
    case top
    case bottom
    case depthN
}

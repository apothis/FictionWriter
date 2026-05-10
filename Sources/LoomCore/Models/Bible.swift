import Foundation

/// The Bible — the canonical reference data the prompt assembler injects
/// into context. Phase 1 surfaces only `characters`; settings, objects,
/// factions, timeline, lorebook, styleSheets land additively in Phase 2+
/// (their absence in 1.b's persisted form is the lazy-versioning posture
/// — a Phase 1 project.json doesn't need a migration when those fields
/// arrive).
public struct Bible: Codable, Equatable {
    public var characters: [Character]

    public init(characters: [Character] = []) {
        self.characters = characters
    }

    public static let empty = Bible()

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.characters = try c.decodeIfPresent([Character].self, forKey: .characters) ?? []
    }
}

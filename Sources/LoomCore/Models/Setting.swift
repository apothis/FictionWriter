import Foundation

/// Bible setting (place). Schema per LOOM_DATA_MODEL.md §3.2.
/// `sensoryNotes` feeds the Phase 4 Describe generation mode —
/// smell, sound, light captured here so the prompt assembler can
/// pull it without re-extracting from the prose.
public struct Setting: Codable, Equatable {
    public let id: UUID
    public var name: String
    public var aliases: [String]
    public var description: String
    public var sensoryNotes: String
    public var significantObjectIds: [UUID]
    public var notes: String
    /// Phase 2 #7 — prompt-assembler activation mode. See
    /// `InjectionMode` docstring.
    public var injectionMode: InjectionMode

    public init(
        id: UUID = UUID(),
        name: String,
        aliases: [String] = [],
        description: String = "",
        sensoryNotes: String = "",
        significantObjectIds: [UUID] = [],
        notes: String = "",
        injectionMode: InjectionMode = .constant
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.description = description
        self.sensoryNotes = sensoryNotes
        self.significantObjectIds = significantObjectIds
        self.notes = notes
        self.injectionMode = injectionMode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
        self.description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        self.sensoryNotes = try c.decodeIfPresent(String.self, forKey: .sensoryNotes) ?? ""
        self.significantObjectIds = try c.decodeIfPresent([UUID].self, forKey: .significantObjectIds) ?? []
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        self.injectionMode = try c.decodeIfPresent(InjectionMode.self, forKey: .injectionMode) ?? .constant
    }
}

/// Bible object (significant artefact). Schema per
/// LOOM_DATA_MODEL.md §3.3. Named `BibleObject` because `Object` is
/// already taken by the language; the on-disk JSON shape uses the
/// natural field set without the prefix.
public struct BibleObject: Codable, Equatable {
    public let id: UUID
    public var name: String
    public var aliases: [String]
    public var description: String
    public var significance: String
    public var notes: String
    /// Phase 2 #7 — prompt-assembler activation mode. See
    /// `InjectionMode` docstring.
    public var injectionMode: InjectionMode

    public init(
        id: UUID = UUID(),
        name: String,
        aliases: [String] = [],
        description: String = "",
        significance: String = "",
        notes: String = "",
        injectionMode: InjectionMode = .constant
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.description = description
        self.significance = significance
        self.notes = notes
        self.injectionMode = injectionMode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
        self.description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        self.significance = try c.decodeIfPresent(String.self, forKey: .significance) ?? ""
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        self.injectionMode = try c.decodeIfPresent(InjectionMode.self, forKey: .injectionMode) ?? .constant
    }
}

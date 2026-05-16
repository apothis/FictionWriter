import Foundation

/// Bible character entry. Phase 1 surfaces only `name` + `description`
/// in the inspector (sub-step 1.g), but the full schema lands in 1.b
/// so adding fields in Phase 2+ is a UI-only change, not a migration.
///
/// `knownFactsBySceneId` is Loom's distinctive engineering — extends
/// the Re3 Edit module pattern (LOOM_RESEARCH.md §L.4) to per-scene
/// granularity. Schema present from 1.b; pipeline lands Phase 4.
public struct Character: Codable, Equatable {
    public let id: UUID
    public var name: String
    public var aliases: [String]
    public var role: CharacterRole
    public var oneLine: String
    public var description: String
    public var personality: String
    public var appearance: String
    public var voice: String
    public var goals: String
    public var relationships: [Relationship]
    public var avatarPath: String?
    public var knownFactsBySceneId: [UUID: [KnownFact]]
    /// Phase 2 #3 — fanfic canon notes (LOOM_FANFIC.md §3.2).
    /// User-pasted canon content from a fandom wiki; one of the
    /// three inputs to the Phase 5.b canon ingestion pipeline.
    /// Nil for original-fiction characters.
    public var canonBrief: String?
    /// Phase 2 #3 — fandom-specific extension slots (HP `house`,
    /// MCU `team`, etc.). HANDOFF §9.4 risk #2: minimal shape.
    public var customFields: [CharacterCustomField]
    /// Phase 2 #7 — prompt-assembler activation mode for this
    /// entity. Defaults to `.constant` (existing always-on
    /// behaviour); user opts into `.keyed` to trigger injection
    /// only when the entity name/alias appears in recent prose.
    public var injectionMode: InjectionMode

    public init(
        id: UUID = UUID(),
        name: String,
        aliases: [String] = [],
        role: CharacterRole = .supporting,
        oneLine: String = "",
        description: String = "",
        personality: String = "",
        appearance: String = "",
        voice: String = "",
        goals: String = "",
        relationships: [Relationship] = [],
        avatarPath: String? = nil,
        knownFactsBySceneId: [UUID: [KnownFact]] = [:],
        canonBrief: String? = nil,
        customFields: [CharacterCustomField] = [],
        injectionMode: InjectionMode = .constant
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.role = role
        self.oneLine = oneLine
        self.description = description
        self.personality = personality
        self.appearance = appearance
        self.voice = voice
        self.goals = goals
        self.relationships = relationships
        self.avatarPath = avatarPath
        self.knownFactsBySceneId = knownFactsBySceneId
        self.canonBrief = canonBrief
        self.customFields = customFields
        self.injectionMode = injectionMode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
        self.role = try c.decodeIfPresent(CharacterRole.self, forKey: .role) ?? .supporting
        self.oneLine = try c.decodeIfPresent(String.self, forKey: .oneLine) ?? ""
        self.description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        self.personality = try c.decodeIfPresent(String.self, forKey: .personality) ?? ""
        self.appearance = try c.decodeIfPresent(String.self, forKey: .appearance) ?? ""
        self.voice = try c.decodeIfPresent(String.self, forKey: .voice) ?? ""
        self.goals = try c.decodeIfPresent(String.self, forKey: .goals) ?? ""
        self.relationships = try c.decodeIfPresent([Relationship].self, forKey: .relationships) ?? []
        self.avatarPath = try c.decodeIfPresent(String.self, forKey: .avatarPath)
        self.knownFactsBySceneId = try c.decodeIfPresent([UUID: [KnownFact]].self, forKey: .knownFactsBySceneId) ?? [:]
        self.canonBrief = try c.decodeIfPresent(String.self, forKey: .canonBrief)
        self.customFields = try c.decodeIfPresent([CharacterCustomField].self, forKey: .customFields) ?? []
        self.injectionMode = try c.decodeIfPresent(InjectionMode.self, forKey: .injectionMode) ?? .constant
    }

    public static func empty(name: String) -> Character {
        Character(name: name)
    }
}

public enum CharacterRole: String, Codable, Equatable, CaseIterable {
    case protagonist, antagonist, supporting, minor, narrator
}

/// Phase 10 — whether a relationship is live in the story's present
/// or has been superseded. A past relationship is retained, not
/// deleted: when A's partner changes from B to C, B becomes `.past`.
public enum RelationshipStatus: String, Codable, Equatable, CaseIterable {
    case current
    case past
}

public struct Relationship: Codable, Equatable {
    public var toCharacterId: UUID
    public var kind: String
    /// Phase 10 — temporal status. Existing project files have no
    /// `status`; forward-load defaults to `.current` (an edge on
    /// disk is assumed live until prose demotes it).
    public var status: RelationshipStatus
    public var notes: String
    /// Phase 10 — scene the edge was last observed in. Lets
    /// relationship discovery dedup against prior runs and anchor
    /// status transitions to a point in the story.
    public var sourceSceneId: UUID?

    public init(
        toCharacterId: UUID,
        kind: String,
        status: RelationshipStatus = .current,
        notes: String = "",
        sourceSceneId: UUID? = nil
    ) {
        self.toCharacterId = toCharacterId
        self.kind = kind
        self.status = status
        self.notes = notes
        self.sourceSceneId = sourceSceneId
    }

    private enum CodingKeys: String, CodingKey {
        case toCharacterId, kind, status, notes, sourceSceneId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        toCharacterId = try c.decode(UUID.self, forKey: .toCharacterId)
        kind = try c.decode(String.self, forKey: .kind)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        status = try c.decodeIfPresent(RelationshipStatus.self, forKey: .status) ?? .current
        sourceSceneId = try c.decodeIfPresent(UUID.self, forKey: .sourceSceneId)
    }
}

public struct KnownFact: Codable, Equatable {
    public let id: UUID
    public var fact: String
    public var sourceSceneId: UUID?
    public var certainty: Certainty
    public var addedAt: Date

    public init(
        id: UUID = UUID(),
        fact: String,
        sourceSceneId: UUID? = nil,
        certainty: Certainty,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.fact = fact
        self.sourceSceneId = sourceSceneId
        self.certainty = certainty
        self.addedAt = addedAt
    }
}

public enum Certainty: String, Codable, Equatable, CaseIterable {
    case asserted, suspected, unknown, mistaken
}

/// Free-form extension slot on Character. Phase 5 fandom templates
/// drop into customFields (HP gets `house`/`wand`/`bloodStatus`; MCU
/// gets `team`/`affiliation`/`powers` — LOOM_FANFIC.md §3.2). The
/// shape is intentionally minimal — label + value + a tiny kind enum
/// — so we don't drift into a generic ORM.
public struct CharacterCustomField: Codable, Equatable {
    public var label: String
    public var value: String
    public var kind: CustomFieldKind

    public init(label: String, value: String = "", kind: CustomFieldKind = .text) {
        self.label = label
        self.value = value
        self.kind = kind
    }
}

public enum CustomFieldKind: String, Codable, Equatable, CaseIterable {
    case text             // single-line value
    case multilineText    // multi-paragraph value
}

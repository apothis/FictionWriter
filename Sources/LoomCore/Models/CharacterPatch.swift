import Foundation

/// Phase 4.5 Session 2 — JSON contract for JS→Swift partial updates
/// to a `Character`. Every field is `Optional`; the React side
/// sends only the fields the user changed since the last snapshot.
/// `nil` means "leave this field alone"; a present value (including
/// empty string / empty array) means "set this field exactly."
///
/// Collection semantics:
/// - `nil`: leave the array unchanged.
/// - `[]`: clear it.
/// - `[x, y]`: replace entirely.
///
/// `knownFactsBySceneId` is intentionally **not** patchable — facts
/// are managed via the suggestions queue + facts examiner flows
/// (Sessions 4 + 5). `id` is also not in the patch; the intent
/// carries it at the envelope level (`BibleWorkspaceIntent.patchCharacter`).
public struct CharacterPatch: Codable, Equatable {
    public var name: String?
    public var aliases: [String]?
    public var role: CharacterRole?
    public var oneLine: String?
    public var description: String?
    public var personality: String?
    public var appearance: String?
    public var voice: String?
    public var goals: String?
    public var relationships: [Relationship]?
    public var canonBrief: String?
    public var customFields: [CharacterCustomField]?
    public var injectionMode: InjectionMode?
    public var kinks: [CharacterKink]?
    public var intimateAnatomy: String?

    public init(
        name: String? = nil,
        aliases: [String]? = nil,
        role: CharacterRole? = nil,
        oneLine: String? = nil,
        description: String? = nil,
        personality: String? = nil,
        appearance: String? = nil,
        voice: String? = nil,
        goals: String? = nil,
        relationships: [Relationship]? = nil,
        canonBrief: String? = nil,
        customFields: [CharacterCustomField]? = nil,
        injectionMode: InjectionMode? = nil,
        kinks: [CharacterKink]? = nil,
        intimateAnatomy: String? = nil
    ) {
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
        self.canonBrief = canonBrief
        self.customFields = customFields
        self.injectionMode = injectionMode
        self.kinks = kinks
        self.intimateAnatomy = intimateAnatomy
    }

    /// Apply the patch to `character`, returning a new `Character`
    /// with the non-nil fields overwritten. Pure function — no
    /// mutation of the input.
    public func apply(to character: Character) -> Character {
        var c = character
        if let v = name { c.name = v }
        if let v = aliases { c.aliases = v }
        if let v = role { c.role = v }
        if let v = oneLine { c.oneLine = v }
        if let v = description { c.description = v }
        if let v = personality { c.personality = v }
        if let v = appearance { c.appearance = v }
        if let v = voice { c.voice = v }
        if let v = goals { c.goals = v }
        if let v = relationships { c.relationships = v }
        if let v = canonBrief { c.canonBrief = v }
        if let v = customFields { c.customFields = v }
        if let v = injectionMode { c.injectionMode = v }
        if let v = kinks { c.kinks = v }
        if let v = intimateAnatomy { c.intimateAnatomy = v }
        return c
    }
}

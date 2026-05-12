import Foundation

/// Phase 4.5 Session 3 — JSON contract for JS→Swift partial updates
/// to a `LorebookEntry`. Mirrors `CharacterPatch` semantics: every
/// field is `Optional`; the React side sends only diverging fields.
/// `nil` means "leave alone"; a present value sets exactly.
///
/// Collection semantics: `nil` → leave alone, `[]` → clear,
/// `[x, y]` → replace entirely. `id` is not patchable; the intent
/// carries it at the envelope level.
public struct LorebookEntryPatch: Codable, Equatable {
    public var name: String?
    public var content: String?
    public var activationMode: LorebookActivationMode?
    public var keys: [String]?
    public var secondaryKeys: [String]?
    public var enabled: Bool?
    public var priority: Int?
    public var positionMode: LorebookPositionMode?
    public var depth: Int?
    public var maxRecentScenesScanned: Int?
    public var group: String?
    public var weight: Int?
    public var sticky: Bool?

    public init(
        name: String? = nil,
        content: String? = nil,
        activationMode: LorebookActivationMode? = nil,
        keys: [String]? = nil,
        secondaryKeys: [String]? = nil,
        enabled: Bool? = nil,
        priority: Int? = nil,
        positionMode: LorebookPositionMode? = nil,
        depth: Int? = nil,
        maxRecentScenesScanned: Int? = nil,
        group: String? = nil,
        weight: Int? = nil,
        sticky: Bool? = nil
    ) {
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

    public func apply(to entry: LorebookEntry) -> LorebookEntry {
        var e = entry
        if let v = name { e.name = v }
        if let v = content { e.content = v }
        if let v = activationMode { e.activationMode = v }
        if let v = keys { e.keys = v }
        if let v = secondaryKeys { e.secondaryKeys = v }
        if let v = enabled { e.enabled = v }
        if let v = priority { e.priority = v }
        if let v = positionMode { e.positionMode = v }
        if let v = depth { e.depth = v }
        if let v = maxRecentScenesScanned { e.maxRecentScenesScanned = v }
        if let v = group { e.group = v }
        if let v = weight { e.weight = v }
        if let v = sticky { e.sticky = v }
        return e
    }
}

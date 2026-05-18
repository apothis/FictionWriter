import Foundation

/// JSON contract for JS→Swift partial updates to a `DynamicSheet`.
/// Mirrors `LorebookEntryPatch` semantics: every field optional, the
/// React side sends only diverging fields. `nil` → leave alone.
public struct DynamicSheetPatch: Codable, Equatable {
    public var name: String?
    public var participantIds: [UUID]?
    public var roles: String?
    public var wants: String?
    public var softLimits: String?
    public var hardLimits: String?
    public var safeword: String?
    public var arc: String?
    public var alwaysOn: Bool?
    public var enabled: Bool?

    public init(
        name: String? = nil,
        participantIds: [UUID]? = nil,
        roles: String? = nil,
        wants: String? = nil,
        softLimits: String? = nil,
        hardLimits: String? = nil,
        safeword: String? = nil,
        arc: String? = nil,
        alwaysOn: Bool? = nil,
        enabled: Bool? = nil
    ) {
        self.name = name
        self.participantIds = participantIds
        self.roles = roles
        self.wants = wants
        self.softLimits = softLimits
        self.hardLimits = hardLimits
        self.safeword = safeword
        self.arc = arc
        self.alwaysOn = alwaysOn
        self.enabled = enabled
    }

    public func apply(to sheet: DynamicSheet) -> DynamicSheet {
        var d = sheet
        if let v = name { d.name = v }
        if let v = participantIds { d.participantIds = v }
        if let v = roles { d.roles = v }
        if let v = wants { d.wants = v }
        if let v = softLimits { d.softLimits = v }
        if let v = hardLimits { d.hardLimits = v }
        if let v = safeword { d.safeword = v }
        if let v = arc { d.arc = v }
        if let v = alwaysOn { d.alwaysOn = v }
        if let v = enabled { d.enabled = v }
        return d
    }
}

import Foundation

/// P2b — a structured per-relationship spec for the writer model.
///
/// Kink-aware fiction communities negotiate scenes with a written
/// sheet — roles, wants, soft/hard limits, a safeword, the intended
/// arc. A `DynamicSheet` is that artefact as Loom data: the author's
/// planning doc *and* a generation constraint. It is fed to the model
/// as a positive/structural spec (what the dynamic is), never as a
/// prohibition list.
///
/// Lives on the `Bible` alongside the lorebook. Injected when
/// `enabled` and either `alwaysOn` or a participant character's name
/// appears in the recent prose.
public struct DynamicSheet: Codable, Equatable {
    public let id: UUID
    public var name: String
    /// Character ids in this dynamic — drives keyed activation.
    public var participantIds: [UUID]
    public var roles: String
    public var wants: String
    public var softLimits: String
    public var hardLimits: String
    public var safeword: String
    public var arc: String
    /// `true` → injected on every generation; `false` → injected only
    /// when a participant is present in the recent prose.
    public var alwaysOn: Bool
    public var enabled: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        participantIds: [UUID] = [],
        roles: String = "",
        wants: String = "",
        softLimits: String = "",
        hardLimits: String = "",
        safeword: String = "",
        arc: String = "",
        alwaysOn: Bool = false,
        enabled: Bool = true
    ) {
        self.id = id
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

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.participantIds = try c.decodeIfPresent([UUID].self, forKey: .participantIds) ?? []
        self.roles = try c.decodeIfPresent(String.self, forKey: .roles) ?? ""
        self.wants = try c.decodeIfPresent(String.self, forKey: .wants) ?? ""
        self.softLimits = try c.decodeIfPresent(String.self, forKey: .softLimits) ?? ""
        self.hardLimits = try c.decodeIfPresent(String.self, forKey: .hardLimits) ?? ""
        self.safeword = try c.decodeIfPresent(String.self, forKey: .safeword) ?? ""
        self.arc = try c.decodeIfPresent(String.self, forKey: .arc) ?? ""
        self.alwaysOn = try c.decodeIfPresent(Bool.self, forKey: .alwaysOn) ?? false
        self.enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

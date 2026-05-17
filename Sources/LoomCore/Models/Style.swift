import Foundation

/// Planned Project mode — what kind of signal a `Style` carries.
///
/// Genre and register are kept distinct because the prompt assembler
/// slots them into separate, separately-labelled sections: a vivid
/// genre exemplar must not be able to drown the register constraints
/// (LOOM_PLANNED_PROJECT.md §3.2).
public enum StyleType: String, Codable, Equatable, CaseIterable {
    case genre
    case register
}

/// A reusable, mixable style — a genre or register the writer can
/// assign to a project. Threaded into every generation call. Styles
/// live in an app-level library (built-in starters plus the writer's
/// own), so this is a persisted, forward-load-tolerant model
/// (LOOM_PLANNED_PROJECT.md §5).
public struct Style: Codable, Equatable {
    public let id: UUID
    public var name: String
    public var type: StyleType
    /// A short natural-language style descriptor (2–4 sentences).
    public var descriptor: String
    /// Explicit do/don't constraints — concrete, structural.
    public var constraints: [String]
    /// 0–3 short exemplar passages. Optional: a descriptor-only
    /// style is valid; exemplars sharpen imitation when present.
    public var exemplars: [String]
    /// True for the curated starter styles, false for writer-created
    /// ones — lets the UI mark, but never lock, the built-ins.
    public var isBuiltIn: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        type: StyleType,
        descriptor: String = "",
        constraints: [String] = [],
        exemplars: [String] = [],
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.descriptor = descriptor
        self.constraints = constraints
        self.exemplars = exemplars
        self.isBuiltIn = isBuiltIn
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.type = try c.decode(StyleType.self, forKey: .type)
        self.descriptor = try c.decodeIfPresent(String.self, forKey: .descriptor) ?? ""
        self.constraints = try c.decodeIfPresent([String].self, forKey: .constraints) ?? []
        self.exemplars = try c.decodeIfPresent([String].self, forKey: .exemplars) ?? []
        self.isBuiltIn = try c.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
    }
}

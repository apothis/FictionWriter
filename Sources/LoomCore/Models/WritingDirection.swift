import Foundation

/// Per-project writing-direction configuration.
///
/// Phase 2 #1 ships the schema; the explicit-foreground generation
/// behaviour that `kind == .porn` triggers (depth-2 Author's Note,
/// longer Continue defaults, no scene-break suggestion) lands in
/// Phase 4. The schema needs to distinguish .porn from .erotica
/// because Phase 4 reads this field; see HANDOFF.md §9.3 and
/// LOOM_NSFW.md §3.1 / §3.2 for the contract.
///
/// Defaults are HANDOFF §9.4-locked: literary / literary /
/// fadeToBlack — a brand-new project with no user intent attached
/// reads as "literary, fade-to-black" so the model doesn't pick up
/// an explicit-foreground configuration the user didn't ask for.
public struct WritingDirection: Codable, Equatable {
    public var kind: DirectionKind
    public var register: VocabularyRegister
    public var explicitnessLevel: ExplicitnessLevel
    public var themes: [Theme]
    public var pacing: PacingProfile
    public var fadeToBlackPolicy: FTBPolicy

    public init(
        kind: DirectionKind = .literary,
        register: VocabularyRegister = .literary,
        explicitnessLevel: ExplicitnessLevel = .fadeToBlack,
        themes: [Theme] = [],
        pacing: PacingProfile = .balanced,
        fadeToBlackPolicy: FTBPolicy = .modelDecides
    ) {
        self.kind = kind
        self.register = register
        self.explicitnessLevel = explicitnessLevel
        self.themes = themes
        self.pacing = pacing
        self.fadeToBlackPolicy = fadeToBlackPolicy
    }

    public static let defaults = WritingDirection()

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.kind = try c.decodeIfPresent(DirectionKind.self, forKey: .kind) ?? .literary
        self.register = try c.decodeIfPresent(VocabularyRegister.self, forKey: .register) ?? .literary
        self.explicitnessLevel = try c.decodeIfPresent(ExplicitnessLevel.self, forKey: .explicitnessLevel) ?? .fadeToBlack
        self.themes = try c.decodeIfPresent([Theme].self, forKey: .themes) ?? []
        self.pacing = try c.decodeIfPresent(PacingProfile.self, forKey: .pacing) ?? .balanced
        self.fadeToBlackPolicy = try c.decodeIfPresent(FTBPolicy.self, forKey: .fadeToBlackPolicy) ?? .modelDecides
    }
}

public enum DirectionKind: String, Codable, Equatable, CaseIterable {
    case literary        // mainstream fiction; explicit content rare or absent
    case mainstream      // commercial fiction; integrated explicit content
    case romance         // romance-genre conventions; explicit scenes integrated
    case erotica         // explicit content is co-equal with plot
    case porn            // explicit content IS the focus; plot is scaffolding
}

public enum VocabularyRegister: String, Codable, Equatable, CaseIterable {
    case clinical        // medical / anatomical / distant
    case literary        // metaphor, indirection, sensory imagery
    case earthy          // direct physical language, no slang
    case crude           // explicit slang, taboo language
    case mixed           // varies per character / per scene
}

public enum ExplicitnessLevel: String, Codable, Equatable, CaseIterable {
    case fadeToBlack
    case suggestive
    case onScreen
    case graphic
    case extreme
}

public enum PacingProfile: String, Codable, Equatable, CaseIterable {
    case fastPlot
    case balanced
    case slowExplicit
    case explicitForeground
}

public enum FTBPolicy: String, Codable, Equatable, CaseIterable {
    case never
    case userChoice
    case modelDecides
}

/// Free-form user-named theme. Phase 4 surfaces `alwaysOn: true`
/// themes as constant lorebook entries; styleExemplarRefs wires to
/// Phase 5 reference-text retrieval (LOOM_NSFW.md §3.4).
public struct Theme: Codable, Equatable {
    public let id: UUID
    public var name: String
    public var description: String
    public var alwaysOn: Bool
    public var styleExemplarRefs: [UUID]

    public init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        alwaysOn: Bool = false,
        styleExemplarRefs: [UUID] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.alwaysOn = alwaysOn
        self.styleExemplarRefs = styleExemplarRefs
    }
}

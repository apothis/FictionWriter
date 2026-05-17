import Foundation

/// Top-level project shape. On-disk representation is `project.json`
/// inside the `<title>.loom/` bundle directory; Scene prose + frontmatter
/// live alongside as `scenes/<id>.md`.
///
/// Phase 1 ships a subset of LOOM_DATA_MODEL.md §1: writingDirection
/// (Phase 2), fanficMetadata (Phase 5.c), styleSheetId (Phase 5), and
/// references (Phase 5) are intentionally absent from this struct. They
/// land additively in their phase via `decodeIfPresent`-shaped migration.
public struct Project: Codable, Equatable {
    public let id: UUID
    public var title: String
    public var author: String?
    public var createdAt: Date
    public var schemaVersion: Int
    public var kind: ProjectKind
    public var settings: ProjectSettings
    public var manuscript: Manuscript
    public var bible: Bible
    /// Free-form per-project notepad. Phase 1 ships a Notes inspector
    /// tab that reads/writes this field.
    public var notes: String
    /// Last inspector tab the user had open. Persists per-project so
    /// reopening a project restores their context. Optional because
    /// fresh projects haven't had a tab selection yet.
    public var selectedInspectorTab: InspectorTab?
    /// Phase 2 #2 — fanfic-mode metadata. Populated only when
    /// `kind == .fanfic`; nil otherwise. The UI to edit this lands
    /// Phase 5.b-c; the schema is here so the migration is one-time
    /// (HANDOFF §9.1 #2).
    public var fanficMetadata: FanficMetadata?
    /// Planned Project mode — the guided-planning record. Nil for an
    /// ordinary blank project; non-nil when the project was created
    /// through the guided outline flow (LOOM_PLANNED_PROJECT.md §5).
    public var plannedConfig: PlannedProjectConfig?

    public init(
        id: UUID = UUID(),
        title: String,
        author: String? = nil,
        createdAt: Date = Date(),
        schemaVersion: Int = 1,
        kind: ProjectKind = .originalFiction,
        settings: ProjectSettings = .defaults,
        manuscript: Manuscript = .empty,
        bible: Bible = .empty,
        notes: String = "",
        selectedInspectorTab: InspectorTab? = nil,
        fanficMetadata: FanficMetadata? = nil,
        plannedConfig: PlannedProjectConfig? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        // Round to ms so round-trip through the on-disk Date format is
        // identity (the encoder emits `.SSS`-precision strings).
        self.createdAt = LoomISO8601.roundedToMillisecond(createdAt)
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.settings = settings
        self.manuscript = manuscript
        self.bible = bible
        self.notes = notes
        self.selectedInspectorTab = selectedInspectorTab
        self.fanficMetadata = fanficMetadata
        self.plannedConfig = plannedConfig
    }

    public static func empty(title: String, author: String? = nil) -> Project {
        Project(title: title, author: author)
    }

    /// Lazy-versioning decode: any field added after schemaVersion 1 must
    /// be optional or use `decodeIfPresent` here. Keeping this explicit
    /// (instead of relying on synthesized init) so future additive fields
    /// have an obvious place to land.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.author = try c.decodeIfPresent(String.self, forKey: .author)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        self.kind = try c.decodeIfPresent(ProjectKind.self, forKey: .kind) ?? .originalFiction
        self.settings = try c.decode(ProjectSettings.self, forKey: .settings)
        self.manuscript = try c.decodeIfPresent(Manuscript.self, forKey: .manuscript) ?? .empty
        self.bible = try c.decodeIfPresent(Bible.self, forKey: .bible) ?? .empty
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        self.selectedInspectorTab = try c.decodeIfPresent(InspectorTab.self, forKey: .selectedInspectorTab)
        self.fanficMetadata = try c.decodeIfPresent(FanficMetadata.self, forKey: .fanficMetadata)
        self.plannedConfig = try c.decodeIfPresent(PlannedProjectConfig.self, forKey: .plannedConfig)
    }
}

/// Inspector tab cases. Persists on Project.selectedInspectorTab so the
/// user's last-viewed tab survives reopen.
public enum InspectorTab: String, Codable, Equatable, CaseIterable {
    case bible
    case history
    case notes
}

public enum ProjectKind: String, Codable, Equatable, CaseIterable {
    case originalFiction
    case fanfic    // Phase 5.c — see LOOM_FANFIC.md §3.1
}

public struct ProjectSettings: Codable, Equatable {
    public var serverProfileId: UUID?
    public var contextBudgetTokens: Int
    public var generationDefaults: GenerationDefaults
    public var authorsNote: String
    public var authorsNoteDepthLines: Int
    public var memory: String
    public var instructTemplate: InstructTemplate
    /// Phase 2 #1 — see WritingDirection.swift. Carries the
    /// per-project `kind` / `register` / `explicitnessLevel` /
    /// `themes` / `pacing` / `fadeToBlackPolicy` configuration.
    /// Non-optional so projects always read a sensible default;
    /// the decode path is lazy-versioned so Phase 1 bundles load
    /// cleanly with the literary defaults populated.
    public var writingDirection: WritingDirection
    /// Phase 2 #6 — project-level narrative POV style.
    /// Distinct from `Scene.pov` (which references a character).
    /// Surfaced as a pill-picker in the Settings window.
    public var pov: POVStyle
    /// Phase 2 #6 — project-level narrative tense.
    public var tense: NarrativeTense
    /// Phase 3 §F — project-level target word count. Nil = no
    /// target set. Scene + Chapter have their own
    /// `targetWordCount: Int?` already (LOOM_DATA_MODEL.md §2).
    public var targetWordCount: Int?

    public init(
        serverProfileId: UUID? = nil,
        contextBudgetTokens: Int = 8192,
        generationDefaults: GenerationDefaults = .phase1Defaults,
        authorsNote: String = "",
        authorsNoteDepthLines: Int = 4,
        memory: String = "",
        instructTemplate: InstructTemplate = .auto,
        writingDirection: WritingDirection = .defaults,
        pov: POVStyle = .thirdPersonLimited,
        tense: NarrativeTense = .past,
        targetWordCount: Int? = nil
    ) {
        self.serverProfileId = serverProfileId
        self.contextBudgetTokens = contextBudgetTokens
        self.generationDefaults = generationDefaults
        self.authorsNote = authorsNote
        self.authorsNoteDepthLines = authorsNoteDepthLines
        self.memory = memory
        self.instructTemplate = instructTemplate
        self.writingDirection = writingDirection
        self.pov = pov
        self.tense = tense
        self.targetWordCount = targetWordCount
    }

    public static let defaults = ProjectSettings()

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.serverProfileId = try c.decodeIfPresent(UUID.self, forKey: .serverProfileId)
        self.contextBudgetTokens = try c.decodeIfPresent(Int.self, forKey: .contextBudgetTokens) ?? 8192
        self.generationDefaults = try c.decodeIfPresent(GenerationDefaults.self, forKey: .generationDefaults) ?? .phase1Defaults
        self.authorsNote = try c.decodeIfPresent(String.self, forKey: .authorsNote) ?? ""
        self.authorsNoteDepthLines = try c.decodeIfPresent(Int.self, forKey: .authorsNoteDepthLines) ?? 4
        self.memory = try c.decodeIfPresent(String.self, forKey: .memory) ?? ""
        self.instructTemplate = try c.decodeIfPresent(InstructTemplate.self, forKey: .instructTemplate) ?? .auto
        self.writingDirection = try c.decodeIfPresent(WritingDirection.self, forKey: .writingDirection) ?? .defaults
        self.pov = try c.decodeIfPresent(POVStyle.self, forKey: .pov) ?? .thirdPersonLimited
        self.tense = try c.decodeIfPresent(NarrativeTense.self, forKey: .tense) ?? .past
        self.targetWordCount = try c.decodeIfPresent(Int.self, forKey: .targetWordCount)
    }
}

public enum InstructTemplate: String, Codable, Equatable, CaseIterable {
    case auto
    case chatml         // Qwen 2.5 / 3.x family + many merges
    case gemma3         // Gemma 1/2/3 family — <start_of_turn>; no native system role
    case gemma4         // Gemma 4 — <|turn>...<turn|>; native system role
    case mistralV3      // Mistral 7B / Nemo era — [INST] only, no [SYSTEM_PROMPT]
    case mistralV7      // Mistral Large / Ministral 2407+ — [SYSTEM_PROMPT] + [INST]
    case llama3
    case alpaca
    case raw
}

/// Sampler configuration. Defaults track the Phase 1 contract in
/// LOOM_DATA_MODEL.md §5 + LOOM_RESEARCH.md §I.3 (Min-P + DRY +
/// XTC at the local-model tier). All values are user-editable in
/// Settings (lands later in Phase 2+).
public struct GenerationDefaults: Codable, Equatable {
    public var continueWordTarget: Int
    public var expandWordTarget: Int
    public var temperature: Double
    public var minP: Double
    public var dryMultiplier: Double
    public var dryBase: Double
    public var dryAllowedLength: Int
    public var xtcThreshold: Double
    public var xtcProbability: Double
    public var topK: Int
    public var maxOutputTokens: Int

    public init(
        continueWordTarget: Int = 500,
        expandWordTarget: Int = 1500,
        temperature: Double = 1.0,
        minP: Double = 0.05,
        dryMultiplier: Double = 0.8,
        dryBase: Double = 1.75,
        dryAllowedLength: Int = 2,
        xtcThreshold: Double = 0.1,
        xtcProbability: Double = 0.5,
        topK: Int = 0,
        maxOutputTokens: Int = 1024
    ) {
        self.continueWordTarget = continueWordTarget
        self.expandWordTarget = expandWordTarget
        self.temperature = temperature
        self.minP = minP
        self.dryMultiplier = dryMultiplier
        self.dryBase = dryBase
        self.dryAllowedLength = dryAllowedLength
        self.xtcThreshold = xtcThreshold
        self.xtcProbability = xtcProbability
        self.topK = topK
        self.maxOutputTokens = maxOutputTokens
    }

    public static let phase1Defaults = GenerationDefaults()
}

import Foundation

/// A scene of prose. The persisted form is split: frontmatter + prose body
/// in `scenes/<id>.md`; non-frontmatter metadata (generatedSpans, snapshots,
/// notes) is reserved for later sub-steps and is not yet written to disk.
///
/// `prose` is a runtime field — its on-disk home is the .md body, not
/// project.json. Excluded from Codable so encoding a Scene for any
/// reason (debug logging, snapshots later) doesn't carry the prose
/// blob along with the metadata.
public struct Scene: Codable, Equatable {
    public let id: UUID
    public var title: String
    public var pov: UUID?
    public var location: UUID?
    public var status: SceneStatus
    public var conflict: String
    public var outcome: String
    public var summary: String
    public var summaryDirty: Bool
    public var targetWordCount: Int?
    public var contentPath: String       // `scenes/<id>.md`, derived from id
    public var notes: String              // Phase 2+ persistence
    /// Author-written scenario/framing block for this scene — the
    /// dynamic, what's at stake, the intended intensity. Unlike `notes`
    /// (private), `framing` is injected near the cursor at generation
    /// time. LOOM_NSFW per-scene framing (P2a).
    public var framing: String
    /// Per-scene explicitness override. `nil` = use the project's
    /// `WritingDirection.explicitnessLevel`. Lets a non-explicit scene
    /// in an explicit project (or vice versa) opt out/in — `.fadeToBlack`
    /// here fully suppresses the explicit-foreground posture for the
    /// scene regardless of the project's writing direction.
    public var explicitnessLevel: ExplicitnessLevel?
    /// Characters the author has explicitly marked undressed in this
    /// scene — a deterministic signal for the intimate-anatomy gate
    /// (`AnatomyGate`), used alongside the prose-keyword heuristic so
    /// a pronoun-only undressing the scan would miss can still unlock.
    public var undressedCharacterIds: [UUID]
    public var generatedSpans: [GeneratedSpan]   // Phase 1.k persistence
    public var snapshots: [Snapshot]             // Phase 2+ persistence
    public var extraFrontmatter: [String: String] // forward-compat sink

    /// Runtime-only. Excluded from Codable so the scene metadata can be
    /// serialised for debug / generation-log purposes without carrying
    /// the prose body. Source of truth for prose is `scenes/<id>.md`.
    public var prose: String

    private enum CodingKeys: String, CodingKey {
        case id, title, pov, location, status, conflict, outcome
        case summary, summaryDirty, targetWordCount, contentPath
        case notes, framing, explicitnessLevel, undressedCharacterIds
        case generatedSpans, snapshots, extraFrontmatter
        // prose intentionally excluded
    }

    public init(
        id: UUID,
        title: String,
        pov: UUID? = nil,
        location: UUID? = nil,
        status: SceneStatus = .draft,
        conflict: String = "",
        outcome: String = "",
        summary: String = "",
        summaryDirty: Bool = false,
        targetWordCount: Int? = nil,
        contentPath: String? = nil,
        notes: String = "",
        framing: String = "",
        explicitnessLevel: ExplicitnessLevel? = nil,
        undressedCharacterIds: [UUID] = [],
        generatedSpans: [GeneratedSpan] = [],
        snapshots: [Snapshot] = [],
        extraFrontmatter: [String: String] = [:],
        prose: String = ""
    ) {
        self.id = id
        self.title = title
        self.pov = pov
        self.location = location
        self.status = status
        self.conflict = conflict
        self.outcome = outcome
        self.summary = summary
        self.summaryDirty = summaryDirty
        self.targetWordCount = targetWordCount
        self.contentPath = contentPath ?? "scenes/\(id.uuidString).md"
        self.notes = notes
        self.framing = framing
        self.explicitnessLevel = explicitnessLevel
        self.undressedCharacterIds = undressedCharacterIds
        self.generatedSpans = generatedSpans
        self.snapshots = snapshots
        self.extraFrontmatter = extraFrontmatter
        self.prose = prose
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.pov = try c.decodeIfPresent(UUID.self, forKey: .pov)
        self.location = try c.decodeIfPresent(UUID.self, forKey: .location)
        self.status = try c.decodeIfPresent(SceneStatus.self, forKey: .status) ?? .draft
        self.conflict = try c.decodeIfPresent(String.self, forKey: .conflict) ?? ""
        self.outcome = try c.decodeIfPresent(String.self, forKey: .outcome) ?? ""
        self.summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        self.summaryDirty = try c.decodeIfPresent(Bool.self, forKey: .summaryDirty) ?? false
        self.targetWordCount = try c.decodeIfPresent(Int.self, forKey: .targetWordCount)
        self.contentPath = try c.decodeIfPresent(String.self, forKey: .contentPath)
            ?? "scenes/\(self.id.uuidString).md"
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        self.framing = try c.decodeIfPresent(String.self, forKey: .framing) ?? ""
        self.explicitnessLevel = try c.decodeIfPresent(ExplicitnessLevel.self, forKey: .explicitnessLevel)
        self.undressedCharacterIds = try c.decodeIfPresent([UUID].self, forKey: .undressedCharacterIds) ?? []
        self.generatedSpans = try c.decodeIfPresent([GeneratedSpan].self, forKey: .generatedSpans) ?? []
        self.snapshots = try c.decodeIfPresent([Snapshot].self, forKey: .snapshots) ?? []
        self.extraFrontmatter = try c.decodeIfPresent([String: String].self, forKey: .extraFrontmatter) ?? [:]
        self.prose = ""
    }

    public static func empty(id: UUID = UUID(), title: String) -> Scene {
        Scene(id: id, title: title)
    }
}

public enum SceneStatus: String, Codable, Equatable, CaseIterable {
    case todo, draft, revised, final
}

/// Phase 1.k schema (declared now, persisted later). Captures the link
/// between an in-prose run of AI-generated text and the per-event
/// `generation-log/<ts>.json` it came from.
public struct GeneratedSpan: Codable, Equatable {
    public let id: UUID
    public var generatedAt: Date
    public var mode: GenerationMode
    public var promptLogPath: String
    public var rangeInScene: SceneRange?
    public var accepted: Bool

    public init(
        id: UUID = UUID(),
        generatedAt: Date,
        mode: GenerationMode,
        promptLogPath: String,
        rangeInScene: SceneRange? = nil,
        accepted: Bool = false
    ) {
        self.id = id
        self.generatedAt = generatedAt
        self.mode = mode
        self.promptLogPath = promptLogPath
        self.rangeInScene = rangeInScene
        self.accepted = accepted
    }
}

/// Codable analogue of NSRange: avoids tying Scene to AppKit / Foundation's
/// non-Codable NSRange. Same shape (location, length).
public struct SceneRange: Codable, Equatable {
    public var location: Int
    public var length: Int

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }
}

/// Snapshot — Phase 2+ Scrivener-style "save the prose before this
/// destructive operation". Schema present in 1.b; persistence later.
public struct Snapshot: Codable, Equatable {
    public let id: UUID
    public var takenAt: Date
    public var label: String?
    public var contentSnapshot: String

    public init(id: UUID = UUID(), takenAt: Date, label: String? = nil, contentSnapshot: String) {
        self.id = id
        self.takenAt = takenAt
        self.label = label
        self.contentSnapshot = contentSnapshot
    }
}

/// Generation modes per LOOM_DATA_MODEL.md §5 / LOOM_GENERATION_MODES.md.
/// Phase 1 only fires `.continueProse` and `.expand`; the rest are wired
/// in Phase 4.
public enum GenerationMode: String, Codable, Equatable, CaseIterable {
    case continueProse
    case expand
    case rewrite
    case rewriteVoice
    case rewriteTense
    case rewritePOV
    case rewriteLength
    case showDontTell
    case brainstorm
    case critique
    case bridge
    case describe
    case nameSuggest
}

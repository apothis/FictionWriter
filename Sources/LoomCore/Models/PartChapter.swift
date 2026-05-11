import Foundation

/// Phase 3 §A — Part of a manuscript (Act / Volume / Book — the
/// label is user-supplied). Per LOOM_DATA_MODEL.md §2 Parts wrap
/// Chapters; Chapters wrap scene-id references. The structural
/// hierarchy is opt-in: a project's `manuscript.orphanedSceneIds`
/// continues to carry scenes that haven't been placed into a
/// chapter yet, so Phase 1/2 projects keep working unchanged.
public struct Part: Codable, Equatable {
    public let id: UUID
    public var title: String
    public var chapters: [Chapter]
    public var notes: String

    public init(
        id: UUID = UUID(),
        title: String,
        chapters: [Chapter] = [],
        notes: String = ""
    ) {
        self.id = id
        self.title = title
        self.chapters = chapters
        self.notes = notes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.chapters = try c.decodeIfPresent([Chapter].self, forKey: .chapters) ?? []
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }
}

/// Phase 3 §A — Chapter under a Part. Holds scene-id references
/// (the scenes themselves live in `scenes/<id>.md` on disk;
/// `session.scenes` is the in-memory lookup table).
///
/// `summary` is the recursive-summary feed (LOOM_RESEARCH.md §L.1)
/// — Phase 4+ extracts this from the underlying scenes;
/// `summaryDirty` flags regen-needed when underlying scenes change.
/// `targetWordCount` drives Phase 6 polish word-count progress.
public struct Chapter: Codable, Equatable {
    public let id: UUID
    public var title: String
    public var sceneIds: [UUID]
    public var summary: String?
    public var summaryDirty: Bool
    public var targetWordCount: Int?
    public var notes: String

    public init(
        id: UUID = UUID(),
        title: String,
        sceneIds: [UUID] = [],
        summary: String? = nil,
        summaryDirty: Bool = false,
        targetWordCount: Int? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.title = title
        self.sceneIds = sceneIds
        self.summary = summary
        self.summaryDirty = summaryDirty
        self.targetWordCount = targetWordCount
        self.notes = notes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.sceneIds = try c.decodeIfPresent([UUID].self, forKey: .sceneIds) ?? []
        self.summary = try c.decodeIfPresent(String.self, forKey: .summary)
        self.summaryDirty = try c.decodeIfPresent(Bool.self, forKey: .summaryDirty) ?? false
        self.targetWordCount = try c.decodeIfPresent(Int.self, forKey: .targetWordCount)
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }
}

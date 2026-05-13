import Foundation

/// A reference text — a piece of user-curated prose held in the
/// project for style-RAG retrieval (Phase 5). Persisted as
/// `references/<id>.md` (frontmatter + body, mirroring `Scene`),
/// with a sidecar `references/<id>.index` JSON file holding the
/// per-chunk D + E vectors.
///
/// `body` is a runtime field — its on-disk home is the .md body,
/// not the metadata JSON. Excluded from Codable so encoding a
/// ReferenceText for debug / log purposes doesn't carry the prose
/// blob.
public struct ReferenceText: Codable, Equatable {
    public let id: UUID
    public var name: String
    public var nsfw: Bool
    public var createdAt: Date
    public var extraFrontmatter: [String: String]
    public var body: String

    public var contentPath: String { "references/\(id.uuidString).md" }
    public var indexPath: String { "references/\(id.uuidString).index" }

    private enum CodingKeys: String, CodingKey {
        case id, name, nsfw, createdAt, extraFrontmatter
        // body, contentPath, indexPath intentionally excluded.
    }

    public init(
        id: UUID,
        name: String,
        nsfw: Bool = false,
        createdAt: Date = Date(),
        extraFrontmatter: [String: String] = [:],
        body: String = ""
    ) {
        self.id = id
        self.name = name
        self.nsfw = nsfw
        self.createdAt = createdAt
        self.extraFrontmatter = extraFrontmatter
        self.body = body
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.nsfw = try c.decodeIfPresent(Bool.self, forKey: .nsfw) ?? false
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.extraFrontmatter = try c.decodeIfPresent([String: String].self, forKey: .extraFrontmatter) ?? [:]
        self.body = ""
    }
}

/// On-disk sidecar for a reference text. Per-chunk D and E vectors
/// (Path D = StyleDistance via MLX; Path E = function-word z-score).
/// Both vectors are optional so the schema can model the pre-embed
/// state (chunks computed, embed pass not yet run) and the partial
/// state (e.g., D ran, E pending after a model swap).
public struct ReferenceTextIndex: Codable, Equatable {
    public var schemaVersion: Int
    public var dModel: ModelFingerprint?
    public var eModel: ModelFingerprint?
    public var chunks: [Chunk]

    public struct ModelFingerprint: Codable, Equatable {
        public let id: String
        public let dim: Int
        public init(id: String, dim: Int) {
            self.id = id
            self.dim = dim
        }
    }

    public struct Chunk: Codable, Equatable {
        public let text: String
        public let wordRangeStart: Int
        public let wordRangeEnd: Int
        /// Phase 5 scope-lock #5 — per-scene-type retrieval pillar.
        /// Tagging policy (LLM-classified vs user-marked) undecided
        /// at this schema's v1; the slot is here so once policy
        /// lands no migration is needed.
        public var modality: String?
        public var dVec: [Float]?
        public var eVec: [Float]?

        public init(
            text: String,
            wordRangeStart: Int,
            wordRangeEnd: Int,
            modality: String? = nil,
            dVec: [Float]? = nil,
            eVec: [Float]? = nil
        ) {
            self.text = text
            self.wordRangeStart = wordRangeStart
            self.wordRangeEnd = wordRangeEnd
            self.modality = modality
            self.dVec = dVec
            self.eVec = eVec
        }
    }

    public init(
        schemaVersion: Int = 1,
        dModel: ModelFingerprint? = nil,
        eModel: ModelFingerprint? = nil,
        chunks: [Chunk] = []
    ) {
        self.schemaVersion = schemaVersion
        self.dModel = dModel
        self.eModel = eModel
        self.chunks = chunks
    }
}

import Foundation

/// Phase 7.b.1 — a *template scene*: a scene-sized prose chunk
/// (500–5000 words) ingested for re-use as a structural blueprint.
/// New scenes generated via `.generateFromTemplate` mode consume the
/// `ExtractedSceneSkeleton` derived from this template's body.
///
/// Persisted as `templates/<id>.md` (frontmatter + body — mirrors
/// `ReferenceText` per the Phase 5 A2 References pattern) with a
/// sidecar `templates/<id>.beats.json` (the `ExtractedSceneSkeleton`).
///
/// `body` is runtime-only (lives in the .md body, not in Codable JSON)
/// to keep metadata-export payloads tight.
///
/// Pinned in [`LOOM_SCENE_TEMPLATE.md`](../../../LOOM_SCENE_TEMPLATE.md) §6.1.
public struct TemplateScene: Codable, Equatable {
    public let id: UUID
    public var name: String
    public var nsfw: Bool
    public var createdAt: Date
    public var extraFrontmatter: [String: String]
    public var body: String

    public var contentPath: String { "templates/\(id.uuidString).md" }
    public var beatsPath: String { "templates/\(id.uuidString).beats.json" }

    private enum CodingKeys: String, CodingKey {
        case id, name, nsfw, createdAt, extraFrontmatter
        // body intentionally excluded.
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

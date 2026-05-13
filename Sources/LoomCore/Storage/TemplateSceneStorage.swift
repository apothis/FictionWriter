import Foundation

/// Disk operations for Phase 7 template scenes + their beat-skeleton
/// sidecars. Template scenes live at `<project>/templates/<id>.md`
/// (frontmatter + body, format owned by `TemplateSceneFile`); their
/// extracted skeletons live at `<project>/templates/<id>.beats.json`
/// (`ExtractedSceneSkeleton` JSON).
///
/// Two artifacts per template because their lifecycles differ: the
/// .md is user-edited content (source of truth); the .beats.json is
/// rebuildable derivative state (regenerated from .md when the user
/// clicks Extract). Missing or malformed .beats.json is not fatal —
/// `loadSkeleton` returns nil and the caller schedules a re-extract.
///
/// Mirrors `ReferenceStorage` directly per [`LOOM_SCENE_TEMPLATE.md`](../../../LOOM_SCENE_TEMPLATE.md)
/// §6.1 + D1.
public enum TemplateSceneStorage {
    private static let dirName = "templates"

    public static func ensureDirectory(in projectURL: URL) throws {
        let url = projectURL.appendingPathComponent(dirName)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    // MARK: - .md (frontmatter + body)

    public static func saveTemplate(_ scene: TemplateScene, in projectURL: URL) throws {
        try ensureDirectory(in: projectURL)
        let url = projectURL
            .appendingPathComponent(dirName)
            .appendingPathComponent("\(scene.id.uuidString).md")
        let text = TemplateSceneFile.encode(scene)
        try text.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    public static func loadTemplate(id: UUID, in projectURL: URL) throws -> TemplateScene {
        let url = projectURL
            .appendingPathComponent(dirName)
            .appendingPathComponent("\(id.uuidString).md")
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw TemplateSceneStorageError.malformedMarkdown
        }
        return try TemplateSceneFile.decode(text)
    }

    // MARK: - .beats.json sidecar

    public static func saveSkeleton(
        _ skeleton: ExtractedSceneSkeleton,
        for id: UUID,
        in projectURL: URL
    ) throws {
        try ensureDirectory(in: projectURL)
        let url = projectURL
            .appendingPathComponent(dirName)
            .appendingPathComponent("\(id.uuidString).beats.json")
        let data = try JSONEncoder.loomPretty.encode(skeleton)
        try data.write(to: url, options: .atomic)
    }

    /// Returns nil on missing or malformed sidecar — both are
    /// recoverable conditions. The caller schedules a re-extract.
    public static func loadSkeleton(for id: UUID, in projectURL: URL) -> ExtractedSceneSkeleton? {
        let url = projectURL
            .appendingPathComponent(dirName)
            .appendingPathComponent("\(id.uuidString).beats.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.loom.decode(ExtractedSceneSkeleton.self, from: data)
    }

    // MARK: - Delete + list

    /// Removes both files. Idempotent — missing files do not throw.
    public static func deleteTemplate(id: UUID, in projectURL: URL) throws {
        let fm = FileManager.default
        let base = projectURL.appendingPathComponent(dirName)
        let mdURL = base.appendingPathComponent("\(id.uuidString).md")
        let beatsURL = base.appendingPathComponent("\(id.uuidString).beats.json")
        if fm.fileExists(atPath: mdURL.path) {
            try fm.removeItem(at: mdURL)
        }
        if fm.fileExists(atPath: beatsURL.path) {
            try fm.removeItem(at: beatsURL)
        }
    }

    /// Enumerates the .md files in templates/ and returns their UUIDs.
    /// Files that aren't `<uuid>.md` are skipped. Returns an empty
    /// array if templates/ doesn't exist yet (new projects).
    public static func listTemplateIds(in projectURL: URL) throws -> [UUID] {
        let fm = FileManager.default
        let dir = projectURL.appendingPathComponent(dirName)
        guard fm.fileExists(atPath: dir.path) else { return [] }
        let entries = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        var ids: [UUID] = []
        for entry in entries {
            guard entry.pathExtension == "md" else { continue }
            let name = entry.deletingPathExtension().lastPathComponent
            if let id = UUID(uuidString: name) {
                ids.append(id)
            }
        }
        return ids
    }
}

public enum TemplateSceneStorageError: Error, Equatable {
    case malformedMarkdown
}

import Foundation

/// Disk operations for Phase 5 reference texts + their embedding-index
/// sidecars. Reference texts live at `<project>/references/<id>.md`
/// (frontmatter + body, format owned by ReferenceFile); their per-chunk
/// vectors live at `<project>/references/<id>.index` (JSON, format owned
/// by ReferenceTextIndex).
///
/// Two on-disk artifacts per reference because their lifecycles differ:
/// the .md is user-edited content (source of truth); the .index is
/// rebuildable derivative state (regenerated from .md on demand, or
/// after a model swap). Missing or malformed .index files are not
/// fatal — the load path returns nil and the caller schedules an
/// embed pass.
public enum ReferenceStorage {
    private static let dirName = "references"

    public static func ensureDirectory(in projectURL: URL) throws {
        let url = projectURL.appendingPathComponent(dirName)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    // MARK: - .md (frontmatter + body)

    public static func saveReference(_ ref: ReferenceText, in projectURL: URL) throws {
        try ensureDirectory(in: projectURL)
        let url = projectURL
            .appendingPathComponent(dirName)
            .appendingPathComponent("\(ref.id.uuidString).md")
        let text = ReferenceFile.encode(ref)
        try text.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    public static func loadReference(id: UUID, in projectURL: URL) throws -> ReferenceText {
        let url = projectURL
            .appendingPathComponent(dirName)
            .appendingPathComponent("\(id.uuidString).md")
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ReferenceStorageError.malformedMarkdown
        }
        return try ReferenceFile.decode(text)
    }

    // MARK: - .index (JSON sidecar)

    public static func saveIndex(
        _ index: ReferenceTextIndex,
        for id: UUID,
        in projectURL: URL
    ) throws {
        try ensureDirectory(in: projectURL)
        let url = projectURL
            .appendingPathComponent(dirName)
            .appendingPathComponent("\(id.uuidString).index")
        let data = try JSONEncoder.loomPretty.encode(index)
        try data.write(to: url, options: .atomic)
    }

    /// Returns nil on missing or malformed sidecar — both are
    /// recoverable conditions. The caller schedules a rebuild.
    public static func loadIndex(for id: UUID, in projectURL: URL) -> ReferenceTextIndex? {
        let url = projectURL
            .appendingPathComponent(dirName)
            .appendingPathComponent("\(id.uuidString).index")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.loom.decode(ReferenceTextIndex.self, from: data)
    }

    // MARK: - Delete + list

    /// Removes both files. Idempotent — missing files do not throw.
    public static func deleteReference(id: UUID, in projectURL: URL) throws {
        let fm = FileManager.default
        let base = projectURL.appendingPathComponent(dirName)
        let mdURL = base.appendingPathComponent("\(id.uuidString).md")
        let indexURL = base.appendingPathComponent("\(id.uuidString).index")
        if fm.fileExists(atPath: mdURL.path) {
            try fm.removeItem(at: mdURL)
        }
        if fm.fileExists(atPath: indexURL.path) {
            try fm.removeItem(at: indexURL)
        }
    }

    /// Enumerates the .md files in references/ and returns their UUIDs.
    /// Files that aren't `<uuid>.md` are skipped. Returns an empty
    /// array if references/ doesn't exist yet (new projects).
    public static func listReferenceIds(in projectURL: URL) throws -> [UUID] {
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

public enum ReferenceStorageError: Error, Equatable {
    case malformedMarkdown
}

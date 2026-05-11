import Foundation

/// Phase 2 #9 — Scrivener-pattern snapshots-before-AI-rewrite.
/// One JSON file per snapshot at `<project>/snapshots/<ts>-<uuid>.json`,
/// matching the generation-log shape (HANDOFF §9.1 row 9). The
/// timestamp prefix gives `ls`-sorted directory order out of the box;
/// each file is self-contained so manual restore from disk works
/// without an index.
public struct PersistedSnapshot: Codable, Equatable {
    public let id: UUID
    public let sceneId: UUID
    public let takenAt: Date
    public let label: String?
    public let contentSnapshot: String

    public init(
        id: UUID = UUID(),
        sceneId: UUID,
        takenAt: Date,
        label: String?,
        contentSnapshot: String
    ) {
        self.id = id
        self.sceneId = sceneId
        self.takenAt = takenAt
        self.label = label
        self.contentSnapshot = contentSnapshot
    }
}

/// Phase 2 #9 — policy: which generation modes warrant capturing the
/// scene's prose before the call runs. Continue/Expand append at
/// cursor (non-destructive); the rewrite family replaces selected
/// prose in place (destructive — snapshot it).
public enum SnapshotPolicy {
    public static func shouldSnapshot(beforeMode mode: GenerationMode) -> Bool {
        switch mode {
        case .rewrite, .rewriteVoice, .rewriteTense, .rewritePOV, .rewriteLength:
            return true
        default:
            return false
        }
    }
}

public final class SnapshotStore {
    private let fm: FileManager

    public init(fileManager: FileManager = .default) {
        self.fm = fileManager
    }

    /// Write a single snapshot. Filename is
    /// `<sortable-timestamp>-<uuid>.json`. Returns the file URL.
    @discardableResult
    public func write(_ snap: PersistedSnapshot, in projectURL: URL) throws -> URL {
        let dir = projectURL.appendingPathComponent("snapshots", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = Self.filenameTimestamp(snap.takenAt)
        let filename = "\(stamp)-\(snap.id.uuidString).json"
        let url = dir.appendingPathComponent(filename)
        let data = try JSONEncoder.loomPretty.encode(snap)
        try data.write(to: url, options: .atomic)
        DebugLog.shared.write("[snapshot] written: \(filename)")
        return url
    }

    /// Read all snapshots in the project's snapshots directory, sorted
    /// newest first. Corrupt JSON files are silently skipped — best-
    /// effort recovery mirrors GenerationLogStore.list (a bad file
    /// doesn't blank the whole list).
    public func list(in projectURL: URL) -> [PersistedSnapshot] {
        let dir = projectURL.appendingPathComponent("snapshots", isDirectory: true)
        guard fm.fileExists(atPath: dir.path) else { return [] }
        guard let urls = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        var entries: [PersistedSnapshot] = []
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let snap = try? JSONDecoder.loom.decode(PersistedSnapshot.self, from: data)
            else { continue }
            entries.append(snap)
        }
        entries.sort { $0.takenAt > $1.takenAt }
        return entries
    }

    private static func filenameTimestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return f.string(from: date)
    }
}

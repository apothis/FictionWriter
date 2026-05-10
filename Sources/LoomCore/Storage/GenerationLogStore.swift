import Foundation

/// Read/write façade over `<project>/generation-log/*.json`. Each
/// entry lives in its own file (per LOOM_DATA_MODEL.md §7.3 — append-
/// only log, easy to back up, easy to delete selectively, easy to
/// audit). Phase 6 polish may add compaction; Phase 1 lets the
/// directory grow.
public final class GenerationLogStore {
    private let fm: FileManager

    public init(fileManager: FileManager = .default) {
        self.fm = fileManager
    }

    /// Write a single entry. Filename is `<sortable-timestamp>-<uuid>.json`
    /// — the timestamp prefix lets `ls`-sorted views of the directory
    /// match the in-app sort. Returns the URL on success.
    @discardableResult
    public func write(_ entry: GenerationLogEntry, in projectURL: URL) throws -> URL {
        let dir = projectURL.appendingPathComponent("generation-log", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = filenameTimestamp(entry.timestamp)
        let filename = "\(stamp)-\(entry.id.uuidString).json"
        let url = dir.appendingPathComponent(filename)
        let data = try JSONEncoder.loomPretty.encode(entry)
        try data.write(to: url, options: .atomic)
        DebugLog.shared.write("[gen] log-written: \(filename)")
        return url
    }

    /// Read all entries in the project's log directory, sorted newest
    /// first. Corrupt JSON files are silently skipped — best-effort
    /// recovery so a single bad file doesn't blank out the whole
    /// History tab.
    public func list(in projectURL: URL) -> [GenerationLogEntry] {
        let dir = projectURL.appendingPathComponent("generation-log", isDirectory: true)
        guard fm.fileExists(atPath: dir.path) else { return [] }
        guard let urls = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        ) else { return [] }

        var entries: [GenerationLogEntry] = []
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let entry = try? JSONDecoder.loom.decode(GenerationLogEntry.self, from: data)
            else { continue }
            entries.append(entry)
        }
        entries.sort { $0.timestamp > $1.timestamp }
        return entries
    }

    private func filenameTimestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return f.string(from: date)
    }
}

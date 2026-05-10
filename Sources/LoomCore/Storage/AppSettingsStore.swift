import Foundation

/// Loads + saves global Loom settings at
/// `~/Library/Application Support/Loom/settings.json`. A separate type
/// (rather than a method on AppSettings) so test code can inject a
/// custom root URL.
public final class AppSettingsStore {
    private let fm: FileManager
    private let rootDir: URL

    public init(fileManager: FileManager = .default, rootDir: URL? = nil) {
        self.fm = fileManager
        self.rootDir = rootDir ?? Self.defaultRootDir(fileManager: fileManager)
    }

    public static func defaultRootDir(fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Loom", isDirectory: true)
    }

    public var settingsURL: URL { rootDir.appendingPathComponent("settings.json") }

    /// Read settings from disk; returns `.defaults` on missing/corrupt
    /// file. Mirrors RPClient's "never crash on bad settings" posture.
    public func load() -> AppSettings {
        guard fm.fileExists(atPath: settingsURL.path),
              let data = try? Data(contentsOf: settingsURL),
              let settings = try? JSONDecoder.loom.decode(AppSettings.self, from: data)
        else {
            return .defaults
        }
        return settings
    }

    public func save(_ settings: AppSettings) throws {
        try fm.createDirectory(at: rootDir, withIntermediateDirectories: true)
        let data = try JSONEncoder.loomPretty.encode(settings)
        try data.write(to: settingsURL, options: .atomic)
        DebugLog.shared.write("[storage] wrote settings.json (\(data.count) bytes)")
    }
}

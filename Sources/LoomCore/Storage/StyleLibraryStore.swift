import Foundation

/// Loads + saves the app-level style library at
/// `~/Library/Application Support/Loom/styles.json`. A separate type
/// (rather than a method on `Style`) so test code can inject a custom
/// root URL — mirrors `AppSettingsStore`.
///
/// On first run (no file) the library is the curated built-in starter
/// set; once `styles.json` exists it is the source of truth and the
/// writer owns it fully (LOOM_PLANNED_PROJECT.md §5).
public final class StyleLibraryStore {
    private let fm: FileManager
    private let rootDir: URL

    public init(fileManager: FileManager = .default, rootDir: URL? = nil) {
        self.fm = fileManager
        self.rootDir = rootDir ?? AppSettingsStore.defaultRootDir(fileManager: fileManager)
    }

    public var stylesURL: URL { rootDir.appendingPathComponent("styles.json") }

    /// The writer's style library. Returns the built-in starters when
    /// no file exists (first run) or the file is corrupt; an
    /// explicitly-saved empty library decodes as `[]` and is honoured.
    public func load() -> [Style] {
        guard fm.fileExists(atPath: stylesURL.path),
              let data = try? Data(contentsOf: stylesURL),
              let styles = try? JSONDecoder.loom.decode([Style].self, from: data)
        else {
            return StyleLibrary.builtInStarters
        }
        return styles
    }

    public func save(_ styles: [Style]) throws {
        try fm.createDirectory(at: rootDir, withIntermediateDirectories: true)
        let data = try JSONEncoder.loomPretty.encode(styles)
        try data.write(to: stylesURL, options: .atomic)
        DebugLog.shared.write("[storage] wrote styles.json (\(data.count) bytes)")
    }
}

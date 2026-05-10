import Foundation

/// Minimal app-level singleton: owns the AppSettings + the
/// KoboldClientRegistry. Lazy-loaded on first access so `AppDelegate`
/// can simply reference `AppState.shared` to bootstrap the world.
///
/// Phase 1 is intentionally tiny — just enough state to make Continue/
/// Expand work in 1.i. Per-project settings (Project.settings) are
/// owned by whoever loaded the .loom bundle (later sub-steps), not by
/// AppState.
public final class AppState {
    public static let shared = AppState()

    public let settingsStore: AppSettingsStore
    public private(set) var settings: AppSettings
    public let registry: KoboldClientRegistry
    public let currentSession: ProjectSession

    /// Test-only init. Production code uses `.shared`.
    public init(settingsStore: AppSettingsStore = AppSettingsStore()) {
        self.settingsStore = settingsStore
        self.settings = settingsStore.load()
        self.registry = KoboldClientRegistry(
            profiles: self.settings.servers,
            defaultServerId: self.settings.defaultServerId
        )
        // Phase 1 boots into an in-memory "Untitled" project with a
        // single starting scene so the user can begin typing immediately.
        // File picker / "open existing project" land when needed.
        let session = ProjectSession(project: Project(title: "Untitled"))
        _ = session.addScene()
        self.currentSession = session
        DebugLog.shared.write("[loom] app-state init servers=\(self.settings.servers.count) default=\(self.settings.defaultServerId?.uuidString ?? "nil") session=\(session.project.title)")
    }

    /// Replace settings in memory + on disk, then refresh the registry.
    public func updateSettings(_ newSettings: AppSettings) throws {
        self.settings = newSettings
        try settingsStore.save(newSettings)
        registry.updateProfiles(newSettings.servers, defaultServerId: newSettings.defaultServerId)
    }
}

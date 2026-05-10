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

    /// Test-only init. Production code uses `.shared`.
    public init(settingsStore: AppSettingsStore = AppSettingsStore()) {
        self.settingsStore = settingsStore
        self.settings = settingsStore.load()
        self.registry = KoboldClientRegistry(
            profiles: self.settings.servers,
            defaultServerId: self.settings.defaultServerId
        )
        DebugLog.shared.write("[loom] app-state init servers=\(self.settings.servers.count) default=\(self.settings.defaultServerId?.uuidString ?? "nil")")
    }

    /// Replace settings in memory + on disk, then refresh the registry.
    public func updateSettings(_ newSettings: AppSettings) throws {
        self.settings = newSettings
        try settingsStore.save(newSettings)
        registry.updateProfiles(newSettings.servers, defaultServerId: newSettings.defaultServerId)
    }
}

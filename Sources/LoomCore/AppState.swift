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
    /// Model name returned by the most recent successful ServerProbe.
    /// Set by AppDelegate's launch + project-replace probe; consumed
    /// by GenerationCoordinator so PromptBuilder's `.auto` template
    /// detection can match against it (e.g. "Qwen3.6-..." → .chatml).
    public var lastProbedModelName: String?

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

    // MARK: - Project lifecycle (1.j.A)

    /// Create a fresh `.loom` directory at `url`, switch the current
    /// session to it, and seed it with a starter scene so the user has
    /// somewhere to type immediately. The session keeps its identity
    /// (existing UI observers stay valid via didReplaceNotification).
    public func createProject(at url: URL, title: String) throws {
        let storage = ProjectStorage()
        var project = try storage.createNewProject(at: url, title: title, author: nil)
        let starter = Scene.empty(id: UUID(), title: "Scene 1")
        project.manuscript.orphanedSceneIds = [starter.id]
        try storage.saveScene(starter, in: url)
        try storage.saveProject(project, at: url)
        currentSession.replace(project: project, scenes: [starter.id: starter], url: url)
        try pushRecentAndSave(url)
        DebugLog.shared.write("[loom] createProject at=\(url.lastPathComponent)")
    }

    /// Load an existing `.loom` directory at `url` and switch the
    /// current session to it. Uses the recovery path so a corrupt
    /// `project.json` falls back to `project.json.bak` automatically.
    public func openProject(at url: URL) throws {
        let storage = ProjectStorage()
        let loaded = try storage.loadProjectWithRecovery(from: url)
        currentSession.replace(project: loaded.project, scenes: loaded.scenes, url: url)
        try pushRecentAndSave(url)
        DebugLog.shared.write("[loom] openProject at=\(url.lastPathComponent) scenes=\(loaded.scenes.count)")
    }

    private func pushRecentAndSave(_ url: URL) throws {
        var newSettings = settings
        newSettings.pushRecentProject(url)
        try updateSettings(newSettings)
    }

    /// Save the current in-memory session to a new on-disk location
    /// (Save As). The session adopts the new URL and is auto-saved
    /// from then on.
    public func saveCurrentSessionAs(url: URL, title: String?) throws {
        let storage = ProjectStorage()
        // Update the session's project title if the caller supplied one
        // (Save As typically derives it from the chosen filename).
        if let title = title {
            currentSession.replace(
                project: { var p = currentSession.project; p.title = title; return p }(),
                scenes: currentSession.scenes,
                url: nil
            )
        }
        // Create the on-disk directory if it doesn't exist; if it does,
        // ProjectStorage.saveProject will write project.json into it.
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: url.appendingPathComponent("scenes"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: url.appendingPathComponent("generation-log"),
            withIntermediateDirectories: true
        )
        try storage.saveProject(currentSession.project, at: url)
        for (_, scene) in currentSession.scenes {
            try storage.saveScene(scene, in: url)
        }
        currentSession.url = url
        currentSession.markCleanForTest()
        DebugLog.shared.write("[loom] saveAs at=\(url.lastPathComponent)")
    }
}

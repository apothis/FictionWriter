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
    public var lastProbedMaxContext: Int?

    /// Phase 4 #7 sub-task 2 — debounced post-scene knowledge-ledger
    /// side-call coordinator. Constructed once at app init; the
    /// extractorProvider closure consults `settings.extractorServer()`
    /// at call time so the coordinator picks up server changes
    /// without rebuild. Sub-task 3 routes the coordinator's
    /// `onExtractionComplete` into `ledgerSuggestionsQueue` via the
    /// `LedgerDiff` pure-data pass.
    public let ledgerCoordinator: LedgerExtractionCoordinator

    /// Phase 4 #7 sub-task 3 — in-memory pending-suggestions queue,
    /// populated from extraction results via `LedgerDiff.diff(...)`.
    /// The Bible inspector chip (sub-task 4) reads from this; the
    /// accept-handler (sub-task 5) persists into
    /// `Character.knownFactsBySceneId` and removes from the queue.
    public let ledgerSuggestionsQueue: LedgerSuggestionsQueue

    /// Posted on the main queue when new suggestions are appended
    /// to `ledgerSuggestionsQueue`. Sub-task 4's Bible inspector
    /// subscribes to refresh the chip count + list.
    public static let ledgerSuggestionsDidChangeNotification = Notification.Name("LoomLedger.suggestionsDidChange")

    private var dirtyObserver: NSObjectProtocol?

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

        // Captured-locally lookups (the closures can't reference `self`
        // until after super.init / property assignment completes).
        var settingsSnapshot: () -> AppSettings = { AppSettings() }
        var sessionRef: () -> ProjectSession = { session }
        let coordinator = LedgerExtractionCoordinator(
            extractorProvider: { () -> LedgerExtractor? in
                guard let profile = settingsSnapshot().extractorServer() else { return nil }
                let model = profile.capabilities?.modelName ?? "gemma4_2b:latest"
                return OllamaLedgerExtractor(baseURL: profile.baseURL, model: model)
            },
            scheduler: TimerScheduler(),
            sceneProvider: { sceneId in
                let s = sessionRef()
                guard let scene = s.scenes[sceneId] else { return nil }
                let characters = s.project.bible.characters.map {
                    LedgerExtraction.CharacterRef(name: $0.name, aliases: $0.aliases)
                }
                return (prose: scene.prose, characters: characters)
            }
        )
        self.ledgerCoordinator = coordinator
        self.ledgerSuggestionsQueue = LedgerSuggestionsQueue()

        // Now that all stored properties are initialized, rebind the
        // closures to reach `self` for live settings + session.
        settingsSnapshot = { [weak self] in self?.settings ?? AppSettings() }
        sessionRef = { [weak self] in self?.currentSession ?? session }

        // Phase 4 #7 sub-task 3 — feed successful extractions into the
        // suggestions queue via the LedgerDiff pure-data pass.
        coordinator.onExtractionComplete = { [weak self] sceneId, result in
            self?.handleExtractionComplete(sceneId: sceneId, result: result)
        }

        DebugLog.shared.write("[loom] app-state init servers=\(self.settings.servers.count) default=\(self.settings.defaultServerId?.uuidString ?? "nil") session=\(session.project.title)")

        // Subscribe to dirty→clean transitions (post-autosave) and
        // evaluate the active scene against the ledger threshold.
        // Production wiring; the coordinator itself is fully tested in
        // Phase4LedgerExtractionCoordinatorTests.
        dirtyObserver = NotificationCenter.default.addObserver(
            forName: ProjectSession.didChangeDirtyStateNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handleDirtyStateChange(note)
        }
    }

    deinit {
        if let obs = dirtyObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    private func handleExtractionComplete(
        sceneId: UUID,
        result: Result<[LedgerExtraction.ExtractedFact], Error>
    ) {
        switch result {
        case .failure(let err):
            DebugLog.shared.write("[ledger] extraction failed for scene=\(sceneId): \(err)")
            return
        case .success(let extracted):
            let bible = currentSession.project.bible
            let suggestions = LedgerDiff.diff(
                extracted: extracted,
                bible: bible,
                sourceSceneId: sceneId
            )
            guard !suggestions.isEmpty else {
                DebugLog.shared.write("[ledger] diff produced 0 new suggestions for scene=\(sceneId) (extracted=\(extracted.count))")
                return
            }
            ledgerSuggestionsQueue.add(suggestions)
            DebugLog.shared.write("[ledger] queued \(suggestions.count) suggestions for scene=\(sceneId)")
            NotificationCenter.default.post(
                name: Self.ledgerSuggestionsDidChangeNotification,
                object: self
            )
        }
    }

    private func handleDirtyStateChange(_ note: Notification) {
        guard let session = note.object as? ProjectSession, session === currentSession else { return }
        // Only fire on dirty→clean (post-save) — clean→dirty is just
        // "user started typing" and we don't want to schedule on the
        // very first keystroke of a burst.
        guard session.isDirty == false else { return }
        guard let sceneId = session.currentSceneId else { return }
        guard let scene = session.scenes[sceneId] else { return }
        let wordCount = WordCount.count(scene.prose)
        ledgerCoordinator.evaluate(sceneId: sceneId, currentWordCount: wordCount)
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

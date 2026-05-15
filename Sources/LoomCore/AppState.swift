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

    /// Templates whose Pass-A beat extraction is currently in flight.
    /// Mutated by `extractTemplateScene`. The Bible Workspace bridge
    /// reads this on every snapshot push so the React UI can show
    /// "Extracting…" on the template editor. Transient — never
    /// persisted, cleared on app relaunch.
    public private(set) var extractingTemplateIds: Set<UUID> = []

    /// Phase 8.b.7 — References whose chunk+embed pipeline is
    /// currently in flight. Mutated by `ingestReference`. The Bible
    /// Workspace bridge reads this on every snapshot push so the
    /// React UI can show "Ingesting…" on the reference editor + the
    /// unified Scene Exemplar editor. Transient — never persisted,
    /// cleared on app relaunch.
    public private(set) var ingestingReferenceIds: Set<UUID> = []

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

    private var wordCountObserver: NSObjectProtocol?

    /// Phase 4 #7 sub-task 8 — resolver for the embedding endpoint
    /// the `LedgerFilterPipeline` calls. Production wiring uses the
    /// default writer server's `KoboldClient` (it hosts the
    /// nomic-embed-text endpoint alongside generation). Tests inject
    /// a deferred-completion stub so the §10.5 filter chain can be
    /// exercised end-to-end without hitting the network.
    ///
    /// Returning `nil` skips the filter pipeline entirely and ships
    /// the post-diff suggestions unfiltered. The default closure
    /// returns `nil` when there's no `defaultServerId` configured —
    /// covers both the first-launch case (no servers added yet) and
    /// the existing wiring tests that construct an `AppState` against
    /// an empty settings store.
    public var embedderProvider: () -> KoboldEmbedding?

    /// Phase 5 production A1 — factory for the D `EmbeddingClient` used
    /// by the per-project style-retrieval surface. Production wiring
    /// (`AppState.shared`) defaults to a `PythonEmbeddingClient` bound
    /// to the repo's bundled venv (default model: Wegmann
    /// `AnnaWegmann/Style-Embedding`); tests inject a stub so the suite
    /// never spawns a Python subprocess. The factory is called once
    /// per project-open, NOT per query.
    public typealias EmbeddingClientFactory = (URL) -> EmbeddingClient
    public var embeddingClientFactory: EmbeddingClientFactory

    /// Phase 5 production A1 — the current project's retrieval service,
    /// or nil for in-memory ("Untitled") sessions. Rebuilt on every
    /// `openProject` / `createProject` / `saveCurrentSessionAs` call.
    /// Releasing the old service deinits its `PythonEmbeddingClient`,
    /// which closes the subprocess's stdin and lets it exit cleanly.
    public private(set) var currentRetrievalService: RetrievalService?

    /// Test-only init. Production code uses `.shared`.
    public init(
        settingsStore: AppSettingsStore = AppSettingsStore(),
        embedderProvider: (() -> KoboldEmbedding?)? = nil,
        embeddingClientFactory: EmbeddingClientFactory? = nil
    ) {
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

        // Default embedder: hand out the writer-server client if one
        // is configured; otherwise nil (skip filtering). Set
        // pre-self-reference; rebound below to capture `self`.
        self.embedderProvider = { nil }

        // Phase 5 production A1 — default factory spawns the
        // Python+Wegmann subprocess against the repo's bundled venv
        // (model id locked by the Phase 8.a §6.1 spike). Paths are
        // relative to the current working directory, matching the
        // self-use deployment model. Phase 5.5 sub-row will swap this
        // for a `Loom.app/Contents/Resources/Python` bundled lookup.
        self.embeddingClientFactory = embeddingClientFactory ?? AppState.defaultEmbeddingClientFactory

        // Now that all stored properties are initialized, rebind the
        // closures to reach `self` for live settings + session.
        settingsSnapshot = { [weak self] in self?.settings ?? AppSettings() }
        sessionRef = { [weak self] in self?.currentSession ?? session }

        if let provided = embedderProvider {
            self.embedderProvider = provided
        } else {
            self.embedderProvider = { [weak self] () -> KoboldEmbedding? in
                guard let self = self,
                      let defaultId = self.settings.defaultServerId,
                      self.settings.servers.contains(where: { $0.id == defaultId })
                else { return nil }
                return self.registry.clientForDefault()
            }
        }

        // Phase 4 #7 sub-task 3 — feed successful extractions into the
        // suggestions queue via the LedgerDiff pure-data pass.
        coordinator.onExtractionComplete = { [weak self] sceneId, result in
            self?.handleExtractionComplete(sceneId: sceneId, result: result)
        }

        DebugLog.shared.write("[loom] app-state init servers=\(self.settings.servers.count) default=\(self.settings.defaultServerId?.uuidString ?? "nil") session=\(session.project.title)")

        // Subscribe to the editor's per-keystroke word-count signal
        // and evaluate the active scene against the ledger threshold.
        // (Originally hooked into ProjectSession.didChangeDirtyState
        // on the dirty→clean post-autosave edge, but
        // ProjectSession.scheduleAutoSave is a no-op when url == nil
        // — i.e., untitled in-memory projects never reach the
        // dirty→clean edge, so the coordinator was never called for
        // the most common first-run case. The coordinator's own 2s
        // debounce already handles keystroke-burst collapse, so
        // gating on autosave was both redundant and broken.)
        wordCountObserver = NotificationCenter.default.addObserver(
            forName: EditorViewController.wordCountChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handleWordCountChange(note)
        }
    }

    deinit {
        if let obs = wordCountObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    // MARK: - Ledger suggestion accept/reject (Phase 4 #7 sub-tasks 4+5)

    /// Accept a pending `LedgerSuggestion`: persist the underlying
    /// `KnownFact` onto the resolved character's
    /// `knownFactsBySceneId[sourceSceneId]`, remove the suggestion
    /// from the queue, and post the change notification so the
    /// inspector refreshes. Bible-inspector Suggestions chip wires
    /// its Accept button to this.
    ///
    /// Stale character ids (the user deleted the character before
    /// reviewing the suggestion) are a graceful no-op for the bible
    /// write; the suggestion is still removed from the queue because
    /// the user's intent is "done with this".
    public func acceptLedgerSuggestion(_ suggestion: LedgerSuggestion) {
        if let character = currentSession.project.bible.characters.first(where: { $0.id == suggestion.characterId }) {
            let updated = LedgerSuggestionAcceptor.apply(suggestion, to: character)
            currentSession.updateCharacter(updated)
            DebugLog.shared.write("[ledger] accepted suggestion fact=\(suggestion.fact.id) character=\(suggestion.characterId)")
        } else {
            DebugLog.shared.write("[ledger] accept on stale character=\(suggestion.characterId); dropping suggestion")
        }
        ledgerSuggestionsQueue.remove(factId: suggestion.fact.id)
        NotificationCenter.default.post(
            name: Self.ledgerSuggestionsDidChangeNotification,
            object: self
        )
    }

    /// Reject a pending suggestion: remove it from the queue and
    /// post the change notification. The bible is NOT mutated.
    /// Rejecting doesn't blacklist the fact — the next extraction
    /// may re-surface it, and that's intentional for Phase 4 #7
    /// (a blacklist is a Phase 6 polish concern).
    public func rejectLedgerSuggestion(factId: UUID) {
        ledgerSuggestionsQueue.remove(factId: factId)
        DebugLog.shared.write("[ledger] rejected suggestion fact=\(factId)")
        NotificationCenter.default.post(
            name: Self.ledgerSuggestionsDidChangeNotification,
            object: self
        )
    }

    // MARK: - Phase 9 entity-discovery (proposed-entity acceptance)

    /// Accept a proposed entity from the EntityProposalsQueue webview.
    /// Promotes the proposal to a real Character or Setting in the
    /// bible (with the user's edits applied from `accepted`), attaches
    /// any extracted facts to the Character's `knownFactsBySceneId`
    /// keyed by the proposal's `sourceSceneId`, then removes the
    /// proposal from the on-disk store. No-op on stale proposal id or
    /// in-memory session.
    public func acceptEntityProposal(proposalId: UUID, accepted: ProposedEntityAcceptance) {
        guard let projectURL = currentSession.url else {
            DebugLog.shared.write("[proposals] acceptEntityProposal dropped — in-memory session id=\(proposalId)")
            return
        }
        guard let payload = ProposedEntitiesStore.load(in: projectURL) else {
            DebugLog.shared.write("[proposals] acceptEntityProposal: no store, ignoring id=\(proposalId)")
            return
        }
        guard let proposal = payload.entities.first(where: { $0.id == proposalId }) else {
            DebugLog.shared.write("[proposals] acceptEntityProposal: stale id=\(proposalId)")
            return
        }
        let attachedFacts = payload.facts.first(where: { $0.proposedEntityId == proposalId })?.facts ?? []

        switch proposal.kind {
        case .character:
            // Build Character with edited values + attach facts under
            // the proposal's source scene.
            let knownFacts: [KnownFact] = attachedFacts.map { ef in
                KnownFact(
                    fact: ef.fact,
                    sourceSceneId: proposal.sourceSceneId,
                    certainty: Certainty(rawValue: ef.certainty.rawValue) ?? .asserted
                )
            }
            let character = Character(
                name: accepted.canonicalName,
                aliases: accepted.aliases,
                oneLine: accepted.oneLine,
                knownFactsBySceneId: knownFacts.isEmpty ? [:] : [proposal.sourceSceneId: knownFacts]
            )
            currentSession.addCharacter(character)
            DebugLog.shared.write("[proposals] promoted character id=\(character.id) name=\(accepted.canonicalName) facts=\(knownFacts.count)")
        case .place:
            let setting = Setting(
                name: accepted.canonicalName,
                aliases: accepted.aliases,
                description: accepted.oneLine
            )
            currentSession.addSetting(setting)
            DebugLog.shared.write("[proposals] promoted place id=\(setting.id) name=\(accepted.canonicalName)")
        }
        try? ProposedEntitiesStore.remove(proposalId: proposalId, in: projectURL)
        NotificationCenter.default.post(
            name: Self.proposedEntitiesDidChangeNotification,
            object: self
        )
    }

    /// Reject a proposed entity: drop it from the on-disk store. The
    /// bible is NOT mutated. Rejecting doesn't blacklist — a future
    /// entity-discovery pass may re-surface it (and the user can
    /// reject it again or accept).
    public func rejectEntityProposal(proposalId: UUID) {
        guard let projectURL = currentSession.url else {
            DebugLog.shared.write("[proposals] rejectEntityProposal dropped — in-memory session id=\(proposalId)")
            return
        }
        try? ProposedEntitiesStore.remove(proposalId: proposalId, in: projectURL)
        DebugLog.shared.write("[proposals] rejected id=\(proposalId)")
        NotificationCenter.default.post(
            name: Self.proposedEntitiesDidChangeNotification,
            object: self
        )
    }

    public static let proposedEntitiesDidChangeNotification = Notification.Name("LoomProposedEntitiesDidChange")

    /// Fire the full entity-discovery pipeline against `sceneId` and
    /// append the results to the project's `ProposedEntitiesStore`.
    /// Async — returns immediately; the pipeline takes ~30s and
    /// notifies via `proposedEntitiesDidChangeNotification` on
    /// completion. No-op on in-memory session, missing extractor
    /// profile, or unknown scene id.
    public func runEntityDiscovery(for sceneId: UUID) {
        guard let projectURL = currentSession.url else {
            DebugLog.shared.write("[proposals] runEntityDiscovery dropped — in-memory session")
            return
        }
        guard let profile = settings.extractorServer() else {
            DebugLog.shared.write("[proposals] runEntityDiscovery dropped — no extractor profile configured")
            return
        }
        guard let scene = currentSession.scenes[sceneId] else {
            DebugLog.shared.write("[proposals] runEntityDiscovery dropped — unknown scene id=\(sceneId)")
            return
        }
        // Build known-names from bible characters + settings (with
        // aliases). The extractor expands proper-noun tokens via
        // Fix 4 internally — caller passes the raw list.
        var knownNames: [String] = []
        var existingEntities: [EntityDedupEngine.ExistingEntity] = []
        for c in currentSession.project.bible.characters {
            knownNames.append(c.name)
            knownNames.append(contentsOf: c.aliases)
            existingEntities.append(.init(id: c.id, canonicalName: c.name, aliases: c.aliases))
        }
        for s in currentSession.project.bible.settings {
            knownNames.append(s.name)
            knownNames.append(contentsOf: s.aliases)
            existingEntities.append(.init(id: s.id, canonicalName: s.name, aliases: s.aliases))
        }
        let model = profile.capabilities?.modelName ?? "gemma4_2b:latest"
        let extractor = OllamaEntityDiscoveryExtractor(
            client: OllamaClient(baseURL: profile.baseURL, model: model)
        )
        let embedder = embeddingClientFactory(projectURL)

        DebugLog.shared.write("[proposals] firing entity-discovery: scene=\(sceneId) known=\(knownNames.count) existing=\(existingEntities.count)")
        extractor.extract(
            scenePose: scene.prose,
            sceneId: sceneId,
            knownEntityNames: knownNames,
            existingEntities: existingEntities,
            embedder: embedder
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.handleEntityDiscoveryComplete(projectURL: projectURL, result: result)
            }
        }
    }

    private func handleEntityDiscoveryComplete(
        projectURL: URL,
        result: Result<[EntityDiscovery.ProposedEntity], Error>
    ) {
        switch result {
        case .failure(let err):
            DebugLog.shared.write("[proposals] entity-discovery failed: \(err)")
        case .success(let proposals):
            DebugLog.shared.write("[proposals] entity-discovery produced \(proposals.count) proposals")
            guard !proposals.isEmpty else { return }
            do {
                try ProposedEntitiesStore.append(entities: proposals, facts: [], in: projectURL)
            } catch {
                DebugLog.shared.write("[proposals] failed to persist proposals: \(error)")
                return
            }
            NotificationCenter.default.post(
                name: Self.proposedEntitiesDidChangeNotification,
                object: self
            )
        }
    }

    /// Per-session memo of scenes that have already triggered an
    /// entity-discovery auto-fire. Phase 9 auto-trigger piggybacks on
    /// the ledger-extraction completion (first time only per scene per
    /// session); the user can re-run discovery manually via the Bible
    /// menu after that. Transient — cleared on app relaunch.
    private var sceneEntityDiscoveryFired: Set<UUID> = []

    private func handleExtractionComplete(
        sceneId: UUID,
        result: Result<[LedgerExtraction.ExtractedFact], Error>
    ) {
        // Phase 9 auto-trigger: piggyback on ledger extraction.
        // First time per session per scene only — keeps the user from
        // getting spammed with discovery runs on every 200-word edit.
        // Fires regardless of ledger result (success or failure) so
        // a scene that fails ledger extraction can still get its
        // entity discovery pass.
        if !sceneEntityDiscoveryFired.contains(sceneId) {
            sceneEntityDiscoveryFired.insert(sceneId)
            DebugLog.shared.write("[proposals] auto-firing entity discovery on first ledger event for scene=\(sceneId)")
            runEntityDiscovery(for: sceneId)
        }
        switch result {
        case .failure:
            // The coordinator already wrote a `[ledger] extraction
            // failed` line with the error; the extractor adapter
            // wrote a `[ledger] parse failed raw=...` line if it was
            // a parse error. Don't re-log here — just drop out.
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
            let droppedByDiff = extracted.count - suggestions.count

            // Sub-task 8 — gate the suggestions through the §10.5
            // filter pipeline when an embedder is available. The
            // pipeline is fail-soft on embed errors (returns the
            // input list unchanged), so even a flaky writer server
            // never costs the user a candidate.
            guard let embedder = embedderProvider() else {
                commitSuggestions(
                    suggestions,
                    sceneId: sceneId,
                    extractedCount: extracted.count,
                    droppedByDiff: droppedByDiff,
                    dedupDropped: 0,
                    evidenceDropped: 0,
                    leakageDropped: 0
                )
                return
            }
            let scene = currentSession.scenes[sceneId]
            let sceneSentences = scene.map { SentenceSplitter.split($0.prose) } ?? []
            let existingFactsByCharacter = existingFactsByCharacter(
                for: suggestions,
                bible: bible
            )
            LedgerFilterPipeline.apply(
                embedder: embedder,
                suggestions: suggestions,
                existingFactsByCharacter: existingFactsByCharacter,
                sceneSentences: sceneSentences
            ) { [weak self] result in
                // The pipeline may invoke this on the URLSession queue;
                // hop to main before touching the suggestions queue +
                // posting the notification.
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.commitSuggestions(
                        result.suggestions,
                        sceneId: sceneId,
                        extractedCount: extracted.count,
                        droppedByDiff: droppedByDiff,
                        dedupDropped: result.dedupDropped,
                        evidenceDropped: result.evidenceDropped,
                        leakageDropped: result.leakageDropped
                    )
                }
            }
        }
    }

    /// Build the `[characterId: [factText]]` table the §10.5 dedup
    /// filter compares against. Scoped to characters that appear in
    /// the current batch of suggestions — no point embedding
    /// existing facts for characters whose ledger isn't in play.
    private func existingFactsByCharacter(
        for suggestions: [LedgerSuggestion],
        bible: Bible
    ) -> [UUID: [String]] {
        let activeCharacterIds = Set(suggestions.map(\.characterId))
        var out: [UUID: [String]] = [:]
        for character in bible.characters where activeCharacterIds.contains(character.id) {
            var texts: [String] = []
            for facts in character.knownFactsBySceneId.values {
                for fact in facts { texts.append(fact.fact) }
            }
            if !texts.isEmpty { out[character.id] = texts }
        }
        return out
    }

    private func commitSuggestions(
        _ suggestions: [LedgerSuggestion],
        sceneId: UUID,
        extractedCount: Int,
        droppedByDiff: Int,
        dedupDropped: Int,
        evidenceDropped: Int,
        leakageDropped: Int
    ) {
        let totalFilterDropped = dedupDropped + evidenceDropped + leakageDropped
        let filterBreakdown = "dedup=\(dedupDropped) evidence=\(evidenceDropped) leakage=\(leakageDropped)"
        guard !suggestions.isEmpty else {
            DebugLog.shared.write("[ledger] all candidates filtered out for scene=\(sceneId) extracted=\(extractedCount) diff-dropped=\(droppedByDiff) filter-dropped=\(totalFilterDropped) {\(filterBreakdown)}")
            return
        }
        ledgerSuggestionsQueue.add(suggestions)
        let perCharacterBreakdown: String = {
            var counts: [UUID: Int] = [:]
            for s in suggestions { counts[s.characterId, default: 0] += 1 }
            let parts = counts.compactMap { (id, n) -> String? in
                let name = currentSession.project.bible.characters.first(where: { $0.id == id })?.name ?? id.uuidString.prefix(8).description
                return "\(name)=\(n)"
            }
            return parts.joined(separator: " ")
        }()
        DebugLog.shared.write("[ledger] queued \(suggestions.count) suggestions for scene=\(sceneId) breakdown={\(perCharacterBreakdown)} diff-dropped=\(droppedByDiff) filter-dropped=\(totalFilterDropped)/\(extractedCount) {\(filterBreakdown)}")
        NotificationCenter.default.post(
            name: Self.ledgerSuggestionsDidChangeNotification,
            object: self
        )
    }

    private func handleWordCountChange(_ note: Notification) {
        guard let info = note.userInfo,
              let sceneId = info["sceneId"] as? UUID,
              let wordCount = info["wordCount"] as? Int else { return }
        // The coordinator's 2s debounce collapses bursts: rapid-fire
        // keystroke posts cancel + reschedule, so the extractor only
        // runs once after the user pauses.
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
        reconfigureRetrieval(for: url)
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
        reconfigureRetrieval(for: url)
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
        reconfigureRetrieval(for: url)
        DebugLog.shared.write("[loom] saveAs at=\(url.lastPathComponent)")
    }

    // MARK: - Phase 5 production A1 — style retrieval

    /// Returns a closure suitable for
    /// `GenerationCoordinator.styleRetriever`. The closure resolves
    /// the current `RetrievalService` on every call so the coordinator
    /// — wired once at editor construction — keeps working across
    /// project replacement. Empty `[]` is the no-op result for
    /// in-memory sessions and for graceful retrieval failures.
    public func styleRetriever() -> (String, NarrativeMode?) -> [StyleExemplar] {
        return { [weak self] query, modality in
            guard let self = self, let svc = self.currentRetrievalService else { return [] }
            return (try? svc.retrieve(query: query, modalityFilter: modality, topK: 3)) ?? []
        }
    }

    /// Release the old `RetrievalService` (which drops its Python
    /// subprocess via `PythonEmbeddingClient.deinit`) and install
    /// a fresh one for the given project URL. Called from the three
    /// project-lifecycle entry points: `createProject`, `openProject`,
    /// `saveCurrentSessionAs`.
    private func reconfigureRetrieval(for url: URL) {
        if currentRetrievalService != nil {
            currentRetrievalService = nil
            DebugLog.shared.write("[retrieval] released previous service")
        }
        let client = embeddingClientFactory(url)
        currentRetrievalService = RetrievalService(projectURL: url, dClient: client)
        DebugLog.shared.write("[retrieval] installed service for project=\(url.lastPathComponent) model=\(client.modelId)")
    }

    /// Phase 8.c — default factory now returns a `CoreMLEmbeddingClient`
    /// driving the bundled Wegmann `.mlpackage` via Apple's CoreML
    /// framework. Replaces the Phase 5 Python subprocess path. Cosine
    /// equivalence vs the Python reference was verified at conversion
    /// time within 1e-4 (see Tools/CoreMLProbe/probe_wegmann_coreml.py
    /// + commit history). Existing `.index` sidecars stay valid.
    ///
    /// Fallback: if the bundled mlpackage isn't present (e.g. dev
    /// machine where the Python build script hasn't been run yet),
    /// fall back to `PythonEmbeddingClient` against the venv. The
    /// fallback keeps repo-bootstrap painless — `swift build` works
    /// before the user runs `Tools/CoreMLProbe/build_mlpackage.py`.
    private static let defaultEmbeddingClientFactory: EmbeddingClientFactory = { projectURL in
        if let bundleURL = CoreMLEmbeddingClient.defaultBundleURL() {
            DebugLog.shared.write("[embed-factory] using CoreMLEmbeddingClient at \(bundleURL.lastPathComponent)")
            return CoreMLEmbeddingClient(bundleURL: bundleURL)
        }
        DebugLog.shared.write("[embed-factory] CoreML bundle missing; falling back to PythonEmbeddingClient")
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return PythonEmbeddingClient(
            pythonExecutable: cwd.appendingPathComponent("Tools/RagSpike/Python/.venv/bin/python3"),
            scriptPath: cwd.appendingPathComponent("Tools/RagSpike/Python/embed_st.py"),
            workingDirectory: projectURL
        )
    }

    // MARK: - Phase 5 production A2.1 — reference ingest

    /// Posted on the main queue when an ingest finishes (success or
    /// failure). `userInfo` carries `["referenceId": UUID, "error":
    /// Error?]`. The Bible Workspace listens for this to refresh the
    /// snapshot so chunk counts surface as soon as the index sidecar
    /// is on disk.
    public static let referenceIngestDidFinishNotification = Notification.Name("LoomReference.ingestDidFinish")

    /// Kick off a single-reference ingest on a background queue.
    /// Builds a fresh D `EmbeddingClient` via `embeddingClientFactory`,
    /// wires the production `KoboldNarrativeModeClassifier` against
    /// the current writer server, and runs
    /// `chunkAndEmbedD(referenceId:) + refitAllEVectors()`. On
    /// completion, posts `referenceIngestDidFinishNotification` and
    /// the session's `didChangeNotification` so the snapshot refreshes.
    ///
    /// No-op for in-memory sessions or when no default writer server
    /// is configured (modality classifier can't run without it).
    /// The transient `EmbeddingClient` is dropped at the end of the
    /// closure — its `PythonEmbeddingClient` deinit closes the
    /// subprocess. Phase 5.5 may cache this if the per-ingest cold
    /// start (~7.65s) becomes a UX concern in practice.
    // MARK: - Phase 7 — template scene extraction

    /// Posted on the main queue when a Pass-A beat extraction finishes
    /// (success or failure). `userInfo` carries `["templateId": UUID,
    /// "beatCount": Int?, "error": Error?]`. The Bible Workspace
    /// listens for this to refresh the snapshot so the new
    /// `.beats.json` sidecar surfaces as "N beats" instead of "not
    /// yet extracted."
    public static let templateExtractDidFinishNotification = Notification.Name("LoomTemplate.extractDidFinish")

    /// Kick off Pass A beat extraction for a template scene on a
    /// background queue. Uses the configured extractor server
    /// (Ollama gemma4_2b by default — same server Phase 4's ledger
    /// extractor uses). Posts `templateExtractDidFinishNotification`
    /// + `ProjectSession.didChangeNotification` on completion so the
    /// workspace snapshot refreshes with the new beat count.
    ///
    /// No-op for in-memory sessions or when no extractor server is
    /// configured. The transient `OllamaClient` is dropped at the
    /// end of the closure.
    public func extractTemplateScene(id: UUID) {
        guard let projectURL = currentSession.url else {
            DebugLog.shared.write("[template] extract skipped: in-memory session id=\(id)")
            return
        }
        guard let profile = settings.extractorServer() else {
            DebugLog.shared.write("[template] extract skipped: no extractor server configured id=\(id)")
            return
        }
        // Reject re-entrancy. Double-clicking Extract while a run is
        // in flight is a no-op; the UI also disables the button while
        // the id is in this set.
        guard !extractingTemplateIds.contains(id) else {
            DebugLog.shared.write("[template] extract ignored: already in flight id=\(id)")
            return
        }
        extractingTemplateIds.insert(id)
        // Re-push a snapshot so the React UI flips to "Extracting…"
        // immediately, before the async pipeline call returns.
        NotificationCenter.default.post(
            name: ProjectSession.didChangeNotification,
            object: currentSession
        )
        let model = profile.capabilities?.modelName ?? "gemma4_2b:latest"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let client = OllamaClient(baseURL: profile.baseURL, model: model)
            let extractor = OllamaBeatExtractor(client: client)
            let pipeline = BeatExtractionPipeline(projectURL: projectURL, extractor: extractor)
            pipeline.extractAndPersist(templateId: id) { result in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.extractingTemplateIds.remove(id)
                    var info: [AnyHashable: Any] = ["templateId": id]
                    switch result {
                    case .success(let skeleton):
                        info["beatCount"] = skeleton.beats.count
                        DebugLog.shared.write("[template] extract completed id=\(id) beats=\(skeleton.beats.count)")
                    case .failure(let err):
                        info["error"] = err
                        DebugLog.shared.write("[template] extract failed id=\(id) error=\(err)")
                    }
                    NotificationCenter.default.post(
                        name: Self.templateExtractDidFinishNotification,
                        object: self,
                        userInfo: info
                    )
                    NotificationCenter.default.post(
                        name: ProjectSession.didChangeNotification,
                        object: self.currentSession
                    )
                }
            }
        }
    }

    /// Phase 8.b.2 — unified scene-exemplar ingest. Fans out to both
    /// reference ingest (chunks + Wegmann embed) AND template
    /// extraction (Pass-A skeleton). The Reference and Template must
    /// already exist on disk under the shared UUID (created by
    /// `ProjectSession.addSceneExemplar`).
    ///
    /// Both sub-pipelines fire on independent background queues. Each
    /// posts its own finish notification + a `didChangeNotification`,
    /// so the workspace UI sees state advance as either side completes.
    /// Partial-failure recovery is the §7.2 design contract: if one
    /// sub-pass fails, the other can still land; user re-triggers
    /// ingest to retry the failed side.
    public func ingestSceneExemplar(id: UUID) {
        DebugLog.shared.write("[scene-exemplar] ingest fan-out id=\(id)")
        ingestReference(id: id)
        extractTemplateScene(id: id)
    }

    public func ingestReference(id: UUID) {
        guard let projectURL = currentSession.url else {
            DebugLog.shared.write("[ingest] skipped: in-memory session id=\(id)")
            return
        }
        guard let defaultId = settings.defaultServerId,
              let profile = settings.servers.first(where: { $0.id == defaultId }) else {
            DebugLog.shared.write("[ingest] skipped: no default writer server configured id=\(id)")
            return
        }
        // Phase 8.b.7 — de-dupe in-flight + mark for the React UI.
        // Same pattern extractTemplateScene uses: insert before kicking
        // off the async pipeline, re-push a snapshot so the editor's
        // Ingest button flips to "Ingesting…" immediately.
        guard !ingestingReferenceIds.contains(id) else {
            DebugLog.shared.write("[ingest] ignored: already in flight id=\(id)")
            return
        }
        ingestingReferenceIds.insert(id)
        NotificationCenter.default.post(
            name: ProjectSession.didChangeNotification,
            object: currentSession
        )
        let modalityLLM = KoboldNarrativeModeClassifier.makeClosure(baseURL: profile.baseURL)
        let factory = self.embeddingClientFactory
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let dClient = factory(projectURL)
            let pipeline = ReferenceIngestPipeline(
                projectURL: projectURL,
                chunkSize: 200,
                chunkOverlap: 0,
                dClient: dClient,
                modalityLLM: modalityLLM
            )
            var thrown: Error?
            do {
                _ = try pipeline.chunkAndEmbedD(referenceId: id)
                try pipeline.refitAllEVectors()
                DebugLog.shared.write("[ingest] completed id=\(id)")
            } catch {
                thrown = error
                DebugLog.shared.write("[ingest] failed id=\(id) error=\(error)")
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.ingestingReferenceIds.remove(id)
                var info: [AnyHashable: Any] = ["referenceId": id]
                if let thrown = thrown { info["error"] = thrown }
                NotificationCenter.default.post(
                    name: Self.referenceIngestDidFinishNotification,
                    object: self,
                    userInfo: info
                )
                // Trigger a snapshot refresh by re-pushing didChange.
                // The session itself wasn't mutated, but the disk did
                // — listReferenceSnapshots will now see the .index
                // sidecar.
                NotificationCenter.default.post(
                    name: ProjectSession.didChangeNotification,
                    object: self.currentSession
                )
            }
        }
    }
}

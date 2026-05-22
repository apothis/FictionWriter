import AppKit

/// Sub-step 1.a — minimum viable AppDelegate. Opens a single empty
/// `NSWindow` titled "Loom" and emits a `[loom] launched` debug line.
///
/// The three-pane `NSSplitViewController` (sidebar / editor / inspector)
/// lands in sub-step 1.d once `DesignTokens` is in place. The full menu
/// (File → New Project, Open, Export, etc.) lands incrementally as
/// later sub-steps need entry points; 1.a keeps the standard AppKit
/// menu only so a sane "Quit Loom" is reachable.
public final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var mainWindow: MainWindowController!
    private weak var recentProjectsMenu: NSMenu?
    private var settingsWindow: SettingsWindowController?
    /// Lazy in-app reference help window. Opened via Help → Loom Help
    /// (or ⌘?). One instance per app; survives re-opens.
    private var helpWindow: HelpWindowController?

    /// Last server status observed by the periodic health probe.
    /// Drives edge-only debug logging via
    /// `ServerHealthMonitor.transitionMessage` so a 30s tick doesn't
    /// spam the log with "still reachable" lines.
    private var lastObservedServerStatus: StatusStripView.ServerStatus?

    /// Initial-probe retry budget. Consumed by failures that land
    /// before any successful observation. Once `.unreachable` or
    /// `.reachable` is posted, retries are gated off — the budget is
    /// only there to absorb the macOS TCC settle window at launch.
    private var initialProbeRetriesRemaining: Int = ServerHealthMonitor.initialProbeRetryBudget

    /// 30s periodic health-check timer. Re-issues
    /// `probeAndPublishServerStatus()` so the status-strip dot tracks
    /// drops + reconnects without a generation attempt to discover
    /// them. Mirrors the RPClient health-tick pattern.
    private var healthCheckTimer: Timer?

    /// 30s matches the RPClient cadence — short enough to surface a
    /// drop quickly, long enough that the 5s `/api/v1/model` GET is
    /// noise-floor. Exposed for tests / future tuning.
    public static let healthCheckInterval: TimeInterval = 30

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        DebugLog.shared.write("[loom] launched")
        // Force lazy-init of the app-state singleton so the registry is
        // ready by the time the first generation request fires (1.i).
        _ = AppState.shared

        buildMenu()

        mainWindow = MainWindowController()
        mainWindow.showAndActivate()

        // Probe the configured server (or localhost fallback) once on
        // launch so the status strip dot reflects reachability. The
        // 30s health-check timer picks up drops + reconnects mid-
        // session so the user doesn't only discover an outage at the
        // next generation attempt.
        probeAndPublishServerStatus()
        startServerHealthChecks()
        NotificationCenter.default.addObserver(
            forName: ProjectSession.didReplaceNotification,
            object: AppState.shared.currentSession,
            queue: .main
        ) { [weak self] _ in
            self?.probeAndPublishServerStatus()
        }
    }

    /// Schedule a periodic `probeAndPublishServerStatus()`. Calling
    /// repeatedly is safe — any prior timer is invalidated first.
    private func startServerHealthChecks() {
        healthCheckTimer?.invalidate()
        let timer = Timer.scheduledTimer(
            withTimeInterval: Self.healthCheckInterval, repeats: true
        ) { [weak self] _ in
            self?.probeAndPublishServerStatus()
        }
        // .common keeps the tick alive during modal menu tracking.
        RunLoop.main.add(timer, forMode: .common)
        healthCheckTimer = timer
    }

    private func probeAndPublishServerStatus() {
        let client = AppState.shared.registry.clientForDefault()
        ServerProbe.probe(baseURL: client.baseURL) { [weak self] result in
            DispatchQueue.main.async {
                let status: StatusStripView.ServerStatus
                switch result {
                case .success(let caps):
                    AppState.shared.lastProbedModelName = caps.modelName
                    AppState.shared.lastProbedMaxContext = caps.trueMaxContext
                    // Persist the loaded model onto the writer profile so
                    // instruct-template detection (and the Settings model
                    // field) default to it — no manual entry needed.
                    // Change-guarded, so this is a no-op on most ticks.
                    AppState.shared.refreshWriterCapabilitiesFromProbe(
                        modelName: caps.modelName, trueMaxContext: caps.trueMaxContext
                    )
                    status = .reachable(model: caps.modelName, maxContext: caps.trueMaxContext)
                case .failure(let error):
                    AppState.shared.lastProbedModelName = nil
                    AppState.shared.lastProbedMaxContext = nil
                    // Initial-probe retry burst: when the OS hasn't
                    // yet settled Local Network permission, the first
                    // probe(s) fail with a transport error that looks
                    // identical to a real outage. Stay in `.unknown`
                    // for a short retry burst before committing to
                    // `.unreachable` so the user doesn't see a red
                    // dot for a TCC race.
                    if let self = self,
                       ServerHealthMonitor.shouldRetryInitialProbe(
                           lastObserved: self.lastObservedServerStatus,
                           retriesRemaining: self.initialProbeRetriesRemaining
                       ) {
                        self.initialProbeRetriesRemaining -= 1
                        DebugLog.shared.write(
                            "[health] initial probe failed, retrying in \(ServerHealthMonitor.initialProbeRetryDelay)s "
                            + "(\(self.initialProbeRetriesRemaining) retries left): \(error)"
                        )
                        DispatchQueue.main.asyncAfter(
                            deadline: .now() + ServerHealthMonitor.initialProbeRetryDelay
                        ) { [weak self] in
                            self?.probeAndPublishServerStatus()
                        }
                        return
                    }
                    // The error itself is only useful on the
                    // transition (so the user knows *why* it dropped);
                    // include it in the transition log line.
                    if let message = ServerHealthMonitor.transitionMessage(
                        from: self?.lastObservedServerStatus, to: .unreachable
                    ) {
                        DebugLog.shared.write("\(message) — \(error)")
                    }
                    status = .unreachable
                }
                // Reachable transitions don't carry the error path;
                // log them via the unmodified transition message.
                if case .reachable = status,
                   let message = ServerHealthMonitor.transitionMessage(
                       from: self?.lastObservedServerStatus, to: status
                   ) {
                    DebugLog.shared.write(message)
                }
                self?.lastObservedServerStatus = status
                NotificationCenter.default.post(
                    name: StatusStripView.serverStatusChangedNotification,
                    object: nil,
                    userInfo: ["status": status]
                )
            }
        }
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func buildMenu() {
        let main = NSMenu()

        let appMenuItem = NSMenuItem()
        main.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(
            title: "About Loom",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(showSettings(_:)),
            keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(
            title: "Hide Loom",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"))
        let hideOthers = NSMenuItem(
            title: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(NSMenuItem(
            title: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(
            title: "Quit Loom",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"))
        appMenuItem.submenu = appMenu

        // File menu — 1.j.A.
        let fileMenuItem = NSMenuItem()
        main.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")

        let newProject = NSMenuItem(
            title: "New Project…",
            action: #selector(newProjectClicked),
            keyEquivalent: "n")
        newProject.keyEquivalentModifierMask = [.command, .shift]
        newProject.target = self
        fileMenu.addItem(newProject)

        let newPlannedProject = NSMenuItem(
            title: "New Planned Project…",
            action: #selector(newPlannedProjectClicked),
            keyEquivalent: "")
        newPlannedProject.target = self
        fileMenu.addItem(newPlannedProject)

        let styleLibrary = NSMenuItem(
            title: "Style Library…",
            action: #selector(openStyleLibraryClicked),
            keyEquivalent: "")
        styleLibrary.target = self
        fileMenu.addItem(styleLibrary)

        let openProject = NSMenuItem(
            title: "Open Project…",
            action: #selector(openProjectClicked),
            keyEquivalent: "o")
        openProject.target = self
        fileMenu.addItem(openProject)

        // Open Recent — submenu rebuilt on every menu open so recently-
        // used projects surface in real time as the user creates / opens.
        let openRecent = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let recentSubmenu = NSMenu(title: "Open Recent")
        recentSubmenu.delegate = self
        openRecent.submenu = recentSubmenu
        recentProjectsMenu = recentSubmenu
        fileMenu.addItem(openRecent)

        fileMenu.addItem(NSMenuItem.separator())

        let saveAs = NSMenuItem(
            title: "Save As…",
            action: #selector(saveAsClicked),
            keyEquivalent: "s")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        saveAs.target = self
        fileMenu.addItem(saveAs)

        fileMenu.addItem(NSMenuItem.separator())

        let export = NSMenuItem(
            title: "Export as Markdown…",
            action: #selector(exportMarkdownClicked),
            keyEquivalent: "e")
        export.keyEquivalentModifierMask = [.command, .shift]
        export.target = self
        fileMenu.addItem(export)

        fileMenu.addItem(NSMenuItem.separator())

        let close = NSMenuItem(
            title: "Close",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w")
        fileMenu.addItem(close)

        fileMenuItem.submenu = fileMenu

        // Edit menu — the standard text-editing commands. Without
        // these menu items the Cmd-Z/X/C/V/A key equivalents never
        // reach the responder chain, so undo/cut/copy/paste/select-all
        // only worked via the right-click context menu. Each item has
        // a nil target, so AppKit routes the action to the first
        // responder — the focused NSTextView, WKWebView, NSTextField,
        // etc. — exactly as the system Edit menu does.
        let editMenuItem = NSMenuItem()
        main.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(
            title: "Undo",
            action: Selector(("undo:")),
            keyEquivalent: "z"))
        let redoItem = NSMenuItem(
            title: "Redo",
            action: Selector(("redo:")),
            keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(
            title: "Cut",
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(
            title: "Copy",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(
            title: "Paste",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(
            title: "Delete",
            action: #selector(NSText.delete(_:)),
            keyEquivalent: ""))
        editMenu.addItem(NSMenuItem(
            title: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"))
        editMenuItem.submenu = editMenu

        // View menu — Phase 3 §E adds the Plan view toggle.
        let viewMenuItem = NSMenuItem()
        main.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        let planView = NSMenuItem(
            title: "Plan View",
            action: #selector(showPlanWindow),
            keyEquivalent: "p")
        planView.keyEquivalentModifierMask = [.command, .shift]
        planView.target = self
        viewMenu.addItem(planView)
        viewMenuItem.submenu = viewMenu

        // Bible menu — Phase 4 home for project-content actions
        // (sphiratrioth install today; knowledge-ledger import,
        // lorebook tools as they land).
        let bibleMenuItem = NSMenuItem()
        main.addItem(bibleMenuItem)
        let bibleMenu = NSMenu(title: "Bible")
        let installSph = NSMenuItem(
            title: "Install Sphiratrioth Lorebook Pack",
            action: #selector(installSphiratriothClicked),
            keyEquivalent: "")
        installSph.target = self
        installSph.toolTip = "Adds the curated anti-positive-bias + sticky-scenario + weighted-outcome lorebook entries (LOOM_NSFW §2.5). Safe to re-run."
        bibleMenu.addItem(installSph)
        let rollOutcome = NSMenuItem(
            title: "Roll Outcome…",
            action: #selector(rollOutcomeClicked),
            keyEquivalent: "")
        rollOutcome.target = self
        rollOutcome.toolTip = "Pick a weighted lorebook group; Loom rolls one outcome and seeds it into the tray's per-call instruction field for the next Continue. (LOOM_NSFW §3.5)"
        bibleMenu.addItem(rollOutcome)
        bibleMenu.addItem(.separator())
        let workspace = NSMenuItem(
            title: "Open Bible Workspace…",
            action: #selector(openBibleWorkspaceClicked),
            keyEquivalent: "b")
        workspace.keyEquivalentModifierMask = [.command, .shift]
        workspace.target = self
        workspace.toolTip = "Open the dedicated entity-management window: full character editors, lorebook power-user fields, accepted-facts examiner, suggestions queue. (Phase 4.5 — see LOOM_BIBLE_WORKSPACE.md)"
        bibleMenu.addItem(workspace)
        bibleMenu.addItem(.separator())
        // P2 — project-tools webviews.
        let sceneFraming = NSMenuItem(
            title: "Edit Scene Framing…",
            action: #selector(openSceneFramingClicked),
            keyEquivalent: "")
        sceneFraming.target = self
        sceneFraming.toolTip = "Edit the current scene's framing block — the scenario, dynamic, and intended intensity injected near the cursor at generation time."
        bibleMenu.addItem(sceneFraming)
        let antiSlop = NSMenuItem(
            title: "Edit Anti-slop List…",
            action: #selector(openAntiSlopClicked),
            keyEquivalent: "")
        antiSlop.target = self
        antiSlop.toolTip = "Edit the project's curated anti-slop phrase list."
        bibleMenu.addItem(antiSlop)
        let workFraming = NSMenuItem(
            title: "Edit Work Framing…",
            action: #selector(openWorkFramingClicked),
            keyEquivalent: "")
        workFraming.target = self
        workFraming.toolTip = "Declare the work's dark content elements and your authorial stance on each (AO3 'Dead Dove'–style)."
        bibleMenu.addItem(workFraming)
        bibleMenu.addItem(.separator())
        // Phase 7.b.6 — trigger for the Scene-Template Generation
        // feature. Lives in the Bible menu because it consumes a
        // Template Scene entity (managed via Bible Workspace).
        let writeFromTemplate = NSMenuItem(
            title: "Write Scene From Template…",
            action: #selector(writeSceneFromTemplateClicked),
            keyEquivalent: "")
        writeFromTemplate.target = self
        writeFromTemplate.toolTip = "Generate a new scene using a Template Scene's extracted structural skeleton (beat ordering, modality flow, pacing) but with new characters and content. (Phase 7 — see LOOM_SCENE_TEMPLATE.md)"
        bibleMenu.addItem(writeFromTemplate)
        // Phase 5 — draft the current scene from its outline summary.
        let draftFromOutline = NSMenuItem(
            title: "Draft Scene From Outline",
            action: #selector(draftSceneFromOutlineClicked),
            keyEquivalent: "")
        draftFromOutline.target = self
        draftFromOutline.toolTip = "Draft the current scene's prose from its outline summary — planned beat by beat, in the project's assigned styles. (Phase 5 — Planned Project mode)"
        bibleMenu.addItem(draftFromOutline)
        bibleMenu.addItem(.separator())
        // Phase 9 — manual trigger for the entity-discovery pipeline.
        // Auto-trigger landing later; for now the user invokes per
        // scene from the menu.
        let discoverEntities = NSMenuItem(
            title: "Discover Entities in Current Scene",
            action: #selector(discoverEntitiesClicked),
            keyEquivalent: "")
        discoverEntities.target = self
        discoverEntities.toolTip = "Run the entity-discovery pipeline against the current scene. Proposed characters and places appear in the Bible Workspace under \"Entity proposals\". (Phase 9 — see LOOM_ENTITY_DISCOVERY_SPIKE.md)"
        bibleMenu.addItem(discoverEntities)
        // Phase 10 — manual trigger for relationship discovery.
        let discoverRelationships = NSMenuItem(
            title: "Discover Relationships in Current Scene",
            action: #selector(discoverRelationshipsClicked),
            keyEquivalent: "")
        discoverRelationships.target = self
        discoverRelationships.toolTip = "Run relationship discovery against the current scene. Proposed character relationships are written to the project's proposed-relationships sidecar. (Phase 10)"
        bibleMenu.addItem(discoverRelationships)
        bibleMenuItem.submenu = bibleMenu

        // Help menu — last in the menu bar by macOS convention.
        // Carries the canonical "<App> Help" item; future entries
        // (release notes, report-an-issue, etc.) live here too.
        let helpMenuItem = NSMenuItem()
        main.addItem(helpMenuItem)
        let helpMenu = NSMenu(title: "Help")
        let loomHelp = NSMenuItem(
            title: "Loom Help",
            action: #selector(showHelp(_:)),
            keyEquivalent: "?")
        loomHelp.target = self
        loomHelp.toolTip = "Open the in-app reference help panel (User Help + Technical Reference)."
        helpMenu.addItem(loomHelp)
        helpMenuItem.submenu = helpMenu
        // Tell AppKit this is the application's Help menu so it gets
        // the standard Spotlight-search field at the top + correct
        // automatic positioning.
        NSApp.helpMenu = helpMenu

        NSApp.mainMenu = main
    }

    // MARK: - Bible menu actions (Phase 4)

    @objc private func installSphiratriothClicked() {
        let session = AppState.shared.currentSession
        let added = session.installSphiratriothStarterPack()
        DebugLog.shared.write("[bible] menu: installSphiratriothStarterPack added=\(added)")
        let alert = NSAlert()
        if added == 0 {
            alert.messageText = "Already installed"
            alert.informativeText = "All Sphiratrioth starter-pack entries are already present in this project's lorebook."
        } else {
            alert.messageText = "Installed \(added) Sphiratrioth entr\(added == 1 ? "y" : "ies")"
            alert.informativeText = "Open the lorebook section of the Bible inspector to review or customise the new entries."
        }
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func rollOutcomeClicked() {
        let session = AppState.shared.currentSession
        let groups = LorebookRoller.availableGroups(in: session.project.bible.lorebook)
        guard !groups.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "No outcome groups available"
            alert.informativeText = "Roll-Outcome rolls one entry from a weighted lorebook group. Install the Sphiratrioth starter pack (Bible menu) or add your own grouped lorebook entries with non-zero weights, then try again."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        let chosenGroup: String
        if groups.count == 1 {
            chosenGroup = groups[0]
        } else {
            let picker = NSAlert()
            picker.messageText = "Roll Outcome"
            picker.informativeText = "Pick a weighted lorebook group to roll over."
            for g in groups { picker.addButton(withTitle: g) }
            picker.addButton(withTitle: "Cancel")
            let response = picker.runModal()
            let idx = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
            guard idx >= 0 && idx < groups.count else { return }
            chosenGroup = groups[idx]
        }
        guard let rolled = LorebookRoller.pick(group: chosenGroup, from: session.project.bible.lorebook) else {
            DebugLog.shared.write("[bible] menu: rollOutcome group=\(chosenGroup) result=nil")
            return
        }
        DebugLog.shared.write("[bible] menu: rollOutcome group=\(chosenGroup) entry=\(rolled.name)")
        NotificationCenter.default.post(
            name: AppDelegate.requestRolledOutcomeNotification,
            object: self,
            userInfo: [
                "instruction": rolled.content,
                "group": chosenGroup,
                "entryName": rolled.name
            ]
        )
    }

    /// Posted when the user rolls an outcome from the Bible menu. The
    /// editor observes and loads the rolled content into the tray's
    /// per-call instruction field. The user fires Continue themselves
    /// — Roll-Outcome is a Bible action, not an auto-firing mode.
    public static let requestRolledOutcomeNotification = Notification.Name("LoomBible.requestRolledOutcome")

    // MARK: - Phase 7.b.6 — template-scene generation menu

    @objc private func discoverEntitiesClicked() {
        let session = AppState.shared.currentSession
        guard let sceneId = session.currentSceneId else {
            let alert = NSAlert()
            alert.messageText = "No active scene"
            alert.informativeText = "Open a scene in the editor before running entity discovery."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        // Confirm before firing — pipeline takes ~30s and the user
        // may have invoked accidentally.
        let confirm = NSAlert()
        confirm.messageText = "Run entity discovery on this scene?"
        confirm.informativeText = "The pipeline takes around 30 seconds and runs in the background. New proposed characters and places will appear in the Bible Workspace under \"Entity proposals\" when it finishes."
        confirm.alertStyle = .informational
        confirm.addButton(withTitle: "Run")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        AppState.shared.runEntityDiscovery(for: sceneId)
        let started = NSAlert()
        started.messageText = "Entity discovery started"
        started.informativeText = "Open the Bible Workspace to see results when the pipeline completes (~30 seconds)."
        started.alertStyle = .informational
        started.addButton(withTitle: "OK")
        started.runModal()
    }

    @objc private func discoverRelationshipsClicked() {
        let session = AppState.shared.currentSession
        guard let sceneId = session.currentSceneId else {
            let alert = NSAlert()
            alert.messageText = "No active scene"
            alert.informativeText = "Open a scene in the editor before running relationship discovery."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        if session.project.bible.characters.count < 2 {
            let alert = NSAlert()
            alert.messageText = "Not enough characters"
            alert.informativeText = "Relationship discovery needs at least two characters in the bible. Add characters (or run entity discovery first), then try again."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        let confirm = NSAlert()
        confirm.messageText = "Run relationship discovery on this scene?"
        confirm.informativeText = "The pipeline runs in the background and proposes relationships between the bible's characters as evidenced in this scene."
        confirm.alertStyle = .informational
        confirm.addButton(withTitle: "Run")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        AppState.shared.runRelationshipDiscovery(for: sceneId)
        let started = NSAlert()
        started.messageText = "Relationship discovery started"
        started.informativeText = "Proposed relationships will be written to the project when the pipeline completes."
        started.alertStyle = .informational
        started.addButton(withTitle: "OK")
        started.runModal()
    }

    @objc private func writeSceneFromTemplateClicked() {
        let session = AppState.shared.currentSession
        let templates = session.listTemplateSceneSnapshots()
            .filter { $0.beatCount != nil }
        guard !templates.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "No extracted templates available"
            alert.informativeText = "Add a Template Scene in the Bible Workspace and click Extract to generate its structural skeleton. Once that's on disk, this command can use it."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Write Scene From Template"
        alert.informativeText = """
            Pick a Template Scene to use as the structural blueprint, then describe the new characters / setting / situation. Loom will generate a new scene with the template's beat ordering, modality sequence, pacing, and voice — but with content drawn from your description below.

            The writer renders new prose from the cast/setting description; a few sentences with concrete details work much better than a short label. Three or four lines is usually enough.
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Generate")
        alert.addButton(withTitle: "Cancel")

        // Accessory view: template picker + multi-line cast-mapping text view.
        // Width 480 keeps the alert at a reasonable modal width; the text
        // view is ~8 visible lines so the user has room for several
        // sentences (the writer's quality is sensitive to how much
        // concrete detail is supplied — Phase 7 smoke testing showed
        // 30-char mappings produce invented plot, 200+ char mappings
        // render the user's intended scene).
        let accessoryWidth: CGFloat = 480
        let textViewHeight: CGFloat = 160

        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: accessoryWidth, height: 24))
        for t in templates {
            let beatCount = t.beatCount ?? 0
            picker.addItem(withTitle: "\(t.name) — \(beatCount) beat\(beatCount == 1 ? "" : "s")")
        }
        let pickerLabel = NSTextField(labelWithString: "Template")
        pickerLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)

        // Phase 8.b.x — per-template field persistence. Load state
        // for the initially-selected template + repopulate on picker
        // change. State sidecar lives at
        // `<project>/template-gen-state/<templateId>.json`. Saved on
        // Generate. Per-template so multiple templates remember
        // their own cast / hint / toggle independently.
        let projectURL: URL? = session.url

        let castLabel = NSTextField(labelWithString: "Cast / setting / situation")
        castLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)

        // Real multi-line text area. NSTextField even with usesSingleLineMode
        // = false collapses to a single visible line inside NSAlert; an
        // NSScrollView-wrapped NSTextView gives a proper sized text area
        // with vertical scroll when the content overflows.
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: accessoryWidth, height: textViewHeight))
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.allowsUndo = true
        // Placeholder analogue — NSTextView doesn't have placeholderString
        // natively. Insert grey hint text that the user can simply
        // overwrite. Cleared on the first edit if they don't delete it
        // first.
        let placeholder = """
            e.g. "Maya is a freelance investigator stuck on the 12th floor of an abandoned research tower. Above her, the building's AI is preparing to vent the upper floors. She has six hours of oxygen and a partial schematic. She refuses to evacuate without retrieving the encrypted drive in her dead mentor's office."
            """
        textView.string = placeholder
        textView.textColor = .placeholderTextColor
        // Reset to normal text colour on first focus + clear placeholder.
        let textDelegate = TemplateGenCastMappingPlaceholderDelegate(textView: textView, placeholder: placeholder)
        textView.delegate = textDelegate
        // Keep the delegate alive for the lifetime of the alert.
        objc_setAssociatedObject(textView, &TemplateGenCastMappingPlaceholderDelegate.assocKey, textDelegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: accessoryWidth, height: textViewHeight))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.documentView = textView
        textView.minSize = NSSize(width: 0, height: textViewHeight)
        textView.maxSize = NSSize(width: .greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = .width
        textView.textContainer?.containerSize = NSSize(width: accessoryWidth, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        // Phase 8.b.8 — D4 soft toggle. Default-off matches the locked
        // design (§4 D7); when on, the writer prompt switches from
        // "Do NOT reuse plot/characters/settings/specific events" to a
        // positive-constraint phrasing that lets the source's content
        // register + vocabulary transfer. Character-name leakage is
        // still guarded upstream via STRAP content-stripping at Pass-A.
        let imitateToggle = NSButton(checkboxWithTitle: "Imitate content (preserve source vocabulary + act patterns)", target: nil, action: nil)
        imitateToggle.state = .off
        imitateToggle.toolTip = "When off (default): writer treats the template as a voice exemplar only. When on: writer may carry source vocabulary, content register, and act patterns into the new beat. Use for the NSFW-exemplar case where the cast mapping alone underspecifies the desired content."

        // Phase 8.b.x — optional per-call hint. Mirrors the editor
        // tray's instruction box for Continue/Expand: a free-form
        // line or two of guidance ("skip dialogue this beat",
        // "lean into the tension", "be more explicit") that lands
        // as `[ADDITIONAL INSTRUCTION]` next to the per-beat
        // directive in every writer call.
        let hintLabel = NSTextField(labelWithString: "Additional instructions (optional)")
        hintLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)

        let hintHeight: CGFloat = 60
        let hintTextView = NSTextView(frame: NSRect(x: 0, y: 0, width: accessoryWidth, height: hintHeight))
        hintTextView.isRichText = false
        hintTextView.isAutomaticQuoteSubstitutionEnabled = false
        hintTextView.isAutomaticDashSubstitutionEnabled = false
        hintTextView.isEditable = true
        hintTextView.isSelectable = true
        hintTextView.font = NSFont.systemFont(ofSize: 13)
        hintTextView.allowsUndo = true
        let hintPlaceholder = "e.g. \"lean into the tension; keep dialogue terse\""
        hintTextView.string = hintPlaceholder
        hintTextView.textColor = .placeholderTextColor
        let hintDelegate = TemplateGenCastMappingPlaceholderDelegate(textView: hintTextView, placeholder: hintPlaceholder)
        hintTextView.delegate = hintDelegate
        objc_setAssociatedObject(hintTextView, &TemplateGenCastMappingPlaceholderDelegate.assocKey, hintDelegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        let hintScroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: accessoryWidth, height: hintHeight))
        hintScroll.hasVerticalScroller = true
        hintScroll.hasHorizontalScroller = false
        hintScroll.autohidesScrollers = true
        hintScroll.borderType = .bezelBorder
        hintScroll.documentView = hintTextView
        hintTextView.minSize = NSSize(width: 0, height: hintHeight)
        hintTextView.maxSize = NSSize(width: .greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        hintTextView.isVerticallyResizable = true
        hintTextView.isHorizontallyResizable = false
        hintTextView.autoresizingMask = .width
        hintTextView.textContainer?.containerSize = NSSize(width: accessoryWidth, height: CGFloat.greatestFiniteMagnitude)
        hintTextView.textContainer?.widthTracksTextView = true

        let stack = NSStackView(views: [pickerLabel, picker, castLabel, scroll, hintLabel, hintScroll, imitateToggle])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setFrameSize(NSSize(width: accessoryWidth, height: 24 + textViewHeight + hintHeight + 110))
        // Ensure the scroll views + picker get the full accessory width.
        scroll.widthAnchor.constraint(equalToConstant: accessoryWidth).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: textViewHeight).isActive = true
        hintScroll.widthAnchor.constraint(equalToConstant: accessoryWidth).isActive = true
        hintScroll.heightAnchor.constraint(equalToConstant: hintHeight).isActive = true
        picker.widthAnchor.constraint(equalToConstant: accessoryWidth).isActive = true
        alert.accessoryView = stack

        // Per-template state restore + picker-change handler. Loads
        // the saved state into the fields when the user selects a
        // template. The handler also fires for the initial selection
        // (index 0) below.
        let stateController = TemplateGenMenuStateController(
            templates: templates,
            picker: picker,
            castTextView: textView,
            castPlaceholder: placeholder,
            castPlaceholderDelegate: textDelegate,
            hintTextView: hintTextView,
            hintPlaceholder: hintPlaceholder,
            hintPlaceholderDelegate: hintDelegate,
            imitateToggle: imitateToggle,
            projectURL: projectURL
        )
        picker.target = stateController
        picker.action = #selector(TemplateGenMenuStateController.pickerChanged(_:))
        objc_setAssociatedObject(
            picker, &TemplateGenMenuStateController.assocKey,
            stateController, .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        // Restore for the initial selection (index 0) before the
        // modal runs, so the fields are populated when the alert
        // appears.
        stateController.restoreState(forTemplateIndex: picker.indexOfSelectedItem)

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        let idx = picker.indexOfSelectedItem
        guard idx >= 0, idx < templates.count else { return }
        let chosen = templates[idx]
        // Treat the placeholder string as empty submission.
        let raw = textView.string
        let castMapping = (raw == placeholder ? "" : raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !castMapping.isEmpty else {
            DebugLog.shared.write("[template-gen] menu: cancelled — empty cast mapping")
            return
        }
        let imitateContent = imitateToggle.state == .on
        let rawHint = hintTextView.string
        let extraInstruction = (rawHint == hintPlaceholder ? "" : rawHint)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        DebugLog.shared.write("[template-gen] menu: launching template=\(chosen.name) id=\(chosen.id) castMapping-chars=\(castMapping.count) imitateContent=\(imitateContent) extraInstruction-chars=\(extraInstruction.count)")

        // Phase 8.b.x — persist the just-submitted state so the
        // next open of the menu for this template pre-fills the
        // fields. Save is best-effort; failure is logged but does
        // not block generation.
        if let projectURL = projectURL {
            let state = TemplateGenState(
                castMapping: castMapping,
                extraInstruction: extraInstruction,
                imitateContent: imitateContent,
                savedAt: Date()
            )
            do {
                try TemplateGenStateStore.save(state, templateId: chosen.id, in: projectURL)
            } catch {
                DebugLog.shared.write("[template-gen] state save failed: \(error)")
            }
        }

        NotificationCenter.default.post(
            name: EditorViewController.requestStartTemplateGenerationNotification,
            object: self,
            userInfo: [
                "templateId": chosen.id,
                "castMapping": castMapping,
                "imitateContent": imitateContent,
                "extraInstruction": extraInstruction,
            ]
        )
    }

    // MARK: - Plan window (Phase 3 §E)

    private var planWindow: PlanWindowController?

    @objc private func showPlanWindow() {
        if planWindow == nil {
            planWindow = PlanWindowController(session: AppState.shared.currentSession)
        }
        planWindow?.showAndActivate()
    }

    // MARK: - Bible Workspace window (Phase 4.5 — LOOM_BIBLE_WORKSPACE.md)

    private var bibleWorkspaceWindow: BibleWorkspaceWindowController?

    // MARK: - Planned Project wizard window (LOOM_PLANNED_PROJECT.md §6)

    private var plannedProjectWindow: PlannedProjectWindowController?
    private var styleLibraryWindow: PlannedProjectWindowController?

    @objc private func newPlannedProjectClicked() {
        // A fresh controller each time — the wizard is single-use and
        // closes itself once the project is created.
        plannedProjectWindow = PlannedProjectWindowController(appState: AppState.shared)
        plannedProjectWindow?.showAndActivate()
    }

    @objc private func draftSceneFromOutlineClicked() {
        let session = AppState.shared.currentSession
        guard let sceneId = session.currentSceneId else {
            let alert = NSAlert()
            alert.messageText = "No scene selected"
            alert.informativeText = "Select a scene in the sidebar or Plan view, then draft it from its outline."
            alert.runModal()
            return
        }
        AppState.shared.draftSceneFromOutline(sceneId: sceneId)
    }

    @objc private func openStyleLibraryClicked() {
        // The style library is app-level and editable any time —
        // reachable from the menu, not only inside the wizard. Reuse
        // the window while it's open; a fresh controller after it has
        // been closed (closing may release the window).
        if let existing = styleLibraryWindow, existing.window?.isVisible == true {
            existing.showAndActivate()
            return
        }
        styleLibraryWindow = PlannedProjectWindowController(
            appState: AppState.shared, mode: .styleLibrary
        )
        styleLibraryWindow?.showAndActivate()
    }

    @objc private func openBibleWorkspaceClicked() {
        if bibleWorkspaceWindow == nil {
            bibleWorkspaceWindow = BibleWorkspaceWindowController(
                session: AppState.shared.currentSession,
                appState: AppState.shared
            )
        }
        bibleWorkspaceWindow?.showAndActivate()
    }

    // MARK: - Project-tools windows (P2)

    private var sceneFramingWindow: ProjectToolsWindowController?
    private var antiSlopWindow: ProjectToolsWindowController?

    @objc private func openSceneFramingClicked() {
        let session = AppState.shared.currentSession
        guard let sceneId = session.currentSceneId else {
            let alert = NSAlert()
            alert.messageText = "No scene selected"
            alert.informativeText = "Select a scene in the sidebar, then edit its framing."
            alert.runModal()
            return
        }
        sceneFramingWindow = ProjectToolsWindowController(
            session: session, mode: .sceneFraming(sceneId: sceneId)
        )
        sceneFramingWindow?.showAndActivate()
    }

    @objc private func openAntiSlopClicked() {
        if let existing = antiSlopWindow, existing.window?.isVisible == true {
            existing.showAndActivate()
            return
        }
        antiSlopWindow = ProjectToolsWindowController(
            session: AppState.shared.currentSession, mode: .antiSlop
        )
        antiSlopWindow?.showAndActivate()
    }

    private var workFramingWindow: ProjectToolsWindowController?

    @objc private func openWorkFramingClicked() {
        if let existing = workFramingWindow, existing.window?.isVisible == true {
            existing.showAndActivate()
            return
        }
        workFramingWindow = ProjectToolsWindowController(
            session: AppState.shared.currentSession, mode: .workFraming
        )
        workFramingWindow?.showAndActivate()
    }

    // MARK: - File menu actions

    @objc private func newProjectClicked() {
        let panel = NSSavePanel()
        panel.title = "Create New Loom Project"
        panel.message = "Choose a location for your new .loom project bundle."
        panel.nameFieldStringValue = "MyNovel.loom"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = []
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.tryCreateProject(at: url)
        }
    }

    @objc private func openProjectClicked() {
        let panel = NSOpenPanel()
        panel.title = "Open Loom Project"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.tryOpenProject(at: url)
        }
    }

    @objc private func saveAsClicked() {
        let panel = NSSavePanel()
        panel.title = "Save Loom Project As"
        panel.message = "Choose a location to save this project's .loom bundle."
        let suggested = AppState.shared.currentSession.project.title.isEmpty
            ? "MyNovel.loom"
            : "\(AppState.shared.currentSession.project.title).loom"
        panel.nameFieldStringValue = suggested
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let title = url.deletingPathExtension().lastPathComponent
                try AppState.shared.saveCurrentSessionAs(url: url, title: title)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    @objc private func exportMarkdownClicked() {
        let session = AppState.shared.currentSession
        let panel = NSSavePanel()
        panel.title = "Export Manuscript as Markdown"
        panel.message = "Choose where to save the Markdown export."
        let suggested = session.project.title.isEmpty ? "MyNovel.md" : "\(session.project.title).md"
        panel.nameFieldStringValue = suggested
        panel.canCreateDirectories = true
        panel.allowedContentTypes = []
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let markdown = MarkdownExporter.export(
                project: session.project,
                scenes: session.scenes
            )
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
                DebugLog.shared.write("[storage] exported markdown → \(url.lastPathComponent)")
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    private func tryCreateProject(at url: URL) {
        do {
            let title = url.deletingPathExtension().lastPathComponent
            try AppState.shared.createProject(at: url, title: title)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func tryOpenProject(at url: URL) {
        do {
            try AppState.shared.openProject(at: url)
        } catch {
            // Decode error after the recovery path means the backup
            // was missing OR also corrupt. Surface a clear alert
            // rather than burying the user.
            let alert = NSAlert()
            alert.messageText = "Couldn’t open this project"
            alert.informativeText = "The project at \(url.lastPathComponent) couldn't be loaded.\n\n\(error.localizedDescription)"
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    // MARK: - NSMenuDelegate (Open Recent)

    public func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === recentProjectsMenu else { return }
        menu.removeAllItems()
        let recents = AppState.shared.settings.recentProjectURLs
        if recents.isEmpty {
            let none = NSMenuItem(title: "(empty)", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
            return
        }
        for url in recents {
            let item = NSMenuItem(
                title: url.lastPathComponent,
                action: #selector(recentProjectClicked(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = url
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())
        let clear = NSMenuItem(title: "Clear Menu", action: #selector(clearRecentProjectsClicked), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
    }

    @objc private func recentProjectClicked(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        tryOpenProject(at: url)
    }

    @objc private func clearRecentProjectsClicked() {
        var settings = AppState.shared.settings
        settings.recentProjectURLs = []
        try? AppState.shared.updateSettings(settings)
    }

    @objc func showSettings(_ sender: Any?) {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(appState: AppState.shared)
        }
        settingsWindow?.showAndActivate()
    }

    /// Open (or front) the in-app help panel. App-level — no project
    /// context needed. Lazy-created on first invocation; reused
    /// thereafter so the user's place in the TOC survives close/open.
    @objc func showHelp(_ sender: Any?) {
        if helpWindow == nil {
            helpWindow = HelpWindowController()
        }
        helpWindow?.showWindow(nil)
        helpWindow?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// NSTextView delegate that clears a placeholder string on first focus
/// + restores the normal text colour. Scoped to the
/// `Write Scene From Template` cast-mapping field; held alive via
/// objc_setAssociatedObject on the text view itself so the delegate
/// outlives the alert presentation but is dropped with the view.
private final class TemplateGenCastMappingPlaceholderDelegate: NSObject, NSTextViewDelegate {
    nonisolated(unsafe) static var assocKey: UInt8 = 0
    private weak var textView: NSTextView?
    private let placeholder: String
    private var clearedOnce = false

    init(textView: NSTextView, placeholder: String) {
        self.textView = textView
        self.placeholder = placeholder
    }

    /// Phase 8.b.x — explicitly flip the cleared flag from the
    /// per-template state controller when it pre-fills the field
    /// with persisted text (so subsequent edits aren't re-cleared
    /// to the placeholder).
    func markAsCleared() {
        clearedOnce = true
    }

    /// Reset to the not-yet-cleared state when the controller
    /// repopulates the placeholder (no persisted text for the new
    /// template).
    func markAsNotCleared() {
        clearedOnce = false
    }

    /// Fires BEFORE AppKit's first keystroke is committed to the
    /// text buffer. Using `textShouldBeginEditing` (rather than the
    /// post-edit `textDidBeginEditing`) eliminates a race where the
    /// user's first character was being eaten — observed in the
    /// 2026-05-15 smoke gen-log: cast mapping arrived as "arah is 18"
    /// (leading "S" missing) when the user typed quickly into a
    /// placeholder-active textView.
    func textShouldBeginEditing(_ textObject: NSText) -> Bool {
        guard !clearedOnce, let tv = textView, tv.string == placeholder else { return true }
        clearedOnce = true
        tv.string = ""
        tv.textColor = .labelColor
        return true
    }
}

/// Phase 8.b.x — owns the per-template state-restore logic for the
/// Write-Scene-From-Template NSAlert. Lives for the duration of the
/// modal (associated-object retained by the NSPopUpButton). When the
/// user picks a different template from the popup, fills the cast/
/// hint/imitate-toggle fields from disk (or clears them if no
/// state has been saved yet). Save-on-Generate is handled inline in
/// the caller after the modal returns.
///
/// Not annotated `@MainActor` because AppKit menu actions already
/// run on the main thread; the annotation would push the call sites
/// through MainActor-isolation checks unnecessarily.
private final class TemplateGenMenuStateController: NSObject {
    nonisolated(unsafe) static var assocKey: UInt8 = 0

    private let templates: [SnapshotTemplateScene]
    private let picker: NSPopUpButton
    private let castTextView: NSTextView
    private let castPlaceholder: String
    private let castPlaceholderDelegate: TemplateGenCastMappingPlaceholderDelegate
    private let hintTextView: NSTextView
    private let hintPlaceholder: String
    private let hintPlaceholderDelegate: TemplateGenCastMappingPlaceholderDelegate
    private let imitateToggle: NSButton
    private let projectURL: URL?

    init(
        templates: [SnapshotTemplateScene],
        picker: NSPopUpButton,
        castTextView: NSTextView,
        castPlaceholder: String,
        castPlaceholderDelegate: TemplateGenCastMappingPlaceholderDelegate,
        hintTextView: NSTextView,
        hintPlaceholder: String,
        hintPlaceholderDelegate: TemplateGenCastMappingPlaceholderDelegate,
        imitateToggle: NSButton,
        projectURL: URL?
    ) {
        self.templates = templates
        self.picker = picker
        self.castTextView = castTextView
        self.castPlaceholder = castPlaceholder
        self.castPlaceholderDelegate = castPlaceholderDelegate
        self.hintTextView = hintTextView
        self.hintPlaceholder = hintPlaceholder
        self.hintPlaceholderDelegate = hintPlaceholderDelegate
        self.imitateToggle = imitateToggle
        self.projectURL = projectURL
    }

    @objc func pickerChanged(_ sender: NSPopUpButton) {
        restoreState(forTemplateIndex: sender.indexOfSelectedItem)
    }

    func restoreState(forTemplateIndex idx: Int) {
        guard idx >= 0, idx < templates.count,
              let url = projectURL else {
            applyEmpty()
            return
        }
        let templateId = templates[idx].id
        // loadOrBackfill: sidecar first; falls back to the most recent
        // matching generation-log entry's templateGenerationInfo.
        // Critical for users whose first generations predated the
        // sidecar mechanism — without backfill they see empty fields
        // despite having generated before.
        if let state = TemplateGenStateStore.loadOrBackfill(templateId: templateId, in: url) {
            applyState(state)
        } else {
            applyEmpty()
        }
    }

    private func applyState(_ state: TemplateGenState) {
        // Cast field: persisted text means "user has edited"; bypass
        // placeholder logic + show real-content color.
        castTextView.string = state.castMapping
        castTextView.textColor = .labelColor
        castPlaceholderDelegate.markAsCleared()

        // Hint field: empty string from disk → leave the placeholder
        // visible so the affordance is still discoverable. Otherwise
        // populate.
        if state.extraInstruction.isEmpty {
            hintTextView.string = hintPlaceholder
            hintTextView.textColor = .placeholderTextColor
            hintPlaceholderDelegate.markAsNotCleared()
        } else {
            hintTextView.string = state.extraInstruction
            hintTextView.textColor = .labelColor
            hintPlaceholderDelegate.markAsCleared()
        }

        imitateToggle.state = state.imitateContent ? .on : .off
    }

    private func applyEmpty() {
        castTextView.string = castPlaceholder
        castTextView.textColor = .placeholderTextColor
        castPlaceholderDelegate.markAsNotCleared()
        hintTextView.string = hintPlaceholder
        hintTextView.textColor = .placeholderTextColor
        hintPlaceholderDelegate.markAsNotCleared()
        imitateToggle.state = .off
    }
}

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
        bibleMenuItem.submenu = bibleMenu

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

        let stack = NSStackView(views: [pickerLabel, picker, castLabel, scroll, imitateToggle])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setFrameSize(NSSize(width: accessoryWidth, height: 24 + textViewHeight + 82))
        // Ensure the scroll view + picker get the full accessory width.
        scroll.widthAnchor.constraint(equalToConstant: accessoryWidth).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: textViewHeight).isActive = true
        picker.widthAnchor.constraint(equalToConstant: accessoryWidth).isActive = true
        alert.accessoryView = stack

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
        DebugLog.shared.write("[template-gen] menu: launching template=\(chosen.name) id=\(chosen.id) castMapping-chars=\(castMapping.count) imitateContent=\(imitateContent)")
        NotificationCenter.default.post(
            name: EditorViewController.requestStartTemplateGenerationNotification,
            object: self,
            userInfo: [
                "templateId": chosen.id,
                "castMapping": castMapping,
                "imitateContent": imitateContent,
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

    @objc private func openBibleWorkspaceClicked() {
        if bibleWorkspaceWindow == nil {
            bibleWorkspaceWindow = BibleWorkspaceWindowController(
                session: AppState.shared.currentSession,
                appState: AppState.shared
            )
        }
        bibleWorkspaceWindow?.showAndActivate()
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

    func textDidBeginEditing(_ notification: Notification) {
        guard !clearedOnce, let tv = textView, tv.string == placeholder else { return }
        clearedOnce = true
        tv.string = ""
        tv.textColor = .labelColor
    }
}

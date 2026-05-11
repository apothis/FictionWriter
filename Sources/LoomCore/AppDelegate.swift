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
        // launch so the status strip dot reflects reachability. 1.m
        // ships single-shot probing; periodic re-probe is Phase 2 polish.
        probeAndPublishServerStatus()
        NotificationCenter.default.addObserver(
            forName: ProjectSession.didReplaceNotification,
            object: AppState.shared.currentSession,
            queue: .main
        ) { [weak self] _ in
            self?.probeAndPublishServerStatus()
        }
    }

    private func probeAndPublishServerStatus() {
        let client = AppState.shared.registry.clientForDefault()
        ServerProbe.probe(baseURL: client.baseURL) { result in
            DispatchQueue.main.async {
                let status: StatusStripView.ServerStatus
                switch result {
                case .success(let caps):
                    AppState.shared.lastProbedModelName = caps.modelName
                    AppState.shared.lastProbedMaxContext = caps.trueMaxContext
                    DebugLog.shared.write("[loom] server probe ok: model=\(caps.modelName ?? "?") ctx=\(caps.trueMaxContext.map(String.init) ?? "?")")
                    status = .reachable(model: caps.modelName, maxContext: caps.trueMaxContext)
                case .failure(let error):
                    AppState.shared.lastProbedModelName = nil
                    AppState.shared.lastProbedMaxContext = nil
                    DebugLog.shared.write("[loom] server probe failed: \(error)")
                    status = .unreachable
                }
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

    // MARK: - Plan window (Phase 3 §E)

    private var planWindow: PlanWindowController?

    @objc private func showPlanWindow() {
        if planWindow == nil {
            planWindow = PlanWindowController(session: AppState.shared.currentSession)
        }
        planWindow?.showAndActivate()
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

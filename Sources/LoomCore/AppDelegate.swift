import AppKit

/// Sub-step 1.a — minimum viable AppDelegate. Opens a single empty
/// `NSWindow` titled "Loom" and emits a `[loom] launched` debug line.
///
/// The three-pane `NSSplitViewController` (sidebar / editor / inspector)
/// lands in sub-step 1.d once `DesignTokens` is in place. The full menu
/// (File → New Project, Open, Export, etc.) lands incrementally as
/// later sub-steps need entry points; 1.a keeps the standard AppKit
/// menu only so a sane "Quit Loom" is reachable.
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: MainWindowController!

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

        fileMenu.addItem(NSMenuItem.separator())

        let saveAs = NSMenuItem(
            title: "Save As…",
            action: #selector(saveAsClicked),
            keyEquivalent: "s")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        saveAs.target = self
        fileMenu.addItem(saveAs)

        fileMenu.addItem(NSMenuItem.separator())

        let close = NSMenuItem(
            title: "Close",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w")
        fileMenu.addItem(close)

        fileMenuItem.submenu = fileMenu

        NSApp.mainMenu = main
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
            NSAlert(error: error).runModal()
        }
    }
}

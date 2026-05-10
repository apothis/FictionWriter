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
    private var window: NSWindow!

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        DebugLog.shared.write("[loom] launched")
        // Force lazy-init of the app-state singleton so the registry is
        // ready by the time the first generation request fires (1.i).
        _ = AppState.shared

        buildMenu()

        let frame = NSRect(x: 0, y: 0, width: 1100, height: 720)
        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Loom"
        window.center()
        window.setFrameAutosaveName("Loom.MainWindow")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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

        NSApp.mainMenu = main
    }
}

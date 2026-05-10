import AppKit

/// Lightweight NSWindowController that hosts a SettingsViewController.
/// Window is 640×500, non-fullSizeContentView (so we don't fight
/// AppKit's macOS 26 titlebar-drag-region hijack the way the main
/// editor window does — see MainWindowController commit notes).
public final class SettingsWindowController: NSWindowController {
    public let appState: AppState
    private let settingsVC: SettingsViewController

    public init(appState: AppState) {
        self.appState = appState
        self.settingsVC = SettingsViewController(appState: appState)
        let frame = NSRect(x: 0, y: 0, width: 640, height: 520)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.minSize = NSSize(width: 480, height: 380)
        window.contentViewController = settingsVC
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable) public required init?(coder: NSCoder) { nil }

    public func showAndActivate() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

import AppKit

/// Phase 3 §E — standalone Plan window. Hosts the
/// `PlanViewController` (NSCollectionView card grid). Decoupled
/// from the main window so the NSCollectionView spike doesn't
/// touch the existing 3-pane split layout — if the spike fights
/// AppKit (HANDOFF §11.4 reassess gate), the pivot is contained.
public final class PlanWindowController: NSWindowController {
    public let planVC: PlanViewController
    private var replaceObserver: NSObjectProtocol?

    public init(session: ProjectSession) {
        self.planVC = PlanViewController(session: session)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Plan — \(session.project.title)"
        window.contentViewController = planVC
        window.minSize = NSSize(width: 480, height: 360)
        window.setFrameAutosaveName("Loom.PlanWindow")
        super.init(window: window)

        // Keep the window title in sync when the user opens a
        // different project.
        replaceObserver = NotificationCenter.default.addObserver(
            forName: ProjectSession.didReplaceNotification,
            object: session,
            queue: .main
        ) { [weak self, weak session] _ in
            guard let session = session else { return }
            self?.window?.title = "Plan — \(session.project.title)"
            self?.planVC.reload()
        }
    }

    @available(*, unavailable) public required init?(coder: NSCoder) { nil }

    deinit {
        if let o = replaceObserver { NotificationCenter.default.removeObserver(o) }
    }

    public func showAndActivate() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

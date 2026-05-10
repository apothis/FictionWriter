import AppKit

/// The single Loom project window. Three vertical zones per
/// LOOM_DESIGN_LANGUAGE.md §14.2: toolbar (system, no custom items in
/// Phase 1), workspace (NSSplitViewController three-pane), status strip
/// (1.m polish — placeholder for now).
///
/// Window frame and split-view divider positions persist across launches
/// via NSWindow.setFrameAutosaveName + NSSplitView.autosaveName. The
/// LOOM_PHASE1_EDITOR_MVP.md §4.1.d contract calls for a
/// `~/Library/Application Support/Loom/window-state.json` file, but
/// AppKit's autosaveName covers the same observable behaviour for free
/// (writes go to the app's NSUserDefaults plist). Custom JSON
/// persistence is deferred — sub-step 1.m polish if it matters.
public final class MainWindowController: NSWindowController {
    private let splitVC: NSSplitViewController
    private let statusStrip: StatusStripView
    private var replaceObserver: NSObjectProtocol?
    private var dirtyObserver: NSObjectProtocol?

    public init() {
        let sidebar = SidebarController(session: AppState.shared.currentSession)
        let editor = EditorViewController(session: AppState.shared.currentSession)
        let inspector = InspectorController(session: AppState.shared.currentSession)

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = DesignTokens.Editor.sidebarMinWidth
        sidebarItem.maximumThickness = 360
        sidebarItem.canCollapse = true
        // Stable starting width; user resizes persist via splitView.autosaveName.
        sidebarItem.preferredThicknessFraction = -1
        sidebarItem.holdingPriority = NSLayoutConstraint.Priority(rawValue: 250)

        let editorItem = NSSplitViewItem(viewController: editor)
        editorItem.minimumThickness = 400

        let inspectorItem = NSSplitViewItem(viewController: inspector)
        inspectorItem.minimumThickness = DesignTokens.Editor.inspectorMinWidth
        inspectorItem.maximumThickness = 420
        inspectorItem.canCollapse = true
        // Hold priority higher than the editor pane so divider drags persist
        // after release (without this, NSSplitView uses the editor's hold
        // priority to "settle" the inspector back to its previous width).
        inspectorItem.holdingPriority = NSLayoutConstraint.Priority(rawValue: 251)

        let split = NSSplitViewController()
        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(editorItem)
        split.addSplitViewItem(inspectorItem)
        // Persist divider positions across launches.
        split.splitView.autosaveName = "Loom.MainSplitView"
        self.splitVC = split

        // Status strip pinned at the bottom of the window — full width
        // (1.m §14.8 spec). Sits OUTSIDE the splitVC so it spans across
        // sidebar + editor + inspector.
        let strip = StatusStripView()
        strip.translatesAutoresizingMaskIntoConstraints = false
        self.statusStrip = strip

        let frame = NSRect(
            x: 0, y: 0,
            width: DesignTokens.Editor.sidebarDefaultWidth
                + DesignTokens.Editor.editorMaxWidth
                + DesignTokens.Editor.inspectorDefaultWidth,
            height: 720
        )
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Loom"
        // Restore the previous frame when one is saved AND it lands on a
        // currently-visible screen; otherwise centre. Order matters —
        // setFrameUsingName loads the saved value; setFrameAutosaveName
        // wires up auto-save going forward. (The previous order called
        // center() after setFrameAutosaveName, which clobbered the
        // restored frame on every launch.)
        let restored = window.setFrameUsingName("Loom.MainWindow")
        window.setFrameAutosaveName("Loom.MainWindow")
        if !restored || !Self.isFrameOnVisibleScreen(window.frame) {
            window.center()
        }

        // Compose: splitVC.view above the status strip inside a single
        // contentView. (Replaces the previous direct
        // window.contentViewController = split assignment.)
        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        split.view.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(split.view)
        content.addSubview(strip)
        NSLayoutConstraint.activate([
            split.view.topAnchor.constraint(equalTo: content.topAnchor),
            split.view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            split.view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            split.view.bottomAnchor.constraint(equalTo: strip.topAnchor),
            strip.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            strip.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            strip.heightAnchor.constraint(equalToConstant: 22),
        ])
        window.contentView = content
        // Add the splitVC as a child of a host VC so its lifecycle is
        // honoured (the framework expects child controllers to have a
        // parent).
        let host = NSViewController()
        host.view = content
        host.addChild(split)
        window.contentViewController = host

        super.init(window: window)
        refreshTitleFromSession()
        observeSession()
        DebugLog.shared.write("[loom] main-window opened")
    }

    @available(*, unavailable) public required init?(coder: NSCoder) { nil }

    deinit {
        if let o = replaceObserver { NotificationCenter.default.removeObserver(o) }
        if let o = dirtyObserver { NotificationCenter.default.removeObserver(o) }
    }

    public func showAndActivate() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Sanity check: a saved frame from a previous launch may sit
    /// entirely off the user's current screen layout (laptop without
    /// its external monitor, screen resized, etc.). We accept frames
    /// that have at least 80pt × 80pt of overlap with any visible
    /// screen; smaller fragments fall through to center().
    private static func isFrameOnVisibleScreen(_ frame: NSRect) -> Bool {
        let minOverlap: CGFloat = 80
        for screen in NSScreen.screens {
            let intersection = screen.visibleFrame.intersection(frame)
            if intersection.width >= minOverlap && intersection.height >= minOverlap {
                return true
            }
        }
        return false
    }

    private func observeSession() {
        let session = AppState.shared.currentSession
        replaceObserver = NotificationCenter.default.addObserver(
            forName: ProjectSession.didReplaceNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            self?.refreshTitleFromSession()
        }
        dirtyObserver = NotificationCenter.default.addObserver(
            forName: ProjectSession.didChangeDirtyStateNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            self?.refreshTitleFromSession()
        }
    }

    private func refreshTitleFromSession() {
        guard let window = window else { return }
        let session = AppState.shared.currentSession
        let title = session.project.title.isEmpty ? "Untitled" : session.project.title
        window.title = title
        window.representedURL = session.url
        // Standard macOS document-edited indicator: a dot in the close
        // button. Tracks `isDirty` (clean→dirty and back, via flushSave).
        window.isDocumentEdited = session.isDirty
    }
}

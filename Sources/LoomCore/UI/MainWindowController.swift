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
        // Persist divider positions across launches. The key is
        // versioned so a one-shot stale-state reset is just a key
        // bump — the previous "Loom.MainSplitView" key wrote frames
        // wider than the saved window width and AppKit's autosave
        // re-saved them on each layout, locking us into a narrow-
        // window / clipped-pane state.
        split.splitView.autosaveName = "Loom.MainSplitView.v2"
        self.splitVC = split

        // Status strip pinned at the bottom of the window — full width
        // (1.m §14.8 spec). Sits OUTSIDE the splitVC so it spans across
        // sidebar + editor + inspector.
        let strip = StatusStripView()
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
        // Minimum size so the autosave never catches a degenerate
        // frame (a previous version's autosave caught a 958×1 window
        // because there was no minSize and a transient resize landed
        // in the saved defaults). Anything smaller than this is
        // unusable for fiction prose anyway.
        window.minSize = NSSize(width: 720, height: 480)
        // Restore the previous frame when one is saved AND it lands
        // on a currently-visible screen with a reasonable size.
        // Order matters — setFrameUsingName loads the saved value;
        // setFrameAutosaveName wires up auto-save going forward.
        // (Previous bug: center() was called after setFrameAutosaveName,
        // which clobbered the restored frame on every launch.)
        // Orphan the v1 split-view autosave key — it had stale wider
        // frames than the saved window width, and AppKit kept re-
        // saving them despite manual removeObject calls (the cached
        // values inside AppKit took precedence). Nuking the v1 key
        // outright is the cleanest reset path.
        UserDefaults.standard.removeObject(forKey: "NSSplitView Subview Frames Loom.MainSplitView")

        // Compose splitVC.view + status strip inside a properly
        // subclassed container view-controller (LoomWindowContentVC,
        // declared below). The previous implementation created an
        // ad-hoc NSViewController() and assigned `host.view = content`
        // outside of loadView; the splitVC's layout machinery doesn't
        // resolve correctly under that pattern — the editor pane's
        // view ended up oversized (>1100pt wide × ~940pt tall on a
        // 1280×720 window), so the acceptance overlay rendered
        // visibly but its hit-test bounds fell outside the parent's
        // and clicks went nowhere. The proper subclass loads everything
        // in loadView, which is when AppKit expects the hierarchy +
        // child-VC plumbing to be set up.
        let host = LoomWindowContentVC(splitVC: split, statusStrip: strip)
        // ORDER MATTERS on macOS 26: setting `contentViewController`
        // triggers an auto-refit-to-fittingSize cascade. Wire the
        // contentViewController FIRST, then restore/apply the frame
        // as the last word — that way the cascade fires while the
        // window is at its default frame, and our setFrame is what
        // the user sees. (The cascade itself is then defeated by a
        // required min-height constraint inside the inspector — see
        // InspectorController's listScroll heightAnchor.)
        window.contentViewController = host

        let restored = window.setFrameUsingName("Loom.MainWindow")
        window.setFrameAutosaveName("Loom.MainWindow")
        let restoredFrame = window.frame
        let isUsable = restored
            && Self.isFrameOnVisibleScreen(restoredFrame)
            && restoredFrame.width >= 600
            && restoredFrame.height >= 400
        if !isUsable {
            DebugLog.shared.write("[loom] window: restoring default frame (saved=\(restored ? "\(restoredFrame)" : "none"))")
            window.setFrame(frame, display: false)
            window.center()
            UserDefaults.standard.removeObject(forKey: "NSSplitView Subview Frames Loom.MainSplitView.v2")
        } else {
            DebugLog.shared.write("[loom] window: restored frame \(restoredFrame)")
        }

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
    /// Parse the saved NSSplitView subview frames string and return
    /// the total width across all panes. Format example:
    /// "0,0,188,458,NO,NO\n188,0,564,458,NO,NO\n753,0,240,458,NO,NO".
    /// Returns 0 if parsing fails — the caller treats that as "no
    /// stale data to worry about."
    private static func parseSplitFramesTotalWidth(_ raw: String) -> CGFloat {
        var total: CGFloat = 0
        for line in raw.split(separator: "\n") {
            let parts = line.split(separator: ",")
            guard parts.count >= 3,
                  let width = Double(parts[2].trimmingCharacters(in: .whitespaces))
            else { continue }
            total += CGFloat(width)
        }
        return total
    }

    /// Parse the saved NSWindow frame string (e.g.
    /// "460 780 720 480 0 0 2560 1410") and return the window width.
    /// Returns 0 if parsing fails.
    private static func parseSavedWindowWidth(_ raw: String) -> CGFloat {
        let parts = raw.split(separator: " ")
        guard parts.count >= 3, let width = Double(parts[2]) else { return 0 }
        return CGFloat(width)
    }

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

/// Window-level content controller. Hosts the three-pane splitVC + the
/// bottom status strip and owns their layout. Loaded properly as an
/// NSViewController subclass — its `loadView` constructs the hierarchy
/// AND adds the splitVC as a child VC, which is what AppKit expects
/// for the splitVC's layout machinery to resolve correctly.
final class LoomWindowContentVC: NSViewController {
    let splitVC: NSSplitViewController
    let statusStrip: StatusStripView

    init(splitVC: NSSplitViewController, statusStrip: StatusStripView) {
        self.splitVC = splitVC
        self.statusStrip = statusStrip
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    override func loadView() {
        let content = NSView()
        addChild(splitVC)
        let splitView = splitVC.view
        splitView.translatesAutoresizingMaskIntoConstraints = false
        statusStrip.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(splitView)
        content.addSubview(statusStrip)
        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: content.topAnchor),
            splitView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: statusStrip.topAnchor),
            statusStrip.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            statusStrip.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            statusStrip.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            statusStrip.heightAnchor.constraint(equalToConstant: 22),
        ])
        self.view = content
    }
}

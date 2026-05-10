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
        window.center()
        window.setFrameAutosaveName("Loom.MainWindow")
        window.contentViewController = split

        super.init(window: window)
        DebugLog.shared.write("[loom] main-window opened")
    }

    @available(*, unavailable) public required init?(coder: NSCoder) { nil }

    public func showAndActivate() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

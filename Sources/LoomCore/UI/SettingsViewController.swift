import AppKit

/// Settings UI tabs (Phase 2). Two tabs:
///   - `.servers` — list of `ServerProfile`s; add/edit/delete/promote default.
///   - `.project` — current project's memory, author's note, depth lines,
///     context/reply token budgets.
public enum SettingsTab: Equatable {
    case servers
    case project
}

/// Top-level settings view controller. Embeds two child VCs and
/// switches between them via a recessed-button tab row matching the
/// Inspector pane's pattern (which IS clickable post the macOS 26
/// fullSizeContentView fix — but the Settings window doesn't use
/// fullSizeContentView, so we can also flip back to NSSegmentedControl
/// later. The button-row pattern is at least known-good).
public final class SettingsViewController: NSViewController {
    public let appState: AppState
    public private(set) var serversTabVC: ServersTabViewController!
    public private(set) var projectTabVC: ProjectSettingsTabViewController!
    public private(set) var currentTab: SettingsTab = .servers

    private var tabButtons: [SettingsTab: NSButton] = [:]
    private var contentContainer: NSView!
    private var currentChildVC: NSViewController?

    public init(appState: AppState) {
        self.appState = appState
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) public required init?(coder: NSCoder) { nil }

    public override func loadView() {
        let container = ThemedBackgroundView(backgroundColor: DesignTokens.Background.window)

        let serversBtn = NSButton(title: "Servers", target: self, action: #selector(showServersTab))
        let projectBtn = NSButton(title: "Project", target: self, action: #selector(showProjectTab))
        for b in [serversBtn, projectBtn] {
            b.bezelStyle = .recessed
            b.setButtonType(.pushOnPushOff)
            b.controlSize = .regular
            b.font = DesignTokens.Typography.headline
            b.translatesAutoresizingMaskIntoConstraints = false
        }
        tabButtons[.servers] = serversBtn
        tabButtons[.project] = projectBtn

        let tabRow = NSStackView(views: [serversBtn, projectBtn])
        tabRow.orientation = .horizontal
        tabRow.spacing = DesignTokens.Spacing.xs
        tabRow.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        contentContainer = content

        container.addSubview(tabRow)
        container.addSubview(content)
        NSLayoutConstraint.activate([
            tabRow.topAnchor.constraint(equalTo: container.topAnchor, constant: DesignTokens.Spacing.md),
            tabRow.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            content.topAnchor.constraint(equalTo: tabRow.bottomAnchor, constant: DesignTokens.Spacing.md),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        serversTabVC = ServersTabViewController(appState: appState)
        projectTabVC = ProjectSettingsTabViewController(session: AppState.shared.currentSession)
        // NOTE: ProjectSettingsTabViewController binds to the
        // app's current session — when the user switches projects,
        // the existing session object is mutated in place (via
        // didReplaceNotification), so the same reference stays valid.

        self.view = container
        showTab(.servers)
    }

    @objc private func showServersTab() { showTab(.servers) }
    @objc private func showProjectTab() { showTab(.project) }

    public func showTab(_ tab: SettingsTab) {
        currentTab = tab
        for (key, button) in tabButtons {
            button.state = (key == tab) ? .on : .off
        }
        let vc: NSViewController = (tab == .servers) ? serversTabVC : projectTabVC
        if currentChildVC === vc { return }
        if let prev = currentChildVC {
            prev.view.removeFromSuperview()
            prev.removeFromParent()
        }
        addChild(vc)
        contentContainer.addSubview(vc.view)
        vc.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            vc.view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            vc.view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            vc.view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            vc.view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
        currentChildVC = vc
    }
}

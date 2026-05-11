import AppKit

/// Servers tab in the Settings window. Lists configured kobold
/// profiles with Add / Remove / Set Default buttons. Mutations
/// round-trip through `AppState.updateSettings(_:)` which both
/// persists to `settings.json` and refreshes the
/// `KoboldClientRegistry`.
///
/// UI is minimum-viable: an NSTableView of name + URL + a "(default)"
/// indicator, plus a strip of action buttons. Per-profile edit
/// happens via a sheet (Phase 2 polish) — initial version edits
/// inline via the "Add Server…" sheet only.
public final class ServersTabViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    public let appState: AppState
    private var tableView: NSTableView!
    private var addButton: NSButton!
    private var removeButton: NSButton!
    private var setDefaultButton: NSButton!
    private var observer: NSObjectProtocol?

    public init(appState: AppState) {
        self.appState = appState
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) public required init?(coder: NSCoder) { nil }

    deinit {
        if let o = observer { NotificationCenter.default.removeObserver(o) }
    }

    public override func loadView() {
        let container = ThemedBackgroundView(backgroundColor: DesignTokens.Background.window)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .lineBorder

        let table = NSTableView()
        table.translatesAutoresizingMaskIntoConstraints = false
        table.headerView = nil
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = true
        table.style = .inset
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ServerColumn"))
        col.title = "Server"
        col.resizingMask = .autoresizingMask
        table.addTableColumn(col)
        table.dataSource = self
        table.delegate = self
        scroll.documentView = table
        tableView = table

        addButton = NSButton(title: "Add Server…", target: self, action: #selector(addClicked))
        removeButton = NSButton(title: "Remove", target: self, action: #selector(removeClicked))
        setDefaultButton = NSButton(title: "Set as Default", target: self, action: #selector(setDefaultClicked))
        for b in [addButton!, removeButton!, setDefaultButton!] {
            b.bezelStyle = .rounded
            b.controlSize = .regular
            b.font = DesignTokens.Typography.subheadline
            b.translatesAutoresizingMaskIntoConstraints = false
        }

        let buttonRow = NSStackView(views: [addButton, removeButton, setDefaultButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = DesignTokens.Spacing.sm
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(scroll)
        container.addSubview(buttonRow)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: container.topAnchor, constant: DesignTokens.Spacing.md),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: DesignTokens.Spacing.md),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -DesignTokens.Spacing.md),
            scroll.bottomAnchor.constraint(equalTo: buttonRow.topAnchor, constant: -DesignTokens.Spacing.sm),

            buttonRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: DesignTokens.Spacing.md),
            buttonRow.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -DesignTokens.Spacing.md),
        ])

        self.view = container
        refreshButtons()
    }

    // MARK: - Public mutation surface (tested via Phase2SettingsControllerMountTests)

    /// Add a server with the given name and base URL. Validates that
    /// the name is non-empty (caller is expected to also verify the
    /// URL parses, since `URL` non-optional input already guarantees
    /// well-formed). On success: appends to AppSettings.servers,
    /// auto-promotes to default if the list was previously empty,
    /// persists via `AppState.updateSettings`.
    public func addServer(name: String, baseURL: URL) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ServersTabError.emptyName
        }
        var settings = appState.settings
        let profile = ServerProfile(name: trimmed, baseURL: baseURL)
        settings.addServer(profile)
        try appState.updateSettings(settings)
        tableView?.reloadData()
        refreshButtons()
        // Phase 2 follow-on (HANDOFF §9.2) — kick off an auto-probe so
        // capabilities + lastProbed populate without waiting for the
        // user's first generation. Async; failure is silent (the user
        // can re-probe by hitting Test).
        autoProbeAsync(profileId: profile.id, baseURL: baseURL)
    }

    private func autoProbeAsync(profileId: UUID, baseURL: URL) {
        DebugLog.shared.write("[servers] auto-probe starting: \(baseURL.absoluteString)")
        ServerProbe.probe(baseURL: baseURL) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let caps):
                    let updated = AutoProbe.applyResult(
                        caps,
                        lastProbed: Date(),
                        to: profileId,
                        in: self.appState.settings
                    )
                    try? self.appState.updateSettings(updated)
                    self.tableView?.reloadData()
                    DebugLog.shared.write("[servers] auto-probe ok: \(caps.modelName ?? "?")")
                case .failure(let err):
                    DebugLog.shared.write("[servers] auto-probe failed: \(err)")
                }
            }
        }
    }

    /// Remove a server by id, persist, refresh.
    public func removeServer(id: UUID) throws {
        var settings = appState.settings
        settings.removeServer(id: id)
        try appState.updateSettings(settings)
        tableView?.reloadData()
        refreshButtons()
    }

    /// Promote a server to default, persist, refresh.
    public func setDefault(id: UUID) throws {
        var settings = appState.settings
        guard settings.setDefault(id: id) else {
            throw ServersTabError.unknownId
        }
        try appState.updateSettings(settings)
        tableView?.reloadData()
        refreshButtons()
    }

    public enum ServersTabError: Error {
        case emptyName
        case unknownId
    }

    // MARK: - Button handlers

    @objc private func addClicked() {
        // Phase 2 minimum-viable: show a sheet with name+URL fields.
        // Defer the sheet implementation to a follow-up; for now
        // just present an NSAlert with an accessory view.
        presentAddServerSheet()
    }

    @objc private func removeClicked() {
        let row = tableView.selectedRow
        guard row >= 0, row < appState.settings.servers.count else { return }
        let id = appState.settings.servers[row].id
        try? removeServer(id: id)
    }

    @objc private func setDefaultClicked() {
        let row = tableView.selectedRow
        guard row >= 0, row < appState.settings.servers.count else { return }
        let id = appState.settings.servers[row].id
        try? setDefault(id: id)
    }

    private func presentAddServerSheet() {
        // Simple alert-with-accessory pattern (vs a full NSPanel) —
        // minimum-viable for Phase 2.
        let alert = NSAlert()
        alert.messageText = "Add Server"
        alert.informativeText = "Name and base URL for the new kobold endpoint."
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = DesignTokens.Spacing.sm
        stack.translatesAutoresizingMaskIntoConstraints = false
        let nameField = NSTextField()
        nameField.placeholderString = "Name (e.g. \"Home\")"
        nameField.translatesAutoresizingMaskIntoConstraints = false
        let urlField = NSTextField()
        urlField.placeholderString = "http://192.168.1.201:5001"
        urlField.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(nameField)
        stack.addArrangedSubview(urlField)
        nameField.widthAnchor.constraint(equalToConstant: 300).isActive = true
        urlField.widthAnchor.constraint(equalToConstant: 300).isActive = true
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 60))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        alert.accessoryView = container

        guard let window = view.window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            guard let url = URL(string: urlField.stringValue) else { return }
            try? self?.addServer(name: nameField.stringValue, baseURL: url)
        }
    }

    private func refreshButtons() {
        let hasSelection = tableView.selectedRow >= 0
        removeButton.isEnabled = hasSelection
        setDefaultButton.isEnabled = hasSelection
    }

    // MARK: - NSTableViewDataSource / Delegate

    public func numberOfRows(in tableView: NSTableView) -> Int {
        appState.settings.servers.count
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("ServerCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? {
            let v = NSTableCellView()
            v.identifier = identifier
            let label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = DesignTokens.Typography.body
            v.addSubview(label)
            v.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: DesignTokens.Spacing.xs),
                label.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -DesignTokens.Spacing.xs),
                label.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            ])
            return v
        }()
        let profile = appState.settings.servers[row]
        let isDefault = (profile.id == appState.settings.defaultServerId)
        let suffix = isDefault ? "  (default)" : ""
        cell.textField?.stringValue = "\(profile.name) — \(profile.baseURL.absoluteString)\(suffix)"
        return cell
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        refreshButtons()
    }
}

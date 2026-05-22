import AppKit

/// Servers tab in the Settings window. Lists configured backend
/// profiles with Add / Remove / Set Default / Set as Extractor
/// buttons. Mutations round-trip through `AppState.updateSettings(_:)`
/// which both persists to `settings.json` and refreshes the
/// `KoboldClientRegistry`.
///
/// Phase 4 #7 sub-task 1 added a `ServerKind` discriminator to
/// support role-routing: the writer (Kobold) drives Continue/Expand/
/// Rewrite, the extractor (Ollama running gemma4_2b) drives the
/// post-scene knowledge-ledger side-call.
public final class ServersTabViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    public let appState: AppState
    private var tableView: NSTableView!
    private var addButton: NSButton!
    private var removeButton: NSButton!
    private var setDefaultButton: NSButton!
    private var setExtractorButton: NSButton!
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
        setExtractorButton = NSButton(title: "Set as Extractor", target: self, action: #selector(setExtractorClicked))
        for b in [addButton!, removeButton!, setDefaultButton!, setExtractorButton!] {
            b.bezelStyle = .rounded
            b.controlSize = .regular
            b.font = DesignTokens.Typography.subheadline
            b.translatesAutoresizingMaskIntoConstraints = false
        }

        let buttonRow = NSStackView(views: [addButton, removeButton, setDefaultButton, setExtractorButton])
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

    // MARK: - Public mutation surface (tested via Phase2/Phase4 wiring suites)

    /// Add a server with the given name, base URL, and kind. Defaults
    /// to `.kobold` so legacy callers (Phase 2 sheet path before the
    /// Phase 4 #7 kind picker landed) keep working. On success:
    /// appends to AppSettings.servers, auto-promotes to default if
    /// the list was previously empty, persists via
    /// `AppState.updateSettings`, kicks off a kind-aware auto-probe.
    public func addServer(name: String, baseURL: URL, kind: ServerKind = .kobold, model: String? = nil) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ServersTabError.emptyName
        }
        let trimmedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines)
        var settings = appState.settings
        let profile = ServerProfile(
            name: trimmed,
            baseURL: baseURL,
            kind: kind,
            model: (trimmedModel?.isEmpty ?? true) ? nil : trimmedModel
        )
        settings.addServer(profile)
        try appState.updateSettings(settings)
        tableView?.reloadData()
        refreshButtons()
        // Phase 2 follow-on (HANDOFF §9.2) — auto-probe so capabilities
        // + lastProbed populate without waiting for the user's first
        // generation. Phase 4 #7: route by `kind` (kobold → ServerProbe,
        // ollama → OllamaProbe). Async; failure is silent.
        autoProbeAsync(profileId: profile.id, baseURL: baseURL, kind: kind)
    }

    private func autoProbeAsync(profileId: UUID, baseURL: URL, kind: ServerKind) {
        DebugLog.shared.write("[servers] auto-probe starting: \(kind.rawValue) \(baseURL.absoluteString)")
        switch kind {
        case .kobold:
            ServerProbe.probe(baseURL: baseURL) { [weak self] result in
                DispatchQueue.main.async {
                    self?.applyProbeOutcome(profileId: profileId, result: result.mapError { $0 as Error })
                }
            }
        case .ollama:
            OllamaProbe.probe(baseURL: baseURL) { [weak self] result in
                DispatchQueue.main.async {
                    self?.applyProbeOutcome(profileId: profileId, result: result.mapError { $0 as Error })
                }
            }
        }
    }

    private func applyProbeOutcome(profileId: UUID, result: Result<ServerCapabilities, Error>) {
        switch result {
        case .success(let caps):
            let updated = AutoProbe.applyResult(
                caps,
                lastProbed: Date(),
                to: profileId,
                in: appState.settings
            )
            try? appState.updateSettings(updated)
            tableView?.reloadData()
            DebugLog.shared.write("[servers] auto-probe ok: \(caps.modelName ?? "?")")
        case .failure(let err):
            DebugLog.shared.write("[servers] auto-probe failed: \(err)")
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

    /// Designate the extractor profile. Pass `nil` to clear the role.
    /// Throws `unknownId` when a non-nil id doesn't match an existing
    /// server (defensive — the UI only enables the button when a row
    /// is selected, but a stale id could slip through across windows).
    public func setExtractor(id: UUID?) throws {
        var settings = appState.settings
        guard settings.setExtractor(id: id) else {
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

    @objc private func setExtractorClicked() {
        let row = tableView.selectedRow
        if row >= 0, row < appState.settings.servers.count {
            let profile = appState.settings.servers[row]
            if appState.settings.extractorServerId == profile.id {
                try? setExtractor(id: nil)   // toggle off
            } else {
                try? setExtractor(id: profile.id)
            }
        } else {
            // No row selected (macOS-26 inset-style click can leave the
            // visual highlight in place without registering selection on
            // the delegate). Fall back to designating the first Ollama-
            // kind profile — that's almost always what the user means
            // when they click this button in the Phase 4 #7 flow.
            setExtractorViaFallbackForTest()
        }
    }

    /// Test-visible fallback used both by the no-selection click path
    /// and by the dedicated suite that pins the behaviour.
    public func setExtractorViaFallbackForTest() {
        guard let ollama = appState.settings.servers.first(where: { $0.kind == .ollama }) else { return }
        try? setExtractor(id: ollama.id)
    }

    private func presentAddServerSheet() {
        let alert = NSAlert()
        alert.messageText = "Add Server"
        alert.informativeText = "Name, base URL, and kind for the new backend endpoint."
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

        // Kind picker — segmented control, Kobold default. Switching
        // updates the URL placeholder so the user sees the Ollama
        // default port (11434) without typing.
        let kindPicker = NSSegmentedControl(labels: ["Kobold (writer)", "Ollama (extractor)"], trackingMode: .selectOne, target: nil, action: nil)
        kindPicker.translatesAutoresizingMaskIntoConstraints = false
        kindPicker.selectedSegment = 0
        kindPicker.target = self
        kindPicker.action = #selector(kindPickerChanged(_:))
        // Model field — the explicit model this endpoint uses. For
        // Ollama it pins the extractor model (a multi-model install
        // otherwise resolves to "first in /api/tags", which could be an
        // embedding model). For Kobold it informs instruct-template
        // detection. Optional — blank falls back to the probe.
        let modelField = NSTextField()
        modelField.placeholderString = "Model (optional, e.g. \"gemma4_2b:latest\")"
        modelField.translatesAutoresizingMaskIntoConstraints = false
        modelField.tag = 97

        // Tag the URL field so the action handler can find it.
        urlField.tag = 99
        // Stash the kindPicker as accessible via tag too.
        kindPicker.tag = 98

        stack.addArrangedSubview(nameField)
        stack.addArrangedSubview(urlField)
        stack.addArrangedSubview(kindPicker)
        stack.addArrangedSubview(modelField)
        nameField.widthAnchor.constraint(equalToConstant: 320).isActive = true
        urlField.widthAnchor.constraint(equalToConstant: 320).isActive = true
        kindPicker.widthAnchor.constraint(equalToConstant: 320).isActive = true
        modelField.widthAnchor.constraint(equalToConstant: 320).isActive = true

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 132))
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
            let kind: ServerKind = kindPicker.selectedSegment == 1 ? .ollama : .kobold
            try? self?.addServer(name: nameField.stringValue, baseURL: url, kind: kind, model: modelField.stringValue)
        }
    }

    @objc private func kindPickerChanged(_ sender: NSSegmentedControl) {
        // Walk siblings to find the URL field by tag and update the
        // placeholder for the user's convenience.
        guard let parent = sender.superview else { return }
        for v in parent.subviews where v.tag == 99 {
            if let tf = v as? NSTextField {
                tf.placeholderString = sender.selectedSegment == 1
                    ? "http://localhost:11434"
                    : "http://192.168.1.201:5001"
            }
        }
    }

    private func refreshButtons() {
        // Enable whenever there's at least one row. macOS-26's
        // `style = .inset` NSTableView shows a visual selection pill
        // on click but doesn't reliably propagate to the delegate's
        // `tableViewSelectionDidChange`, leaving a visually-selected
        // row paired with disabled buttons — confusing dead-end. The
        // click handlers now validate at action time and fall back
        // sensibly when `selectedRow == -1`.
        let hasRows = !appState.settings.servers.isEmpty
        removeButton.isEnabled = hasRows
        setDefaultButton.isEnabled = hasRows
        setExtractorButton.isEnabled = hasRows
        // Update the extractor button's label so the toggle behaviour
        // is visible: "Set as Extractor" / "Clear Extractor". Reads
        // from current selection when valid, else from whether *any*
        // ollama profile is currently the extractor.
        let row = tableView.selectedRow
        if row >= 0, row < appState.settings.servers.count,
           appState.settings.servers[row].id == appState.settings.extractorServerId {
            setExtractorButton.title = "Clear Extractor"
        } else {
            setExtractorButton.title = "Set as Extractor"
        }
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
        let isExtractor = (profile.id == appState.settings.extractorServerId)
        var roleTags: [String] = []
        if isDefault { roleTags.append("writer") }
        if isExtractor { roleTags.append("extractor") }
        let suffix = roleTags.isEmpty ? "" : "  (\(roleTags.joined(separator: ", ")))"
        let kindTag = profile.kind == .ollama ? " [Ollama]" : ""
        cell.textField?.stringValue = "\(profile.name)\(kindTag) — \(profile.baseURL.absoluteString)\(suffix)"
        return cell
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        refreshButtons()
    }
}

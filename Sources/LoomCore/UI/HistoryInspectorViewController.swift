import AppKit

/// History tab — pages over `<project>/generation-log/*.json`. Each
/// entry renders as a row with a one-line summary; clicking the row
/// expands an inline panel showing chiclets + the full assembled
/// prompt + the raw response.
///
/// Phase 1.k ships the read path: rows + expansion. The write path
/// runs from GenerationCoordinator. Re-roll (resending the recorded
/// prompt) is 1.m polish per the contract; "Insert again" works in
/// 1.k since it's a one-line operation against the editor's text view.
public final class HistoryInspectorViewController: NSViewController {
    public let session: ProjectSession
    private var stack: NSStackView!
    private var emptyStateLabel: NSTextField!
    private var expansionState = HistoryExpansionState()
    private let logStore = GenerationLogStore()
    private var entries: [GenerationLogEntry] = []
    private var observers: [NSObjectProtocol] = []

    public init(session: ProjectSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) public required init?(coder: NSCoder) { nil }

    deinit {
        for o in observers { NotificationCenter.default.removeObserver(o) }
    }

    public override func loadView() {
        let container = NSView()
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        let stack = FlippedStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = DesignTokens.Spacing.sm
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(
            top: DesignTokens.Spacing.md,
            left: DesignTokens.Spacing.md,
            bottom: DesignTokens.Spacing.md,
            right: DesignTokens.Spacing.md
        )

        let empty = NSTextField(labelWithString: "No generations yet.")
        empty.font = DesignTokens.Typography.body
        empty.textColor = DesignTokens.Foreground.secondary
        empty.alignment = .center
        empty.translatesAutoresizingMaskIntoConstraints = false
        emptyStateLabel = empty
        stack.addArrangedSubview(empty)

        scroll.documentView = stack
        container.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: container.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.widthAnchor),
        ])

        self.stack = stack
        self.view = container

        // Refresh on log writes + project replace (open / new).
        observers.append(NotificationCenter.default.addObserver(
            forName: GenerationCoordinator.didWriteLogEntryNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reload()
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: ProjectSession.didReplaceNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            self?.expansionState.collapseAll()
            self?.reload()
        })

        reload()
    }

    public func reload() {
        guard let stack = stack else { return }
        // Drop everything except the empty-state placeholder.
        for view in stack.arrangedSubviews where view !== emptyStateLabel {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if let url = session.url {
            entries = logStore.list(in: url)
        } else {
            entries = []
        }

        emptyStateLabel.isHidden = !entries.isEmpty
        for entry in entries {
            let row = HistoryEntryRowView(
                entry: entry,
                isExpanded: expansionState.isExpanded(entry.id),
                onToggle: { [weak self] in
                    self?.expansionState.toggle(entry.id)
                    self?.reload()
                },
                onInsertAgain: { [weak self] in
                    self?.insertResponseAtCursor(entry)
                },
                onPushPastRefusal: { [weak self] in
                    self?.postContinueFromRefusal()
                }
            )
            row.view.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(row.view)
            row.view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -2 * DesignTokens.Spacing.md).isActive = true
        }
    }

    private func insertResponseAtCursor(_ entry: GenerationLogEntry) {
        // Post a notification the editor can listen to. Loose coupling
        // — History inspector doesn't hold an editor reference.
        NotificationCenter.default.post(
            name: HistoryInspectorViewController.requestInsertAgainNotification,
            object: self,
            userInfo: ["text": entry.response.rawText]
        )
    }

    public static let requestInsertAgainNotification = Notification.Name("LoomHistoryInspector.requestInsertAgain")

    // MARK: - Continue from refusal (Phase 4 §14.1 #7 / LOOM_NSFW §5)

    /// Posted when the user clicks "Push past refusal" on a refusal-
    /// flagged History row. Editor handles by inserting the stub at
    /// cursor + loading the breaking instruction into the tray; user
    /// fires Continue from there.
    public static let requestContinueFromRefusalNotification = Notification.Name("LoomHistoryInspector.requestContinueFromRefusal")

    /// Single source of truth for the userInfo payload — the editor
    /// pulls `stub` + `instruction` out without reaching back to the
    /// row's internals.
    public static func makeContinueFromRefusalUserInfo() -> [AnyHashable: Any] {
        return [
            "stub": RefusalContinuation.continuationStub,
            "instruction": RefusalContinuation.breakingInstruction
        ]
    }

    fileprivate func postContinueFromRefusal() {
        NotificationCenter.default.post(
            name: HistoryInspectorViewController.requestContinueFromRefusalNotification,
            object: self,
            userInfo: HistoryInspectorViewController.makeContinueFromRefusalUserInfo()
        )
    }
}

// MARK: - Row view

/// One generation-log row + its expandable panel. Stored as a class
/// reference so the row's button targets stay alive.
final class HistoryEntryRowView {
    let entry: GenerationLogEntry
    let view: NSView
    private let onToggle: () -> Void
    private let onInsertAgain: () -> Void
    private let onPushPastRefusal: () -> Void

    /// Pure predicate: should the "Push past refusal" affordance be
    /// rendered on this entry? Exposed for tests so the UI shape can
    /// be verified without driving AppKit.
    public static func shouldShowPushPastRefusal(_ entry: GenerationLogEntry) -> Bool {
        return entry.response.refusalDetected
    }

    init(
        entry: GenerationLogEntry,
        isExpanded: Bool,
        onToggle: @escaping () -> Void,
        onInsertAgain: @escaping () -> Void,
        onPushPastRefusal: @escaping () -> Void = {}
    ) {
        self.entry = entry
        self.onToggle = onToggle
        self.onInsertAgain = onInsertAgain
        self.onPushPastRefusal = onPushPastRefusal

        let container = ThemedBackgroundView(backgroundColor: DesignTokens.Background.group)
        container.layer?.cornerRadius = DesignTokens.Radius.section

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = DesignTokens.Spacing.sm
        header.translatesAutoresizingMaskIntoConstraints = false

        let disclosure = NSButton(
            title: isExpanded ? "▾" : "▸",
            target: nil,
            action: nil
        )
        disclosure.bezelStyle = .inline
        disclosure.controlSize = .small
        disclosure.font = DesignTokens.Typography.subheadline

        let summary = NSTextField(labelWithString: Self.summaryString(for: entry))
        summary.font = DesignTokens.Typography.subheadline
        summary.textColor = DesignTokens.Foreground.primary
        summary.lineBreakMode = .byTruncatingTail

        header.addArrangedSubview(disclosure)
        header.addArrangedSubview(summary)
        // Refusal chip — yellow pill when the response looks like a
        // model refusal (per RefusalDetector). Signal-not-block:
        // Loom never blocks the insertion, just flags it visually.
        if entry.response.refusalDetected {
            let chip = NSTextField(labelWithString: "refusal?")
            chip.font = DesignTokens.Typography.caption2
            chip.textColor = DesignTokens.Foreground.warning
            chip.wantsLayer = true
            chip.layer?.backgroundColor = DesignTokens.Foreground.warning
                .withAlphaComponent(0.15).cgColor
            chip.layer?.cornerRadius = DesignTokens.Radius.chip
            chip.drawsBackground = false
            chip.isBezeled = false
            chip.isEditable = false
            header.addArrangedSubview(chip)
        }
        header.addArrangedSubview(NSView())  // spacer

        container.addSubview(header)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor, constant: DesignTokens.Spacing.sm),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: DesignTokens.Spacing.sm),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -DesignTokens.Spacing.sm),
        ])

        if isExpanded {
            let panel = Self.makeExpandedPanel(
                entry: entry,
                insertAgain: onInsertAgain,
                pushPastRefusal: onPushPastRefusal
            )
            panel.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(panel)
            NSLayoutConstraint.activate([
                panel.topAnchor.constraint(equalTo: header.bottomAnchor, constant: DesignTokens.Spacing.sm),
                panel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: DesignTokens.Spacing.sm),
                panel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -DesignTokens.Spacing.sm),
                panel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -DesignTokens.Spacing.sm),
            ])
        } else {
            header.bottomAnchor.constraint(
                equalTo: container.bottomAnchor,
                constant: -DesignTokens.Spacing.sm
            ).isActive = true
        }

        self.view = container

        // Bridge — wire actions after init.
        let bridge = HistoryRowBridge(row: self)
        objc_setAssociatedObject(container, &HistoryRowBridge.key, bridge, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        disclosure.target = bridge
        disclosure.action = #selector(HistoryRowBridge.disclosureClicked(_:))

        // Header click also toggles — make container clickable.
        let click = NSClickGestureRecognizer(target: bridge, action: #selector(HistoryRowBridge.disclosureClicked(_:)))
        container.addGestureRecognizer(click)
    }

    fileprivate func emitToggle() { onToggle() }
    fileprivate func emitInsertAgain() { onInsertAgain() }

    /// Pure formatter: how the entry's row label reads. Template gens
    /// are discriminated by `templateGenerationInfo` rather than `mode`
    /// (which is stamped as a least-wrong `.continueProse` for those
    /// entries) — when present, the template name takes precedence.
    /// Exposed for tests.
    public static func summaryString(for entry: GenerationLogEntry) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        let timeStr = f.string(from: entry.timestamp)
        let label: String
        if let info = entry.templateGenerationInfo {
            label = "Template: \(info.templateName)"
        } else {
            switch entry.mode {
            case .continueProse: label = "Continue"
            case .expand:        label = "Expand"
            case .rewrite:       label = "Rewrite"
            default:             label = entry.mode.rawValue
            }
        }
        let proseTok = entry.promptAssembly.promptTokens
        let replyTok = entry.response.completionTokens
        return "\(timeStr) · \(label) · \(proseTok)↑ \(replyTok)↓"
    }

    private static func makeExpandedPanel(
        entry: GenerationLogEntry,
        insertAgain: @escaping () -> Void,
        pushPastRefusal: @escaping () -> Void
    ) -> NSView {
        let panel = NSStackView()
        panel.orientation = .vertical
        panel.alignment = .leading
        panel.spacing = DesignTokens.Spacing.sm

        // Chiclet labels — comma-separated for compactness in Phase 1.
        // Phase 2 polish renders true chip-style flow.
        let chicletLabels = entry.promptAssembly.contextChiclets
            .map { "\($0.label) (\($0.tokenCount))" }
            .joined(separator: " · ")
        let chicletLine = NSTextField(labelWithString: "Sent: \(chicletLabels)")
        chicletLine.font = DesignTokens.Typography.caption1
        chicletLine.textColor = DesignTokens.Foreground.secondary
        chicletLine.lineBreakMode = .byWordWrapping
        chicletLine.maximumNumberOfLines = 0
        panel.addArrangedSubview(chicletLine)

        // Cache + eviction summary.
        var cacheText = "Cache: above=\(entry.promptAssembly.aboveCacheTokens) below=\(entry.promptAssembly.belowCacheTokens)"
        if !entry.promptAssembly.evictedLayers.isEmpty {
            cacheText += " · evicted=\(entry.promptAssembly.evictedLayers.joined(separator: ","))"
        }
        cacheText += " · template=\(entry.promptAssembly.template.rawValue)"
        let cacheLine = NSTextField(labelWithString: cacheText)
        cacheLine.font = DesignTokens.Typography.mono(.caption1)
        cacheLine.textColor = DesignTokens.Foreground.secondary
        panel.addArrangedSubview(cacheLine)

        // Full prompt — scrollable text view.
        let promptHeading = NSTextField(labelWithString: "Full prompt:")
        promptHeading.font = DesignTokens.Typography.headline
        promptHeading.textColor = DesignTokens.Foreground.primary
        panel.addArrangedSubview(promptHeading)
        panel.addArrangedSubview(makeReadOnlyTextScroll(text: entry.promptAssembly.fullPrompt, height: 120))

        // Response — also scrollable.
        let respHeading = NSTextField(labelWithString: "Response:")
        respHeading.font = DesignTokens.Typography.headline
        respHeading.textColor = DesignTokens.Foreground.primary
        panel.addArrangedSubview(respHeading)
        panel.addArrangedSubview(makeReadOnlyTextScroll(text: entry.response.rawText, height: 100))

        // Insert-again button.
        let insertBtn = NSButton(title: "Insert again at cursor", target: nil, action: nil)
        insertBtn.bezelStyle = .inline
        insertBtn.controlSize = .small
        insertBtn.font = DesignTokens.Typography.subheadline
        let bridge = HistoryRowExpandBridge(insertAgain: insertAgain, pushPastRefusal: pushPastRefusal)
        objc_setAssociatedObject(insertBtn, &HistoryRowExpandBridge.key, bridge, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        insertBtn.target = bridge
        insertBtn.action = #selector(HistoryRowExpandBridge.insertClicked(_:))
        panel.addArrangedSubview(insertBtn)

        // "Push past refusal" — only when the entry was flagged as a
        // refusal. LOOM_NSFW §5: load a refusal-breaking instruction
        // into the tray + drop an em-dash anchor at cursor; the user
        // fires Continue themselves.
        if HistoryEntryRowView.shouldShowPushPastRefusal(entry) {
            let pushBtn = NSButton(title: "Push past refusal", target: nil, action: nil)
            pushBtn.bezelStyle = .inline
            pushBtn.controlSize = .small
            pushBtn.font = DesignTokens.Typography.subheadline
            pushBtn.toolTip = "Drop an em-dash anchor and a refusal-breaking instruction; you fire Continue."
            pushBtn.target = bridge
            pushBtn.action = #selector(HistoryRowExpandBridge.pushPastClicked(_:))
            panel.addArrangedSubview(pushBtn)
        }

        return panel
    }

    private static func makeReadOnlyTextScroll(text: String, height: CGFloat) -> NSView {
        let tv = NSTextView()
        tv.string = text
        tv.isEditable = false
        tv.isRichText = false
        tv.drawsBackground = true
        tv.backgroundColor = DesignTokens.Background.textInput
        tv.font = DesignTokens.Typography.mono(.caption1)
        tv.textColor = DesignTokens.Foreground.primary
        tv.textContainerInset = NSSize(width: DesignTokens.Spacing.sm, height: DesignTokens.Spacing.sm)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .lineBorder
        scroll.documentView = tv
        scroll.heightAnchor.constraint(equalToConstant: height).isActive = true
        return scroll
    }
}

private final class HistoryRowBridge: NSObject {
    static var key: UInt8 = 0
    weak var row: HistoryEntryRowView?
    init(row: HistoryEntryRowView) { self.row = row }
    @objc func disclosureClicked(_ sender: Any) { row?.emitToggle() }
}

private final class HistoryRowExpandBridge: NSObject {
    static var key: UInt8 = 0
    let insertAgain: () -> Void
    let pushPastRefusal: () -> Void
    init(insertAgain: @escaping () -> Void, pushPastRefusal: @escaping () -> Void) {
        self.insertAgain = insertAgain
        self.pushPastRefusal = pushPastRefusal
    }
    @objc func insertClicked(_ sender: Any) { insertAgain() }
    @objc func pushPastClicked(_ sender: Any) { pushPastRefusal() }
}

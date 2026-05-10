import AppKit

/// Bottom-of-window status strip per LOOM_DESIGN_LANGUAGE.md §14.8.
/// 22pt strip with three regions:
///   - leading: project word count (current scene) — monospace
///   - centre: cursor scene title (Phase 2 polish — Phase 1 left blank)
///   - trailing: server status indicator (green/yellow/red) — monospace
///
/// Listens for two notifications:
///   - EditorViewController.wordCountChangedNotification: updates the
///     leading word-count label with the count for the active scene
///   - LoomServerStatusChanged: changes the trailing dot's colour
///
/// Server probing fires on app launch + on session.url change. A real
/// periodic-probe scheme is Phase 2+ polish.
public final class StatusStripView: NSView {
    public static let serverStatusChangedNotification = Notification.Name("LoomStatusStrip.serverStatusChanged")

    public enum ServerStatus: Equatable {
        case unknown
        /// `model` is the raw `/api/v1/model` response; `maxContext` is
        /// the value returned by `/api/extra/true_max_context_length`.
        /// Both included in the strip so the user can see at a glance
        /// that the probe round-tripped both endpoints — that's the
        /// difference between "the network reached the host" and
        /// "kobold is actually responding to the API."
        case reachable(model: String?, maxContext: Int?)
        case unreachable
    }

    private let wordCountLabel: NSTextField
    private let sceneLabel: NSTextField
    private let serverDot: NSView
    private let serverLabel: NSTextField
    private var observers: [NSObjectProtocol] = []

    public override init(frame frameRect: NSRect) {
        wordCountLabel = NSTextField(labelWithString: "0 words")
        sceneLabel = NSTextField(labelWithString: "")
        serverDot = NSView()
        serverLabel = NSTextField(labelWithString: "—")
        super.init(frame: frameRect)
        configure()
        observers.append(NotificationCenter.default.addObserver(
            forName: EditorViewController.wordCountChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let count = note.userInfo?["wordCount"] as? Int else { return }
            self?.setWordCount(count)
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: Self.serverStatusChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let status = note.userInfo?["status"] as? ServerStatus else { return }
            self?.setServerStatus(status)
        })
    }

    @available(*, unavailable) public required init?(coder: NSCoder) { nil }

    deinit {
        for o in observers { NotificationCenter.default.removeObserver(o) }
    }

    private func configure() {
        wantsLayer = true
        layer?.backgroundColor = DesignTokens.Background.window.cgColor

        let topDivider = NSBox()
        topDivider.boxType = .separator
        topDivider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topDivider)

        wordCountLabel.font = DesignTokens.Typography.mono(.caption1)
        wordCountLabel.textColor = DesignTokens.Foreground.secondary
        wordCountLabel.translatesAutoresizingMaskIntoConstraints = false

        sceneLabel.font = DesignTokens.Typography.caption1
        sceneLabel.textColor = DesignTokens.Foreground.secondary
        sceneLabel.translatesAutoresizingMaskIntoConstraints = false

        serverDot.translatesAutoresizingMaskIntoConstraints = false
        serverDot.wantsLayer = true
        serverDot.layer?.cornerRadius = 4
        serverDot.layer?.backgroundColor = DesignTokens.Foreground.secondary.cgColor

        serverLabel.font = DesignTokens.Typography.mono(.caption1)
        serverLabel.textColor = DesignTokens.Foreground.secondary
        serverLabel.translatesAutoresizingMaskIntoConstraints = false
        // Truncate-middle if the model name is genuinely too long for
        // the available width. Avoids dropping the ctx number (which
        // sits at the end of the string) when the window is narrow.
        serverLabel.lineBreakMode = .byTruncatingMiddle
        serverLabel.usesSingleLineMode = true
        // Allow the label to expand horizontally as needed; word-count
        // (leading) is small and the centre scene-title is empty in
        // Phase 1, so there's plenty of room.
        serverLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(wordCountLabel)
        addSubview(sceneLabel)
        addSubview(serverDot)
        addSubview(serverLabel)

        NSLayoutConstraint.activate([
            topDivider.topAnchor.constraint(equalTo: topAnchor),
            topDivider.leadingAnchor.constraint(equalTo: leadingAnchor),
            topDivider.trailingAnchor.constraint(equalTo: trailingAnchor),
            topDivider.heightAnchor.constraint(equalToConstant: 1),

            wordCountLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DesignTokens.Spacing.md),
            wordCountLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            sceneLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            sceneLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            serverLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DesignTokens.Spacing.md),
            serverLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            // Don't overrun the word-count label on narrow windows.
            // serverDot sits to the left of the serverLabel, so this
            // covers the dot too.
            serverLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: wordCountLabel.trailingAnchor,
                constant: DesignTokens.Spacing.md + 12   // +12 leaves room for the dot
            ),

            serverDot.trailingAnchor.constraint(equalTo: serverLabel.leadingAnchor, constant: -DesignTokens.Spacing.xs),
            serverDot.centerYAnchor.constraint(equalTo: centerYAnchor),
            serverDot.widthAnchor.constraint(equalToConstant: 8),
            serverDot.heightAnchor.constraint(equalToConstant: 8),
        ])

        setWordCount(0)
        setServerStatus(.unknown)
    }

    public func setWordCount(_ count: Int) {
        wordCountLabel.stringValue = "\(count) words"
    }

    public func setActiveSceneTitle(_ title: String?) {
        sceneLabel.stringValue = title ?? ""
    }

    public func setServerStatus(_ status: ServerStatus) {
        switch status {
        case .unknown:
            serverDot.layer?.backgroundColor = DesignTokens.Foreground.secondary.cgColor
            serverLabel.stringValue = "no server"
        case .reachable(let model, let maxContext):
            serverDot.layer?.backgroundColor = DesignTokens.Foreground.success.cgColor
            // Strip the redundant `koboldcpp/` runtime prefix that the
            // server reports in the model name — leaves the actual
            // model identifier (e.g. "Qwen3.6-27B-..." instead of
            // "koboldcpp/Qwen3.6-27B-...").
            let cleanedModel = (model ?? "").replacingOccurrences(of: "koboldcpp/", with: "")
            let modelPart = cleanedModel.isEmpty ? "ok" : cleanedModel
            let ctxPart = maxContext.map { "\($0) ctx" } ?? "?"
            serverLabel.stringValue = "\(modelPart) · \(ctxPart)"
        case .unreachable:
            serverDot.layer?.backgroundColor = DesignTokens.Foreground.destructive.cgColor
            serverLabel.stringValue = "unreachable"
        }
    }
}

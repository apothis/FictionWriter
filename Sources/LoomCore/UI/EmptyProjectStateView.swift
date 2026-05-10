import AppKit

/// Empty-project placeholder per LOOM_DESIGN_LANGUAGE.md §14.7.
///
/// Centred 96pt SF Symbol `book.closed.fill` in `tertiaryLabelColor`,
/// project title in `title2`, and a single `Create the first scene`
/// button. The button posts a notification the embedding controller
/// (EditorViewController) intercepts to call session.addScene().
///
/// Replaces the NSTextView when `EmptyProjectState.shouldShow(in:)`
/// is true; the editor swaps back to the text view as soon as a scene
/// is selected.
public final class EmptyProjectStateView: NSView {
    public static let createSceneClickedNotification = Notification.Name("LoomEmptyProjectState.createSceneClicked")

    private let titleLabel: NSTextField

    public override init(frame frameRect: NSRect) {
        titleLabel = NSTextField(labelWithString: "")
        super.init(frame: frameRect)
        configure()
    }

    @available(*, unavailable) public required init?(coder: NSCoder) { nil }

    private func configure() {
        wantsLayer = true
        layer?.backgroundColor = DesignTokens.Background.textInput.cgColor

        let symbol = NSImageView()
        symbol.translatesAutoresizingMaskIntoConstraints = false
        if let image = NSImage(systemSymbolName: "book.closed.fill", accessibilityDescription: nil) {
            symbol.image = image
            symbol.symbolConfiguration = .init(pointSize: 96, weight: .regular)
            symbol.contentTintColor = DesignTokens.Foreground.tertiary
        }

        titleLabel.font = DesignTokens.Typography.title2
        titleLabel.textColor = DesignTokens.Foreground.primary
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let button = NSButton(title: "Create the first scene", target: nil, action: nil)
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.font = DesignTokens.Typography.headline
        button.translatesAutoresizingMaskIntoConstraints = false
        button.target = self
        button.action = #selector(buttonClicked)

        let stack = NSStackView(views: [symbol, titleLabel, button])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = DesignTokens.Spacing.lg
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    public func setProjectTitle(_ title: String) {
        titleLabel.stringValue = title.isEmpty ? "Untitled" : title
    }

    @objc private func buttonClicked() {
        NotificationCenter.default.post(
            name: Self.createSceneClickedNotification,
            object: self
        )
    }
}

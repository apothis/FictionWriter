import AppKit

/// Titlebar-attached acceptance bar (Phase 2 polish on top of Phase 1's
/// merged-tray fallback). Three buttons — Accept ⏎ / Reject ⌫ /
/// Keep & Redo ⌘⇧R — slide into the titlebar area when generation
/// finishes, slide out when the acceptance window closes.
///
/// Picked NSTitlebarAccessoryViewController over the previous
/// floating-subview pattern because the accessory is hosted by the
/// window's titlebar machinery — clicks route through AppKit's
/// standard titlebar hit-testing, which (unlike the editor pane's
/// subview tree, which had oversized-container pathologies during
/// Phase 1) is structurally bulletproof.
///
/// `layoutAttribute = .top` puts the bar BELOW the titlebar, spanning
/// the full window width. The bar is hidden by default; the editor
/// flips `isHidden` when the acceptance machine moves to / leaves
/// the .awaiting state.
public final class AcceptanceTitlebarAccessory: NSTitlebarAccessoryViewController {
    public var onAccept: (() -> Void)?
    public var onReject: (() -> Void)?
    public var onRedo: (() -> Void)?

    private let acceptButton: NSButton
    private let rejectButton: NSButton
    private let keepRedoButton: NSButton

    public init() {
        acceptButton = Self.makeButton(title: "Accept ⏎")
        rejectButton = Self.makeButton(title: "Reject ⌫")
        keepRedoButton = Self.makeButton(title: "Keep & Redo ⌘⇧R")
        super.init(nibName: nil, bundle: nil)
        self.layoutAttribute = .top
        // isHidden is set in loadView (see below); setting it here,
        // before the view is loaded, did not stick on macOS 26.
    }

    @available(*, unavailable) public required init?(coder: NSCoder) { nil }

    private static func makeButton(title: String) -> NSButton {
        let b = LoomActionButton(title: title, target: nil, action: nil)
        b.bezelStyle = .rounded
        b.controlSize = .regular
        b.font = DesignTokens.Typography.headline
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }

    public override func loadView() {
        let host = NSView()
        host.wantsLayer = true
        host.layer?.backgroundColor = DesignTokens.Background.window.cgColor

        let stack = NSStackView(views: [acceptButton, rejectButton, keepRedoButton])
        stack.orientation = .horizontal
        stack.spacing = DesignTokens.Spacing.sm
        stack.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(stack)

        // Bottom divider — visually separates the bar from the editor
        // content below, matching the tray's top-divider treatment.
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(divider)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: host.topAnchor, constant: DesignTokens.Spacing.xs),
            stack.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -DesignTokens.Spacing.xs),
            stack.centerXAnchor.constraint(equalTo: host.centerXAnchor),

            divider.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),
        ])

        acceptButton.target = self
        acceptButton.action = #selector(acceptClicked)
        rejectButton.target = self
        rejectButton.action = #selector(rejectClicked)
        keepRedoButton.target = self
        keepRedoButton.action = #selector(redoClicked)

        // Height pin: button-height + vertical padding. The accessory
        // controller honours the view's intrinsic content size.
        self.view = host
        let height: CGFloat = 36
        host.heightAnchor.constraint(equalToConstant: height).isActive = true
        // isHidden is set by the editor AFTER addTitlebarAccessoryViewController
        // — AppKit resets isHidden during attachment, so setting it
        // anywhere inside the accessory (init or loadView) does not stick.
    }

    /// Slide the bar in. Editor calls this when the acceptance machine
    /// moves to .awaiting (post-generation).
    public func show() {
        if isHidden {
            isHidden = false
            DebugLog.shared.write("[editor] acceptance bar: shown")
        }
    }

    /// Slide the bar out. Editor calls this when the user
    /// accepts/rejects/redoes or types implicitly.
    public func hide() {
        if !isHidden {
            isHidden = true
            DebugLog.shared.write("[editor] acceptance bar: hidden")
        }
    }

    @objc private func acceptClicked() {
        DebugLog.shared.write("[gen] acceptance bar: accept clicked")
        onAccept?()
    }

    @objc private func rejectClicked() {
        DebugLog.shared.write("[gen] acceptance bar: reject clicked")
        onReject?()
    }

    @objc private func redoClicked() {
        DebugLog.shared.write("[gen] acceptance bar: keep&redo clicked")
        onRedo?()
    }
}

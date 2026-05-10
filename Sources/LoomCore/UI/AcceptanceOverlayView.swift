import AppKit

/// Floating control-strip presented during the post-generation
/// acceptance window per LOOM_DESIGN_LANGUAGE.md §14.6: three buttons
/// (Accept / Reject / Keep & Redo) with the canonical keybindings
/// (⏎ / ⌫ / ⌘⇧R) shown as labels.
///
/// Phase 1 simplifies the spec: instead of positioning the strip at
/// floating-coordinates above the inserted block (HANDOFF.md §2.2
/// flagged that as finicky on macOS), the strip pins to a fixed
/// position inside the editor pane. The 6%-alpha background tint on
/// the inserted range — applied via NSTextStorage attributes — does
/// the visual job of identifying which block is in question. Phase
/// 1.m can refine to true block-anchored positioning if the fixed
/// strip feels off.
public final class AcceptanceOverlayView: NSView {
    public var onAccept: (() -> Void)?
    public var onReject: (() -> Void)?
    public var onRedo: (() -> Void)?

    private let acceptButton: NSButton
    private let rejectButton: NSButton
    private let redoButton: NSButton

    public override init(frame frameRect: NSRect) {
        acceptButton = Self.makeButton(title: "Accept ⏎")
        rejectButton = Self.makeButton(title: "Reject ⌫")
        redoButton = Self.makeButton(title: "Keep & Redo ⌘⇧R")
        super.init(frame: frameRect)
        configure()
    }

    @available(*, unavailable) public required init?(coder: NSCoder) { nil }

    private static func makeButton(title: String) -> NSButton {
        let b = LoomActionButton(title: title, target: nil, action: nil)
        b.bezelStyle = .rounded
        b.controlSize = .small
        b.font = DesignTokens.Typography.subheadline
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }

    private func configure() {
        wantsLayer = true
        layer?.backgroundColor = DesignTokens.Background.window.withAlphaComponent(0.95).cgColor
        layer?.cornerRadius = DesignTokens.Radius.section
        layer?.borderWidth = 1
        layer?.borderColor = DesignTokens.Foreground.accent.withAlphaComponent(0.4).cgColor

        let row = NSStackView(views: [acceptButton, rejectButton, redoButton])
        row.orientation = .horizontal
        row.spacing = DesignTokens.Spacing.sm
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: DesignTokens.Spacing.sm),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -DesignTokens.Spacing.sm),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DesignTokens.Spacing.md),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DesignTokens.Spacing.md),
        ])

        acceptButton.target = self
        acceptButton.action = #selector(acceptClicked)
        rejectButton.target = self
        rejectButton.action = #selector(rejectClicked)
        redoButton.target = self
        redoButton.action = #selector(redoClicked)

        // Hidden until the editor calls show().
        isHidden = true
    }

    public func show() {
        isHidden = false
        alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = DesignTokens.Motion.suggestionsReveal
            self.animator().alphaValue = 1
        }
    }

    public func hide() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = DesignTokens.Motion.hoverFade
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.isHidden = true
        })
    }

    @objc private func acceptClicked() { onAccept?() }
    @objc private func rejectClicked() { onReject?() }
    @objc private func redoClicked() { onRedo?() }
}

import AppKit

/// Bottom-pinned tray inside the editor pane (LOOM_DESIGN_LANGUAGE.md
/// §14.4). Two rows:
///   1. Horizontal mode-button row + token estimate label.
///   2. History disclosure ("▸ History") — collapsed by default in
///      Phase 1; 1.k populates the chiclets and inline expansion.
///
/// Phase 1 modes wired to the tray (per LOOM_DESIGN_LANGUAGE.md §14.4
/// — selection-driven Expand lives in the floating selection toolbar
/// in the long-form spec, but Phase 1 simplifies by hosting both
/// Continue and Expand in the same tray. The floating toolbar is
/// Phase 2+):
///   - Continue (cursor-driven)
///   - Expand (selection-driven)
/// Disabled rows: Rewrite, Brainstorm, Critique (Phase 4 wires them).
///
/// State pushed via `setState(_:)`. Click handlers fire the closures
/// supplied by the embedding controller — Phase 1.h logs and stubs;
/// 1.i routes them through PromptBuilder + KoboldClient.
public final class GenerationTrayView: NSView {
    public var onContinueClicked: (() -> Void)?
    public var onExpandClicked: (() -> Void)?

    private let continueButton: NSButton
    private let expandButton: NSButton
    private let rewriteButton: NSButton
    private let brainstormButton: NSButton
    private let critiqueButton: NSButton
    private let tokenEstimateLabel: NSTextField
    private let historyDisclosureButton: NSButton
    private(set) public var historyExpanded: Bool = false

    public override init(frame frameRect: NSRect) {
        continueButton = Self.makeModeButton(title: "Continue")
        expandButton = Self.makeModeButton(title: "Expand")
        rewriteButton = Self.makeModeButton(title: "Rewrite")
        brainstormButton = Self.makeModeButton(title: "Brainstorm")
        critiqueButton = Self.makeModeButton(title: "Critique")
        tokenEstimateLabel = NSTextField(labelWithString: "—")
        historyDisclosureButton = NSButton(title: "▸ History", target: nil, action: nil)
        super.init(frame: frameRect)
        configure()
    }

    @available(*, unavailable) public required init?(coder: NSCoder) { nil }

    private static func makeModeButton(title: String) -> NSButton {
        let b = NSButton(title: title, target: nil, action: nil)
        b.bezelStyle = .rounded
        b.controlSize = .regular
        b.font = DesignTokens.Typography.headline
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }

    private func configure() {
        wantsLayer = true
        layer?.backgroundColor = DesignTokens.Background.window.cgColor

        // Top divider — separates the tray from the text view above.
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(divider)

        // Buttons row
        let buttonsRow = NSStackView(views: [
            continueButton, expandButton, rewriteButton, brainstormButton, critiqueButton,
        ])
        buttonsRow.orientation = .horizontal
        buttonsRow.spacing = DesignTokens.Spacing.sm
        buttonsRow.translatesAutoresizingMaskIntoConstraints = false

        tokenEstimateLabel.font = DesignTokens.Typography.mono(.caption1)
        tokenEstimateLabel.textColor = DesignTokens.Foreground.secondary
        tokenEstimateLabel.translatesAutoresizingMaskIntoConstraints = false

        historyDisclosureButton.bezelStyle = .inline
        historyDisclosureButton.controlSize = .small
        historyDisclosureButton.font = DesignTokens.Typography.subheadline
        historyDisclosureButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(buttonsRow)
        addSubview(tokenEstimateLabel)
        addSubview(historyDisclosureButton)

        NSLayoutConstraint.activate([
            divider.topAnchor.constraint(equalTo: topAnchor),
            divider.leadingAnchor.constraint(equalTo: leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),

            buttonsRow.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: DesignTokens.Spacing.sm),
            buttonsRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DesignTokens.Spacing.md),

            tokenEstimateLabel.centerYAnchor.constraint(equalTo: buttonsRow.centerYAnchor),
            tokenEstimateLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DesignTokens.Spacing.md),
            tokenEstimateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: buttonsRow.trailingAnchor, constant: DesignTokens.Spacing.sm),

            historyDisclosureButton.topAnchor.constraint(equalTo: buttonsRow.bottomAnchor, constant: DesignTokens.Spacing.sm),
            historyDisclosureButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DesignTokens.Spacing.md),
            historyDisclosureButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -DesignTokens.Spacing.sm),
        ])

        // Wire actions
        continueButton.target = self
        continueButton.action = #selector(continueClicked)
        expandButton.target = self
        expandButton.action = #selector(expandClicked)
        // Phase 4 buttons rendered for visual completeness; permanently
        // disabled until those modes wire up.
        rewriteButton.isEnabled = false
        brainstormButton.isEnabled = false
        critiqueButton.isEnabled = false
        rewriteButton.toolTip = "Rewrite — Phase 4"
        brainstormButton.toolTip = "Brainstorm — Phase 4"
        critiqueButton.toolTip = "Critique — Phase 4"

        historyDisclosureButton.target = self
        historyDisclosureButton.action = #selector(toggleHistory)

        // Default state: nothing enabled.
        setState(EditorState())
        setTokenEstimate(nil)
    }

    // MARK: - State + token estimate

    public func setState(_ state: EditorState) {
        continueButton.isEnabled = GenerationModeAvailability.isEnabled(.continueProse, in: state)
        expandButton.isEnabled = GenerationModeAvailability.isEnabled(.expand, in: state)
        // Phase-4 buttons stay disabled regardless of state.
    }

    /// Token estimate shown trailing-edge. nil → placeholder dash.
    /// Phase 1.h displays word count as a stand-in (1.i may swap to a
    /// real `/api/extra/tokencount` call once PromptBuilder is wired).
    public func setTokenEstimate(_ tokens: Int?) {
        if let n = tokens {
            tokenEstimateLabel.stringValue = "\(n) tok est"
        } else {
            tokenEstimateLabel.stringValue = "—"
        }
    }

    // MARK: - Actions

    @objc private func continueClicked() {
        DebugLog.shared.write("[gen] tray: continue clicked (no-op until 1.i)")
        onContinueClicked?()
    }

    @objc private func expandClicked() {
        DebugLog.shared.write("[gen] tray: expand clicked (no-op until 1.i)")
        onExpandClicked?()
    }

    @objc private func toggleHistory() {
        historyExpanded.toggle()
        historyDisclosureButton.title = historyExpanded ? "▾ History" : "▸ History"
        // Phase 1.k expands inline content; 1.h is just the disclosure
        // toggle as a UI affordance.
    }
}

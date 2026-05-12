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
    /// Phase 4 §14.1 #6 — replaces `onRewriteClicked`. Clicking the
    /// Rewrite button now pops a sub-mode picker (Voice / Tense
    /// presets / Length presets / Generic, plus dynamic POV entries
    /// from §14.1 #8); the chosen `RewriteSubModeChoice` arrives
    /// here and the controller routes it through
    /// `runSelectionReplacingGeneration` with the resolved
    /// descriptor.
    public var onRewriteSubModeChosen: ((RewriteSubModeChoice) -> Void)?

    /// Phase 4 §14.1 #8 — bible characters to surface as POV
    /// entries in the Rewrite picker. Closure-based so the tray
    /// pulls live state at menu-build time without having to
    /// re-pass on every bible mutation. `nil` (or empty return)
    /// means "no POV entries" — the menu still surfaces Voice /
    /// Tense / Length / Generic.
    public var rewritePOVCharactersProvider: (() -> [Character])?

    /// Phase 4 §15.9 — closure pulled at Rewrite-menu-build time to
    /// classify the current selection's narrative tense. Used to
    /// disable the matching `Tense — past` / `Tense — present` entry
    /// (the no-op-target guard: both writers reliably invent unrelated
    /// shifts when asked to rewrite to a tense the source is already
    /// in). `nil` provider or `.unknown` return → both entries stay
    /// enabled, picker behaves as before.
    public var currentSelectionTenseProvider: (() -> SelectionTense)?
    /// Acceptance-mode click handlers. The tray swaps its visible
    /// button row to Accept / Reject / Keep & Redo when generation
    /// finishes.
    public var onAcceptClicked: (() -> Void)?
    public var onRejectClicked: (() -> Void)?
    public var onRedoClicked: (() -> Void)?

    private let continueButton: NSButton
    private let expandButton: NSButton
    private let rewriteButton: NSButton
    private let brainstormButton: NSButton
    private let critiqueButton: NSButton
    private let acceptButton: NSButton
    private let rejectButton: NSButton
    private let keepRedoButton: NSButton
    private let editingButtons: NSStackView
    private let acceptanceButtons: NSStackView
    private let tokenEstimateLabel: NSTextField
    private let historyDisclosureButton: NSButton
    private let progressIndicator: NSProgressIndicator
    private let stateLabel: NSTextField
    private let instructionField: NSTextField
    private(set) public var historyExpanded: Bool = false

    /// One-shot ad-hoc steering for the next generation only — empty
    /// string when the field is blank.
    public var instructionText: String {
        instructionField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Clear the per-call instruction field. Called by the editor
    /// after a generation fires so the steering doesn't persist
    /// into subsequent calls without the user re-affirming it.
    public func clearInstruction() {
        instructionField.stringValue = ""
    }

    /// Replace the per-call instruction field's contents. Used by
    /// "Push past refusal" (Phase 4 §14.1 #7) to seed the field with
    /// the refusal-breaking direction; the user reviews + clicks
    /// Continue. Does NOT auto-fire generation.
    public func setInstruction(_ text: String) {
        instructionField.stringValue = text
    }

    /// Generation state for the busy indicator. The editor flips
    /// these via setGenerationStarted / setStreaming / setGenerationFinished.
    public enum GenerationState {
        case idle
        case thinking      // request fired, no tokens yet
        case streaming     // first token arrived
    }
    private var generationState: GenerationState = .idle

    public override init(frame frameRect: NSRect) {
        continueButton = Self.makeModeButton(title: "Continue")
        expandButton = Self.makeModeButton(title: "Expand")
        rewriteButton = Self.makeModeButton(title: "Rewrite")
        brainstormButton = Self.makeModeButton(title: "Brainstorm")
        critiqueButton = Self.makeModeButton(title: "Critique")
        acceptButton = Self.makeModeButton(title: "Accept ⏎")
        rejectButton = Self.makeModeButton(title: "Reject ⌫")
        keepRedoButton = Self.makeModeButton(title: "Keep & Redo ⌘⇧R")
        editingButtons = NSStackView()
        acceptanceButtons = NSStackView()
        tokenEstimateLabel = NSTextField(labelWithString: "—")
        historyDisclosureButton = NSButton(title: "▸ History", target: nil, action: nil)
        progressIndicator = NSProgressIndicator()
        stateLabel = NSTextField(labelWithString: "")
        instructionField = NSTextField()
        super.init(frame: frameRect)
        configure()
    }

    @available(*, unavailable) public required init?(coder: NSCoder) { nil }

    private static func makeModeButton(title: String) -> NSButton {
        let b = LoomActionButton(title: title, target: nil, action: nil)
        b.bezelStyle = .rounded
        b.controlSize = .regular
        b.font = DesignTokens.Typography.headline
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }

    public override func updateLayer() {
        // Re-apply on appearance change — raw .cgColor capture in
        // configure() didn't track dark/light flips.
        layer?.backgroundColor = DesignTokens.Background.window.cgColor
    }

    private func configure() {
        wantsLayer = true

        // Top divider — separates the tray from the text view above.
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(divider)

        // Editing buttons row — Continue / Expand / Rewrite (Phase 1.5)
        // and the two Phase 4 placeholders.
        editingButtons.setViews([continueButton, expandButton, rewriteButton, brainstormButton, critiqueButton], in: .leading)
        editingButtons.orientation = .horizontal
        editingButtons.spacing = DesignTokens.Spacing.sm
        editingButtons.translatesAutoresizingMaskIntoConstraints = false

        // Acceptance buttons row — Accept / Reject / Keep & Redo.
        // Visible during the post-generation acceptance window
        // INSTEAD of the editing row (mutually exclusive).
        acceptanceButtons.setViews([acceptButton, rejectButton, keepRedoButton], in: .leading)
        acceptanceButtons.orientation = .horizontal
        acceptanceButtons.spacing = DesignTokens.Spacing.sm
        acceptanceButtons.translatesAutoresizingMaskIntoConstraints = false
        acceptanceButtons.isHidden = true

        tokenEstimateLabel.font = DesignTokens.Typography.mono(.caption1)
        tokenEstimateLabel.textColor = DesignTokens.Foreground.secondary
        tokenEstimateLabel.translatesAutoresizingMaskIntoConstraints = false

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false

        stateLabel.font = DesignTokens.Typography.subheadline
        stateLabel.textColor = DesignTokens.Foreground.accent
        stateLabel.alignment = .right
        stateLabel.translatesAutoresizingMaskIntoConstraints = false
        stateLabel.stringValue = ""

        historyDisclosureButton.bezelStyle = .inline
        historyDisclosureButton.controlSize = .small
        historyDisclosureButton.font = DesignTokens.Typography.subheadline
        historyDisclosureButton.translatesAutoresizingMaskIntoConstraints = false

        // Per-call instruction field — single-line, slim, sits between
        // the mode buttons and the History disclosure. Empty by default;
        // editor reads its value at generation start and clears it.
        instructionField.translatesAutoresizingMaskIntoConstraints = false
        instructionField.placeholderString = "Instruction for this generation (optional) — e.g. \"more dramatic\""
        instructionField.font = DesignTokens.Typography.subheadline
        instructionField.bezelStyle = .roundedBezel
        instructionField.isBordered = true
        instructionField.isBezeled = true
        instructionField.focusRingType = .default

        addSubview(editingButtons)
        addSubview(acceptanceButtons)
        addSubview(progressIndicator)
        addSubview(stateLabel)
        addSubview(tokenEstimateLabel)
        addSubview(instructionField)
        addSubview(historyDisclosureButton)

        NSLayoutConstraint.activate([
            divider.topAnchor.constraint(equalTo: topAnchor),
            divider.leadingAnchor.constraint(equalTo: leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),

            editingButtons.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: DesignTokens.Spacing.sm),
            editingButtons.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DesignTokens.Spacing.md),

            acceptanceButtons.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: DesignTokens.Spacing.sm),
            acceptanceButtons.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DesignTokens.Spacing.md),

            tokenEstimateLabel.centerYAnchor.constraint(equalTo: editingButtons.centerYAnchor),
            tokenEstimateLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DesignTokens.Spacing.md),

            stateLabel.centerYAnchor.constraint(equalTo: editingButtons.centerYAnchor),
            stateLabel.trailingAnchor.constraint(equalTo: tokenEstimateLabel.leadingAnchor, constant: -DesignTokens.Spacing.md),

            progressIndicator.centerYAnchor.constraint(equalTo: editingButtons.centerYAnchor),
            progressIndicator.trailingAnchor.constraint(equalTo: stateLabel.leadingAnchor, constant: -DesignTokens.Spacing.xs),
            progressIndicator.leadingAnchor.constraint(greaterThanOrEqualTo: editingButtons.trailingAnchor, constant: DesignTokens.Spacing.sm),

            instructionField.topAnchor.constraint(equalTo: editingButtons.bottomAnchor, constant: DesignTokens.Spacing.sm),
            instructionField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DesignTokens.Spacing.md),
            instructionField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DesignTokens.Spacing.md),

            historyDisclosureButton.topAnchor.constraint(equalTo: instructionField.bottomAnchor, constant: DesignTokens.Spacing.sm),
            historyDisclosureButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DesignTokens.Spacing.md),
            historyDisclosureButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -DesignTokens.Spacing.sm),
        ])

        // Wire actions
        continueButton.target = self
        continueButton.action = #selector(continueClicked)
        expandButton.target = self
        expandButton.action = #selector(expandClicked)
        rewriteButton.target = self
        rewriteButton.action = #selector(rewriteClicked)
        acceptButton.target = self
        acceptButton.action = #selector(acceptClicked)
        rejectButton.target = self
        rejectButton.action = #selector(rejectClicked)
        keepRedoButton.target = self
        keepRedoButton.action = #selector(redoClickedAction)
        // Phase 4 buttons rendered for visual completeness; permanently
        // disabled until those modes wire up.
        brainstormButton.isEnabled = false
        critiqueButton.isEnabled = false
        brainstormButton.toolTip = "Brainstorm — Phase 4"
        critiqueButton.toolTip = "Critique — Phase 4"
        rewriteButton.toolTip = "Rewrite — voice / tense / length / generic (pick from menu)"

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
        rewriteButton.isEnabled = GenerationModeAvailability.isEnabled(.rewrite, in: state)
        // Brainstorm + Critique stay disabled regardless of state.
    }

    /// Phase 4 §15.9 — surface a short transient note in the trailing
    /// state label and auto-clear after a few seconds. Used by the
    /// rewriteTense no-op-target guard's click-time short-circuit:
    /// when the user picks a tense that matches the selection's
    /// detected tense, we skip the call and tell them why. The
    /// auto-clear avoids stale messages persisting through the next
    /// generation. Cleared immediately if a generation starts.
    public func flashTransientNote(_ message: String, duration: TimeInterval = 4.0) {
        guard generationState == .idle else { return }
        transientNoteToken &+= 1
        let token = transientNoteToken
        stateLabel.stringValue = message
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self = self else { return }
            if self.transientNoteToken == token && self.generationState == .idle {
                self.stateLabel.stringValue = ""
            }
        }
    }

    /// Generation-state token bumped on every `flashTransientNote` so
    /// stale auto-clears (e.g. user flashes a second note before the
    /// first's delay expires) don't blank a newer message.
    private var transientNoteToken: UInt = 0

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

    /// Flip the busy indicator. Editor calls these from the
    /// coordinator's didStart / didEmitToken (first only) / didFinish
    /// notifications. Buttons disable while non-idle so the user
    /// can't double-fire.
    public func setGenerationState(_ state: GenerationState) {
        generationState = state
        switch state {
        case .idle:
            progressIndicator.stopAnimation(nil)
            stateLabel.stringValue = ""
            // Re-enablement happens via pushTrayState → setState below.
        case .thinking:
            progressIndicator.startAnimation(nil)
            stateLabel.stringValue = "Thinking…"
            continueButton.isEnabled = false
            expandButton.isEnabled = false
            rewriteButton.isEnabled = false
        case .streaming:
            progressIndicator.startAnimation(nil)
            stateLabel.stringValue = "Streaming…"
            continueButton.isEnabled = false
            expandButton.isEnabled = false
            rewriteButton.isEnabled = false
        }
    }

    /// Swap between editing-mode buttons (Continue/Expand/Rewrite) and
    /// acceptance-mode buttons (Accept/Reject/Keep&Redo). Editor calls
    /// this on coordinator finish (→ .acceptance) and after the user
    /// accepts/rejects/redoes (→ .editing).
    public enum TrayMode {
        case editing
        case acceptance
    }
    public func setTrayMode(_ mode: TrayMode) {
        switch mode {
        case .editing:
            editingButtons.isHidden = false
            acceptanceButtons.isHidden = true
        case .acceptance:
            editingButtons.isHidden = true
            acceptanceButtons.isHidden = false
        }
    }

    // MARK: - Actions

    @objc private func continueClicked() {
        DebugLog.shared.write("[gen] tray: continue clicked")
        onContinueClicked?()
    }

    @objc private func expandClicked() {
        DebugLog.shared.write("[gen] tray: expand clicked")
        onExpandClicked?()
    }

    @objc private func rewriteClicked() {
        DebugLog.shared.write("[gen] tray: rewrite clicked (sub-mode picker)")
        let povCharacters = rewritePOVCharactersProvider?() ?? []
        let selectionTense = currentSelectionTenseProvider?() ?? .unknown
        let menu = NSMenu()
        // Disabled entries (rewriteTense no-op guard) need autoenables
        // off — NSMenu otherwise defers to validateMenuItem on the
        // target and re-enables our intentionally-disabled rows.
        menu.autoenablesItems = false
        var lastMode: GenerationMode? = nil
        for choice in RewriteSubModeMenuBuilder.choices(
            povCharacters: povCharacters,
            currentSelectionTense: selectionTense
        ) {
            if let prev = lastMode, prev != choice.mode {
                menu.addItem(.separator())
            }
            lastMode = choice.mode
            let item = NSMenuItem(
                title: choice.title,
                action: #selector(rewriteSubModeItemClicked(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = choice
            if let reason = choice.disabledReason {
                item.isEnabled = false
                item.toolTip = reason
            }
            menu.addItem(item)
        }
        let origin = NSPoint(x: 0, y: rewriteButton.bounds.height + 4)
        menu.popUp(positioning: nil, at: origin, in: rewriteButton)
    }

    @objc private func rewriteSubModeItemClicked(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? RewriteSubModeChoice else { return }
        DebugLog.shared.write("[gen] tray: rewrite sub-mode chosen mode=\(choice.mode.rawValue) descriptor=\(choice.descriptor ?? "<tray>")")
        onRewriteSubModeChosen?(choice)
    }

    @objc private func acceptClicked() {
        DebugLog.shared.write("[gen] tray: accept clicked")
        onAcceptClicked?()
    }

    @objc private func rejectClicked() {
        DebugLog.shared.write("[gen] tray: reject clicked")
        onRejectClicked?()
    }

    @objc private func redoClickedAction() {
        DebugLog.shared.write("[gen] tray: keep&redo clicked")
        onRedoClicked?()
    }

    @objc private func toggleHistory() {
        historyExpanded.toggle()
        historyDisclosureButton.title = historyExpanded ? "▾ History" : "▸ History"
        // Phase 1.k expands inline content; 1.h is just the disclosure
        // toggle as a UI affordance.
    }
}

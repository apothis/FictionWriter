import AppKit

/// Project tab in the Settings window. Edits the current project's
/// memory, author's note, AN depth, and token budgets. Writes
/// through `ProjectSession.setX(_:)` setters which mark the session
/// dirty so the debounced auto-save persists the change.
public final class ProjectSettingsTabViewController: NSViewController, NSTextFieldDelegate, NSTextViewDelegate {
    public let session: ProjectSession

    private var memoryTextView: NSTextView!
    private var authorsNoteTextView: NSTextView!
    private var depthField: NSTextField!
    private var depthStepper: NSStepper!
    private var contextBudgetField: NSTextField!
    private var maxOutputField: NSTextField!
    private var useServerMaxButton: NSButton!

    // Phase 2 #6 — narrative-style pill pickers.
    public private(set) var povPicker: NSPopUpButton?
    public private(set) var tensePicker: NSPopUpButton?
    public private(set) var directionKindPicker: NSPopUpButton?
    public private(set) var vocabularyPicker: NSPopUpButton?
    public private(set) var explicitnessPicker: NSPopUpButton?

    private var suppressWriteback: Bool = false
    private var replaceObserver: NSObjectProtocol?

    public init(session: ProjectSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) public required init?(coder: NSCoder) { nil }

    deinit {
        if let o = replaceObserver { NotificationCenter.default.removeObserver(o) }
    }

    public override func loadView() {
        let container = ThemedBackgroundView(backgroundColor: DesignTokens.Background.window)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = DesignTokens.Spacing.md
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(
            top: DesignTokens.Spacing.md,
            left: DesignTokens.Spacing.md,
            bottom: DesignTokens.Spacing.md,
            right: DesignTokens.Spacing.md
        )

        // Narrative style section (Phase 2 #6).
        stack.addArrangedSubview(makeSectionLabel("Narrative Style"))

        povPicker = makePicker(
            label: "POV",
            cases: POVStyle.allCases,
            display: Self.povDisplayName,
            initial: session.project.settings.pov,
            into: stack,
            action: #selector(povPickerChanged)
        )
        tensePicker = makePicker(
            label: "Tense",
            cases: NarrativeTense.allCases,
            display: Self.tenseDisplayName,
            initial: session.project.settings.tense,
            into: stack,
            action: #selector(tensePickerChanged)
        )
        directionKindPicker = makePicker(
            label: "Direction",
            cases: DirectionKind.allCases,
            display: Self.directionDisplayName,
            initial: session.project.settings.writingDirection.kind,
            into: stack,
            action: #selector(directionPickerChanged)
        )
        vocabularyPicker = makePicker(
            label: "Vocabulary",
            cases: VocabularyRegister.allCases,
            display: Self.vocabularyDisplayName,
            initial: session.project.settings.writingDirection.register,
            into: stack,
            action: #selector(vocabularyPickerChanged)
        )
        explicitnessPicker = makePicker(
            label: "Explicitness",
            cases: ExplicitnessLevel.allCases,
            display: Self.explicitnessDisplayName,
            initial: session.project.settings.writingDirection.explicitnessLevel,
            into: stack,
            action: #selector(explicitnessPickerChanged)
        )

        // Memory section
        stack.addArrangedSubview(makeSectionLabel("Project Memory"))
        let memoryScroll = makeTextViewScroll(height: 100)
        memoryTextView = memoryScroll.documentView as? NSTextView
        memoryTextView.delegate = self
        suppressWriteback = true
        memoryTextView.string = session.project.settings.memory
        suppressWriteback = false
        stack.addArrangedSubview(memoryScroll)

        // Author's Note section
        stack.addArrangedSubview(makeSectionLabel("Author's Note"))
        let anScroll = makeTextViewScroll(height: 70)
        authorsNoteTextView = anScroll.documentView as? NSTextView
        authorsNoteTextView.delegate = self
        suppressWriteback = true
        authorsNoteTextView.string = session.project.settings.authorsNote
        suppressWriteback = false
        stack.addArrangedSubview(anScroll)

        // Depth section
        let depthRow = NSStackView()
        depthRow.orientation = .horizontal
        depthRow.alignment = .firstBaseline
        depthRow.spacing = DesignTokens.Spacing.sm
        let depthLabel = NSTextField(labelWithString: "AN depth (lines from cursor):")
        depthLabel.font = DesignTokens.Typography.subheadline
        depthField = NSTextField()
        depthField.alignment = .right
        depthField.delegate = self
        depthField.stringValue = "\(session.project.settings.authorsNoteDepthLines)"
        depthField.widthAnchor.constraint(equalToConstant: 60).isActive = true
        depthStepper = NSStepper()
        depthStepper.minValue = 0
        depthStepper.maxValue = 50
        depthStepper.increment = 1
        depthStepper.integerValue = session.project.settings.authorsNoteDepthLines
        depthStepper.target = self
        depthStepper.action = #selector(depthStepperChanged)
        depthRow.addArrangedSubview(depthLabel)
        depthRow.addArrangedSubview(depthField)
        depthRow.addArrangedSubview(depthStepper)
        stack.addArrangedSubview(depthRow)

        // Token budgets section
        stack.addArrangedSubview(makeSectionLabel("Token Budgets"))
        let ctxRow = NSStackView()
        ctxRow.orientation = .horizontal
        ctxRow.alignment = .firstBaseline
        ctxRow.spacing = DesignTokens.Spacing.sm
        let ctxLabel = NSTextField(labelWithString: "Context budget (tokens):")
        ctxLabel.font = DesignTokens.Typography.subheadline
        contextBudgetField = NSTextField()
        contextBudgetField.alignment = .right
        contextBudgetField.delegate = self
        contextBudgetField.stringValue = "\(session.project.settings.contextBudgetTokens)"
        contextBudgetField.widthAnchor.constraint(equalToConstant: 100).isActive = true
        useServerMaxButton = NSButton(title: "Use server max", target: self, action: #selector(useServerMaxClicked))
        useServerMaxButton.bezelStyle = .rounded
        useServerMaxButton.controlSize = .small
        useServerMaxButton.font = DesignTokens.Typography.subheadline
        useServerMaxButton.toolTip = "Set the context budget to (probed server max) − (max reply tokens) − 256-token safety margin."
        ctxRow.addArrangedSubview(ctxLabel)
        ctxRow.addArrangedSubview(contextBudgetField)
        ctxRow.addArrangedSubview(useServerMaxButton)
        stack.addArrangedSubview(ctxRow)
        refreshUseServerMaxButton()

        let maxRow = NSStackView()
        maxRow.orientation = .horizontal
        maxRow.alignment = .firstBaseline
        maxRow.spacing = DesignTokens.Spacing.sm
        let maxLabel = NSTextField(labelWithString: "Max reply tokens:")
        maxLabel.font = DesignTokens.Typography.subheadline
        maxOutputField = NSTextField()
        maxOutputField.alignment = .right
        maxOutputField.delegate = self
        maxOutputField.stringValue = "\(session.project.settings.generationDefaults.maxOutputTokens)"
        maxOutputField.widthAnchor.constraint(equalToConstant: 100).isActive = true
        maxRow.addArrangedSubview(maxLabel)
        maxRow.addArrangedSubview(maxOutputField)
        stack.addArrangedSubview(maxRow)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.documentView = stack

        container.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: container.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.widthAnchor),
        ])

        self.view = container

        // Reload fields when the session swaps projects (open / new).
        replaceObserver = NotificationCenter.default.addObserver(
            forName: ProjectSession.didReplaceNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            self?.reloadFromSession()
        }
    }

    private func reloadFromSession() {
        suppressWriteback = true
        memoryTextView?.string = session.project.settings.memory
        authorsNoteTextView?.string = session.project.settings.authorsNote
        depthField?.stringValue = "\(session.project.settings.authorsNoteDepthLines)"
        depthStepper?.integerValue = session.project.settings.authorsNoteDepthLines
        contextBudgetField?.stringValue = "\(session.project.settings.contextBudgetTokens)"
        maxOutputField?.stringValue = "\(session.project.settings.generationDefaults.maxOutputTokens)"
        Self.selectCase(POVStyle.allCases, value: session.project.settings.pov, in: povPicker)
        Self.selectCase(NarrativeTense.allCases, value: session.project.settings.tense, in: tensePicker)
        Self.selectCase(DirectionKind.allCases, value: session.project.settings.writingDirection.kind, in: directionKindPicker)
        Self.selectCase(VocabularyRegister.allCases, value: session.project.settings.writingDirection.register, in: vocabularyPicker)
        Self.selectCase(ExplicitnessLevel.allCases, value: session.project.settings.writingDirection.explicitnessLevel, in: explicitnessPicker)
        suppressWriteback = false
    }

    // MARK: - Phase 2 #6 narrative-style public API (smoke-test surface)

    public var selectedPOV: POVStyle? { Self.selectedCase(POVStyle.allCases, in: povPicker) }
    public var selectedTense: NarrativeTense? { Self.selectedCase(NarrativeTense.allCases, in: tensePicker) }
    public var selectedDirectionKind: DirectionKind? { Self.selectedCase(DirectionKind.allCases, in: directionKindPicker) }
    public var selectedVocabulary: VocabularyRegister? { Self.selectedCase(VocabularyRegister.allCases, in: vocabularyPicker) }
    public var selectedExplicitness: ExplicitnessLevel? { Self.selectedCase(ExplicitnessLevel.allCases, in: explicitnessPicker) }

    public func setPOV(_ pov: POVStyle) {
        session.setPOV(pov)
        Self.selectCase(POVStyle.allCases, value: pov, in: povPicker)
    }

    public func setTense(_ tense: NarrativeTense) {
        session.setTense(tense)
        Self.selectCase(NarrativeTense.allCases, value: tense, in: tensePicker)
    }

    public func setDirectionKind(_ kind: DirectionKind) {
        session.setWritingDirectionKind(kind)
        Self.selectCase(DirectionKind.allCases, value: kind, in: directionKindPicker)
    }

    public func setVocabulary(_ register: VocabularyRegister) {
        session.setWritingDirectionRegister(register)
        Self.selectCase(VocabularyRegister.allCases, value: register, in: vocabularyPicker)
    }

    public func setExplicitness(_ level: ExplicitnessLevel) {
        session.setWritingDirectionExplicitness(level)
        Self.selectCase(ExplicitnessLevel.allCases, value: level, in: explicitnessPicker)
    }

    // MARK: - Writebacks

    public func textDidChange(_ notification: Notification) {
        guard !suppressWriteback else { return }
        guard let tv = notification.object as? NSTextView else { return }
        if tv === memoryTextView {
            session.setMemory(tv.string)
        } else if tv === authorsNoteTextView {
            session.setAuthorsNote(tv.string)
        }
    }

    public func controlTextDidEndEditing(_ obj: Notification) {
        guard !suppressWriteback else { return }
        guard let field = obj.object as? NSTextField else { return }
        if field === depthField {
            let value = Int(field.stringValue) ?? 0
            depthStepper.integerValue = value
            session.setAuthorsNoteDepthLines(value)
        } else if field === contextBudgetField {
            let value = Int(field.stringValue) ?? session.project.settings.contextBudgetTokens
            session.setContextBudgetTokens(value)
        } else if field === maxOutputField {
            let value = Int(field.stringValue) ?? session.project.settings.generationDefaults.maxOutputTokens
            session.setMaxOutputTokens(value)
        }
    }

    @objc private func depthStepperChanged() {
        let value = depthStepper.integerValue
        depthField.stringValue = "\(value)"
        session.setAuthorsNoteDepthLines(value)
    }

    @objc private func useServerMaxClicked() {
        let trueMax = AppState.shared.lastProbedMaxContext ?? 0
        let replyBudget = session.project.settings.generationDefaults.maxOutputTokens
        guard let recommended = ContextBudgetRecommendation.recommend(
            trueMaxContext: trueMax,
            replyBudgetTokens: replyBudget
        ) else { return }
        session.setContextBudgetTokens(recommended)
        contextBudgetField.stringValue = "\(recommended)"
    }

    /// Enable the "Use server max" button only when we have a probed
    /// max-context value to compute against.
    private func refreshUseServerMaxButton() {
        let trueMax = AppState.shared.lastProbedMaxContext ?? 0
        useServerMaxButton.isEnabled = trueMax > 0
        if trueMax > 0 {
            useServerMaxButton.toolTip = "Set to \(trueMax) − reply − 256 (server-probed max context)."
        } else {
            useServerMaxButton.toolTip = "No server probe data yet — start a generation first."
        }
    }

    // MARK: - Picker actions

    @objc private func povPickerChanged(_ sender: NSPopUpButton) {
        guard !suppressWriteback,
              let v = Self.selectedCase(POVStyle.allCases, in: sender)
        else { return }
        session.setPOV(v)
    }

    @objc private func tensePickerChanged(_ sender: NSPopUpButton) {
        guard !suppressWriteback,
              let v = Self.selectedCase(NarrativeTense.allCases, in: sender)
        else { return }
        session.setTense(v)
    }

    @objc private func directionPickerChanged(_ sender: NSPopUpButton) {
        guard !suppressWriteback,
              let v = Self.selectedCase(DirectionKind.allCases, in: sender)
        else { return }
        session.setWritingDirectionKind(v)
    }

    @objc private func vocabularyPickerChanged(_ sender: NSPopUpButton) {
        guard !suppressWriteback,
              let v = Self.selectedCase(VocabularyRegister.allCases, in: sender)
        else { return }
        session.setWritingDirectionRegister(v)
    }

    @objc private func explicitnessPickerChanged(_ sender: NSPopUpButton) {
        guard !suppressWriteback,
              let v = Self.selectedCase(ExplicitnessLevel.allCases, in: sender)
        else { return }
        session.setWritingDirectionExplicitness(v)
    }

    // MARK: - Picker helpers

    /// Builds a "<label>:  <popup>" row, adds it to the stack, returns
    /// the popup. Generic over the enum's `allCases` so each picker
    /// keeps a stable index↔case mapping (used by selectedCase /
    /// selectCase below).
    private func makePicker<T: Equatable>(
        label: String,
        cases: [T],
        display: (T) -> String,
        initial: T,
        into stack: NSStackView,
        action: Selector
    ) -> NSPopUpButton {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = DesignTokens.Spacing.sm

        let title = NSTextField(labelWithString: "\(label):")
        title.font = DesignTokens.Typography.subheadline
        title.widthAnchor.constraint(equalToConstant: 100).isActive = true

        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.bezelStyle = .rounded
        popup.controlSize = .regular
        popup.font = DesignTokens.Typography.subheadline
        for value in cases {
            popup.addItem(withTitle: display(value))
        }
        if let initialIndex = cases.firstIndex(of: initial) {
            popup.selectItem(at: initialIndex)
        }
        popup.target = self
        popup.action = action

        row.addArrangedSubview(title)
        row.addArrangedSubview(popup)
        stack.addArrangedSubview(row)
        return popup
    }

    private static func selectedCase<T>(_ cases: [T], in popup: NSPopUpButton?) -> T? {
        guard let popup = popup else { return nil }
        let i = popup.indexOfSelectedItem
        guard i >= 0, i < cases.count else { return nil }
        return cases[i]
    }

    private static func selectCase<T: Equatable>(_ cases: [T], value: T, in popup: NSPopUpButton?) {
        guard let popup = popup, let i = cases.firstIndex(of: value) else { return }
        popup.selectItem(at: i)
    }

    // MARK: - Display strings

    private static func povDisplayName(_ value: POVStyle) -> String {
        switch value {
        case .firstPerson:           return "First person"
        case .secondPerson:          return "Second person"
        case .thirdPersonLimited:    return "Third person (limited)"
        case .thirdPersonOmniscient: return "Third person (omniscient)"
        }
    }

    private static func tenseDisplayName(_ value: NarrativeTense) -> String {
        switch value {
        case .past:    return "Past"
        case .present: return "Present"
        }
    }

    private static func directionDisplayName(_ value: DirectionKind) -> String {
        switch value {
        case .literary:   return "Literary"
        case .mainstream: return "Mainstream"
        case .romance:    return "Romance"
        case .erotica:    return "Erotica"
        case .porn:       return "Porn"
        }
    }

    private static func vocabularyDisplayName(_ value: VocabularyRegister) -> String {
        switch value {
        case .clinical: return "Clinical"
        case .literary: return "Literary"
        case .earthy:   return "Earthy"
        case .crude:    return "Crude"
        case .mixed:    return "Mixed"
        }
    }

    private static func explicitnessDisplayName(_ value: ExplicitnessLevel) -> String {
        switch value {
        case .fadeToBlack: return "Fade to black"
        case .suggestive:  return "Suggestive"
        case .onScreen:    return "On-screen"
        case .graphic:     return "Graphic"
        case .extreme:     return "Extreme"
        }
    }

    // MARK: - Helpers

    private func makeSectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = DesignTokens.Typography.headline
        label.textColor = DesignTokens.Foreground.primary
        return label
    }

    private func makeTextViewScroll(height: CGFloat) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.borderType = .lineBorder
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.heightAnchor.constraint(equalToConstant: height).isActive = true
        scroll.widthAnchor.constraint(equalToConstant: 480).isActive = true

        let tv = NSTextView()
        tv.font = DesignTokens.Typography.body
        tv.isRichText = false
        tv.isEditable = true
        tv.allowsUndo = true
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.textContainerInset = NSSize(width: DesignTokens.Spacing.sm, height: DesignTokens.Spacing.sm)
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isHorizontallyResizable = false
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = tv
        return scroll
    }
}

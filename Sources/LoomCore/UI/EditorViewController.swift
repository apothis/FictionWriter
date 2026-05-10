import AppKit

/// The editor pane: an `NSTextView` inside an `NSScrollView`, content
/// width-bounded to `Editor.editorMaxWidth` (720pt) and centred via
/// dynamic `textContainerInset` adjustment on resize. Body font with
/// 1.45× line height per LOOM_DESIGN_LANGUAGE.md §14.4. Find bar enabled
/// for free Cmd-F find/replace.
///
/// Bound to a `ProjectSession`: the controller listens for selection
/// changes on the session to swap the editor's text-storage to the
/// active scene's prose, and writes back to `session.scenes[id].prose`
/// on every text change. Posts `wordCountChanged` so the status strip
/// (1.m) can listen.
public final class EditorViewController: NSViewController, NSTextViewDelegate {
    public let session: ProjectSession
    private var scrollView: NSScrollView!
    private var textView: NSTextView!
    private var trayView: GenerationTrayView!
    private var coordinator: GenerationCoordinator!
    private var acceptanceOverlay: AcceptanceOverlayView!
    private var acceptanceMachine = AcceptanceMachine()
    private var selectionObserver: NSObjectProtocol?
    private var resizeObserver: NSObjectProtocol?
    private var textSelectionObserver: NSObjectProtocol?
    private var generationTokenObserver: NSObjectProtocol?
    private var generationFinishObserver: NSObjectProtocol?
    private var insertAgainObserver: NSObjectProtocol?
    /// Suppresses re-entrant text writes when we programmatically swap
    /// the text storage on selection change OR when streamed tokens
    /// land at the cursor — neither should round-trip through
    /// `session.updateProse`.
    private var suppressWriteback: Bool = false
    /// True only during the pre-stream selection deletion in Expand
    /// mode — used to skip the implicit-accept path that would
    /// otherwise fire when our own programmatic delete looks like the
    /// user typing.
    private var suppressImplicitAccept: Bool = false

    /// Posted on every text change; userInfo carries `wordCount: Int`
    /// and `sceneId: UUID`. Status strip listens once it lands in 1.m.
    public static let wordCountChangedNotification = Notification.Name("LoomEditor.wordCountChanged")

    public init(session: ProjectSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) public required init?(coder: NSCoder) { nil }

    deinit {
        if let o = selectionObserver { NotificationCenter.default.removeObserver(o) }
        if let o = resizeObserver { NotificationCenter.default.removeObserver(o) }
        if let o = textSelectionObserver { NotificationCenter.default.removeObserver(o) }
        if let o = generationTokenObserver { NotificationCenter.default.removeObserver(o) }
        if let o = generationFinishObserver { NotificationCenter.default.removeObserver(o) }
        if let o = insertAgainObserver { NotificationCenter.default.removeObserver(o) }
    }

    public override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = DesignTokens.Background.textInput.cgColor

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true
        self.scrollView = scroll

        let tv = NSTextView()
        tv.delegate = self
        tv.isRichText = false
        tv.isEditable = true
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.font = DesignTokens.Typography.body
        tv.textColor = DesignTokens.Foreground.primary
        tv.backgroundColor = DesignTokens.Background.textInput
        tv.drawsBackground = true
        // 1.45× line height per §14.4. Applies to text typed afterward
        // and (via setTypingAttributes below) to the active typing
        // attributes. For Phase 1 prose starts empty so default is
        // sufficient; multi-paragraph paste preserves the line height
        // because typingAttributes carries the paragraph style.
        let para = NSMutableParagraphStyle()
        para.lineHeightMultiple = 1.45
        tv.defaultParagraphStyle = para
        tv.typingAttributes = [
            .font: DesignTokens.Typography.body,
            .paragraphStyle: para,
            .foregroundColor: DesignTokens.Foreground.primary,
        ]

        // Width-constrain via the text container, not the view's frame.
        // Setting widthTracksTextView = false makes the container's
        // width independent of the view; we set it to editorMaxWidth so
        // the prose reflows at 720pt regardless of window width.
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.containerSize = NSSize(
            width: DesignTokens.Editor.editorMaxWidth,
            height: CGFloat.greatestFiniteMagnitude
        )
        tv.minSize = NSSize(width: DesignTokens.Editor.editorMaxWidth, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isHorizontallyResizable = false
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]

        scroll.documentView = tv
        self.textView = tv

        // Bottom-pinned generation tray (1.h plumbing; 1.i wires the
        // click handlers to actual generation).
        let tray = GenerationTrayView()
        tray.translatesAutoresizingMaskIntoConstraints = false
        tray.onContinueClicked = { [weak self] in self?.handleContinue() }
        tray.onExpandClicked = { [weak self] in self?.handleExpand() }
        self.trayView = tray

        // Acceptance overlay — pinned at the top of the editor pane,
        // hidden by default. Shown when the acceptance machine moves
        // to .awaiting (1.j.B). Per-block-anchored positioning is
        // §1.m polish (HANDOFF.md §2.2 flagged it as finicky on macOS).
        let overlay = AcceptanceOverlayView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.onAccept = { [weak self] in self?.applyAcceptanceTransition(.accept) }
        overlay.onReject = { [weak self] in self?.applyAcceptanceTransition(.reject) }
        overlay.onRedo = { [weak self] in self?.applyAcceptanceTransition(.redo) }
        self.acceptanceOverlay = overlay

        container.addSubview(scroll)
        container.addSubview(tray)
        container.addSubview(overlay)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: container.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: tray.topAnchor),
            tray.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tray.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tray.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            overlay.topAnchor.constraint(equalTo: container.topAnchor, constant: DesignTokens.Spacing.sm),
            overlay.centerXAnchor.constraint(equalTo: container.centerXAnchor),
        ])

        self.view = container

        selectionObserver = NotificationCenter.default.addObserver(
            forName: ProjectSession.selectionDidChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            self?.refreshFromSession()
        }

        // Re-centre content when the scroll view's frame changes so the
        // 720pt column stays visually centred regardless of inspector/
        // sidebar width changes.
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: scroll,
            queue: .main
        ) { [weak self] _ in
            self?.updateTextContainerInset()
        }
        scroll.postsFrameChangedNotifications = true

        // Push tray state on text-view selection change. Tracks both
        // cursor moves (no-op visually) and selection grow/shrink.
        textSelectionObserver = NotificationCenter.default.addObserver(
            forName: NSTextView.didChangeSelectionNotification,
            object: tv,
            queue: .main
        ) { [weak self] _ in
            self?.pushTrayState()
        }

        // Generation pipeline: one coordinator per editor. Wires
        // PromptBuilder → KoboldClient.generateStream → didEmitToken
        // notifications. EditorVC inserts each token at the running
        // offset and unfreezes the text view on finish.
        coordinator = GenerationCoordinator(session: session, registry: AppState.shared.registry)
        generationTokenObserver = NotificationCenter.default.addObserver(
            forName: GenerationCoordinator.didEmitTokenNotification,
            object: coordinator,
            queue: .main
        ) { [weak self] note in
            guard let token = note.userInfo?["token"] as? String,
                  let offset = note.userInfo?["insertionOffset"] as? Int else { return }
            self?.insertGeneratedToken(token, at: offset)
        }
        generationFinishObserver = NotificationCenter.default.addObserver(
            forName: GenerationCoordinator.didFinishNotification,
            object: coordinator,
            queue: .main
        ) { [weak self] _ in
            self?.handleGenerationFinish()
        }
        insertAgainObserver = NotificationCenter.default.addObserver(
            forName: HistoryInspectorViewController.requestInsertAgainNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let text = note.userInfo?["text"] as? String else { return }
            self?.insertTextAtCursor(text)
        }

        refreshFromSession()
        updateTextContainerInset()
    }

    public override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(textView)
    }

    // MARK: - Session ↔ text-storage sync

    private func refreshFromSession() {
        suppressWriteback = true
        defer { suppressWriteback = false }
        if let id = session.currentSceneId, let scene = session.scenes[id] {
            textView.string = scene.prose
            textView.isEditable = true
        } else {
            textView.string = ""
            textView.isEditable = false
        }
        postWordCount()
        pushTrayState()
    }

    /// Intercept ⏎ and ⌫ during the acceptance window — Phase 1.j.B
/// keyboard shortcuts. ⌘⇧R (Keep & Redo) is reachable from the overlay
/// button; an in-app shortcut for it is 1.m polish.
    public func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard case .awaiting = acceptanceMachine.state else { return false }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            applyAcceptanceTransition(.accept)
            return true
        }
        if commandSelector == #selector(NSResponder.deleteBackward(_:))
            || commandSelector == #selector(NSResponder.deleteForward(_:))
        {
            applyAcceptanceTransition(.reject)
            return true
        }
        return false
    }

    public func textDidChange(_ notification: Notification) {
        guard !suppressWriteback else { return }
        // If the user typed during the acceptance window, treat that
        // as Accept (Cursor / Copilot ghost-text convention). Skip
        // when the editor itself is causing the change (e.g. the
        // pre-Expand selection delete).
        if !suppressImplicitAccept,
           case .awaiting = acceptanceMachine.state
        {
            _ = acceptanceMachine.handleImplicitAccept()
            acceptanceOverlay.hide()
            clearAcceptanceTint()
            DebugLog.shared.write("[editor] acceptance: implicit (user typed)")
        }
        guard let id = session.currentSceneId else { return }
        let prose = textView.string
        session.updateProse(id: id, prose: prose)
        postWordCount()
        pushTrayState()
    }

    private func pushTrayState() {
        let prose = textView.string
        let hasProse = !prose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasSelection = textView.selectedRanges.contains(where: { ($0 as? NSValue)?.rangeValue.length ?? 0 > 0 })
        trayView.setState(EditorState(hasProse: hasProse, hasSelection: hasSelection))
        // Phase 1.h placeholder: word count stands in for token estimate
        // until 1.i wires real `/api/extra/tokencount` calls.
        trayView.setTokenEstimate(WordCount.count(prose))
    }

    private func handleContinue() {
        guard !coordinator.isGenerating else { return }
        let cursor: Int = {
            if let range = textView.selectedRanges.first as? NSValue {
                return NSMaxRange(range.rangeValue)
            }
            return (textView.string as NSString).length
        }()
        lastInvokedMode = .continueProse
        textView.isEditable = false
        coordinator.start(mode: .continueProse, cursorOffset: cursor, selectionRange: nil)
    }

    private func handleExpand() {
        guard !coordinator.isGenerating else { return }
        guard let value = textView.selectedRanges.first as? NSValue else { return }
        let selection = value.rangeValue
        guard selection.length > 0 else { return }

        // Expand replaces the selection with generated prose. Delete
        // the selection now so the cursor sits at selection.location;
        // PromptBuilder reads the *original* prose from the session
        // (which still has it because we suppress writeback during
        // this delete) and frames the selected region as the sketch.
        suppressWriteback = true
        suppressImplicitAccept = true
        textView.textStorage?.deleteCharacters(in: selection)
        textView.setSelectedRange(NSRange(location: selection.location, length: 0))
        suppressWriteback = false
        suppressImplicitAccept = false

        lastInvokedMode = .expand
        textView.isEditable = false
        coordinator.start(
            mode: .expand,
            cursorOffset: selection.location,
            selectionRange: selection
        )
    }

    /// Insert a streamed token at the coordinator's running insertion
    /// offset. Bypasses the textDidChange writeback (the coordinator
    /// updates session prose on finish to avoid mid-stream churn).
    private func insertGeneratedToken(_ token: String, at offset: Int) {
        guard let storage = textView.textStorage else { return }
        suppressWriteback = true
        defer { suppressWriteback = false }
        let nsLength = (textView.string as NSString).length
        let safeOffset = max(0, min(offset, nsLength))
        let attributes: [NSAttributedString.Key: Any] = [
            .font: DesignTokens.Typography.body,
            .foregroundColor: DesignTokens.Foreground.primary,
        ]
        let attributed = NSAttributedString(string: token, attributes: attributes)
        storage.insert(attributed, at: safeOffset)
        // Move the cursor past the just-inserted token so the user sees
        // the prose grow from where Continue began.
        let newCursor = safeOffset + (token as NSString).length
        textView.setSelectedRange(NSRange(location: newCursor, length: 0))
        textView.scrollRangeToVisible(NSRange(location: newCursor, length: 0))
    }

    private func handleGenerationFinish() {
        textView.isEditable = true
        // Sync the session's in-memory prose with what the text view
        // shows now. Single writeback at finish (rather than per-token)
        // keeps the session state consistent without churning.
        if let id = session.currentSceneId {
            session.updateProse(id: id, prose: textView.string)
        }
        postWordCount()
        pushTrayState()
        DebugLog.shared.write("[editor] generation finished — text-view re-editable")

        // Drive the acceptance machine + show the overlay if the
        // generation produced a non-empty insertion. coordinator's
        // insertedText property holds the streamed result; the
        // insertion offset comes from the coordinator's internal
        // tracker. We reconstruct the inserted range from those.
        let nsLength = (coordinator.insertedText as NSString).length
        guard nsLength > 0 else { return }
        let insertedRange = NSRange(
            location: coordinator.insertionOffset - nsLength,
            length: nsLength
        )
        // Determine the mode that just finished — coordinator doesn't
        // currently expose it, but the acceptance machine only
        // strictly needs it for the redo path. Use .continueProse as
        // a safe default; the editor can carry a `lastMode` field
        // if the redo path needs to be tighter.
        let mode = lastInvokedMode ?? .continueProse
        acceptanceMachine.handleGenerationFinished(insertedRange: insertedRange, mode: mode)
        applyAcceptanceTint(insertedRange)
        acceptanceOverlay.show()
    }

    /// Tracks which mode the editor most recently invoked, so the
    /// acceptance machine can re-fire it on Redo. Set in
    /// handleContinue / handleExpand; consumed in handleGenerationFinish.
    private var lastInvokedMode: GenerationMode?

    /// Apply the 6%-alpha accent tint to the inserted range as a
    /// background-color attribute. Removed by `clearAcceptanceTint`
    /// when the user accepts/rejects/types.
    private func applyAcceptanceTint(_ range: NSRange) {
        guard let storage = textView.textStorage else { return }
        let tint = DesignTokens.Foreground.accent.withAlphaComponent(0.06)
        let safeRange = NSRange(
            location: max(0, min(range.location, storage.length)),
            length: max(0, min(range.length, storage.length - max(0, min(range.location, storage.length))))
        )
        storage.addAttribute(.backgroundColor, value: tint, range: safeRange)
    }

    private func clearAcceptanceTint() {
        guard let storage = textView.textStorage else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        storage.removeAttribute(.backgroundColor, range: fullRange)
    }

    private enum AcceptanceTransition {
        case accept
        case reject
        case redo
    }

    private func applyAcceptanceTransition(_ transition: AcceptanceTransition) {
        let action: AcceptanceMachine.Action
        switch transition {
        case .accept: action = acceptanceMachine.handleAccept()
        case .reject: action = acceptanceMachine.handleReject()
        case .redo:   action = acceptanceMachine.handleRedo()
        }
        acceptanceOverlay.hide()
        clearAcceptanceTint()

        switch action {
        case .nothing:
            DebugLog.shared.write("[editor] acceptance: \(transition) — nothing")
        case .removeText(let range):
            removeRange(range, label: "reject")
        case .removeAndRestart(let range, let mode):
            removeRange(range, label: "redo")
            // Re-fire same mode at the prior cursor.
            lastInvokedMode = mode
            textView.isEditable = false
            coordinator.start(mode: mode, cursorOffset: range.location, selectionRange: nil)
        }
    }

    /// Inserts a string at the current cursor position. Used by the
    /// History tab's "Insert again at cursor" button.
    private func insertTextAtCursor(_ text: String) {
        guard let storage = textView.textStorage else { return }
        let cursor: Int = {
            if let value = textView.selectedRanges.first as? NSValue {
                return value.rangeValue.location
            }
            return storage.length
        }()
        let safe = max(0, min(cursor, storage.length))
        suppressWriteback = true
        let attributed = NSAttributedString(string: text, attributes: [
            .font: DesignTokens.Typography.body,
            .foregroundColor: DesignTokens.Foreground.primary,
        ])
        storage.insert(attributed, at: safe)
        suppressWriteback = false
        let newCursor = safe + (text as NSString).length
        textView.setSelectedRange(NSRange(location: newCursor, length: 0))
        if let id = session.currentSceneId {
            session.updateProse(id: id, prose: textView.string)
        }
        DebugLog.shared.write("[editor] insertAgain: \(text.count) chars at \(safe)")
    }

    private func removeRange(_ range: NSRange, label: String) {
        guard let storage = textView.textStorage else { return }
        let safeRange = NSRange(
            location: max(0, min(range.location, storage.length)),
            length: max(0, min(range.length, storage.length - max(0, min(range.location, storage.length))))
        )
        suppressWriteback = true
        storage.deleteCharacters(in: safeRange)
        suppressWriteback = false
        textView.setSelectedRange(NSRange(location: safeRange.location, length: 0))
        if let id = session.currentSceneId {
            session.updateProse(id: id, prose: textView.string)
        }
        DebugLog.shared.write("[editor] acceptance: \(label) — removed range \(safeRange)")
    }

    private func postWordCount() {
        let count = WordCount.count(textView.string)
        var info: [AnyHashable: Any] = ["wordCount": count]
        if let id = session.currentSceneId { info["sceneId"] = id }
        NotificationCenter.default.post(
            name: Self.wordCountChangedNotification,
            object: self,
            userInfo: info
        )
    }

    // MARK: - Centred 720-column layout

    /// Adjust the textContainer's left/right inset so that the bounded
    /// 720pt column is centred inside the visible scroll-view width.
    /// Below 720pt + 2*lg padding, fall back to a `lg` margin on each
    /// side.
    private func updateTextContainerInset() {
        let visibleWidth = scrollView.contentSize.width
        let target = DesignTokens.Editor.editorMaxWidth
        let minMargin = DesignTokens.Spacing.lg
        var sideInset: CGFloat
        if visibleWidth >= target + minMargin * 2 {
            sideInset = (visibleWidth - target) / 2
        } else {
            sideInset = minMargin
        }
        textView.textContainerInset = NSSize(width: sideInset, height: DesignTokens.Spacing.lg)
        // Ensure the text view fills the visible width so the inset
        // computes against the full available space.
        var frame = textView.frame
        frame.size.width = max(visibleWidth, target + minMargin * 2)
        textView.frame = frame
    }
}

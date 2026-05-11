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
    private var acceptanceMachine = AcceptanceMachine()
    private var emptyStateView: EmptyProjectStateView!
    private var emptyStateClickedObserver: NSObjectProtocol?
    private var sessionDidChangeObserver: NSObjectProtocol?
    private var sessionDidReplaceObserver: NSObjectProtocol?
    private var selectionObserver: NSObjectProtocol?
    private var resizeObserver: NSObjectProtocol?
    private var textSelectionObserver: NSObjectProtocol?
    private var generationTokenObserver: NSObjectProtocol?
    private var generationFinishObserver: NSObjectProtocol?
    private var generationStartObserver: NSObjectProtocol?
    private var insertAgainObserver: NSObjectProtocol?
    /// Flipped from .thinking to .streaming on the first emitted token
    /// so the tray's busy indicator reflects "model has begun replying".
    private var firstTokenSeenThisGeneration: Bool = false
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
        if let o = generationStartObserver { NotificationCenter.default.removeObserver(o) }
        if let o = insertAgainObserver { NotificationCenter.default.removeObserver(o) }
        if let o = emptyStateClickedObserver { NotificationCenter.default.removeObserver(o) }
        if let o = sessionDidChangeObserver { NotificationCenter.default.removeObserver(o) }
        if let o = sessionDidReplaceObserver { NotificationCenter.default.removeObserver(o) }
    }

    public override func loadView() {
        let container = ThemedBackgroundView(backgroundColor: DesignTokens.Background.textInput)

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
        tray.onRewriteClicked = { [weak self] in self?.handleRewrite() }
        // Acceptance buttons live in the tray itself, swapping in for
        // Continue/Expand when the post-generation acceptance window
        // opens. The previously-attempted NSTitlebarAccessoryViewController
        // approach triggered an AppKit auto-refit on macOS 26 that
        // shrunk the window to ~104pt wide on every attach — minSize
        // was ignored. The tray-swap is uglier but works.
        tray.onAcceptClicked = { [weak self] in self?.applyAcceptanceTransition(.accept) }
        tray.onRejectClicked = { [weak self] in self?.applyAcceptanceTransition(.reject) }
        tray.onRedoClicked = { [weak self] in self?.applyAcceptanceTransition(.redo) }
        self.trayView = tray

        // Empty-project placeholder per LOOM_DESIGN_LANGUAGE.md §14.7.
        // Overlaid on top of the scroll view; shown when
        // EmptyProjectState.shouldShow(in: session) is true. The
        // text view stays in the hierarchy underneath — the empty
        // view just hides it visually.
        let empty = EmptyProjectStateView()
        empty.translatesAutoresizingMaskIntoConstraints = false
        empty.isHidden = true
        self.emptyStateView = empty

        container.addSubview(scroll)
        container.addSubview(tray)
        container.addSubview(empty)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: container.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: tray.topAnchor),
            tray.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tray.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tray.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            empty.topAnchor.constraint(equalTo: scroll.topAnchor),
            empty.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            empty.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            empty.bottomAnchor.constraint(equalTo: scroll.bottomAnchor),
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
        generationStartObserver = NotificationCenter.default.addObserver(
            forName: GenerationCoordinator.didStartNotification,
            object: coordinator,
            queue: .main
        ) { [weak self] _ in
            self?.firstTokenSeenThisGeneration = false
            self?.trayView.setGenerationState(.thinking)
        }
        generationTokenObserver = NotificationCenter.default.addObserver(
            forName: GenerationCoordinator.didEmitTokenNotification,
            object: coordinator,
            queue: .main
        ) { [weak self] note in
            guard let token = note.userInfo?["token"] as? String,
                  let offset = note.userInfo?["insertionOffset"] as? Int else { return }
            // First token: flip the busy indicator from "thinking" to
            // "streaming" so the user knows the model is actively
            // replying (vs still pre-fill / KV-cache warming).
            if let self = self, !self.firstTokenSeenThisGeneration {
                self.firstTokenSeenThisGeneration = true
                self.trayView.setGenerationState(.streaming)
            }
            self?.insertGeneratedToken(token, at: offset)
        }
        generationFinishObserver = NotificationCenter.default.addObserver(
            forName: GenerationCoordinator.didFinishNotification,
            object: coordinator,
            queue: .main
        ) { [weak self] _ in
            self?.trayView.setGenerationState(.idle)
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
        emptyStateClickedObserver = NotificationCenter.default.addObserver(
            forName: EmptyProjectStateView.createSceneClickedNotification,
            object: emptyStateView,
            queue: .main
        ) { [weak self] _ in
            _ = self?.session.addScene()
        }
        sessionDidChangeObserver = NotificationCenter.default.addObserver(
            forName: ProjectSession.didChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            self?.refreshEmptyState()
        }
        sessionDidReplaceObserver = NotificationCenter.default.addObserver(
            forName: ProjectSession.didReplaceNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            self?.refreshEmptyState()
        }

        refreshFromSession()
        refreshEmptyState()
        updateTextContainerInset()
    }

    private func refreshEmptyState() {
        let shouldShow = EmptyProjectState.shouldShow(in: session)
        emptyStateView.isHidden = !shouldShow
        emptyStateView.setProjectTitle(session.project.title)
    }

    public override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(textView)
    }

    // MARK: - Phase 2 #10 — @-mention autocomplete

    /// Wraps the public detection + match query so callers (the
    /// completion popover, the smoke test) don't need to repeat the
    /// "read textView state → call EntityMentionContext → query
    /// EntityAutocomplete" pattern.
    public func currentMentionContext() -> (context: EntityMentionContext, matches: [EntityAutocompleteMatch])? {
        let prose = textView.string
        let cursor = textView.selectedRange().location
        guard let ctx = EntityMentionContext.detect(in: prose, cursorOffset: cursor) else { return nil }
        let matches = EntityAutocomplete.matches(for: ctx.partialQuery, in: session.project)
        return (ctx, matches)
    }

    /// Commits a chosen autocomplete match: replaces the `@xxx`
    /// substring under the cursor with the canonical entity markdown
    /// link, writes the new prose through the session, and parks the
    /// cursor at the end of the inserted markdown.
    public func applyMention(_ match: EntityAutocompleteMatch) {
        let prose = textView.string
        let cursor = textView.selectedRange().location
        guard let ctx = EntityMentionContext.detect(in: prose, cursorOffset: cursor) else { return }
        let result = ctx.applyReplacement(in: prose, with: match)
        suppressWriteback = true
        textView.string = result.prose
        suppressWriteback = false
        textView.setSelectedRange(NSRange(location: result.cursorOffset, length: 0))
        if let id = session.currentSceneId {
            session.updateProse(id: id, prose: result.prose)
            postWordCount()
        }
    }

    /// Test-only — primes the editor with prose + cursor without
    /// going through the full session-mutation path. The smoke test
    /// suite uses this to set up the cursor-in-@-context state
    /// without driving keystrokes.
    public func setCursorOffsetForTesting(_ offset: Int) {
        textView.string = session.scenes[session.currentSceneId ?? UUID()]?.prose ?? textView.string
        textView.setSelectedRange(NSRange(location: offset, length: 0))
    }

    /// Test-only — public alias for `refreshFromSession()` so smoke
    /// tests can re-pull state after mutating the session.
    public func reloadFromSession() {
        refreshFromSession()
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
            trayView.setTrayMode(.editing)
            trayView.clearInstruction()
            clearAcceptanceTint()
            lastSelectionContext = nil
            lastPerCallInstruction = ""
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
        let instruction = trayView.instructionText
        lastPerCallInstruction = instruction
        coordinator.start(
            mode: .continueProse,
            cursorOffset: cursor,
            selectionRange: nil,
            perCallInstruction: instruction.isEmpty ? nil : instruction
        )
    }

    private func handleExpand() {
        guard !coordinator.isGenerating else { return }
        guard let value = textView.selectedRanges.first as? NSValue else { return }
        let selection = value.rangeValue
        guard selection.length > 0 else { return }
        runSelectionReplacingGeneration(mode: .expand, selection: selection)
    }

    private func handleRewrite() {
        // Same mechanics as Expand — delete the selection from the
        // text view, keep it in the session for PromptBuilder to
        // read as the source passage, stream the new prose into the
        // gap. Only the mode + system prompt differ.
        guard !coordinator.isGenerating else { return }
        guard let value = textView.selectedRanges.first as? NSValue else { return }
        let selection = value.rangeValue
        guard selection.length > 0 else { return }
        runSelectionReplacingGeneration(mode: .rewrite, selection: selection)
    }

    /// Shared mechanics for selection-replacing modes (Expand, Rewrite):
    /// stash the original selection text+range for the redo path,
    /// delete the selection from the text view (keeping it in the
    /// session for PromptBuilder), and start the coordinator.
    private func runSelectionReplacingGeneration(mode: GenerationMode, selection: NSRange) {
        let nsString = textView.string as NSString
        let safeRange = NSRange(
            location: max(0, min(selection.location, nsString.length)),
            length: max(0, min(selection.length, nsString.length - max(0, min(selection.location, nsString.length))))
        )
        let originalText = nsString.substring(with: safeRange)
        lastSelectionContext = (range: selection, text: originalText)

        suppressWriteback = true
        suppressImplicitAccept = true
        textView.textStorage?.deleteCharacters(in: selection)
        textView.setSelectedRange(NSRange(location: selection.location, length: 0))
        suppressWriteback = false
        suppressImplicitAccept = false

        lastInvokedMode = mode
        textView.isEditable = false
        let instruction = trayView.instructionText
        lastPerCallInstruction = instruction
        coordinator.start(
            mode: mode,
            cursorOffset: selection.location,
            selectionRange: selection,
            perCallInstruction: instruction.isEmpty ? nil : instruction
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

        // Reconstruct the inserted range from the coordinator's
        // running offset. We need this BEFORE writing back to the
        // session so we can strip any <think>...</think> blocks
        // that leaked past the prefill suppression.
        let nsLength = (coordinator.insertedText as NSString).length
        guard nsLength > 0 else {
            if let id = session.currentSceneId {
                session.updateProse(id: id, prose: textView.string)
            }
            postWordCount()
            pushTrayState()
            return
        }
        var insertedRange = NSRange(
            location: coordinator.insertionOffset - nsLength,
            length: nsLength
        )
        insertedRange = stripThinkBlocks(in: insertedRange)

        // Sync the session's in-memory prose with what the text view
        // shows NOW (after the strip). Single writeback at finish
        // keeps the session state consistent without churning.
        if let id = session.currentSceneId {
            session.updateProse(id: id, prose: textView.string)
        }
        postWordCount()
        pushTrayState()
        DebugLog.shared.write("[editor] generation finished — text-view re-editable")
        // If stripping consumed the entire generation, treat it as a
        // failed run: don't drive the acceptance window. Restore the
        // original selection if this was Expand/Rewrite so the user
        // doesn't lose their text.
        guard insertedRange.length > 0 else {
            DebugLog.shared.write("[editor] generation finished — entirely <think> noise, skipping acceptance")
            if let saved = lastSelectionContext,
               let mode = lastInvokedMode,
               (mode == .expand || mode == .rewrite)
            {
                reinsertOriginalSelection(saved)
            }
            lastSelectionContext = nil
            lastPerCallInstruction = ""
            trayView.clearInstruction()
            return
        }

        let mode = lastInvokedMode ?? .continueProse
        acceptanceMachine.handleGenerationFinished(insertedRange: insertedRange, mode: mode)
        applyAcceptanceTint(insertedRange)
        trayView.setTrayMode(.acceptance)
    }

    /// Strip any `<think>...</think>` blocks (including trailing
    /// whitespace) from the given range in the text view. Returns the
    /// updated range whose location is unchanged but whose length
    /// reflects the cleaned text. Used at generation finish — the
    /// Qwen ChatML prefill (`<think>\n\n</think>\n\n`) usually
    /// suppresses thinking, but the model can still emit a thinking
    /// block in some prompts. Post-finish strip is a cheap safety net.
    private func stripThinkBlocks(in range: NSRange) -> NSRange {
        guard let storage = textView.textStorage else { return range }
        let nsString = storage.string as NSString
        let safeRange = NSRange(
            location: max(0, min(range.location, nsString.length)),
            length: max(0, min(range.length, nsString.length - max(0, min(range.location, nsString.length))))
        )
        let originalText = nsString.substring(with: safeRange)
        let cleaned = ThinkBlockStripper.strip(originalText)
        guard cleaned != originalText else { return safeRange }

        suppressWriteback = true
        suppressImplicitAccept = true
        let attributes: [NSAttributedString.Key: Any] = [
            .font: DesignTokens.Typography.body,
            .foregroundColor: DesignTokens.Foreground.primary,
        ]
        let replacement = NSAttributedString(string: cleaned, attributes: attributes)
        storage.replaceCharacters(in: safeRange, with: replacement)
        suppressWriteback = false
        suppressImplicitAccept = false
        DebugLog.shared.write("[editor] stripped <think> block(s): \(safeRange.length - (cleaned as NSString).length) chars removed")
        return NSRange(location: safeRange.location, length: (cleaned as NSString).length)
    }

    /// Tracks which mode the editor most recently invoked, so the
    /// acceptance machine can re-fire it on Redo. Set in
    /// handleContinue / handleExpand; consumed in handleGenerationFinish.
    private var lastInvokedMode: GenerationMode?

    /// For Expand and Rewrite: the original selection range + the
    /// prose that lived there before generation deleted it. Used by
    /// the Keep & Redo path to restore the source passage and re-fire
    /// the same mode with the same selection — without this, the redo
    /// passes `selectionRange: nil` and PromptBuilder loses the
    /// "sketch to expand" / "passage to rewrite" framing, so the
    /// model generates from the scene opening instead.
    private var lastSelectionContext: (range: NSRange, text: String)?

    /// Per-call instruction text that fired the most recent
    /// generation. Replayed verbatim on Keep & Redo so the redo
    /// honours the same one-shot steering as the original call.
    /// Cleared on accept / reject / implicit-accept (i.e. anywhere
    /// the cycle ends).
    private var lastPerCallInstruction: String = ""

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
        trayView.setTrayMode(.editing)
        clearAcceptanceTint()

        switch action {
        case .nothing:
            DebugLog.shared.write("[editor] acceptance: \(transition) — nothing")
            // No state change to the saved selection context — a
            // pure accept ends the cycle; clear it.
            if case .accept = transition {
                lastSelectionContext = nil
                lastPerCallInstruction = ""
                trayView.clearInstruction()
            }
        case .removeText(let range):
            removeRange(range, label: "reject")
            // For Expand/Rewrite the original selection was deleted
            // up-front, so a bare remove leaves a hole where the
            // user's prose used to be. Restore the original passage
            // at the same location.
            if let saved = lastSelectionContext,
               let mode = lastInvokedMode,
               (mode == .expand || mode == .rewrite)
            {
                reinsertOriginalSelection(saved)
                DebugLog.shared.write("[editor] reject: restored original selection (mode=\(mode.rawValue))")
            }
            // Reject ends the cycle.
            lastSelectionContext = nil
            lastPerCallInstruction = ""
            trayView.clearInstruction()
        case .removeAndRestart(let range, let mode):
            removeRange(range, label: "redo")
            let savedInstruction = lastPerCallInstruction
            let perCall: String? = savedInstruction.isEmpty ? nil : savedInstruction
            if mode == .expand || mode == .rewrite,
               let saved = lastSelectionContext
            {
                // Re-insert the original passage at the deletion point
                // so PromptBuilder can read it from the session again.
                // Then re-fire the same mode with the original
                // selection range AND the same per-call instruction.
                reinsertOriginalSelection(saved)
                lastInvokedMode = mode
                textView.isEditable = false
                coordinator.start(
                    mode: mode,
                    cursorOffset: saved.range.location,
                    selectionRange: saved.range,
                    perCallInstruction: perCall
                )
            } else {
                // Continue mode (or any future mode with no saved
                // selection): re-fire from the prior cursor.
                lastInvokedMode = mode
                textView.isEditable = false
                coordinator.start(
                    mode: mode,
                    cursorOffset: range.location,
                    selectionRange: nil,
                    perCallInstruction: perCall
                )
            }
        }
    }

    /// Re-insert the captured original selection text at the position
    /// it occupied before Expand/Rewrite deleted it, so PromptBuilder
    /// can read the source passage from the session on the redo's
    /// next prompt build. Suppresses the writeback path so this
    /// doesn't look like a user edit (which would implicit-accept
    /// any in-flight acceptance window).
    private func reinsertOriginalSelection(_ saved: (range: NSRange, text: String)) {
        guard let storage = textView.textStorage else { return }
        let location = max(0, min(saved.range.location, storage.length))
        suppressWriteback = true
        suppressImplicitAccept = true
        let attributed = NSAttributedString(string: saved.text, attributes: [
            .font: DesignTokens.Typography.body,
            .foregroundColor: DesignTokens.Foreground.primary,
        ])
        storage.insert(attributed, at: location)
        textView.setSelectedRange(NSRange(location: location, length: 0))
        // Sync the session so PromptBuilder sees the restored passage.
        if let id = session.currentSceneId {
            session.updateProse(id: id, prose: textView.string)
        }
        suppressWriteback = false
        suppressImplicitAccept = false
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

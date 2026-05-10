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
    private var selectionObserver: NSObjectProtocol?
    private var resizeObserver: NSObjectProtocol?
    private var textSelectionObserver: NSObjectProtocol?
    private var generationTokenObserver: NSObjectProtocol?
    private var generationFinishObserver: NSObjectProtocol?
    /// Suppresses re-entrant text writes when we programmatically swap
    /// the text storage on selection change OR when streamed tokens
    /// land at the cursor — neither should round-trip through
    /// `session.updateProse`.
    private var suppressWriteback: Bool = false

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

        container.addSubview(scroll)
        container.addSubview(tray)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: container.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: tray.topAnchor),
            tray.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tray.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tray.bottomAnchor.constraint(equalTo: container.bottomAnchor),
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

    public func textDidChange(_ notification: Notification) {
        guard !suppressWriteback else { return }
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
        // Continue uses the cursor position; if there's a selection,
        // continue from the end of it.
        let cursor: Int = {
            if let range = textView.selectedRanges.first as? NSValue {
                return NSMaxRange(range.rangeValue)
            }
            return (textView.string as NSString).length
        }()
        // Lock the text view while streaming; user can cancel via the
        // tray (1.j wires the cancel UX). Phase 1.j replaces this with
        // the proper acceptance overlay.
        textView.isEditable = false
        coordinator.start(mode: .continueProse, cursorOffset: cursor, selectionRange: nil)
    }

    private func handleExpand() {
        // 1.j scope.
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

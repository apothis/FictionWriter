import AppKit

/// The editor pane: an `NSTextView` inside an `NSScrollView`, content
/// width-bounded to `Editor.editorMaxWidth` (1080pt) and centred via
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
    // Phase 7.b.6 — parallel observers for TemplateGenerationCoordinator.
    // The userInfo shape is identical to GenerationCoordinator's by
    // design, so the handler closures share the same insertion logic.
    private var templateCoordinator: TemplateGenerationCoordinator!
    private var templateGenStartObserver: NSObjectProtocol?
    private var templateGenTokenObserver: NSObjectProtocol?
    private var templateGenFinishObserver: NSObjectProtocol?
    /// Phase 8.b.x — handler for the coordinator's per-beat
    /// sanitization notification. When the writer emits a hallucinated
    /// `[VALIDATE BEAT]` / `[BEAT CHECK]` meta-block or runs of
    /// trailing whitespace, the coordinator trims them from
    /// `insertedText` and posts a notification with the deletion
    /// range so the editor can drop the same characters from the
    /// visible text view.
    private var templateGenSanitizeObserver: NSObjectProtocol?
    private var templateGenRequestObserver: NSObjectProtocol?
    // Phase 5 — outline-draft coordinator (AppState-owned, created per
    // draft). The editor only surfaces its start/finish for feedback.
    private var outlineDraftStartObserver: NSObjectProtocol?
    private var outlineDraftFinishObserver: NSObjectProtocol?
    private var insertAgainObserver: NSObjectProtocol?
    private var pushPastRefusalObserver: NSObjectProtocol?
    private var rolledOutcomeObserver: NSObjectProtocol?
    private var keyEventMonitor: Any?
    private var mouseMovedMonitor: Any?
    private let mentionPopover = MentionPopover()
    private let hoverPopover = EntityHoverPopover()
    /// Flipped from .thinking to .streaming on the first emitted token
    /// so the tray's busy indicator reflects "model has begun replying".
    private var firstTokenSeenThisGeneration: Bool = false

    /// Phase 4 §15.10 — streaming-aware thinking-block stripper. The
    /// post-finish `ThinkBlockStripper.strip` still runs as defence-
    /// in-depth, but with Gemma 4 31B emitting `<|channel>thought…
    /// <channel|>` on every generation, the user saw the tags +
    /// thought body in the editor for ~60–120s before they got
    /// stripped post-finish. This swallows the tag + body as it
    /// streams. Reset on didStart.
    private var streamingThinkStripper = StreamingThinkBlockStripper()
    /// Cursor offset where the current generation's first visible
    /// token landed. Captured from the first emit notification so
    /// subsequent emits compute their insertion point against actual-
    /// inserted-length rather than the coordinator's raw-token
    /// offset (which counts tokens we swallowed).
    private var streamingStartOffset: Int?
    /// Total length of text actually inserted into the text view for
    /// the current generation (raw token length minus swallowed
    /// thinking-block content). Used at finish to reconstruct the
    /// inserted range for the post-finish strip + acceptance.
    private var streamingInsertedLength: Int = 0
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
        if let o = templateGenStartObserver { NotificationCenter.default.removeObserver(o) }
        if let o = templateGenTokenObserver { NotificationCenter.default.removeObserver(o) }
        if let o = templateGenFinishObserver { NotificationCenter.default.removeObserver(o) }
        if let o = templateGenSanitizeObserver { NotificationCenter.default.removeObserver(o) }
        if let o = templateGenRequestObserver { NotificationCenter.default.removeObserver(o) }
        if let o = outlineDraftStartObserver { NotificationCenter.default.removeObserver(o) }
        if let o = outlineDraftFinishObserver { NotificationCenter.default.removeObserver(o) }
        if let o = insertAgainObserver { NotificationCenter.default.removeObserver(o) }
        if let o = pushPastRefusalObserver { NotificationCenter.default.removeObserver(o) }
        if let o = rolledOutcomeObserver { NotificationCenter.default.removeObserver(o) }
        if let o = emptyStateClickedObserver { NotificationCenter.default.removeObserver(o) }
        if let o = sessionDidChangeObserver { NotificationCenter.default.removeObserver(o) }
        if let o = sessionDidReplaceObserver { NotificationCenter.default.removeObserver(o) }
        if let m = keyEventMonitor { NSEvent.removeMonitor(m) }
        if let m = mouseMovedMonitor { NSEvent.removeMonitor(m) }
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
        tray.onRewriteSubModeChosen = { [weak self] choice in self?.handleRewriteSubMode(choice) }
        tray.rewritePOVCharactersProvider = { [weak self] in
            self?.session.project.bible.characters ?? []
        }
        tray.currentSelectionTenseProvider = { [weak self] in
            self?.currentSelectionTense() ?? .unknown
        }
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
        coordinator = GenerationCoordinator(
            session: session,
            registry: AppState.shared.registry,
            styleRetriever: AppState.shared.styleRetriever()
        )
        generationStartObserver = NotificationCenter.default.addObserver(
            forName: GenerationCoordinator.didStartNotification,
            object: coordinator,
            queue: .main
        ) { [weak self] _ in
            self?.firstTokenSeenThisGeneration = false
            self?.streamingThinkStripper = StreamingThinkBlockStripper()
            self?.streamingStartOffset = nil
            self?.streamingInsertedLength = 0
            self?.trayView.setGenerationState(.thinking)
        }
        generationTokenObserver = NotificationCenter.default.addObserver(
            forName: GenerationCoordinator.didEmitTokenNotification,
            object: coordinator,
            queue: .main
        ) { [weak self] note in
            guard let self = self,
                  let token = note.userInfo?["token"] as? String,
                  let offset = note.userInfo?["insertionOffset"] as? Int else { return }
            // Capture the cursor position the first time any token
            // arrives — that's where the inserted range begins
            // regardless of whether the first tokens were thinking
            // tags we ended up swallowing.
            if self.streamingStartOffset == nil {
                self.streamingStartOffset = offset
            }
            let visible = self.streamingThinkStripper.consume(token)
            guard !visible.isEmpty else { return }
            // First visible token (post-strip): flip the busy
            // indicator from "thinking" to "streaming". Holding the
            // flip until visible prose arrives means the tray says
            // "Thinking…" while the thinking-block tokens stream
            // invisibly, which matches what the user expects.
            if !self.firstTokenSeenThisGeneration {
                self.firstTokenSeenThisGeneration = true
                self.trayView.setGenerationState(.streaming)
            }
            let insertAt = (self.streamingStartOffset ?? offset) + self.streamingInsertedLength
            self.insertGeneratedToken(visible, at: insertAt)
            self.streamingInsertedLength += (visible as NSString).length
        }
        generationFinishObserver = NotificationCenter.default.addObserver(
            forName: GenerationCoordinator.didFinishNotification,
            object: coordinator,
            queue: .main
        ) { [weak self] _ in
            self?.trayView.setGenerationState(.idle)
            self?.handleGenerationFinish()
        }

        // Phase 7.b.6 — parallel TemplateGenerationCoordinator wiring.
        // Closures mirror the GenerationCoordinator handlers above; the
        // didEmitToken userInfo shape is identical by design so the
        // streaming insertion logic is verbatim-reused.
        //
        // Phase 8.b.4 — wire `styleRetriever` to the project's
        // retrieval service so per-beat writer calls receive
        // [STYLE EXEMPLARS] blocks drawn from the project's
        // References. Same shape as GenerationCoordinator's retriever
        // (AppState.styleRetriever() resolves the service every call).
        templateCoordinator = TemplateGenerationCoordinator(
            session: session,
            writerResolver: { profileId in
                AppState.shared.registry.client(forProfileId: profileId)
            },
            appDefaultProfileIdProvider: {
                AppState.shared.settings.defaultServerId
            },
            styleRetriever: AppState.shared.styleRetriever(),
            instructTemplateResolver: {
                AppState.shared.writerInstructTemplate()
            }
        )
        templateGenStartObserver = NotificationCenter.default.addObserver(
            forName: TemplateGenerationCoordinator.didStartNotification,
            object: templateCoordinator,
            queue: .main
        ) { [weak self] _ in
            self?.firstTokenSeenThisGeneration = false
            self?.streamingThinkStripper = StreamingThinkBlockStripper()
            self?.streamingStartOffset = nil
            self?.streamingInsertedLength = 0
            self?.trayView.setGenerationState(.thinking)
        }
        templateGenTokenObserver = NotificationCenter.default.addObserver(
            forName: TemplateGenerationCoordinator.didEmitTokenNotification,
            object: templateCoordinator,
            queue: .main
        ) { [weak self] note in
            guard let self = self,
                  let token = note.userInfo?["token"] as? String,
                  let offset = note.userInfo?["insertionOffset"] as? Int else { return }
            if self.streamingStartOffset == nil {
                self.streamingStartOffset = offset
            }
            // Template-mode prose comes back beat-at-a-time, not
            // token-streaming, so the StreamingThinkBlockStripper is
            // a no-op here (no `<|channel>` tags expected). Push the
            // beat directly through the same insertion path Continue
            // uses.
            let visible = self.streamingThinkStripper.consume(token)
            guard !visible.isEmpty else { return }
            if !self.firstTokenSeenThisGeneration {
                self.firstTokenSeenThisGeneration = true
                self.trayView.setGenerationState(.streaming)
            }
            let insertAt = (self.streamingStartOffset ?? offset) + self.streamingInsertedLength
            self.insertGeneratedToken(visible, at: insertAt)
            self.streamingInsertedLength += (visible as NSString).length
        }
        templateGenSanitizeObserver = NotificationCenter.default.addObserver(
            forName: TemplateGenerationCoordinator.didSanitizeBeatNotification,
            object: templateCoordinator,
            queue: .main
        ) { [weak self] note in
            guard let self = self,
                  let storage = self.textView.textStorage,
                  let deleteFrom = note.userInfo?["deleteFromOffset"] as? Int,
                  let deleteCount = note.userInfo?["deleteCount"] as? Int,
                  deleteCount > 0
            else { return }
            let nsLength = storage.length
            // Clamp defensively — the user MAY have edited the
            // generated range mid-stream (it's still the same
            // NSTextStorage), in which case the offsets are stale.
            // Refuse to delete out-of-range characters.
            guard deleteFrom >= 0, deleteFrom + deleteCount <= nsLength else {
                DebugLog.shared.write(
                    "[template-gen-editor] sanitize delete out of range: from=\(deleteFrom) count=\(deleteCount) docLen=\(nsLength); skipping"
                )
                return
            }
            self.suppressWriteback = true
            storage.deleteCharacters(in: NSRange(location: deleteFrom, length: deleteCount))
            self.suppressWriteback = false
            self.streamingInsertedLength -= deleteCount
            // Keep the cursor at the new end-of-inserted-range so the
            // next beat's first token lands cleanly.
            let newCursor = (self.streamingStartOffset ?? 0) + self.streamingInsertedLength
            self.textView.setSelectedRange(NSRange(location: newCursor, length: 0))
        }
        templateGenFinishObserver = NotificationCenter.default.addObserver(
            forName: TemplateGenerationCoordinator.didFinishNotification,
            object: templateCoordinator,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            // Phase 8.b.x — reconcile the editor textView with the
            // coordinator's canonical insertedText. The streaming
            // path can drift from the coordinator's view in subtle
            // ways (token chunks held back by StreamingThinkBlockStripper
            // across beat boundaries, sanitize-delete clamps when
            // ranges don't line up, etc.); the 2026-05-15 third
            // smoke surfaced editor tails missing a few characters
            // per beat versus the log's rawText. Idempotent reset.
            self.reconcileTemplateGenEditorWithCoordinator()
            self.trayView.setGenerationState(.idle)
            self.handleGenerationFinish()
        }
        // Phase 5 — outline-draft feedback. The OutlineDraftCoordinator
        // is AppState-owned and created per draft, so the editor
        // observes by notification name (no `object:` filter). It does
        // background generation (no token stream) — the editor shows
        // the tray's working state for the run's duration and reloads
        // the scene's prose once the draft lands.
        outlineDraftStartObserver = NotificationCenter.default.addObserver(
            forName: OutlineDraftCoordinator.didStartNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.trayView.setGenerationState(.thinking)
        }
        outlineDraftFinishObserver = NotificationCenter.default.addObserver(
            forName: OutlineDraftCoordinator.didFinishNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.trayView.setGenerationState(.idle)
            // The coordinator wrote the prose straight to the scene;
            // reload so the text view shows it.
            self.refreshFromSession()
        }
        // Trigger observer — AppDelegate's menu item posts this with
        // `templateId` + `castMapping` after the user picks via NSAlert.
        templateGenRequestObserver = NotificationCenter.default.addObserver(
            forName: EditorViewController.requestStartTemplateGenerationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self,
                  let templateId = note.userInfo?["templateId"] as? UUID,
                  let castMapping = note.userInfo?["castMapping"] as? String
            else { return }
            let imitateContent = (note.userInfo?["imitateContent"] as? Bool) ?? false
            let extraInstruction = (note.userInfo?["extraInstruction"] as? String) ?? ""
            self.startTemplateGeneration(
                templateId: templateId,
                castMapping: castMapping,
                imitateContent: imitateContent,
                extraInstruction: extraInstruction
            )
        }
        insertAgainObserver = NotificationCenter.default.addObserver(
            forName: HistoryInspectorViewController.requestInsertAgainNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let text = note.userInfo?["text"] as? String else { return }
            self?.insertTextAtCursor(text)
        }
        pushPastRefusalObserver = NotificationCenter.default.addObserver(
            forName: HistoryInspectorViewController.requestContinueFromRefusalNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let stub = note.userInfo?["stub"] as? String,
                  let instruction = note.userInfo?["instruction"] as? String
            else { return }
            DebugLog.shared.write("[gen] continue-from-refusal: stub=\(stub.count) instruction=\(instruction.count)")
            self?.insertTextAtCursor(stub)
            self?.trayView.setInstruction(instruction)
        }
        rolledOutcomeObserver = NotificationCenter.default.addObserver(
            forName: AppDelegate.requestRolledOutcomeNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let instruction = note.userInfo?["instruction"] as? String else { return }
            let group = (note.userInfo?["group"] as? String) ?? "?"
            let entryName = (note.userInfo?["entryName"] as? String) ?? "?"
            DebugLog.shared.write("[gen] rolled-outcome: group=\(group) entry=\(entryName) instruction-chars=\(instruction.count)")
            self?.trayView.setInstruction(instruction)
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
        view.window?.acceptsMouseMovedEvents = true
        installKeyShortcutMonitorIfNeeded()
        installMouseMovedMonitorIfNeeded()
    }

    /// Phase 2 follow-on (HANDOFF §9.2) — ⌘⇧R Keep & Redo. AppKit
    /// dispatches Cmd-modified keystrokes via the responder chain
    /// rather than the NSTextView's doCommandBy path, so a local
    /// NSEvent monitor is the natural hook. Gated on acceptance state:
    /// during `.awaiting` we swallow the event; otherwise we let it
    /// pass through so the system's ⌘R bindings still work.
    private func installKeyShortcutMonitorIfNeeded() {
        guard keyEventMonitor == nil else { return }
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            // Only when our window is key — avoid swallowing keystrokes
            // for other windows in the app.
            guard self.view.window?.isKeyWindow == true else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isCmdShift = mods.contains(.command) && mods.contains(.shift)
            let isR = (event.charactersIgnoringModifiers?.lowercased() == "r")
            if isCmdShift && isR, case .awaiting = self.acceptanceMachine.state {
                self.triggerKeepAndRedoShortcut()
                DebugLog.shared.write("[editor] shortcut: ⌘⇧R Keep & Redo")
                return nil   // swallow
            }
            // Phase 2.5 — when the mention popover is visible, route
            // arrow keys / Enter / Esc to it before they reach the
            // text view (which would otherwise move the cursor /
            // insert newline / start completion).
            if self.mentionPopover.isVisible {
                // 125 = down, 126 = up, 36 = Return, 76 = numpad Enter,
                // 48 = Tab, 53 = Esc.
                switch event.keyCode {
                case 126: self.moveMentionPopoverSelection(by: -1); return nil
                case 125: self.moveMentionPopoverSelection(by: 1); return nil
                case 36, 76, 48: self.commitMentionPopoverSelection(); return nil
                case 53: self.dismissMentionPopover(); return nil
                default: break
                }
            }
            // Esc or ⌘. while generating → cancel mid-stream
            // (HANDOFF §9.2). Esc has keyCode 53; ⌘. is Cmd +
            // period. Either swallows the event so it doesn't reach
            // any default handler (Esc in NSTextView would otherwise
            // trigger system completion).
            let isEsc = (event.keyCode == 53)
            let isCmdPeriod = mods.contains(.command) && event.charactersIgnoringModifiers == "."
            if (isEsc || isCmdPeriod), self.coordinator.isGenerating {
                self.triggerCancelShortcut()
                return nil
            }
            return event
        }
    }

    // MARK: - Phase 2 follow-on — ⌘⇧R Keep & Redo shortcut (HANDOFF §9.2)

    /// Public read-only view onto the acceptance state machine —
    /// smoke tests use this to assert the shortcut transitioned the
    /// state correctly.
    public var acceptanceState: AcceptanceMachine.State { acceptanceMachine.state }

    /// Fires the Keep & Redo action when the editor is currently
    /// awaiting acceptance; no-op otherwise. Routed from the NSEvent
    /// local monitor in `viewDidAppear` on ⌘⇧R, and from this
    /// public surface for smoke tests.
    public func triggerKeepAndRedoShortcut() {
        guard case .awaiting = acceptanceMachine.state else { return }
        applyAcceptanceTransition(.redo)
    }

    /// Test-only — primes the acceptance machine into `.awaiting`
    /// without driving the full generation pipeline. The smoke test
    /// uses this to set up the state the shortcut should transition
    /// out of.
    public func primeAcceptanceForTesting(range: NSRange, mode: GenerationMode) {
        acceptanceMachine.handleGenerationFinished(insertedRange: range, mode: mode)
    }

    // MARK: - Phase 7.b.6 — template-scene generation trigger

    /// Posted by AppDelegate's "Write scene from template…" menu item
    /// (after the user picks a template + types a cast mapping in the
    /// NSAlert). The editor observes this and kicks off
    /// `TemplateGenerationCoordinator.start(...)` at the current
    /// cursor offset. `userInfo: ["templateId": UUID, "castMapping": String]`.
    public static let requestStartTemplateGenerationNotification = Notification.Name("LoomEditor.requestStartTemplateGeneration")

    /// Public entry for kicking off a template-scene generation at
    /// the current cursor. No-op if either coordinator is already
    /// generating (both pipelines write into the same text view; we
    /// don't multiplex). Surfaced as a public method so smoke tests +
    /// the AppDelegate menu both reach the same path.
    public func startTemplateGeneration(
        templateId: UUID,
        castMapping: String,
        imitateContent: Bool = false,
        extraInstruction: String = ""
    ) {
        guard !coordinator.isGenerating, !templateCoordinator.isGenerating else {
            DebugLog.shared.write("[template-gen] start aborted: a generation is already in flight")
            return
        }
        let cursorOffset = currentCursorOffset()
        DebugLog.shared.write("[template-gen] starting at cursor=\(cursorOffset) templateId=\(templateId) imitateContent=\(imitateContent) extraInstruction-chars=\(extraInstruction.count)")
        templateCoordinator.start(
            templateId: templateId,
            castMapping: castMapping,
            cursorOffset: cursorOffset,
            imitateContent: imitateContent,
            extraInstruction: extraInstruction
        )
    }

    /// Resolves the text view's current cursor offset (location of
    /// the first selected range, or end of document if no selection).
    private func currentCursorOffset() -> Int {
        guard let ranges = textView.selectedRanges as? [NSValue],
              let first = ranges.first else {
            return textView.textStorage?.length ?? 0
        }
        return first.rangeValue.location
    }

    // MARK: - Phase 2 follow-on — Esc / ⌘. mid-stream cancel (HANDOFF §9.2)

    /// Public read-only view onto the coordinator's `isGenerating`
    /// — smoke tests use this to confirm the cancel shortcut routes
    /// without crashing while idle.
    public var isGeneratingForTesting: Bool {
        coordinator.isGenerating || templateCoordinator.isGenerating
    }

    /// Cancels any in-flight generation. No-op when idle. The
    /// coordinator already exposes `cancel()`; this is the editor-
    /// level wrapper the NSEvent local monitor calls on Esc / ⌘.
    public func triggerCancelShortcut() {
        guard coordinator.isGenerating else { return }
        coordinator.cancel()
        DebugLog.shared.write("[editor] shortcut: cancel mid-stream")
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

    // MARK: - Phase 2.5 follow-on — @-mention popover

    /// Recomputes the popover state against the current cursor +
    /// project. Called from `textDidChange` AND directly from smoke
    /// tests after they prime the cursor via `setCursorOffsetForTesting`.
    public func refreshMentionPopover() {
        guard let result = currentMentionContext() else {
            mentionPopover.hide()
            return
        }
        mentionPopover.setMatches(result.matches)
        if mentionPopover.matches.isEmpty {
            // setMatches hides on empty; nothing else to do.
            return
        }
        // Wire commit/dismiss → controller routing on first use.
        if mentionPopover.onCommit == nil {
            mentionPopover.onCommit = { [weak self] in self?.commitMentionPopoverSelection() }
            mentionPopover.onDismiss = nil
        }
        // Position near the cursor. textView's selectedRange().lower
        // is the cursor; firstRect(forCharacterRange:) gives a screen
        // rect we can pin the panel below.
        if let window = view.window, let layoutMgr = textView.layoutManager, let container = textView.textContainer {
            let cursor = textView.selectedRange().location
            let glyphRange = layoutMgr.glyphRange(forCharacterRange: NSRange(location: max(0, cursor - 1), length: 1), actualCharacterRange: nil)
            var rect = layoutMgr.boundingRect(forGlyphRange: glyphRange, in: container)
            rect = rect.offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
            let inView = textView.convert(rect, to: nil)
            let onScreen = window.convertToScreen(inView)
            let origin = NSPoint(x: onScreen.origin.x, y: onScreen.origin.y - 168)   // below the line
            mentionPopover.present(at: origin, in: window)
        } else {
            // No window yet (tests) — still show "logically" so the
            // smoke can observe visibility.
            mentionPopover.present(at: .zero, in: nil)
        }
    }

    public func commitMentionPopoverSelection() {
        guard let match = mentionPopover.currentSelection() else { return }
        applyMention(match)
        mentionPopover.hide()
    }

    public func dismissMentionPopover() {
        mentionPopover.hide()
    }

    public func moveMentionPopoverSelection(by delta: Int) {
        mentionPopover.moveSelection(by: delta)
    }

    // Test-only state accessors.
    public var isMentionPopoverVisibleForTesting: Bool { mentionPopover.isVisible }
    public var mentionPopoverMatchesForTesting: [EntityAutocompleteMatch] { mentionPopover.matches }
    public var mentionPopoverSelectedIndexForTesting: Int { mentionPopover.selectedIndex }

    // MARK: - Phase 2.5 follow-on — entity-link hover preview

    /// Resolves a character-index in the current prose to a
    /// hover-info card (name + role + description excerpt) when it
    /// falls inside an entity link. Public so smoke tests can
    /// exercise the routing without driving mouseMoved events; the
    /// editor's NSEvent monitor hooks it on hover.
    public func hoverInfoAt(characterIndex: Int) -> EntityHoverInfo? {
        let prose = textView.string
        guard let hit = EntityReference.referenceAt(location: characterIndex, in: prose) else {
            return nil
        }
        return EntityHoverResolver.info(for: hit.reference.id, in: session.project)
    }

    /// Installs a `.mouseMoved` local monitor that resolves the
    /// glyph under the cursor and toggles the hover popover when it
    /// lands inside an entity-link range. Mouse-moved events only
    /// fire because `viewDidAppear` sets
    /// `window.acceptsMouseMovedEvents = true`.
    private func installMouseMovedMonitorIfNeeded() {
        guard mouseMovedMonitor == nil else { return }
        mouseMovedMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            guard let self = self else { return event }
            guard self.view.window?.isKeyWindow == true else { return event }
            self.handleMouseMoved(event)
            return event
        }
    }

    private func handleMouseMoved(_ event: NSEvent) {
        guard let layoutMgr = textView.layoutManager, let container = textView.textContainer else { return }
        let pointInWindow = event.locationInWindow
        let pointInTV = textView.convert(pointInWindow, from: nil)
        guard textView.bounds.contains(pointInTV) else {
            hoverPopover.hide()
            return
        }
        // Translate to container coordinates by undoing textContainerOrigin.
        let containerPoint = NSPoint(
            x: pointInTV.x - textView.textContainerOrigin.x,
            y: pointInTV.y - textView.textContainerOrigin.y
        )
        var fraction: CGFloat = 0
        let glyphIndex = layoutMgr.glyphIndex(for: containerPoint, in: container, fractionOfDistanceThroughGlyph: &fraction)
        // Off the end of the text → no hover.
        let glyphCount = layoutMgr.numberOfGlyphs
        guard glyphCount > 0, glyphIndex < glyphCount, fraction < 1 else {
            hoverPopover.hide()
            return
        }
        let charIndex = layoutMgr.characterIndexForGlyph(at: glyphIndex)
        guard let info = hoverInfoAt(characterIndex: charIndex) else {
            hoverPopover.hide()
            return
        }
        // Position the popover just below the hovered glyph.
        guard let window = view.window else {
            hoverPopover.hide()
            return
        }
        let glyphRange = NSRange(location: glyphIndex, length: 1)
        var rect = layoutMgr.boundingRect(forGlyphRange: glyphRange, in: container)
        rect = rect.offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
        let inView = textView.convert(rect, to: nil)
        let onScreen = window.convertToScreen(inView)
        let origin = NSPoint(x: onScreen.origin.x, y: onScreen.origin.y - 108)
        hoverPopover.show(info, at: origin, in: window)
    }

    // Test-only accessor.
    public var isHoverPopoverVisibleForTesting: Bool { hoverPopover.isVisible }

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
        refreshMentionPopover()
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
        let typed = trayView.instructionText
        runSelectionReplacingGeneration(
            mode: .expand,
            selection: selection,
            perCallInstruction: typed.isEmpty ? nil : typed
        )
    }

    /// Phase 4 §14.1 #6 — the tray's Rewrite button now pops a
    /// sub-mode picker (Voice / Tense presets / Length presets /
    /// Generic); this handler resolves the chosen
    /// `RewriteSubModeChoice` into a mode + per-call instruction and
    /// fires the shared selection-replacing path.
    private func handleRewriteSubMode(_ choice: RewriteSubModeChoice) {
        guard !coordinator.isGenerating else { return }
        guard let value = textView.selectedRanges.first as? NSValue else { return }
        let selection = value.rangeValue
        guard selection.length > 0 else { return }
        // Phase 4 §15.9 — rewriteTense no-op-target safety net. The
        // picker already disables the matching-tense entry when the
        // heuristic returns a definite verdict, but defend at click
        // time too: selection may have changed between menu-build and
        // click, or the heuristic may have shifted from .unknown to a
        // definite verdict if the menu lingered. Skip the call with a
        // tray note rather than letting the model invent a shift.
        if choice.mode == .rewriteTense,
           let target = choice.descriptor,
           selectionTenseMatchesTarget(target, in: selection)
        {
            DebugLog.shared.write("[gen] tray: rewriteTense skipped — selection already in \(target) tense")
            trayView.flashTransientNote("Selection already in \(target) tense.")
            return
        }
        let descriptor: String? = resolvedDescriptor(for: choice)
        runSelectionReplacingGeneration(
            mode: choice.mode,
            selection: selection,
            perCallInstruction: descriptor
        )
    }

    /// Phase 4 §15.9 — pull the current selection's text from the
    /// editor and classify its tense for the rewriteTense guard. nil
    /// selection or zero-length selection → `.unknown` (caller treats
    /// as "no guard").
    private func currentSelectionTense() -> SelectionTense {
        guard let value = textView.selectedRanges.first as? NSValue else { return .unknown }
        let selection = value.rangeValue
        guard selection.length > 0 else { return .unknown }
        let text = (textView.string as NSString).substring(with: selection)
        return SelectionTenseHeuristic.classify(text)
    }

    /// True when the heuristic's verdict for `selection` equals
    /// `target` ("past" or "present"). `.unknown` never matches —
    /// when the heuristic abstains, the click goes through.
    private func selectionTenseMatchesTarget(_ target: String, in selection: NSRange) -> Bool {
        let text = (textView.string as NSString).substring(with: selection)
        let verdict = SelectionTenseHeuristic.classify(text)
        return verdict.rawValue == target
    }

    /// Phase 4 §14.1 #6 + #8 — resolves the `perCallInstruction`
    /// string for a sub-mode pick. Voice pulls the tray instruction
    /// field; Tense + Length presets use the fixed descriptor; POV
    /// (§14.1 #8) looks up the target character and computes the
    /// structured descriptor from `LedgerKnowledge.compute` so the
    /// model sees the KNOWS / DOES NOT KNOW bullets it needs to
    /// avoid inventing things the new POV character couldn't know.
    /// Anything the user typed into the tray instruction field on
    /// top is appended (POV power-user override for person /
    /// limited).
    private func resolvedDescriptor(for choice: RewriteSubModeChoice) -> String? {
        if choice.usesTrayInstruction {
            let typed = trayView.instructionText
            return typed.isEmpty ? nil : typed
        }
        if choice.mode == .rewritePOV, let povId = choice.povCharacterId {
            let bible = session.project.bible
            guard let character = bible.characters.first(where: { $0.id == povId }) else {
                DebugLog.shared.write("[gen] tray: rewritePOV stale character id=\(povId); falling back to nil descriptor")
                return nil
            }
            let knowledge: LedgerKnowledge.Result
            if let sceneId = session.currentSceneId {
                knowledge = LedgerKnowledge.compute(
                    characterId: character.id,
                    asOfSceneId: sceneId,
                    in: session.project,
                    scenes: session.scenes
                )
            } else {
                knowledge = LedgerKnowledge.Result(knows: [], unknowns: [])
            }
            var descriptor = RewritePOVDescriptor.build(
                targetName: character.name,
                knowledge: knowledge
            )
            let typed = trayView.instructionText
            if !typed.isEmpty {
                descriptor += "\n\n" + typed
            }
            DebugLog.shared.write("[gen] tray: rewritePOV target=\(character.name) knows=\(knowledge.knows.count) unknowns=\(knowledge.unknowns.count)")
            return descriptor
        }
        return choice.descriptor
    }

    /// Shared mechanics for selection-replacing modes (Expand,
    /// Rewrite, RewriteVoice, RewriteTense, RewriteLength): stash
    /// the original selection text+range for the redo path, delete
    /// the selection from the text view (keeping it in the session
    /// for PromptBuilder), and start the coordinator. The caller
    /// resolves the `perCallInstruction` — for Expand + generic
    /// Rewrite + Voice it's the tray's typed text; for Tense + Length
    /// presets it's the fixed descriptor from the picker.
    private func runSelectionReplacingGeneration(
        mode: GenerationMode,
        selection: NSRange,
        perCallInstruction: String?
    ) {
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
        lastPerCallInstruction = perCallInstruction ?? ""
        coordinator.start(
            mode: mode,
            cursorOffset: selection.location,
            selectionRange: selection,
            perCallInstruction: perCallInstruction
        )
    }

    /// Insert a streamed token at the coordinator's running insertion
    /// offset. Bypasses the textDidChange writeback (the coordinator
    /// updates session prose on finish to avoid mid-stream churn).
    /// Phase 8.b.x — replace the editor's generated range with the
    /// coordinator's canonical `insertedText`. Idempotent end-of-
    /// generation reconciliation that guarantees the visible
    /// textView matches the same prose the log persists. Closes
    /// the gap between streaming + per-beat sanitize-delete + any
    /// hold-back in `StreamingThinkBlockStripper` and the
    /// authoritative prose in `templateCoordinator.insertedText`.
    private func reconcileTemplateGenEditorWithCoordinator() {
        guard let storage = textView.textStorage else { return }
        let canonical = templateCoordinator.insertedText
        let start = streamingStartOffset ?? 0
        let editorLen = streamingInsertedLength
        let nsLength = storage.length
        // Clamp the editor range — user may have edited the textView
        // mid-gen, or the streaming bookkeeping drifted in an
        // unexpected direction. Refuse to mutate beyond docLen.
        let clampedStart = max(0, min(start, nsLength))
        let clampedLen = max(0, min(editorLen, nsLength - clampedStart))
        let editorRange = NSRange(location: clampedStart, length: clampedLen)
        let canonicalLen = (canonical as NSString).length
        if editorRange.length == canonicalLen,
           storage.attributedSubstring(from: editorRange).string == canonical {
            return  // already in sync
        }
        DebugLog.shared.write(
            "[template-gen-editor] reconcile: editor-range=\(editorRange.length) canonical=\(canonicalLen) diff=\(canonicalLen - editorRange.length)"
        )
        suppressWriteback = true
        let attributes: [NSAttributedString.Key: Any] = [
            .font: DesignTokens.Typography.body,
            .foregroundColor: DesignTokens.Foreground.primary,
        ]
        let replacement = NSAttributedString(string: canonical, attributes: attributes)
        storage.replaceCharacters(in: editorRange, with: replacement)
        suppressWriteback = false
        streamingInsertedLength = canonicalLen
        let newCursor = clampedStart + canonicalLen
        textView.setSelectedRange(NSRange(location: newCursor, length: 0))
        textView.scrollRangeToVisible(NSRange(location: newCursor, length: 0))
    }

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

        // Phase 4 §15.10 — flush any residue held back by the
        // streaming stripper (e.g. unclosed thinking block, or a
        // safe-prefix that was still in flight when the stream
        // ended). The flushed text is appended at the end of the
        // already-inserted range so the post-finish strip sees the
        // complete picture.
        let residue = streamingThinkStripper.flush()
        if !residue.isEmpty {
            let insertAt = (streamingStartOffset ?? 0) + streamingInsertedLength
            insertGeneratedToken(residue, at: insertAt)
            streamingInsertedLength += (residue as NSString).length
        }

        // Reconstruct the inserted range from our streaming tracker,
        // not the coordinator's offset — the coordinator counts raw
        // emitted tokens including ones we swallowed inside thinking
        // blocks; the tracker counts only what landed in the text
        // view. The post-finish ThinkBlockStripper still runs as
        // defence-in-depth (handles any edge case the streaming
        // state machine missed; unclosed leaks would survive both).
        let nsLength = streamingInsertedLength
        guard nsLength > 0 else {
            if let id = session.currentSceneId {
                session.updateProse(id: id, prose: textView.string)
            }
            postWordCount()
            pushTrayState()
            return
        }
        var insertedRange = NSRange(
            location: streamingStartOffset ?? (coordinator.insertionOffset - nsLength),
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
               mode.isSelectionReplacing
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
            if mode.isSelectionReplacing,
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

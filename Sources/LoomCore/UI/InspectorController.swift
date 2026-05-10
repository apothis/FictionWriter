import AppKit

/// NSStackView that flips its coordinate system so content stacks
/// from the TOP down inside an NSScrollView documentView. The default
/// non-flipped coordinate system anchors origin at the bottom-left,
/// which makes short content cling to the scroll view's bottom edge
/// with a big empty gap above it.
final class FlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
}

/// Tiny "Saved" label that pops in instantly on each writeback and
/// fades out shortly after. Coalesces rapid keystrokes — one indicator
/// per inspector tab is enough; the per-keystroke writeback path simply
/// calls `flash()` after `session.updateX(...)`.
final class SaveIndicator: NSView {
    private let label = NSTextField(labelWithString: "Saved")
    private var pendingFadeOut: DispatchWorkItem?

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        label.font = DesignTokens.Typography.caption1
        label.textColor = DesignTokens.Foreground.tertiary
        label.alphaValue = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    func flash() {
        pendingFadeOut?.cancel()
        label.alphaValue = 1
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = DesignTokens.Motion.hoverFade
                self.label.animator().alphaValue = 0
            }
        }
        pendingFadeOut = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }
}

/// The tabbed inspector pane. Three tabs in Phase 1:
///   - Bible: Phase 1 minimum is characters only (name + description),
///     stacked. List-detail two-pane layout per LOOM_DESIGN_LANGUAGE.md
///     §14.5.1 lands in Phase 2.
///   - History: empty state until 1.k wires generation-log reads.
///   - Notes: free-form NSTextView bound to `project.notes`.
///
/// Selected tab is persisted on `Project.selectedInspectorTab` so a
/// reopen restores the user's context.
public final class InspectorController: NSViewController {
    public let session: ProjectSession
    private var tabButtons: [InspectorTab: NSButton] = [:]
    private var contentContainer: NSView!
    private var tabRowTopConstraint: NSLayoutConstraint?
    private var bibleVC: BibleInspectorViewController!
    private var historyVC: HistoryInspectorViewController!
    private var notesVC: NotesInspectorViewController!
    private var current: NSViewController?
    private var observer: NSObjectProtocol?

    public init(session: ProjectSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) public required init?(coder: NSCoder) { nil }

    deinit {
        if let o = observer { NotificationCenter.default.removeObserver(o) }
    }

    public override func loadView() {
        // ThemedBackgroundView re-applies its color on appearance
        // change — see file header for why a raw .cgColor capture
        // doesn't react to dark/light mode flips.
        let container = ThemedBackgroundView(backgroundColor: DesignTokens.Background.window)

        // Three NSButtons styled as tabs. CRITICAL: target + action MUST
        // be passed to NSButton(title:target:action:) at construction —
        // setting them after via `button.target = self; button.action = ...`
        // does NOT dispatch clicks on macOS 26 (clicks hit-test the
        // button correctly via the diagnostic monitor, but the action
        // selector is never invoked). The "+ Character" button right
        // below works because it wires target/action at construction.
        let bibleBtn = NSButton(title: "Bible", target: self, action: #selector(bibleTabClicked))
        let historyBtn = NSButton(title: "History", target: self, action: #selector(historyTabClicked))
        let notesBtn = NSButton(title: "Notes", target: self, action: #selector(notesTabClicked))
        for b in [bibleBtn, historyBtn, notesBtn] {
            // .recessed + .pushOnPushOff gives the classic macOS tab
            // appearance: the selected tab visually depresses (toggle
            // state). showTab(_:) flips `button.state` to .on for the
            // active tab, .off for the others.
            b.bezelStyle = .recessed
            b.setButtonType(.pushOnPushOff)
            b.controlSize = .small
            b.font = DesignTokens.Typography.subheadline
            b.translatesAutoresizingMaskIntoConstraints = false
        }
        tabButtons[.bible] = bibleBtn
        tabButtons[.history] = historyBtn
        tabButtons[.notes] = notesBtn

        let tabRow = NSStackView(views: [bibleBtn, historyBtn, notesBtn])
        tabRow.orientation = .horizontal
        tabRow.spacing = DesignTokens.Spacing.xs
        tabRow.distribution = .fillEqually
        tabRow.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        self.contentContainer = content

        container.addSubview(tabRow)
        container.addSubview(content)

        // The window uses .fullSizeContentView so the splitVC's content
        // extends INTO the titlebar area. AppKit hijacks clicks in
        // the top ~28pt of the window for window-drag, regardless of
        // what control sits there — meaning the tab buttons hit-test
        // correctly but mouseDown is never delivered. Position the
        // tab row using the WINDOW'S contentLayoutGuide, which AppKit
        // anchors below the titlebar's drag region. (The sidebar pane
        // is auto-inset by the `sidebarWithViewController` style; the
        // regular inspector pane needs this manually.)
        let tabRowTop = tabRow.topAnchor.constraint(equalTo: container.topAnchor, constant: DesignTokens.Spacing.sm)
        NSLayoutConstraint.activate([
            tabRowTop,
            tabRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: DesignTokens.Spacing.sm),
            tabRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -DesignTokens.Spacing.sm),
            content.topAnchor.constraint(equalTo: tabRow.bottomAnchor, constant: DesignTokens.Spacing.sm),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        self.tabRowTopConstraint = tabRowTop

        bibleVC = BibleInspectorViewController(session: session)
        historyVC = HistoryInspectorViewController(session: session)
        notesVC = NotesInspectorViewController(session: session)

        self.view = container

        // Restore last-viewed tab; default to Bible for fresh projects.
        let initial = session.project.selectedInspectorTab ?? .bible
        showTab(initial)

        // Reload bible on project replace (open / new). We do NOT
        // observe didChange — that fires on every keystroke into the
        // description text view (via updateCharacter → markChanged),
        // and a reload destroys + recreates the row mid-edit, killing
        // first responder. The inspector is the only mutator within
        // a session, so local reload() after add/delete is sufficient.
        observer = NotificationCenter.default.addObserver(
            forName: ProjectSession.didReplaceNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            self?.bibleVC.reload()
        }
    }

    public override func viewDidAppear() {
        super.viewDidAppear()
        // Push the tab row below the titlebar drag region. With
        // .fullSizeContentView, AppKit hijacks clicks in the top
        // ~28pt for window-drag — without this offset, tab clicks
        // hit-test correctly but the action is never delivered.
        // Earlier this used `window.contentLayoutGuide` but that
        // anchor (linking the inspector pane directly to the
        // window) was triggering a window-shrink-to-fit cascade
        // post-super.init on macOS 26. A fixed 28pt offset is the
        // standard titlebar height and avoids cross-hierarchy
        // constraint chains.
        guard let oldTop = tabRowTopConstraint,
              let tabRow = oldTop.firstItem as? NSView,
              let container = tabRow.superview
        else { return }
        let titlebarHeight: CGFloat = 28
        oldTop.constant = titlebarHeight + DesignTokens.Spacing.sm
        DebugLog.shared.write("[inspector] tab row offset below titlebar (constant=\(oldTop.constant))")
        _ = container // silence warning
    }

    @objc private func bibleTabClicked()   { DebugLog.shared.write("[inspector] tab clicked: bible");   showTab(.bible) }
    @objc private func historyTabClicked() { DebugLog.shared.write("[inspector] tab clicked: history"); showTab(.history) }
    @objc private func notesTabClicked()   { DebugLog.shared.write("[inspector] tab clicked: notes");   showTab(.notes) }

    private static func makeTabButton(title: String) -> NSButton {
        // Exact same pattern as the "+ Character" button two rows down
        // (which IS visible and IS clickable per live testing). Plain
        // NSButton, .inline bezel, .small controlSize. No LoomActionButton
        // subclass, no .recessed bezel, no .pushOnPushOff button type —
        // those variants had silent failure modes on macOS 26 (either
        // zero-height rendering or hit-tested-but-no-action-dispatch).
        let b = NSButton(title: title, target: nil, action: nil)
        b.bezelStyle = .inline
        b.controlSize = .small
        b.font = DesignTokens.Typography.subheadline
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }

    private func showTab(_ tab: InspectorTab) {
        let vc: NSViewController
        switch tab {
        case .bible:    vc = bibleVC
        case .history:  vc = historyVC
        case .notes:    vc = notesVC
        }

        // Update visual selection state across the three tab buttons.
        // (.recessed bezel + pushOnPushOff button type renders selected
        // buttons darker.)
        for (key, button) in tabButtons {
            button.state = (key == tab) ? .on : .off
        }

        if current === vc {
            session.setSelectedInspectorTab(tab)
            return
        }
        if let prev = current {
            prev.view.removeFromSuperview()
            prev.removeFromParent()
        }
        addChild(vc)
        contentContainer.addSubview(vc.view)
        vc.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            vc.view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            vc.view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            vc.view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            vc.view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
        current = vc
        session.setSelectedInspectorTab(tab)
        DebugLog.shared.write("[inspector] showTab: \(tab)")
    }
}

// MARK: - Bible tab

/// Phase 1 minimum: top "+ Character" button + vertical stack of
/// character rows (name field + description text view + delete).
/// Always-expanded (no per-row disclosure); fine for 1-3 characters
/// per the Phase 1 scope. Replaced by the list-detail two-pane in
/// Phase 2.
public final class BibleInspectorViewController: NSViewController, NSTextViewDelegate, NSTextFieldDelegate {
    public let session: ProjectSession
    private var stack: NSStackView!
    private var rows: [UUID: BibleCharacterRow] = [:]
    private let saveIndicator = SaveIndicator()

    public init(session: ProjectSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) public required init?(coder: NSCoder) { nil }

    public override func loadView() {
        let container = NSView()
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        let stack = FlippedStackView()
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

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = DesignTokens.Spacing.sm

        let title = NSTextField(labelWithString: "Characters")
        title.font = DesignTokens.Typography.headline
        title.textColor = DesignTokens.Foreground.primary

        let addBtn = NSButton(title: "+ Character", target: self, action: #selector(addCharacter))
        addBtn.bezelStyle = .inline
        addBtn.controlSize = .small
        addBtn.font = DesignTokens.Typography.subheadline

        header.addArrangedSubview(title)
        header.addArrangedSubview(saveIndicator)
        header.addArrangedSubview(NSView())   // spacer
        header.addArrangedSubview(addBtn)

        stack.addArrangedSubview(header)
        if let headerView = stack.arrangedSubviews.first {
            headerView.translatesAutoresizingMaskIntoConstraints = false
            headerView.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -2 * DesignTokens.Spacing.md).isActive = true
        }

        scroll.documentView = stack
        container.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: container.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.widthAnchor),
        ])

        self.stack = stack
        self.view = container

        reload()
    }

    @objc private func addCharacter() {
        let name = "Character \(session.project.bible.characters.count + 1)"
        _ = session.addCharacter(name: name)
        reload()
    }

    public func reload() {
        guard let stack = stack else { return }
        // Drop existing rows; rebuild from session.
        for row in rows.values {
            row.view.removeFromSuperview()
        }
        rows.removeAll()
        for character in session.project.bible.characters {
            let row = BibleCharacterRow(character: character) { [weak self] updated in
                self?.session.updateCharacter(updated)
                self?.saveIndicator.flash()
            } onDelete: { [weak self] id in
                self?.session.deleteCharacter(id: id)
                self?.reload()
            }
            row.view.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(row.view)
            row.view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -2 * DesignTokens.Spacing.md).isActive = true
            rows[character.id] = row
        }
    }
}

/// One character entry in the Bible tab: name field + description text
/// view + delete button. Stored as a class so we can hold a reference
/// to wire the text-view delegate.
final class BibleCharacterRow {
    let character: Character
    let view: NSView
    private let nameField: NSTextField
    private let descriptionView: NSTextView
    private let onUpdate: (Character) -> Void
    private let onDelete: (UUID) -> Void

    init(
        character: Character,
        onUpdate: @escaping (Character) -> Void,
        onDelete: @escaping (UUID) -> Void
    ) {
        self.character = character
        self.onUpdate = onUpdate
        self.onDelete = onDelete

        let container = ThemedBackgroundView(backgroundColor: DesignTokens.Background.group)
        container.layer?.cornerRadius = DesignTokens.Radius.section

        let name = NSTextField(string: character.name)
        name.font = DesignTokens.Typography.headline
        name.translatesAutoresizingMaskIntoConstraints = false
        name.placeholderString = "Name"
        self.nameField = name

        // Standard programmatic NSTextView-in-NSScrollView setup
        // (matches EditorViewController's text view). Leaving
        // translatesAutoresizingMaskIntoConstraints at the default
        // (true) + setting autoresizingMask = .width lets the
        // scroll view manage the document view's frame; without
        // that, the text container stays at default size and clicks
        // miss the glyph area, making the view appear unresponsive.
        let desc = NSTextView()
        desc.font = DesignTokens.Typography.body
        desc.string = character.description
        desc.isRichText = false
        desc.isEditable = true
        desc.allowsUndo = true
        desc.isAutomaticTextReplacementEnabled = false
        desc.isAutomaticQuoteSubstitutionEnabled = false
        desc.drawsBackground = false
        desc.textContainerInset = NSSize(width: DesignTokens.Spacing.sm, height: DesignTokens.Spacing.sm)
        desc.minSize = NSSize(width: 0, height: 0)
        desc.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        desc.isHorizontallyResizable = false
        desc.isVerticallyResizable = true
        desc.autoresizingMask = [.width]
        desc.textContainer?.widthTracksTextView = true
        desc.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        self.descriptionView = desc

        let descScroll = NSScrollView()
        descScroll.translatesAutoresizingMaskIntoConstraints = false
        descScroll.borderType = .lineBorder
        descScroll.hasVerticalScroller = true
        descScroll.documentView = desc

        let deleteBtn = NSButton(title: "Delete", target: nil, action: nil)
        deleteBtn.bezelStyle = .inline
        deleteBtn.controlSize = .small
        deleteBtn.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(name)
        container.addSubview(descScroll)
        container.addSubview(deleteBtn)

        NSLayoutConstraint.activate([
            name.topAnchor.constraint(equalTo: container.topAnchor, constant: DesignTokens.Spacing.sm),
            name.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: DesignTokens.Spacing.sm),
            deleteBtn.centerYAnchor.constraint(equalTo: name.centerYAnchor),
            deleteBtn.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -DesignTokens.Spacing.sm),
            name.trailingAnchor.constraint(equalTo: deleteBtn.leadingAnchor, constant: -DesignTokens.Spacing.sm),
            descScroll.topAnchor.constraint(equalTo: name.bottomAnchor, constant: DesignTokens.Spacing.sm),
            descScroll.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: DesignTokens.Spacing.sm),
            descScroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -DesignTokens.Spacing.sm),
            descScroll.heightAnchor.constraint(equalToConstant: 80),
            descScroll.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -DesignTokens.Spacing.sm),
        ])

        self.view = container

        // Wire after init so self-references resolve.
        let bridge = BibleCharacterRowBridge(row: self)
        objc_setAssociatedObject(container, &BibleCharacterRowBridge.key, bridge, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        name.target = bridge
        name.action = #selector(BibleCharacterRowBridge.nameEdited(_:))
        desc.delegate = bridge
        deleteBtn.target = bridge
        deleteBtn.action = #selector(BibleCharacterRowBridge.deletePressed(_:))
    }

    fileprivate func emitUpdate() {
        var updated = character
        updated.name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.description = descriptionView.string
        onUpdate(updated)
    }

    fileprivate func emitDelete() {
        onDelete(character.id)
    }
}

/// Objective-C bridge to dispatch text-field action and text-view
/// delegate callbacks back to the Swift `BibleCharacterRow`. Stored
/// via objc_setAssociatedObject so the row's lifetime tracks the view's.
private final class BibleCharacterRowBridge: NSObject, NSTextViewDelegate {
    static var key: UInt8 = 0
    weak var row: BibleCharacterRow?
    init(row: BibleCharacterRow) { self.row = row }

    @objc func nameEdited(_ sender: Any) {
        row?.emitUpdate()
    }
    @objc func deletePressed(_ sender: Any) {
        row?.emitDelete()
    }
    func textDidChange(_ notification: Notification) {
        row?.emitUpdate()
    }
}

// MARK: - Notes tab

/// Free-form notepad bound to `Project.notes`. Plain text NSTextView
/// in a scroll view. No find bar (notes are short by definition;
/// users find via the editor's find).
public final class NotesInspectorViewController: NSViewController, NSTextViewDelegate {
    public let session: ProjectSession
    private var textView: NSTextView!
    private var suppressWriteback: Bool = false
    private let saveIndicator = SaveIndicator()

    public init(session: ProjectSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) public required init?(coder: NSCoder) { nil }

    public override func loadView() {
        let container = NSView()
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        // Standard programmatic NSTextView-in-NSScrollView setup
        // (autoresizingMask + isVerticallyResizable so the scroll view
        // can manage the document view's frame; without this the text
        // container stays at default size and clicks miss the glyph area).
        let tv = NSTextView()
        tv.delegate = self
        tv.isRichText = false
        tv.isEditable = true
        tv.allowsUndo = true
        tv.isAutomaticTextReplacementEnabled = false
        tv.font = DesignTokens.Typography.body
        tv.textContainerInset = NSSize(width: DesignTokens.Spacing.md, height: DesignTokens.Spacing.md)
        tv.drawsBackground = true
        tv.backgroundColor = DesignTokens.Background.textInput
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isHorizontallyResizable = false
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        suppressWriteback = true
        tv.string = session.project.notes
        suppressWriteback = false
        scroll.documentView = tv
        self.textView = tv

        // Slim header carries the shared save indicator. The Bible tab
        // gets its indicator inside its existing "Characters" row; Notes
        // has no native header otherwise, so this strip is the minimum
        // chrome needed to surface "Saved" feedback.
        let header = NSStackView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = DesignTokens.Spacing.sm
        header.edgeInsets = NSEdgeInsets(
            top: 0,
            left: DesignTokens.Spacing.md,
            bottom: 0,
            right: DesignTokens.Spacing.md
        )
        header.addArrangedSubview(NSView())
        header.addArrangedSubview(saveIndicator)

        container.addSubview(header)
        container.addSubview(scroll)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor, constant: DesignTokens.Spacing.xs),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: DesignTokens.Spacing.xs),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        self.view = container
    }

    public func textDidChange(_ notification: Notification) {
        guard !suppressWriteback else { return }
        session.updateNotes(textView.string)
        saveIndicator.flash()
    }
}

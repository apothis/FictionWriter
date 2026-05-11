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
    /// Phase 4 #7 sub-task 4 — optional AppState handle so the Bible
    /// inspector can render the per-character Suggestions section
    /// (queue + accept/reject). Nil in unit tests; the production
    /// MainWindowController passes `AppState.shared`.
    public let appState: AppState?
    private var tabButtons: [InspectorTab: NSButton] = [:]
    private var contentContainer: NSView!
    private var tabRowTopConstraint: NSLayoutConstraint?
    private var bibleVC: BibleInspectorViewController!
    private var historyVC: HistoryInspectorViewController!
    private var notesVC: NotesInspectorViewController!
    private var current: NSViewController?
    private var observer: NSObjectProtocol?

    public init(session: ProjectSession, appState: AppState? = nil) {
        self.session = session
        self.appState = appState
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
        tabRow.alignment = .centerY
        tabRow.translatesAutoresizingMaskIntoConstraints = false
        // Pin the tab row to its button-row height. Without this, the
        // vertical chain (tabRow.top → content.top → content.bottom)
        // leaves Auto Layout free to grow the row to fill — observed
        // at 373pt in a 458pt-tall pane, with the buttons centered
        // inside the bloated stack and the bible content squashed.
        // Use NON-required priority: a `.required` height (or
        // `.required` content hugging) propagates into the contentView
        // fittingSize and triggers the macOS-26 auto-refit cascade
        // that snaps the window's height down to ~127pt every layout
        // pass (per HANDOFF §2.1). `.defaultHigh + 1` (751) wins over
        // the stack's default low hugging priority but isn't strong
        // enough to participate in fittingSize. (Pinned by
        // Phase4InspectorLayoutTests.)
        let tabRowHeight = tabRow.heightAnchor.constraint(equalToConstant: 24)
        tabRowHeight.priority = NSLayoutConstraint.Priority(rawValue: 751)
        tabRowHeight.isActive = true

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

        bibleVC = BibleInspectorViewController(session: session, appState: appState)
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

// MARK: - Bible tab (list-detail two-pane, Phase 2 #4)

/// Phase 2 #4 — list-detail two-pane Bible inspector. Top filter strip
/// (All / Characters / Settings / Objects); left 40% list of sectioned
/// entities with `+` add-buttons; right 60% detail pane for the
/// selected entity.
///
/// Filter + selection state lives on `viewModel` (BibleInspectorViewModel
/// — pure-data, tested in Phase2BibleViewModelTests). This controller
/// is the rendering + event-routing layer; smoke tests for the public
/// surface live in Phase2BibleInspectorMountTests.
///
/// Per-entity sub-tabs (Description / Knowledge ledger / Relationships /
/// Mentions / Notes per LOOM_DESIGN_LANGUAGE.md §14.5.1) defer to a
/// follow-on: most contain Phase 4+ data (knowledge ledger, mentions)
/// or aren't materially different from the flat form. Phase 2 ships
/// the structural list-detail layout the spec calls for.
public final class BibleInspectorViewController: NSViewController, NSTextViewDelegate, NSTextFieldDelegate {
    public let session: ProjectSession
    public let appState: AppState?
    public let viewModel = BibleInspectorViewModel()
    private let saveIndicator = SaveIndicator()
    private var filterButtons: [BibleFilter: NSButton] = [:]
    private var listStack: NSStackView!
    private var detailContainer: NSView!
    private var detailEditor: BibleDetailEditor?
    private var sessionObserver: NSObjectProtocol?
    private var suggestionsObserver: NSObjectProtocol?

    public init(session: ProjectSession, appState: AppState? = nil) {
        self.session = session
        self.appState = appState
        super.init(nibName: nil, bundle: nil)
    }

    deinit {
        if let obs = sessionObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        if let obs = suggestionsObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    @available(*, unavailable) public required init?(coder: NSCoder) { nil }

    public override func loadView() {
        let container = NSView()

        // Top filter strip — 4 toggle buttons.
        let filterStrip = NSStackView()
        filterStrip.orientation = .horizontal
        filterStrip.alignment = .centerY
        filterStrip.spacing = DesignTokens.Spacing.xs
        filterStrip.translatesAutoresizingMaskIntoConstraints = false
        filterStrip.edgeInsets = NSEdgeInsets(
            top: DesignTokens.Spacing.sm,
            left: DesignTokens.Spacing.md,
            bottom: DesignTokens.Spacing.sm,
            right: DesignTokens.Spacing.md
        )
        // Same fix as the outer tab row — non-required height pin so
        // the bible's filterStrip doesn't balloon to fill, but the
        // constraint stays below the priority threshold that would
        // make AppKit treat it as a fittingSize requirement and
        // trigger the macOS-26 auto-refit-to-fit cascade.
        let filterStripHeight = filterStrip.heightAnchor.constraint(equalToConstant: 32)
        filterStripHeight.priority = NSLayoutConstraint.Priority(rawValue: 751)
        filterStripHeight.isActive = true

        let allBtn = makeFilterButton(title: "All", filter: .all)
        filterStrip.addArrangedSubview(allBtn)
        filterButtons[.all] = allBtn
        for category in BibleCategory.allCases {
            let btn = makeFilterButton(title: category.displayName, filter: .category(category))
            filterStrip.addArrangedSubview(btn)
            filterButtons[.category(category)] = btn
        }
        filterStrip.addArrangedSubview(NSView())   // trailing spacer
        filterStrip.addArrangedSubview(saveIndicator)

        // Left list pane — scrollable sectioned list.
        let listScroll = NSScrollView()
        listScroll.translatesAutoresizingMaskIntoConstraints = false
        listScroll.hasVerticalScroller = true
        listScroll.drawsBackground = false
        listScroll.borderType = .noBorder

        let stack = FlippedStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = DesignTokens.Spacing.sm
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(
            top: DesignTokens.Spacing.sm,
            left: DesignTokens.Spacing.sm,
            bottom: DesignTokens.Spacing.sm,
            right: DesignTokens.Spacing.sm
        )
        listScroll.documentView = stack
        self.listStack = stack

        // Right detail pane — replaceable container.
        let detail = NSView()
        detail.translatesAutoresizingMaskIntoConstraints = false
        self.detailContainer = detail

        // Vertical divider between list + detail.
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(filterStrip)
        container.addSubview(listScroll)
        container.addSubview(divider)
        container.addSubview(detail)

        NSLayoutConstraint.activate([
            filterStrip.topAnchor.constraint(equalTo: container.topAnchor),
            filterStrip.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            filterStrip.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            listScroll.topAnchor.constraint(equalTo: filterStrip.bottomAnchor),
            listScroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            listScroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            // 40% width — Novelcrafter B.2.1 list-detail proportion
            // (LOOM_DESIGN_LANGUAGE.md §14.5.1).
            listScroll.widthAnchor.constraint(equalTo: container.widthAnchor, multiplier: 0.4),

            divider.topAnchor.constraint(equalTo: listScroll.topAnchor),
            divider.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: listScroll.trailingAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),

            detail.topAnchor.constraint(equalTo: listScroll.topAnchor),
            detail.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            detail.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            detail.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            // Stack's width must equal its scroll-clip's; without
            // this, flipped stack content collapses to intrinsic
            // width and rows clip on the right.
            stack.widthAnchor.constraint(equalTo: listScroll.widthAnchor),

            // Required floor on the list scroll view's height. This is
            // load-bearing for the window: macOS-26's auto-refit-to-
            // fittingSize cascade snaps the window's height down to
            // the contentView's Auto-Layout fittingSize, and `minSize`
            // / `contentMinSize` are ignored by the cascade. The only
            // thing the cascade can't override is a `.required` Auto-
            // Layout constraint. Pin the list (which has no intrinsic
            // height of its own) to a 400pt floor — that pushes the
            // inspector's fittingSize to ~500pt, and (since the
            // inspector is the tallest split-item content) the
            // window's fittingSize to ~520pt. The window can't shrink
            // below that. (The constraint is `greaterThanOrEqual`, so
            // the list happily grows above 400pt when there's room.)
            listScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 400),
        ])

        self.view = container

        // Auto-pick a sensible initial selection if entities exist.
        viewModel.reconcileSelection(in: session.project)

        // Re-render on any project mutation (this VC's edits, another
        // tab's edits, undo).
        sessionObserver = NotificationCenter.default.addObserver(
            forName: ProjectSession.didChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            self?.reload()
        }

        // Phase 4 #7 sub-task 4 — refresh the per-character Suggestions
        // panel when the ledger queue mutates (new extraction lands,
        // user accepts/rejects).
        if let appState = appState {
            suggestionsObserver = NotificationCenter.default.addObserver(
                forName: AppState.ledgerSuggestionsDidChangeNotification,
                object: appState,
                queue: .main
            ) { [weak self] _ in
                self?.renderDetail()
            }
        }

        reload()
    }

    // MARK: Public surface (mount smoke tests + parent VC)

    public func setFilter(_ filter: BibleFilter) {
        viewModel.setFilter(filter, in: session.project)
        viewModel.reconcileSelection(in: session.project)
        reload()
    }

    public func selectEntity(_ ref: BibleEntityRef?) {
        viewModel.setSelection(ref)
        reload()
    }

    /// Creates a new entity in the given category and selects it.
    @discardableResult
    public func addEntity(in category: BibleCategory) -> BibleEntityRef {
        let ref: BibleEntityRef
        switch category {
        case .characters:
            let next = session.project.bible.characters.count + 1
            let c = session.addCharacter(name: "Character \(next)")
            ref = BibleEntityRef(category: .characters, id: c.id)
        case .settings:
            let next = session.project.bible.settings.count + 1
            let s = session.addSetting(name: "Setting \(next)")
            ref = BibleEntityRef(category: .settings, id: s.id)
        case .objects:
            let next = session.project.bible.objects.count + 1
            let o = session.addObject(name: "Object \(next)")
            ref = BibleEntityRef(category: .objects, id: o.id)
        }
        viewModel.setSelection(ref)
        // The session-change observer would also re-render, but it
        // posts async to the main queue; call reload synchronously so
        // the test (and the user's "click + and the new entity is
        // selected" expectation) holds immediately.
        reload()
        return ref
    }

    public func deleteSelected() {
        guard let sel = viewModel.selection else { return }
        switch sel.category {
        case .characters: session.deleteCharacter(id: sel.id)
        case .settings:   session.deleteSetting(id: sel.id)
        case .objects:    session.deleteObject(id: sel.id)
        }
        viewModel.setSelection(nil)
        reload()
    }

    /// Phase 2 #11 — total mentions of an entity across all scenes
    /// in the current project. Reads from a freshly-built MentionIndex
    /// each call (Phase 2 scope; if the manuscript gets large the
    /// caller can cache across reloads).
    public func mentionCount(for ref: BibleEntityRef) -> Int {
        MentionIndex
            .build(for: session.project, scenes: session.scenes)
            .totalCount(for: ref.id)
    }

    /// Phase 2.5 (#11 follow-on) — builds the sparkline layout for
    /// an entity. The manuscript order for Phase 1 is just
    /// `orphanedSceneIds`; Phase 3's Part/Chapter hierarchy will
    /// supersede this with a flat-walk of the tree.
    public func sparklineLayout(for ref: BibleEntityRef) -> MentionSparklineLayout {
        let index = MentionIndex.build(for: session.project, scenes: session.scenes)
        let perScene = index.perSceneByEntityId[ref.id] ?? [:]
        return MentionSparklineLayout.build(
            sceneOrder: session.project.manuscript.orphanedSceneIds,
            mentionsBySceneId: perScene
        )
    }

    /// Phase 2.5 (#11 follow-on) — switches the active scene. The
    /// editor listens on `selectionDidChangeNotification` and pulls
    /// the new scene's prose into the text view.
    public func scrollToScene(_ sceneId: UUID) {
        session.selectScene(id: sceneId)
    }

    /// Phase 2 #7 — sets the injection mode on the currently-selected
    /// entity. Routed from the detail editor's mode pill.
    public func setInjectionMode(_ mode: InjectionMode) {
        guard let sel = viewModel.selection else { return }
        session.setInjectionMode(mode, for: sel)
        // The session-change observer reloads, but call sync so the
        // detail editor's mode pill reflects the new value
        // immediately.
        reload()
    }

    public func reload() {
        guard let stack = listStack else { return }
        // A delete elsewhere may have invalidated our ref.
        viewModel.reconcileSelection(in: session.project)
        renderList(into: stack)
        updateFilterButtonStates()
        renderDetail()
    }

    // MARK: Rendering

    private func makeFilterButton(title: String, filter: BibleFilter) -> NSButton {
        let btn = NSButton(title: title, target: self, action: #selector(filterButtonClicked(_:)))
        btn.bezelStyle = .recessed
        btn.setButtonType(.pushOnPushOff)
        btn.font = DesignTokens.Typography.subheadline
        // Carry the filter on the identifier so the action doesn't
        // need a per-filter selector.
        btn.identifier = NSUserInterfaceItemIdentifier(filter.identifierString)
        return btn
    }

    private func updateFilterButtonStates() {
        for (filter, btn) in filterButtons {
            btn.state = (filter == viewModel.filter) ? .on : .off
        }
    }

    private func renderList(into stack: NSStackView) {
        for view in stack.arrangedSubviews {
            view.removeFromSuperview()
        }
        let project = session.project
        for section in viewModel.sections(for: project) {
            let header = makeSectionHeader(section)
            stack.addArrangedSubview(header)
            header.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -2 * DesignTokens.Spacing.sm).isActive = true

            for item in section.items {
                let row = makeEntityRow(item)
                stack.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -2 * DesignTokens.Spacing.sm).isActive = true
            }
        }
    }

    private func makeSectionHeader(_ section: BibleSectionRow) -> NSView {
        let row = NSStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = DesignTokens.Spacing.xs

        let title = NSTextField(labelWithString: section.title)
        title.font = DesignTokens.Typography.caption1
        title.textColor = DesignTokens.Foreground.secondary

        let count = NSTextField(labelWithString: "\(section.items.count)")
        count.font = DesignTokens.Typography.caption1
        count.textColor = DesignTokens.Foreground.tertiary

        let addBtn = NSButton(title: "+", target: self, action: #selector(sectionAddButtonClicked(_:)))
        addBtn.bezelStyle = .inline
        addBtn.controlSize = .small
        addBtn.font = DesignTokens.Typography.subheadline
        addBtn.identifier = NSUserInterfaceItemIdentifier(section.category.rawValue)

        row.addArrangedSubview(title)
        row.addArrangedSubview(count)
        row.addArrangedSubview(NSView())   // spacer
        row.addArrangedSubview(addBtn)
        return row
    }

    private func makeEntityRow(_ item: BibleEntityListItem) -> NSView {
        let isSelected = (viewModel.selection == item.ref)
        let btn = BibleEntityRowButton(ref: item.ref, target: self, action: #selector(entityRowClicked(_:)))
        btn.title = item.name.isEmpty ? "Untitled" : item.name
        btn.isSelectedRow = isSelected
        return btn
    }

    private func renderDetail() {
        for subview in detailContainer.subviews {
            subview.removeFromSuperview()
        }
        detailEditor = nil

        guard let sel = viewModel.selection else {
            let empty = NSTextField(labelWithString: "Select an entity to view details.")
            empty.font = DesignTokens.Typography.body
            empty.textColor = DesignTokens.Foreground.tertiary
            empty.translatesAutoresizingMaskIntoConstraints = false
            detailContainer.addSubview(empty)
            NSLayoutConstraint.activate([
                empty.centerXAnchor.constraint(equalTo: detailContainer.centerXAnchor),
                empty.centerYAnchor.constraint(equalTo: detailContainer.centerYAnchor),
            ])
            return
        }
        // Phase 4 #7 sub-task 4 — suggestions pulled from AppState if
        // wired; empty array otherwise. Only characters carry ledger
        // suggestions (settings/objects don't).
        let suggestions: [LedgerSuggestion] = {
            guard let appState = appState, sel.category == .characters else { return [] }
            return appState.ledgerSuggestionsQueue.suggestions(forCharacter: sel.id)
        }()
        let editor = BibleDetailEditor(
            ref: sel,
            session: session,
            mentionCount: mentionCount(for: sel),
            sparklineLayout: sparklineLayout(for: sel),
            suggestions: suggestions,
            onChanged: { [weak self] in self?.saveIndicator.flash() },
            onDelete: { [weak self] in self?.deleteSelected() },
            onInjectionModeChanged: { [weak self] mode in self?.setInjectionMode(mode) },
            onSparklineMarkerClicked: { [weak self] sceneId in self?.scrollToScene(sceneId) },
            onAcceptSuggestion: { [weak self] suggestion in self?.appState?.acceptLedgerSuggestion(suggestion) },
            onRejectSuggestion: { [weak self] factId in self?.appState?.rejectLedgerSuggestion(factId: factId) }
        )
        editor.view.translatesAutoresizingMaskIntoConstraints = false
        detailContainer.addSubview(editor.view)
        NSLayoutConstraint.activate([
            editor.view.topAnchor.constraint(equalTo: detailContainer.topAnchor),
            editor.view.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            editor.view.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
            editor.view.bottomAnchor.constraint(equalTo: detailContainer.bottomAnchor),
        ])
        self.detailEditor = editor
    }

    // MARK: Actions

    @objc private func filterButtonClicked(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue,
              let filter = BibleFilter(identifierString: raw)
        else { return }
        setFilter(filter)
    }

    @objc private func sectionAddButtonClicked(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue,
              let category = BibleCategory(rawValue: raw)
        else { return }
        addEntity(in: category)
    }

    @objc private func entityRowClicked(_ sender: BibleEntityRowButton) {
        selectEntity(sender.ref)
    }
}

// MARK: - List row button (carries a ref + a selection highlight)

private final class BibleEntityRowButton: NSButton {
    let ref: BibleEntityRef
    var isSelectedRow: Bool = false {
        didSet { needsDisplay = true }
    }

    init(ref: BibleEntityRef, target: AnyObject?, action: Selector) {
        self.ref = ref
        super.init(frame: .zero)
        self.target = target
        self.action = action
        self.bezelStyle = .inline
        self.isBordered = false
        self.font = DesignTokens.Typography.body
        self.contentTintColor = DesignTokens.Foreground.primary
        self.alignment = .left
        self.translatesAutoresizingMaskIntoConstraints = false
        self.wantsLayer = true
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        if isSelectedRow {
            DesignTokens.Background.selectedRow.setFill()
            let path = NSBezierPath(
                roundedRect: bounds,
                xRadius: DesignTokens.Radius.control,
                yRadius: DesignTokens.Radius.control
            )
            path.fill()
        }
        super.draw(dirtyRect)
    }
}

// MARK: - Detail editor (right pane)

/// Phase 2 minimum-viable detail form: name field + description text
/// view + delete button. Wires straight through to ProjectSession's
/// update*/delete* per the selected entity's category. Sub-tabs
/// (Knowledge ledger, Relationships, Mentions) defer to follow-ons —
/// most depend on Phase 4 data that doesn't exist yet.
private final class BibleDetailEditor {
    let view: NSView
    private let ref: BibleEntityRef
    private let session: ProjectSession
    private let nameField: NSTextField
    private let descriptionView: NSTextView
    private let injectionPicker: NSPopUpButton
    private let onChanged: () -> Void
    private let onDelete: () -> Void
    private let onInjectionModeChanged: (InjectionMode) -> Void
    private var bridge: BibleDetailBridge!

    init(
        ref: BibleEntityRef,
        session: ProjectSession,
        mentionCount: Int,
        sparklineLayout: MentionSparklineLayout,
        suggestions: [LedgerSuggestion] = [],
        onChanged: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onInjectionModeChanged: @escaping (InjectionMode) -> Void,
        onSparklineMarkerClicked: @escaping (UUID) -> Void,
        onAcceptSuggestion: @escaping (LedgerSuggestion) -> Void = { _ in },
        onRejectSuggestion: @escaping (UUID) -> Void = { _ in }
    ) {
        self.ref = ref
        self.session = session
        self.onChanged = onChanged
        self.onDelete = onDelete
        self.onInjectionModeChanged = onInjectionModeChanged

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let (initialName, initialDescription, initialMode) = Self.snapshot(ref: ref, session: session)

        let name = NSTextField(string: initialName)
        name.font = DesignTokens.Typography.title2
        name.translatesAutoresizingMaskIntoConstraints = false
        name.placeholderString = "Name"
        name.bezelStyle = .roundedBezel
        self.nameField = name

        // Phase 2 #7 — injection mode pill (Constant | Keyed).
        let modePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        modePopup.bezelStyle = .rounded
        modePopup.controlSize = .small
        modePopup.font = DesignTokens.Typography.subheadline
        modePopup.translatesAutoresizingMaskIntoConstraints = false
        modePopup.addItem(withTitle: "Constant")
        modePopup.addItem(withTitle: "Keyed")
        modePopup.toolTip = "Constant: always injected. Keyed: injected when the name/alias appears in recent prose."
        modePopup.selectItem(at: initialMode == .keyed ? 1 : 0)
        self.injectionPicker = modePopup

        let desc = NSTextView()
        desc.font = DesignTokens.Typography.body
        desc.string = initialDescription
        desc.isRichText = false
        desc.isEditable = true
        desc.allowsUndo = true
        desc.isAutomaticTextReplacementEnabled = false
        desc.isAutomaticQuoteSubstitutionEnabled = false
        desc.drawsBackground = true
        desc.backgroundColor = DesignTokens.Background.textInput
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

        // Inject-mode row sits between the name field and the
        // description: "Inject: [Constant | Keyed]". The pill is the
        // user-facing affordance for Phase 2 #7. Phase 2 #11 +
        // Phase 2.5 polish — trailing edge carries the mention
        // sparkline bar + count caption per §14.5.1.
        let modeRow = NSStackView()
        modeRow.translatesAutoresizingMaskIntoConstraints = false
        modeRow.orientation = .horizontal
        modeRow.alignment = .centerY
        modeRow.spacing = DesignTokens.Spacing.sm
        let modeLabel = NSTextField(labelWithString: "Inject:")
        modeLabel.font = DesignTokens.Typography.subheadline
        modeLabel.textColor = DesignTokens.Foreground.secondary

        let sparkline = MentionSparklineView()
        sparkline.translatesAutoresizingMaskIntoConstraints = false
        sparkline.setLayout(sparklineLayout)
        sparkline.onMarkerClicked = onSparklineMarkerClicked

        let mentionCaption = NSTextField(labelWithString: mentionCount == 1 ? "1 mention" : "\(mentionCount) mentions")
        mentionCaption.font = DesignTokens.Typography.caption1
        mentionCaption.textColor = DesignTokens.Foreground.tertiary

        modeRow.addArrangedSubview(modeLabel)
        modeRow.addArrangedSubview(modePopup)
        modeRow.addArrangedSubview(sparkline)
        modeRow.addArrangedSubview(mentionCaption)
        sparkline.widthAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true
        sparkline.heightAnchor.constraint(equalToConstant: 14).isActive = true

        // Phase 4 #7 sub-task 4 — Suggestions panel (characters only,
        // and only when there's at least one pending suggestion).
        // Sits between modeRow and the description so it surfaces
        // when present but doesn't claim screen space otherwise.
        let suggestionsPanel = SuggestionsPanelBuilder.build(
            suggestions: suggestions,
            onAccept: onAcceptSuggestion,
            onReject: onRejectSuggestion
        )

        container.addSubview(name)
        container.addSubview(modeRow)
        container.addSubview(suggestionsPanel)
        container.addSubview(descScroll)
        container.addSubview(deleteBtn)

        NSLayoutConstraint.activate([
            name.topAnchor.constraint(equalTo: container.topAnchor, constant: DesignTokens.Spacing.md),
            name.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: DesignTokens.Spacing.md),
            deleteBtn.centerYAnchor.constraint(equalTo: name.centerYAnchor),
            deleteBtn.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -DesignTokens.Spacing.md),
            name.trailingAnchor.constraint(equalTo: deleteBtn.leadingAnchor, constant: -DesignTokens.Spacing.sm),

            modeRow.topAnchor.constraint(equalTo: name.bottomAnchor, constant: DesignTokens.Spacing.sm),
            modeRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: DesignTokens.Spacing.md),
            modeRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -DesignTokens.Spacing.md),

            suggestionsPanel.topAnchor.constraint(equalTo: modeRow.bottomAnchor, constant: DesignTokens.Spacing.sm),
            suggestionsPanel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: DesignTokens.Spacing.md),
            suggestionsPanel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -DesignTokens.Spacing.md),

            descScroll.topAnchor.constraint(equalTo: suggestionsPanel.bottomAnchor, constant: DesignTokens.Spacing.sm),
            descScroll.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: DesignTokens.Spacing.md),
            descScroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -DesignTokens.Spacing.md),
            descScroll.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -DesignTokens.Spacing.md),
        ])

        self.view = container

        let bridge = BibleDetailBridge(detail: self)
        self.bridge = bridge
        name.target = bridge
        name.action = #selector(BibleDetailBridge.nameEdited(_:))
        desc.delegate = bridge
        deleteBtn.target = bridge
        deleteBtn.action = #selector(BibleDetailBridge.deletePressed(_:))
        modePopup.target = bridge
        modePopup.action = #selector(BibleDetailBridge.injectionModeChanged(_:))
    }

    fileprivate func writeBack() {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = descriptionView.string
        switch ref.category {
        case .characters:
            guard var c = session.project.bible.characters.first(where: { $0.id == ref.id }) else { return }
            c.name = name
            c.description = body
            session.updateCharacter(c)
        case .settings:
            guard var s = session.project.bible.settings.first(where: { $0.id == ref.id }) else { return }
            s.name = name
            s.description = body
            session.updateSetting(s)
        case .objects:
            guard var o = session.project.bible.objects.first(where: { $0.id == ref.id }) else { return }
            o.name = name
            o.description = body
            session.updateObject(o)
        }
        onChanged()
    }

    fileprivate func requestDelete() {
        onDelete()
    }

    fileprivate func injectionModeSelected(_ mode: InjectionMode) {
        onInjectionModeChanged(mode)
    }

    private static func snapshot(ref: BibleEntityRef, session: ProjectSession) -> (String, String, InjectionMode) {
        switch ref.category {
        case .characters:
            if let c = session.project.bible.characters.first(where: { $0.id == ref.id }) {
                return (c.name, c.description, c.injectionMode)
            }
        case .settings:
            if let s = session.project.bible.settings.first(where: { $0.id == ref.id }) {
                return (s.name, s.description, s.injectionMode)
            }
        case .objects:
            if let o = session.project.bible.objects.first(where: { $0.id == ref.id }) {
                return (o.name, o.description, o.injectionMode)
            }
        }
        return ("", "", .constant)
    }
}

/// Bridge from AppKit selectors back into the Swift detail editor.
private final class BibleDetailBridge: NSObject, NSTextViewDelegate {
    weak var detail: BibleDetailEditor?
    init(detail: BibleDetailEditor) { self.detail = detail }

    @objc func nameEdited(_ sender: Any) { detail?.writeBack() }
    @objc func deletePressed(_ sender: Any) { detail?.requestDelete() }
    @objc func injectionModeChanged(_ sender: NSPopUpButton) {
        let mode: InjectionMode = (sender.indexOfSelectedItem == 1) ? .keyed : .constant
        detail?.injectionModeSelected(mode)
    }
    func textDidChange(_ notification: Notification) { detail?.writeBack() }
}

// `SuggestionRowView` lives alongside `SuggestionsPanelBuilder` in
// `SuggestionsPanelBuilder.swift` so the testable builder can use it
// without dragging `BibleDetailEditor`'s private surface into tests.

// MARK: - Filter identifier marshalling

private extension BibleFilter {
    var identifierString: String {
        switch self {
        case .all: return "all"
        case .category(let c): return "category:\(c.rawValue)"
        }
    }

    init?(identifierString: String) {
        if identifierString == "all" {
            self = .all
            return
        }
        let prefix = "category:"
        guard identifierString.hasPrefix(prefix) else { return nil }
        let raw = String(identifierString.dropFirst(prefix.count))
        guard let cat = BibleCategory(rawValue: raw) else { return nil }
        self = .category(cat)
    }
}

private extension BibleCategory {
    var displayName: String {
        switch self {
        case .characters: return "Characters"
        case .settings:   return "Settings"
        case .objects:    return "Objects"
        }
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

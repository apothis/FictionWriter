import AppKit

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
    private var segmented: NSSegmentedControl!
    private var contentContainer: NSView!
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
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = DesignTokens.Background.window.cgColor

        let seg = NSSegmentedControl(labels: ["Bible", "History", "Notes"], trackingMode: .selectOne, target: self, action: #selector(tabChanged(_:)))
        seg.translatesAutoresizingMaskIntoConstraints = false
        seg.controlSize = .small
        seg.font = DesignTokens.Typography.subheadline
        self.segmented = seg

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        self.contentContainer = content

        container.addSubview(seg)
        container.addSubview(content)

        NSLayoutConstraint.activate([
            seg.topAnchor.constraint(equalTo: container.topAnchor, constant: DesignTokens.Spacing.sm),
            seg.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: DesignTokens.Spacing.sm),
            seg.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -DesignTokens.Spacing.sm),
            content.topAnchor.constraint(equalTo: seg.bottomAnchor, constant: DesignTokens.Spacing.sm),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        bibleVC = BibleInspectorViewController(session: session)
        historyVC = HistoryInspectorViewController(session: session)
        notesVC = NotesInspectorViewController(session: session)

        self.view = container

        // Restore last-viewed tab; default to Bible for fresh projects.
        let initial = session.project.selectedInspectorTab ?? .bible
        showTab(initial)

        // Refresh bible tab when characters change elsewhere (Phase 2+
        // — Phase 1 inspector is the only mutator, but the cost of
        // observing is low and future-proofs the wiring).
        observer = NotificationCenter.default.addObserver(
            forName: ProjectSession.didChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            self?.bibleVC.reload()
        }
    }

    @objc private func tabChanged(_ sender: NSSegmentedControl) {
        let tabs: [InspectorTab] = [.bible, .history, .notes]
        let index = sender.indexOfSelectedItem
        guard index >= 0, index < tabs.count else { return }
        showTab(tabs[index])
    }

    private func showTab(_ tab: InspectorTab) {
        let vc: NSViewController
        let segIndex: Int
        switch tab {
        case .bible:    vc = bibleVC;   segIndex = 0
        case .history:  vc = historyVC; segIndex = 1
        case .notes:    vc = notesVC;   segIndex = 2
        }

        if current === vc { return }
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
        segmented.selectedSegment = segIndex
        session.setSelectedInspectorTab(tab)
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

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = DesignTokens.Background.group.cgColor
        container.layer?.cornerRadius = DesignTokens.Radius.section

        let name = NSTextField(string: character.name)
        name.font = DesignTokens.Typography.headline
        name.translatesAutoresizingMaskIntoConstraints = false
        name.placeholderString = "Name"
        self.nameField = name

        let desc = NSTextView()
        desc.font = DesignTokens.Typography.body
        desc.string = character.description
        desc.isRichText = false
        desc.isEditable = true
        desc.isAutomaticTextReplacementEnabled = false
        desc.isAutomaticQuoteSubstitutionEnabled = false
        desc.translatesAutoresizingMaskIntoConstraints = false
        desc.drawsBackground = false
        desc.textContainerInset = NSSize(width: DesignTokens.Spacing.sm, height: DesignTokens.Spacing.sm)
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
        suppressWriteback = true
        tv.string = session.project.notes
        suppressWriteback = false
        scroll.documentView = tv
        self.textView = tv

        container.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: container.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        self.view = container
    }

    public func textDidChange(_ notification: Notification) {
        guard !suppressWriteback else { return }
        session.updateNotes(textView.string)
    }
}

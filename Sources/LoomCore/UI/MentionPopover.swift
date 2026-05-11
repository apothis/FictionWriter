import AppKit

/// Phase 2.5 (#10 polish) — borderless popover that lists entity
/// autocomplete matches when the editor's cursor is in an @-context.
/// Owned by EditorViewController. Stays AppKit-free of business
/// logic — matches + selection state flow in from the controller,
/// commit/dismiss actions flow back out via the action closures.
///
/// The visual rendering (panel + table) is honest UI — verified by
/// running the app. State transitions (visibility / selected row /
/// matches list) are pinned in Phase2MentionPopoverTests by reading
/// the publicly-exposed properties off the controller.
public final class MentionPopover: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    public private(set) var matches: [EntityAutocompleteMatch] = []
    public private(set) var selectedIndex: Int = 0
    public var isVisible: Bool { panel?.isVisible == true }

    public var onCommit: (() -> Void)?
    public var onDismiss: (() -> Void)?

    private var panel: NSPanel?
    private var tableView: NSTableView?

    /// Updates matches + reselects. If `matches` becomes empty, the
    /// popover dismisses; otherwise it shows (positioned by the
    /// caller via `present(at:relativeTo:)`).
    public func setMatches(_ newMatches: [EntityAutocompleteMatch]) {
        if newMatches.isEmpty {
            hide()
            return
        }
        let isNewList = newMatches.map(\.ref) != matches.map(\.ref)
        matches = newMatches
        if isNewList || selectedIndex >= matches.count {
            selectedIndex = 0
        }
        ensurePanel()
        tableView?.reloadData()
        tableView?.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
    }

    public func moveSelection(by delta: Int) {
        guard !matches.isEmpty else { return }
        let n = matches.count
        // Wrap both directions.
        selectedIndex = ((selectedIndex + delta) % n + n) % n
        tableView?.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        tableView?.scrollRowToVisible(selectedIndex)
    }

    public func currentSelection() -> EntityAutocompleteMatch? {
        guard !matches.isEmpty, selectedIndex < matches.count else { return nil }
        return matches[selectedIndex]
    }

    /// Position the popover at a screen-coordinate origin (the
    /// caller computes this from the textView's cursor rect).
    public func present(at screenOrigin: NSPoint, in window: NSWindow?) {
        ensurePanel()
        guard let panel = panel else { return }
        var frame = panel.frame
        frame.origin = screenOrigin
        panel.setFrame(frame, display: false)
        if let window = window, panel.parent !== window {
            window.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
    }

    public func hide() {
        guard let panel = panel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
            onDismiss?()
        }
    }

    // MARK: NSTableViewDataSource / NSTableViewDelegate

    public func numberOfRows(in tableView: NSTableView) -> Int { matches.count }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("MentionCell")
        let cell: NSTableCellView
        if let existing = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
            cell = existing
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier
            let label = NSTextField(labelWithString: "")
            label.font = DesignTokens.Typography.body
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            cell.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: DesignTokens.Spacing.sm),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -DesignTokens.Spacing.sm),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        let match = matches[row]
        cell.textField?.stringValue = match.displayName
        return cell
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tv = notification.object as? NSTableView else { return }
        if tv.selectedRow >= 0 {
            selectedIndex = tv.selectedRow
        }
    }

    @objc private func rowDoubleClicked(_ sender: Any) {
        onCommit?()
    }

    // MARK: Internals

    private func ensurePanel() {
        if panel != nil { return }
        // Borderless, non-activating panel — doesn't steal focus from
        // the editor's text view.
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 160),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        p.level = .popUpMenu
        p.hasShadow = true
        p.backgroundColor = DesignTokens.Background.group
        p.isOpaque = false

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        let table = NSTableView()
        table.headerView = nil
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.rowHeight = 22
        table.style = .plain
        table.target = self
        table.doubleAction = #selector(rowDoubleClicked(_:))
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("MentionColumn"))
        col.resizingMask = .autoresizingMask
        table.addTableColumn(col)
        table.dataSource = self
        table.delegate = self
        scroll.documentView = table

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 160))
        content.wantsLayer = true
        content.layer?.cornerRadius = DesignTokens.Radius.control
        content.layer?.borderWidth = 0.5
        content.layer?.borderColor = NSColor.separatorColor.cgColor
        content.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ])
        p.contentView = content
        self.panel = p
        self.tableView = table
    }
}

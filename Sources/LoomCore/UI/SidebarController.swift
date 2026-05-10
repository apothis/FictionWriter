import AppKit

/// Sidebar (Binder) controller. NSOutlineView with two top-level group
/// rows — Manuscript and Trash — each containing scene rows.
///
/// Phase 1 ships a flat scene list (no Parts/Chapters); Phase 3+ adds the
/// hierarchical structure under Manuscript. Drag-rearrange is supported
/// within the Manuscript group.
public final class SidebarController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    public let session: ProjectSession
    private var outlineView: NSOutlineView!
    private var observer: NSObjectProtocol?

    /// Internal pasteboard type for drag-rearrange. Carries the source
    /// scene id as a UUID string.
    private static let scenePasteboardType = NSPasteboard.PasteboardType("com.local.loom.scene-id")

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

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        let outline = NSOutlineView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        column.title = ""
        column.isEditable = true
        column.width = DesignTokens.Editor.sidebarDefaultWidth
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.style = .sourceList
        outline.rowSizeStyle = .default
        outline.allowsMultipleSelection = false
        outline.allowsEmptySelection = true
        outline.autoresizesOutlineColumn = false
        outline.dataSource = self
        outline.delegate = self
        outline.registerForDraggedTypes([Self.scenePasteboardType])
        scroll.documentView = outline
        self.outlineView = outline

        // Bottom toolbar with `+ Scene`.
        let addButton = NSButton(title: "+ Scene", target: self, action: #selector(addSceneClicked))
        addButton.bezelStyle = .inline
        addButton.controlSize = .small
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.font = DesignTokens.Typography.subheadline

        let toolbar = NSView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(addButton)

        container.addSubview(scroll)
        container.addSubview(toolbar)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: container.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: toolbar.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 28),
            addButton.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: DesignTokens.Spacing.sm),
            addButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
        ])

        // Right-click menu for scene rows.
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "New Scene", action: #selector(addSceneClicked), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Rename", action: #selector(renameSelected), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Delete", action: #selector(deleteSelected), keyEquivalent: ""))
        outline.menu = menu

        self.view = container

        observer = NotificationCenter.default.addObserver(
            forName: ProjectSession.didChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            self?.outlineView.reloadData()
        }

        outline.expandItem(SidebarItem.group(.manuscript))

        // Restore visual selection if the session already has a current
        // scene (AppState bootstraps with one starter scene auto-selected).
        if let id = session.currentSceneId {
            let row = outline.row(forItem: SidebarItem.scene(id))
            if row >= 0 {
                outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
        }
    }

    // MARK: - Actions

    @objc private func addSceneClicked() {
        let scene = session.addScene()
        // After reload, select + scroll-to + start inline edit.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.expandManuscriptGroup()
            let item = SidebarItem.scene(scene.id)
            let row = self.outlineView.row(forItem: item)
            if row >= 0 {
                self.outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                self.outlineView.scrollRowToVisible(row)
            }
        }
    }

    @objc private func renameSelected() {
        let row = outlineView.clickedRow >= 0 ? outlineView.clickedRow : outlineView.selectedRow
        guard row >= 0 else { return }
        outlineView.editColumn(0, row: row, with: nil, select: true)
    }

    @objc private func deleteSelected() {
        let row = outlineView.clickedRow >= 0 ? outlineView.clickedRow : outlineView.selectedRow
        guard row >= 0 else { return }
        guard let item = outlineView.item(atRow: row) as? SidebarItem,
              case .scene(let id) = item else { return }
        session.deleteScene(id: id)
    }

    private func expandManuscriptGroup() {
        let group = SidebarItem.group(.manuscript)
        outlineView.expandItem(group)
    }

    // MARK: - NSOutlineViewDataSource

    public func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return 2 }
        guard let sidebarItem = item as? SidebarItem else { return 0 }
        switch sidebarItem {
        case .group(.manuscript): return session.project.manuscript.orphanedSceneIds.count
        case .group(.trash): return session.project.manuscript.trashedSceneIds.count
        case .scene: return 0
        }
    }

    public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return index == 0
                ? SidebarItem.group(.manuscript)
                : SidebarItem.group(.trash)
        }
        guard let sidebarItem = item as? SidebarItem else {
            return SidebarItem.scene(UUID())   // unreachable; data source contract violated
        }
        switch sidebarItem {
        case .group(.manuscript):
            return SidebarItem.scene(session.project.manuscript.orphanedSceneIds[index])
        case .group(.trash):
            return SidebarItem.scene(session.project.manuscript.trashedSceneIds[index])
        case .scene:
            return SidebarItem.scene(UUID())   // scenes have no children
        }
    }

    public func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let sidebarItem = item as? SidebarItem else { return false }
        if case .group = sidebarItem { return true }
        return false
    }

    public func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        guard let sidebarItem = item as? SidebarItem else { return false }
        if case .group = sidebarItem { return true }
        return false
    }

    public func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let sidebarItem = item as? SidebarItem else { return nil }
        switch sidebarItem {
        case .group(let kind):
            let cell = NSTableCellView()
            let label = NSTextField(labelWithString: kind.title)
            label.font = DesignTokens.Typography.subheadline
            label.textColor = DesignTokens.Foreground.secondary
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.textField = label
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: DesignTokens.Spacing.xs),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor),
            ])
            return cell
        case .scene(let id):
            let cell = NSTableCellView()
            let title = session.scenes[id]?.title ?? "Untitled"
            let field = NSTextField()
            field.stringValue = title
            field.isBezeled = false
            field.drawsBackground = false
            field.isEditable = true
            field.font = DesignTokens.Typography.headline
            field.textColor = DesignTokens.Foreground.primary
            field.translatesAutoresizingMaskIntoConstraints = false
            field.target = self
            field.action = #selector(sceneTitleEdited(_:))
            field.identifier = NSUserInterfaceItemIdentifier(id.uuidString)
            cell.textField = field
            cell.addSubview(field)
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: DesignTokens.Spacing.xs),
                field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -DesignTokens.Spacing.xs),
                field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }
    }

    public func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        guard let sidebarItem = item as? SidebarItem else { return false }
        if case .scene = sidebarItem { return true }
        return false
    }

    public func outlineViewSelectionDidChange(_ notification: Notification) {
        let row = outlineView.selectedRow
        guard row >= 0,
              let sidebarItem = outlineView.item(atRow: row) as? SidebarItem,
              case .scene(let id) = sidebarItem
        else { return }
        session.selectScene(id: id)
    }

    @objc private func sceneTitleEdited(_ sender: NSTextField) {
        guard let idStr = sender.identifier?.rawValue, let id = UUID(uuidString: idStr) else { return }
        let trimmed = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            // Restore original — empty titles aren't allowed.
            sender.stringValue = session.scenes[id]?.title ?? ""
            return
        }
        session.renameScene(id: id, to: trimmed)
    }

    // MARK: - Drag-rearrange (within Manuscript group)

    public func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let sidebarItem = item as? SidebarItem,
              case .scene(let id) = sidebarItem,
              session.project.manuscript.orphanedSceneIds.contains(id)
        else { return nil }
        let provider = NSPasteboardItem()
        provider.setString(id.uuidString, forType: Self.scenePasteboardType)
        return provider
    }

    public func outlineView(
        _ outlineView: NSOutlineView,
        validateDrop info: NSDraggingInfo,
        proposedItem item: Any?,
        proposedChildIndex index: Int
    ) -> NSDragOperation {
        // Only allow drops on the Manuscript group.
        guard let sidebarItem = item as? SidebarItem,
              case .group(.manuscript) = sidebarItem,
              index >= 0
        else { return [] }
        return .move
    }

    public func outlineView(
        _ outlineView: NSOutlineView,
        acceptDrop info: NSDraggingInfo,
        item: Any?,
        childIndex index: Int
    ) -> Bool {
        guard let pb = info.draggingPasteboard.pasteboardItems?.first,
              let idStr = pb.string(forType: Self.scenePasteboardType),
              let id = UUID(uuidString: idStr),
              let from = session.project.manuscript.orphanedSceneIds.firstIndex(of: id)
        else { return false }
        // NSOutlineView's child index is inclusive of the inserted slot;
        // when dragging downward, the destination index is one greater
        // than the visual insertion point because the source is removed
        // first. Adjust accordingly.
        let to = from < index ? index - 1 : index
        session.reorderScenes(from: from, to: to)
        return true
    }
}

/// Outline-view item type. NSOutlineView wants `Any` items, but we want
/// type-safety inside the controller — the enum is the bridge.
///
/// `Hashable` identity must be stable across reloads (NSOutlineView
/// uses `isEqual:` to track expanded-state). The group case carries
/// only its kind for that reason; scenes are identified by UUID alone.
public enum SidebarItem: Hashable {
    case group(SidebarGroupKind)
    case scene(UUID)
}

public enum SidebarGroupKind: Hashable {
    case manuscript
    case trash

    var title: String {
        switch self {
        case .manuscript: return "Manuscript"
        case .trash: return "Trash"
        }
    }
}

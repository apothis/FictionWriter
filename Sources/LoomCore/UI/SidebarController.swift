import AppKit

/// Sidebar (Binder) controller. NSOutlineView with two top-level group
/// rows — Manuscript and Trash — each containing scene rows.
///
/// Phase 1 ships a flat scene list (no Parts/Chapters); Phase 3+ adds the
/// hierarchical structure under Manuscript. Drag-rearrange is supported
/// within the Manuscript group.
public final class SidebarController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
    public let session: ProjectSession
    private var outlineView: NSOutlineView!
    private var observer: NSObjectProtocol?

    /// Internal pasteboard type for drag-rearrange. Carries the source
    /// scene id as a UUID string.
    private static let scenePasteboardType = NSPasteboard.PasteboardType("com.local.loom.scene-id")

    /// Tag on the "Set POV" parent menu item so `menuNeedsUpdate` can
    /// find it without string matching the title.
    private static let setPOVMenuTag = 9_001

    /// Payload stashed on each POV submenu item's `representedObject`,
    /// so the action handler can resolve the target scene + character
    /// without re-reading `clickedRow` (which can be -1 by the time
    /// the action fires depending on AppKit's menu lifecycle).
    private struct POVMenuClick {
        let sceneId: UUID
        let characterId: UUID?
    }

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

        // Bottom toolbar with `+ Scene` and `+ Part`.
        let addButton = NSButton(title: "+ Scene", target: self, action: #selector(addSceneClicked))
        addButton.bezelStyle = .inline
        addButton.controlSize = .small
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.font = DesignTokens.Typography.subheadline

        let addPartButton = NSButton(title: "+ Part", target: self, action: #selector(addPartClicked))
        addPartButton.bezelStyle = .inline
        addPartButton.controlSize = .small
        addPartButton.translatesAutoresizingMaskIntoConstraints = false
        addPartButton.font = DesignTokens.Typography.subheadline

        let toolbar = NSView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(addButton)
        toolbar.addSubview(addPartButton)

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
            addPartButton.leadingAnchor.constraint(equalTo: addButton.trailingAnchor, constant: DesignTokens.Spacing.sm),
            addPartButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
        ])

        // Right-click menu for rows (scene + part rows share it;
        // "Add Chapter" only does anything on a Part row).
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "New Scene", action: #selector(addSceneClicked), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "New Part", action: #selector(addPartClicked), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Add Chapter to Part", action: #selector(addChapterToSelectedPart), keyEquivalent: ""))
        menu.addItem(.separator())
        let povItem = NSMenuItem(title: "Set POV", action: nil, keyEquivalent: "")
        povItem.tag = Self.setPOVMenuTag
        povItem.submenu = NSMenu(title: "Set POV")
        menu.addItem(povItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Rename", action: #selector(renameSelected), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Delete", action: #selector(deleteSelected), keyEquivalent: ""))
        menu.delegate = self
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

    @objc private func addPartClicked() {
        let next = session.project.manuscript.parts.count + 1
        let part = session.addPart(title: "Part \(next)")
        // The session-change observer reloads; force the new Part
        // visible by expanding the Manuscript group.
        DispatchQueue.main.async { [weak self] in
            self?.expandManuscriptGroup()
            self?.outlineView.expandItem(SidebarItem.part(part.id))
        }
    }

    @objc private func addChapterToSelectedPart() {
        let row = outlineView.clickedRow >= 0 ? outlineView.clickedRow : outlineView.selectedRow
        guard row >= 0,
              let item = outlineView.item(atRow: row) as? SidebarItem,
              case .part(let partId) = item,
              let chap = session.addChapter(
                  title: "Chapter \((session.project.manuscript.parts.first(where: { $0.id == partId })?.chapters.count ?? 0) + 1)",
                  in: partId
              )
        else { return }
        DispatchQueue.main.async { [weak self] in
            self?.outlineView.expandItem(SidebarItem.part(partId))
            self?.outlineView.expandItem(SidebarItem.chapter(chap.id))
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

    // MARK: - NSMenuDelegate (Set POV submenu rebuild)

    public func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === outlineView.menu else { return }
        guard let povItem = menu.item(withTag: Self.setPOVMenuTag) else { return }

        // Show "Set POV" only when the right-clicked row is a scene.
        let row = outlineView.clickedRow
        guard row >= 0,
              let sidebarItem = outlineView.item(atRow: row) as? SidebarItem,
              case .scene(let sceneId) = sidebarItem,
              let scene = session.scenes[sceneId]
        else {
            povItem.isHidden = true
            return
        }
        povItem.isHidden = false

        let descriptors = ScenePOVMenuBuilder.menuItems(
            characters: session.project.bible.characters,
            currentPOV: scene.pov
        )
        let submenu = NSMenu(title: "Set POV")
        for descriptor in descriptors {
            let item = NSMenuItem(
                title: descriptor.title,
                action: #selector(povItemClicked(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.state = descriptor.isCurrent ? .on : .off
            item.representedObject = POVMenuClick(
                sceneId: sceneId,
                characterId: descriptor.characterId
            )
            submenu.addItem(item)
        }
        povItem.submenu = submenu
    }

    @objc private func povItemClicked(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? POVMenuClick else { return }
        session.setScenePOV(id: payload.sceneId, to: payload.characterId)
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
        case .group(.manuscript):
            // Phase 3 §D: Parts come first, then orphan scenes.
            return session.project.manuscript.parts.count
                + session.project.manuscript.orphanedSceneIds.count
        case .group(.trash):
            return session.project.manuscript.trashedSceneIds.count
        case .part(let id):
            return session.project.manuscript.parts.first(where: { $0.id == id })?.chapters.count ?? 0
        case .chapter(let id):
            for part in session.project.manuscript.parts {
                if let chap = part.chapters.first(where: { $0.id == id }) {
                    return chap.sceneIds.count
                }
            }
            return 0
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
            let parts = session.project.manuscript.parts
            if index < parts.count {
                return SidebarItem.part(parts[index].id)
            }
            // Past the Parts segment → orphan scenes.
            let orphanIndex = index - parts.count
            return SidebarItem.scene(session.project.manuscript.orphanedSceneIds[orphanIndex])
        case .group(.trash):
            return SidebarItem.scene(session.project.manuscript.trashedSceneIds[index])
        case .part(let id):
            guard let part = session.project.manuscript.parts.first(where: { $0.id == id }) else {
                return SidebarItem.scene(UUID())
            }
            return SidebarItem.chapter(part.chapters[index].id)
        case .chapter(let id):
            for part in session.project.manuscript.parts {
                if let chap = part.chapters.first(where: { $0.id == id }) {
                    return SidebarItem.scene(chap.sceneIds[index])
                }
            }
            return SidebarItem.scene(UUID())
        case .scene:
            return SidebarItem.scene(UUID())   // scenes have no children
        }
    }

    public func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let sidebarItem = item as? SidebarItem else { return false }
        switch sidebarItem {
        case .group: return true
        case .part:  return true
        case .chapter: return true
        case .scene: return false
        }
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
        case .part(let id):
            let title = session.project.manuscript.parts.first(where: { $0.id == id })?.title ?? "Untitled Part"
            return makeStructureRow(title: title, font: DesignTokens.Typography.headline)
        case .chapter(let id):
            var label = "Untitled Chapter"
            for part in session.project.manuscript.parts {
                if let chap = part.chapters.first(where: { $0.id == id }) {
                    label = chap.title
                    break
                }
            }
            return makeStructureRow(title: label, font: DesignTokens.Typography.body)
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
        // Phase 3: only scenes are selectable — Parts and Chapters
        // are structural rows. The editor pane needs a single
        // current-scene id and structural rows can't fill that slot.
        if case .scene = sidebarItem { return true }
        return false
    }

    private func makeStructureRow(title: String, font: NSFont) -> NSView {
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: title)
        label.font = font
        label.textColor = DesignTokens.Foreground.primary
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.textField = label
        cell.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: DesignTokens.Spacing.xs),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor),
        ])
        return cell
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
    /// Phase 3 §D — a Part in the manuscript hierarchy.
    case part(UUID)
    /// Phase 3 §D — a Chapter inside a Part.
    case chapter(UUID)
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

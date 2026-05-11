import AppKit

/// Phase 2.5 (#10 follow-on) — hover-preview card for an entity link
/// in prose. Borderless NSPanel like MentionPopover but rendering a
/// single info block: name + role chip + description excerpt. Owned
/// by EditorViewController; visibility tracks mouseMoved over a link
/// range.
public final class EntityHoverPopover {
    public private(set) var currentInfo: EntityHoverInfo?
    public var isVisible: Bool { panel?.isVisible == true }

    private var panel: NSPanel?
    private var nameLabel: NSTextField?
    private var roleChip: NSTextField?
    private var descriptionLabel: NSTextField?

    public init() {}

    public func show(_ info: EntityHoverInfo, at screenOrigin: NSPoint, in window: NSWindow?) {
        ensurePanel()
        guard let panel = panel else { return }
        if currentInfo != info {
            nameLabel?.stringValue = info.displayName
            if let role = info.roleLabel, !role.isEmpty {
                roleChip?.stringValue = role
                roleChip?.isHidden = false
            } else {
                roleChip?.isHidden = true
            }
            descriptionLabel?.stringValue = info.descriptionExcerpt
            currentInfo = info
        }
        var frame = panel.frame
        frame.origin = screenOrigin
        panel.setFrame(frame, display: false)
        if let window = window, panel.parent !== window {
            window.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
    }

    public func hide() {
        currentInfo = nil
        panel?.orderOut(nil)
    }

    private func ensurePanel() {
        if panel != nil { return }
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        p.isFloatingPanel = true
        p.becomesKeyOnlyIfNeeded = true
        p.level = .popUpMenu
        p.hasShadow = true
        p.backgroundColor = DesignTokens.Background.group
        p.isOpaque = false

        let content = NSView()
        content.wantsLayer = true
        content.layer?.cornerRadius = DesignTokens.Radius.section
        content.layer?.borderWidth = 0.5
        content.layer?.borderColor = NSColor.separatorColor.cgColor
        content.translatesAutoresizingMaskIntoConstraints = false

        let name = NSTextField(labelWithString: "")
        name.font = DesignTokens.Typography.headline
        name.textColor = DesignTokens.Foreground.primary
        name.translatesAutoresizingMaskIntoConstraints = false

        let role = NSTextField(labelWithString: "")
        role.font = DesignTokens.Typography.caption1
        role.textColor = DesignTokens.Foreground.secondary
        role.translatesAutoresizingMaskIntoConstraints = false

        let desc = NSTextField(wrappingLabelWithString: "")
        desc.font = DesignTokens.Typography.body
        desc.textColor = DesignTokens.Foreground.secondary
        desc.translatesAutoresizingMaskIntoConstraints = false
        desc.maximumNumberOfLines = 4

        content.addSubview(name)
        content.addSubview(role)
        content.addSubview(desc)

        NSLayoutConstraint.activate([
            name.topAnchor.constraint(equalTo: content.topAnchor, constant: DesignTokens.Spacing.sm),
            name.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: DesignTokens.Spacing.sm),
            name.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -DesignTokens.Spacing.sm),

            role.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 2),
            role.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: DesignTokens.Spacing.sm),
            role.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -DesignTokens.Spacing.sm),

            desc.topAnchor.constraint(equalTo: role.bottomAnchor, constant: DesignTokens.Spacing.xs),
            desc.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: DesignTokens.Spacing.sm),
            desc.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -DesignTokens.Spacing.sm),
            desc.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -DesignTokens.Spacing.sm),
        ])

        p.contentView = content
        self.panel = p
        self.nameLabel = name
        self.roleChip = role
        self.descriptionLabel = desc
    }
}

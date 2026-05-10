import AppKit

/// Phase 1 sub-step 1.d placeholder view controllers. Each sub-step
/// 1.f / 1.g replaces these with the real Editor / Inspector
/// implementations. Centred role label in `secondaryLabelColor` so the
/// three-pane scaffold is visually obvious while the real surfaces
/// don't exist. (1.e replaced the sidebar's placeholder with the real
/// SidebarController.)
public final class EditorPlaceholderViewController: PlaceholderViewController {
    public init() { super.init(roleLabel: "Editor") }
    @available(*, unavailable) public required init?(coder: NSCoder) { nil }
}

public final class InspectorPlaceholderViewController: PlaceholderViewController {
    public init() { super.init(roleLabel: "Inspector") }
    @available(*, unavailable) public required init?(coder: NSCoder) { nil }
}

public class PlaceholderViewController: NSViewController {
    private let roleLabel: String

    init(roleLabel: String) {
        self.roleLabel = roleLabel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) public required init?(coder: NSCoder) { nil }

    public override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = DesignTokens.Background.window.cgColor

        let label = NSTextField(labelWithString: roleLabel)
        label.font = DesignTokens.Typography.headline
        label.textColor = DesignTokens.Foreground.secondary
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        self.view = container
    }
}

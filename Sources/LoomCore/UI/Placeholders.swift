import AppKit

/// Phase 1 sub-step 1.d placeholder view controllers. Sub-step 1.g
/// replaces InspectorPlaceholderViewController with the real Inspector.
/// (1.e replaced sidebar's placeholder with SidebarController; 1.f
/// replaced editor's placeholder with EditorViewController.)
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

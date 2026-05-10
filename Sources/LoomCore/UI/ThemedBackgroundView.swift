import AppKit

/// Layer-backed NSView that re-applies its background color on every
/// appearance change. Use this instead of `let v = NSView(); v.wantsLayer
/// = true; v.layer?.backgroundColor = someNSColor.cgColor` — the
/// raw `.cgColor` snapshot doesn't react when the user flips the
/// system between light and dark, so the once-set value gets stuck.
///
/// AppKit calls `updateLayer()` whenever a layer-backed view needs
/// to refresh its layer (including on appearance change), and
/// `NSColor.cgColor` resolves against the view's *current*
/// effectiveAppearance inside that override.
public final class ThemedBackgroundView: NSView {
    public var backgroundColor: NSColor {
        didSet { needsDisplay = true }
    }

    public init(backgroundColor: NSColor) {
        self.backgroundColor = backgroundColor
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable) public required init?(coder: NSCoder) { nil }

    public override func updateLayer() {
        layer?.backgroundColor = backgroundColor.cgColor
    }
}

import AppKit

/// Phase 2.5 (#11 follow-on) — thin horizontal bar with marker dots
/// at scenes that mention an entity. LOOM_DESIGN_LANGUAGE.md §14.5.1.
/// Mouse click on a marker fires `onMarkerClicked(sceneId)` — the
/// inspector wires this to `session.selectScene(id:)`.
///
/// State + layout live on MentionSparklineLayout (pure-data, tested).
/// This view is a thin draw + click forwarder.
public final class MentionSparklineView: NSView {
    public var onMarkerClicked: ((UUID) -> Void)?

    private var layout: MentionSparklineLayout = MentionSparklineLayout(markers: [], totalScenes: 0)

    public override var isFlipped: Bool { true }
    public override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 14)
    }
    public override var allowsVibrancy: Bool { false }

    public func setLayout(_ layout: MentionSparklineLayout) {
        self.layout = layout
        needsDisplay = true
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let r = bounds
        // Bar — 1.5pt tall stripe centred vertically.
        let barY = (r.height - 1.5) / 2
        let bar = NSRect(x: r.minX, y: barY, width: r.width, height: 1.5)
        DesignTokens.Foreground.quaternary.setFill()
        NSBezierPath(rect: bar).fill()

        // Markers — circles 5pt wide, centred on the bar.
        let dotRadius: CGFloat = 2.5
        DesignTokens.Foreground.accent.setFill()
        for marker in layout.markers {
            let cx = r.minX + CGFloat(marker.xRatio) * r.width
            let cy = r.midY
            let dot = NSRect(
                x: cx - dotRadius,
                y: cy - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            )
            NSBezierPath(ovalIn: dot).fill()
        }
    }

    public override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        guard bounds.width > 0 else { return }
        let xRatio = Double(local.x / bounds.width)
        dispatchClick(xRatio: xRatio)
    }

    /// Hit-test tolerance is fixed in pixels (8pt forgiveness around
    /// each dot's centre) → converted to a ratio against the current
    /// width. Keeps clicks generous enough on narrow inspectors.
    private func dispatchClick(xRatio: Double) {
        let tolerancePx: Double = 8
        let tolerance = bounds.width > 0 ? tolerancePx / Double(bounds.width) : 0.05
        if let marker = layout.hitTest(xRatio: xRatio, tolerance: tolerance) {
            onMarkerClicked?(marker.sceneId)
        }
    }

    // MARK: Test surface

    public var markerCountForTesting: Int { layout.markers.count }

    public func simulateClickForTesting(xRatio: Double) {
        dispatchClick(xRatio: xRatio)
    }
}

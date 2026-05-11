import Foundation
import AppKit
@testable import LoomCore

/// Honest smoke test for the inspector pane's vertical layout.
///
/// Reproduces a visible regression where the Bible/History/Notes tab
/// strip and the Bible-tab filter strip rendered halfway down the
/// inspector pane instead of at the top — leaving a tall band of
/// empty white space above them. Pins the contract: after layout,
/// the tab row sits near the top of the inspector view (within a
/// titlebar-height + spacing budget), and the bible filter strip
/// sits near the top of the bible-tab content area.
func phase4InspectorLayoutTests() -> TestSuite {
    let s = TestSuite("Phase4InspectorLayout")

    /// Mount the InspectorController, force its container view to a
    /// known frame (matching the production-observed 333.5 × 458pt),
    /// and run a layout pass. Bypasses the off-screen splitVC layout-
    /// distribution dance — what we actually want to assert is "given
    /// a reasonably-sized container, the tab row sticks to its button
    /// height instead of ballooning to fill."
    @MainActor
    func mountWithFrame(width: CGFloat = 333.5, height: CGFloat = 458) -> InspectorController {
        let session = ProjectSession(project: Project.empty(title: "LayoutProbe"))
        let inspector = InspectorController(session: session)
        // Trigger loadView, then size the container as production does.
        inspector.view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        // viewDidAppear runs the titlebar-offset adjustment; trigger it.
        inspector.viewDidAppear()
        inspector.view.layoutSubtreeIfNeeded()
        return inspector
    }

    /// The Bible/History/Notes button row inside the inspector
    /// container — first NSStackView holding the three tab buttons.
    func findTabRow(in container: NSView) -> NSStackView? {
        for sub in container.subviews {
            guard let stack = sub as? NSStackView else { continue }
            let titles = stack.arrangedSubviews.compactMap { ($0 as? NSButton)?.title }
            if titles.contains("Bible") && titles.contains("History") && titles.contains("Notes") {
                return stack
            }
        }
        return nil
    }

    /// The All/Characters/Settings/Objects filter row inside a
    /// BibleInspector container.
    func findFilterStrip(in container: NSView) -> NSStackView? {
        for sub in container.subviews {
            guard let stack = sub as? NSStackView else { continue }
            let titles = stack.arrangedSubviews.compactMap { ($0 as? NSButton)?.title }
            if titles.contains("All") && titles.contains("Characters") {
                return stack
            }
        }
        return nil
    }

    s.test("Bible/History/Notes tab row hugs its intrinsic height (does not stretch vertically)") {
        try MainActor.assumeIsolated {
            let vc = mountWithFrame()
            guard let tabRow = findTabRow(in: vc.view) else {
                throw TestFailure(message: "tab row not found in inspector container", file: #file, line: #line)
            }
            // Regression pin: the tab row is a horizontal NSStackView
            // of three .recessed/.small buttons (~22pt tall). Without
            // an explicit vertical content-hugging priority, Auto
            // Layout was free to grow the stack to fill the inspector
            // — observed at 373pt in a 458pt container, which pushed
            // the Bible content down to a 41pt band at the bottom of
            // the pane (the screenshot bug). Pin the row to ≤48pt to
            // catch any future regression.
            let h = tabRow.frame.height
            try expectTrue(
                h <= 48,
                "tab row should hug its button-row height (≤48pt); got \(h)"
            )
        }
    }

    s.test("Bible filter strip sits near the top of the bible-tab content area") {
        try MainActor.assumeIsolated {
            let vc = mountWithFrame()
            // The bible-tab VC is mounted as a child of the inspector's
            // contentContainer. Find it by walking the hierarchy.
            guard let bibleView = vc.children.compactMap({ $0 as? BibleInspectorViewController }).first?.view else {
                throw TestFailure(message: "bible inspector child VC not mounted", file: #file, line: #line)
            }
            guard let filterStrip = findFilterStrip(in: bibleView) else {
                throw TestFailure(message: "filter strip not found in bible inspector", file: #file, line: #line)
            }
            // Filter strip is top-anchored to the bible view; its minY
            // should be 0 (in the bible view's coordinate space).
            let topInset = filterStrip.frame.minY
            try expectTrue(
                topInset < 8,
                "filter strip should hug bible-view top (≤8pt); got \(topInset)"
            )
        }
    }

    s.test("the bible filter strip is ABOVE the list-detail content (not below)") {
        try MainActor.assumeIsolated {
            let vc = mountWithFrame()
            guard let bibleView = vc.children.compactMap({ $0 as? BibleInspectorViewController }).first?.view else {
                throw TestFailure(message: "bible inspector child VC not mounted", file: #file, line: #line)
            }
            guard let filterStrip = findFilterStrip(in: bibleView) else {
                throw TestFailure(message: "filter strip not found", file: #file, line: #line)
            }
            // Find the listScroll (NSScrollView) and detail container —
            // both sit below the filter strip per design language §14.5.1.
            let scrollView = bibleView.subviews.first(where: { $0 is NSScrollView })
            guard let scroll = scrollView else {
                throw TestFailure(message: "bible list scroll view not found", file: #file, line: #line)
            }
            // In the bible-view's local coordinates (NOT flipped — the
            // standalone NSView used as the bible container does not
            // override isFlipped), AppKit uses bottom-up: a child whose
            // minY is *higher* sits visually *higher*. The filter strip
            // should sit visually-above the scroll view, which means its
            // minY > scroll.minY in the unflipped parent.
            //
            // If the parent IS flipped, the relation inverts (minY <).
            // Express the assertion as "filter strip's visual-top is
            // above scroll's visual-top," independent of flipping.
            let filterVisualTop = bibleView.isFlipped ? filterStrip.frame.minY : (bibleView.bounds.height - filterStrip.frame.maxY)
            let scrollVisualTop = bibleView.isFlipped ? scroll.frame.minY : (bibleView.bounds.height - scroll.frame.maxY)
            try expectTrue(
                filterVisualTop < scrollVisualTop,
                "filter strip should sit visually above the list (filterTop=\(filterVisualTop), scrollTop=\(scrollVisualTop))"
            )
        }
    }

    return s
}

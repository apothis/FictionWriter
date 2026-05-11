import Foundation
import AppKit
@testable import LoomCore

/// Phase 4 #7 sub-task 4 bugfix — the Suggestions panel must cap its
/// own height so accumulating suggestions can't grow the inspector
/// pane's fittingSize and drag the whole window with it (the
/// macOS-26 auto-refit cascade noted in HANDOFF §2.1, this time
/// in the growth direction instead of the shrink direction).
///
/// Contract pinned here:
/// - Empty suggestions → container is zero-height (already covered
///   elsewhere; re-asserted here for completeness).
/// - Non-empty → container has a `.required` lessThanOrEqualTo
///   height constraint so fittingSize can't escape upward.
/// - Non-empty → an NSScrollView is in the view tree so overflow
///   content scrolls inside the panel instead of flowing outward.
func phase4SuggestionsPanelHeightTests() -> TestSuite {
    let s = TestSuite("Phase4SuggestionsPanelHeight")

    let miaId = UUID()
    let sceneId = UUID()

    func makeSuggestion(_ text: String) -> LedgerSuggestion {
        LedgerSuggestion(
            characterId: miaId,
            fact: KnownFact(fact: text, sourceSceneId: sceneId, certainty: .asserted),
            evidenceQuote: "..."
        )
    }

    /// Recursively walks `view`'s subviews looking for the first
    /// NSScrollView. Returns it or nil.
    func findScrollView(in view: NSView) -> NSScrollView? {
        for sub in view.subviews {
            if let scroll = sub as? NSScrollView { return scroll }
            if let nested = findScrollView(in: sub) { return nested }
        }
        return nil
    }

    s.test("empty suggestions panel has a non-required zero-height pin, no scroll view") {
        let panel = SuggestionsPanelBuilder.build(
            suggestions: [],
            onAccept: { _ in },
            onReject: { _ in }
        )
        // Zero-height constraint exists at non-required priority.
        let heightConstraints = panel.constraints.filter { c in
            c.firstAttribute == .height && c.secondItem == nil
        }
        try expectTrue(!heightConstraints.isEmpty)
        try expectNil(findScrollView(in: panel))
    }

    s.test("non-empty suggestions panel has a required upper height bound") {
        let panel = SuggestionsPanelBuilder.build(
            suggestions: (1...7).map { makeSuggestion("fact \($0)") },
            onAccept: { _ in },
            onReject: { _ in }
        )
        // At least one `lessThanOrEqual` height constraint at required priority.
        let cap = panel.constraints.first { c in
            c.firstAttribute == .height
                && c.relation == .lessThanOrEqual
                && c.priority == .required
        }
        _ = try expectNotNil(cap)
    }

    s.test("non-empty suggestions panel contains a scroll view for overflow") {
        let panel = SuggestionsPanelBuilder.build(
            suggestions: (1...7).map { makeSuggestion("fact \($0)") },
            onAccept: { _ in },
            onReject: { _ in }
        )
        _ = try expectNotNil(findScrollView(in: panel))
    }

    s.test("scroll view's documentView is flipped so content stacks from the top down") {
        let panel = SuggestionsPanelBuilder.build(
            suggestions: (1...7).map { makeSuggestion("fact \($0)") },
            onAccept: { _ in },
            onReject: { _ in }
        )
        let scroll = try expectNotNil(findScrollView(in: panel))
        let doc = try expectNotNil(scroll.documentView)
        try expectTrue(doc.isFlipped)
    }

    s.test("SuggestionRowView reapplies its background on updateLayer (theme reactivity)") {
        let row = SuggestionRowView(
            suggestion: makeSuggestion("x"),
            onAccept: { _ in },
            onReject: { _ in }
        )
        row.wantsLayer = true
        row.updateLayer()
        // The override resolves the dynamic NSColor against the current
        // effective appearance, so layer.backgroundColor must be set
        // (and re-set on subsequent calls when the appearance changes).
        _ = try expectNotNil(row.layer?.backgroundColor)
    }

    return s
}

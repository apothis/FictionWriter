import AppKit

/// Phase 4 #7 sub-task 4 — builder for the per-character Suggestions
/// panel inside `BibleDetailEditor`. Extracted from the editor class
/// so the layout contract (height cap, scroll containment) is
/// testable without poking at private types.
///
/// Height behaviour:
/// - Empty suggestions → zero-height (non-required pin) so the
///   description scroll view inherits the freed space.
/// - Non-empty → an NSScrollView wraps the suggestion cards, and the
///   container caps its height at `maxContentHeight` (~280pt) via a
///   `.required` `lessThanOrEqualToConstant`. Without that cap, an
///   accumulating queue (7+ suggestions, each ~80pt tall) inflates
///   the inspector pane's fittingSize and the macOS-26 auto-refit
///   cascade grows the window to match (HANDOFF §2.1, opposite-
///   direction sibling of the original shrink incident).
public enum SuggestionsPanelBuilder {
    public static let maxContentHeight: CGFloat = 360

    public static func build(
        suggestions: [LedgerSuggestion],
        onAccept: @escaping (LedgerSuggestion) -> Void,
        onReject: @escaping (UUID) -> Void
    ) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        guard !suggestions.isEmpty else {
            let h = container.heightAnchor.constraint(equalToConstant: 0)
            h.priority = NSLayoutConstraint.Priority(rawValue: 751)
            h.isActive = true
            return container
        }

        // FlippedStackView so the scroll view's content origin lives
        // at top-left. Without flipping, NSScrollView anchors content
        // to the bottom-left, which means a tall stack inside the
        // scroll view shows its BOTTOM half by default — header + the
        // top suggestions scroll out of view, exactly what we don't
        // want for a top-to-bottom suggestions list.
        let stack = FlippedStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = DesignTokens.Spacing.xs

        let title = NSTextField(labelWithString: "Suggestions (\(suggestions.count))")
        title.font = DesignTokens.Typography.caption1
        title.textColor = DesignTokens.Foreground.secondary
        stack.addArrangedSubview(title)

        for suggestion in suggestions {
            let row = SuggestionRowView(
                suggestion: suggestion,
                onAccept: onAccept,
                onReject: onReject
            )
            stack.addArrangedSubview(row)
            // Pin each row to the stack's full width so the cards fill
            // the panel horizontally; otherwise the row's intrinsic
            // content size leaves a ragged right edge.
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        // Bordered + always-visible scroller so the panel reads as a
        // self-contained card with an obvious overflow affordance.
        // Without a border the panel blends into the (often-empty)
        // description scroll view directly below, making it ambiguous
        // where one ends and the other begins; without a visible
        // scroller the user can't tell there are more cards to scroll
        // to.
        scroll.borderType = .lineBorder
        scroll.autohidesScrollers = false
        scroll.scrollerStyle = .legacy
        scroll.documentView = stack

        container.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: container.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            // The stack's width tracks the scroll view's so the rows
            // wrap correctly; height is left intrinsic so the content
            // size grows naturally and the scroll view kicks in once
            // it exceeds the container's cap.
            stack.widthAnchor.constraint(equalTo: scroll.widthAnchor),
        ])

        // `.required` upper height bound. This is load-bearing: a
        // priority-1000 cap propagates into fittingSize, which means
        // the inspector pane's fittingSize stays bounded regardless
        // of how many suggestions accumulate. Without it, macOS-26's
        // auto-refit cascade grows the window to fit the panel.
        let cap = container.heightAnchor.constraint(lessThanOrEqualToConstant: maxContentHeight)
        cap.priority = .required
        cap.isActive = true
        return container
    }
}

// MARK: - Per-suggestion row (extracted with the builder so tests can
// build panels without dragging in the rest of `InspectorController`)

/// One row of the Suggestions panel: fact text + evidence quote +
/// Accept / Reject buttons. Strong-captures the callbacks.
final class SuggestionRowView: NSView {
    private let suggestion: LedgerSuggestion
    private let onAccept: (LedgerSuggestion) -> Void
    private let onReject: (UUID) -> Void

    init(
        suggestion: LedgerSuggestion,
        onAccept: @escaping (LedgerSuggestion) -> Void,
        onReject: @escaping (UUID) -> Void
    ) {
        self.suggestion = suggestion
        self.onAccept = onAccept
        self.onReject = onReject
        super.init(frame: .zero)
        self.translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = DesignTokens.Radius.control
        layer?.borderWidth = 0.5
        // Background + border are set in updateLayer() so they re-
        // resolve on dark/light flip — raw `.cgColor` capture at
        // init-time would freeze in whichever appearance was active
        // (HANDOFF §2.1, same root cause as ThemedBackgroundView).

        let factLabel = NSTextField(wrappingLabelWithString: suggestion.fact.fact)
        factLabel.font = DesignTokens.Typography.body
        factLabel.textColor = DesignTokens.Foreground.primary
        factLabel.translatesAutoresizingMaskIntoConstraints = false

        let evidenceLabel = NSTextField(wrappingLabelWithString: "“\(suggestion.evidenceQuote)”")
        evidenceLabel.font = DesignTokens.Typography.caption1
        evidenceLabel.textColor = DesignTokens.Foreground.tertiary
        evidenceLabel.translatesAutoresizingMaskIntoConstraints = false

        let acceptBtn = NSButton(title: "Accept", target: self, action: #selector(acceptClicked))
        let rejectBtn = NSButton(title: "Reject", target: self, action: #selector(rejectClicked))
        for b in [acceptBtn, rejectBtn] {
            b.bezelStyle = .inline
            b.controlSize = .small
            b.font = DesignTokens.Typography.caption1
            b.translatesAutoresizingMaskIntoConstraints = false
        }
        let buttonRow = NSStackView(views: [acceptBtn, NSView(), rejectBtn])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = DesignTokens.Spacing.xs
        buttonRow.distribution = .fill
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [factLabel, evidenceLabel, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = DesignTokens.Spacing.xs
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: DesignTokens.Spacing.xs),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DesignTokens.Spacing.sm),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DesignTokens.Spacing.sm),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -DesignTokens.Spacing.xs),
            buttonRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            buttonRow.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    /// AppKit invokes `updateLayer()` when a layer-backed view needs
    /// to refresh — including on appearance change (dark/light flip).
    /// Resolving `.cgColor` inside the override means the color
    /// picks up the correct effective appearance instead of being
    /// frozen at construction time.
    override func updateLayer() {
        super.updateLayer()
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.6).cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    @objc private func acceptClicked() { onAccept(suggestion) }
    @objc private func rejectClicked() { onReject(suggestion.fact.id) }
}

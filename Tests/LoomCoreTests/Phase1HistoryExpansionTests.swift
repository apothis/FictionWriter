import Foundation
@testable import LoomCore

/// Sub-step 1.k — pure expansion-state tracking for the History tab.
/// Independent of the rendering: the History inspector queries this
/// state to decide which entry rows show their expand panel.
func phase1HistoryExpansionTests() -> TestSuite {
    let s = TestSuite("Phase1HistoryExpansion")

    s.test("default state is fully collapsed") {
        let state = HistoryExpansionState()
        try expectFalse(state.isExpanded(UUID()))
    }

    s.test("toggle expands a collapsed entry") {
        var state = HistoryExpansionState()
        let id = UUID()
        state.toggle(id)
        try expectTrue(state.isExpanded(id))
    }

    s.test("toggle collapses an expanded entry") {
        var state = HistoryExpansionState()
        let id = UUID()
        state.toggle(id)
        state.toggle(id)
        try expectFalse(state.isExpanded(id))
    }

    s.test("multiple entries can be expanded simultaneously") {
        var state = HistoryExpansionState()
        let a = UUID(), b = UUID()
        state.toggle(a)
        state.toggle(b)
        try expectTrue(state.isExpanded(a))
        try expectTrue(state.isExpanded(b))
    }

    s.test("collapseAll empties the expansion set") {
        var state = HistoryExpansionState()
        state.toggle(UUID())
        state.toggle(UUID())
        state.collapseAll()
        try expectFalse(state.isExpanded(UUID()))
    }

    return s
}

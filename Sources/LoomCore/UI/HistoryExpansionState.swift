import Foundation

/// Pure expansion-state tracker for the History tab. Kept separate from
/// the view controller so it's testable without AppKit machinery.
public struct HistoryExpansionState: Equatable {
    private var expandedIds: Set<UUID> = []

    public init() {}

    public func isExpanded(_ id: UUID) -> Bool {
        expandedIds.contains(id)
    }

    public mutating func toggle(_ id: UUID) {
        if expandedIds.contains(id) {
            expandedIds.remove(id)
        } else {
            expandedIds.insert(id)
        }
    }

    public mutating func expand(_ id: UUID) {
        expandedIds.insert(id)
    }

    public mutating func collapse(_ id: UUID) {
        expandedIds.remove(id)
    }

    public mutating func collapseAll() {
        expandedIds.removeAll()
    }
}

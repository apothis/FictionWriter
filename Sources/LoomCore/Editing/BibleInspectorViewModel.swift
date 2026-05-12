import Foundation

/// Bible entity category. Order in `allCases` drives section render
/// order in the list-detail inspector (LOOM_DESIGN_LANGUAGE.md §14.5.1
/// filter tab strip).
public enum BibleCategory: String, Codable, Equatable, CaseIterable {
    case characters
    case settings
    case objects
    case lorebook
}

/// Filter selection above the entity list.
public enum BibleFilter: Equatable, Hashable {
    case all
    case category(BibleCategory)
}

/// Stable reference to one Bible entity. Carries the category so a
/// selection can be resolved without ambiguity when entity collections
/// share UUIDs by accident.
public struct BibleEntityRef: Equatable, Hashable {
    public let category: BibleCategory
    public let id: UUID

    public init(category: BibleCategory, id: UUID) {
        self.category = category
        self.id = id
    }
}

/// One row in the left-pane list — entity name + back-ref. The right
/// pane reads the full entity off the project; this projection is just
/// what the list needs to render.
public struct BibleEntityListItem: Equatable {
    public let ref: BibleEntityRef
    public let name: String
}

/// A section in the left-pane list — header + rows. Empty sections
/// are still rendered (the `+` add-button per LOOM_DESIGN_LANGUAGE.md
/// §14.5.1 lives on the header, so the section needs to be visible
/// even when its entity list is empty).
public struct BibleSectionRow: Equatable {
    public let category: BibleCategory
    public let title: String
    public let items: [BibleEntityListItem]
}

/// Pure-data viewmodel behind the list-detail Bible inspector (Phase
/// 2 #4). Owns the filter + selection state; projects `Project.bible`
/// into the section/row list the UI renders. AppKit-free so the
/// contract pins under unit tests; the UI layer treats this as a
/// dumb state holder.
///
/// Reference class (not struct) because the controller mutates filter
/// and selection from user input and expects in-place state on a
/// shared instance.
public final class BibleInspectorViewModel {
    public private(set) var filter: BibleFilter
    public private(set) var selection: BibleEntityRef?

    public init(filter: BibleFilter = .all, selection: BibleEntityRef? = nil) {
        self.filter = filter
        self.selection = selection
    }

    // MARK: Projection

    public func sections(for project: Project) -> [BibleSectionRow] {
        let categories: [BibleCategory]
        switch filter {
        case .all:
            categories = BibleCategory.allCases
        case .category(let c):
            categories = [c]
        }
        return categories.map { category in
            BibleSectionRow(
                category: category,
                title: Self.title(for: category),
                items: items(in: category, project: project)
            )
        }
    }

    public func count(of category: BibleCategory, in project: Project) -> Int {
        switch category {
        case .characters: return project.bible.characters.count
        case .settings:   return project.bible.settings.count
        case .objects:    return project.bible.objects.count
        case .lorebook:   return project.bible.lorebook.count
        }
    }

    public func totalCount(in project: Project) -> Int {
        BibleCategory.allCases.map { count(of: $0, in: project) }.reduce(0, +)
    }

    public func entity(for ref: BibleEntityRef, in project: Project) -> BibleEntityListItem? {
        items(in: ref.category, project: project).first { $0.ref == ref }
    }

    // MARK: State transitions

    public func setSelection(_ ref: BibleEntityRef?) {
        selection = ref
    }

    /// Changes the active filter; clears any selection that wouldn't
    /// be visible under the new filter.
    public func setFilter(_ newFilter: BibleFilter, in project: Project) {
        filter = newFilter
        guard let sel = selection else { return }
        if !isVisible(sel, under: newFilter) || entity(for: sel, in: project) == nil {
            selection = nil
        }
    }

    /// Reconciles selection against the current project + filter.
    /// Clears a stale ref; otherwise picks the first visible entity
    /// when nothing is selected. Returns `true` when state changed.
    @discardableResult
    public func reconcileSelection(in project: Project) -> Bool {
        if let sel = selection {
            if !isVisible(sel, under: filter) || entity(for: sel, in: project) == nil {
                selection = nil
                return true
            }
            return false
        }
        // No selection — fall back to first visible entity, if any.
        for section in sections(for: project) {
            if let first = section.items.first {
                selection = first.ref
                return true
            }
        }
        return false
    }

    // MARK: Internals

    private func items(in category: BibleCategory, project: Project) -> [BibleEntityListItem] {
        switch category {
        case .characters:
            return project.bible.characters.map {
                BibleEntityListItem(
                    ref: BibleEntityRef(category: .characters, id: $0.id),
                    name: $0.name
                )
            }
        case .settings:
            return project.bible.settings.map {
                BibleEntityListItem(
                    ref: BibleEntityRef(category: .settings, id: $0.id),
                    name: $0.name
                )
            }
        case .objects:
            return project.bible.objects.map {
                BibleEntityListItem(
                    ref: BibleEntityRef(category: .objects, id: $0.id),
                    name: $0.name
                )
            }
        case .lorebook:
            return project.bible.lorebook.map {
                BibleEntityListItem(
                    ref: BibleEntityRef(category: .lorebook, id: $0.id),
                    name: $0.name
                )
            }
        }
    }

    private func isVisible(_ ref: BibleEntityRef, under filter: BibleFilter) -> Bool {
        switch filter {
        case .all: return true
        case .category(let c): return c == ref.category
        }
    }

    private static func title(for category: BibleCategory) -> String {
        switch category {
        case .characters: return "Characters"
        case .settings:   return "Settings"
        case .objects:    return "Objects"
        case .lorebook:   return "Lorebook"
        }
    }
}

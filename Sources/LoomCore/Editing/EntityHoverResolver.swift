import Foundation

/// Phase 2.5 (#10 follow-on) — populates the hover-preview popover.
/// Pure projection: given an entity id + a project, return the
/// display info the popover renders (name, role chip text,
/// description excerpt). Nil when the id no longer matches any
/// Bible entity — a stale entity-link in prose would surface
/// nothing rather than show a phantom card.
public struct EntityHoverInfo: Equatable {
    public let displayName: String
    /// Role label for characters (e.g. "protagonist"). Nil for
    /// Settings + Objects — those don't carry a role chip per
    /// §14.5.1.
    public let roleLabel: String?
    /// First ~200 chars of the entity's description, with an
    /// ellipsis suffix when truncated.
    public let descriptionExcerpt: String

    public init(displayName: String, roleLabel: String?, descriptionExcerpt: String) {
        self.displayName = displayName
        self.roleLabel = roleLabel
        self.descriptionExcerpt = descriptionExcerpt
    }
}

public enum EntityHoverResolver {
    public static func info(for id: UUID, in project: Project) -> EntityHoverInfo? {
        if let c = project.bible.characters.first(where: { $0.id == id }) {
            return EntityHoverInfo(
                displayName: c.name,
                roleLabel: c.role.rawValue,
                descriptionExcerpt: excerpt(c.description)
            )
        }
        if let s = project.bible.settings.first(where: { $0.id == id }) {
            return EntityHoverInfo(
                displayName: s.name,
                roleLabel: nil,
                descriptionExcerpt: excerpt(s.description)
            )
        }
        if let o = project.bible.objects.first(where: { $0.id == id }) {
            return EntityHoverInfo(
                displayName: o.name,
                roleLabel: nil,
                descriptionExcerpt: excerpt(o.description)
            )
        }
        return nil
    }

    private static func excerpt(_ s: String) -> String {
        let limit = 200
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= limit { return trimmed }
        let prefix = trimmed.prefix(limit)
        return String(prefix) + "…"
    }
}

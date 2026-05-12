import Foundation

/// One candidate in an @-mention autocomplete result.
public struct EntityAutocompleteMatch: Equatable {
    public let ref: BibleEntityRef
    /// The canonical name the editor should insert when the user
    /// selects this match. Never the matched alias — the underlying
    /// markdown reference is `[Mia](#entity/<uuid>)` regardless of
    /// which alias the user was typing.
    public let displayName: String
}

/// Phase 2 #10 (pure-data) — entity-mention autocomplete provider.
/// Given a project and a partial query (already stripped of the
/// leading `@`), returns ranked match candidates by:
///   1. Prefix match on the entity's name OR any alias.
///   2. Case-insensitive.
///   3. Empty query returns all entities, alphabetised by name —
///      useful when the user types `@` and pauses.
///
/// De-dupes when name + an alias both match the prefix; the popover
/// shows the entity once.
public enum EntityAutocomplete {
    public static func matches(for query: String, in project: Project) -> [EntityAutocompleteMatch] {
        let q = query.lowercased()
        var candidates: [(BibleEntityRef, String)] = []   // (ref, displayName)
        for c in project.bible.characters {
            candidates.append((BibleEntityRef(category: .characters, id: c.id), c.name))
        }
        for st in project.bible.settings {
            candidates.append((BibleEntityRef(category: .settings, id: st.id), st.name))
        }
        for o in project.bible.objects {
            candidates.append((BibleEntityRef(category: .objects, id: o.id), o.name))
        }

        let filtered = candidates.filter { (ref, displayName) in
            if q.isEmpty { return true }
            // Match against displayName + any alias for the entity.
            let candidateKeys = [displayName] + aliases(for: ref, in: project)
            return candidateKeys.contains(where: { $0.lowercased().hasPrefix(q) })
        }

        // De-dup by entity id (name + alias may both match).
        var seen: Set<UUID> = []
        var unique: [(BibleEntityRef, String)] = []
        for c in filtered {
            if seen.insert(c.0.id).inserted {
                unique.append(c)
            }
        }

        // Alphabetical by name. Stable; the popover order is the
        // user's first impression.
        unique.sort { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }

        return unique.map { EntityAutocompleteMatch(ref: $0.0, displayName: $0.1) }
    }

    private static func aliases(for ref: BibleEntityRef, in project: Project) -> [String] {
        switch ref.category {
        case .characters: return project.bible.characters.first { $0.id == ref.id }?.aliases ?? []
        case .settings:   return project.bible.settings.first { $0.id == ref.id }?.aliases ?? []
        case .objects:    return project.bible.objects.first { $0.id == ref.id }?.aliases ?? []
        case .lorebook:   return []   // lorebook entries aren't @-mention candidates
        }
    }
}

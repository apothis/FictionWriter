import Foundation

// Phase 8.b.1 — pure-data projection that unifies References (Phase 5)
// + Templates (Phase 7) into a single user-facing concept per
// LOOM_SCENE_EXEMPLAR.md §5.1 Option C ("rename + soft-merge"). The
// underlying storage stays exactly as it was — ReferenceText in
// references/ and TemplateScene in templates/ — but the workspace
// shows one card per scene-exemplar (joined by shared UUID).
//
// New ingest paths write a Reference + Template with a SHARED UUID
// from a single user paste; legacy items appear as orphans with
// either hasIndex=false (Pass-A skeleton only) or hasBeats=false
// (chunks only). The user can re-ingest to fill the missing sidecar.

public struct SceneExemplar: Equatable {
    public let id: UUID
    public let name: String
    public let nsfw: Bool
    /// True when a `.index` sidecar (chunks + embedded vectors) is
    /// present for this UUID.
    public let hasIndex: Bool
    /// True when a `.beats.json` sidecar (Pass-A skeleton + voice
    /// descriptor + cast/setting markers) is present for this UUID.
    public let hasBeats: Bool

    public init(
        id: UUID,
        name: String,
        nsfw: Bool = false,
        hasIndex: Bool,
        hasBeats: Bool
    ) {
        self.id = id
        self.name = name
        self.nsfw = nsfw
        self.hasIndex = hasIndex
        self.hasBeats = hasBeats
    }
}

public enum SceneExemplarComposer {
    /// Project the (references, templates) pair onto a unified
    /// `SceneExemplar` array. Items with a matching UUID across both
    /// inputs collapse into one card; items present in only one
    /// surface as orphans with the corresponding `has...` flag false.
    /// The id-set arguments are the source of truth for sidecar
    /// presence (caller probes the filesystem; the composer is pure
    /// data).
    public static func merge(
        references: [ReferenceText],
        templates: [TemplateScene],
        indexedReferenceIds: Set<UUID>,
        skeletonTemplateIds: Set<UUID>
    ) -> [SceneExemplar] {
        let refsById = Dictionary(uniqueKeysWithValues: references.map { ($0.id, $0) })
        let tmplsById = Dictionary(uniqueKeysWithValues: templates.map { ($0.id, $0) })
        var allIds = Set<UUID>()
        for r in references { allIds.insert(r.id) }
        for t in templates { allIds.insert(t.id) }

        return allIds.map { id in
            let ref = refsById[id]
            let tmpl = tmplsById[id]
            // Template name wins when both exist: in Phase 7 templates
            // were user-named while references were often pasted with
            // auto-generated labels.
            let name = tmpl?.name ?? ref?.name ?? ""
            let nsfw = (tmpl?.nsfw ?? false) || (ref?.nsfw ?? false)
            return SceneExemplar(
                id: id,
                name: name,
                nsfw: nsfw,
                hasIndex: indexedReferenceIds.contains(id),
                hasBeats: skeletonTemplateIds.contains(id)
            )
        }
    }
}

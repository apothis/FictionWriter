import Foundation

/// Phase 2 #11 — pre-computed mention index across all scenes.
/// Pure projection: scan every scene's prose with EntityReference.scan,
/// fold into per-entity counts + per-scene breakdowns. The sparkline
/// view (when it lands) reads from this; the inspector "N mentions"
/// chip in the detail header reads `totalCount(for:)`.
public struct MentionIndex: Equatable {
    /// Per-entity total mention counts across the whole manuscript.
    public let totalsByEntityId: [UUID: Int]
    /// Per-entity, per-scene mention counts. The sparkline reads
    /// this to position marker dots; an entry of 0 is omitted.
    public let perSceneByEntityId: [UUID: [UUID: Int]]

    public init(
        totalsByEntityId: [UUID: Int] = [:],
        perSceneByEntityId: [UUID: [UUID: Int]] = [:]
    ) {
        self.totalsByEntityId = totalsByEntityId
        self.perSceneByEntityId = perSceneByEntityId
    }

    public func totalCount(for entityId: UUID) -> Int {
        totalsByEntityId[entityId] ?? 0
    }

    public func count(for entityId: UUID, in sceneId: UUID) -> Int {
        perSceneByEntityId[entityId]?[sceneId] ?? 0
    }

    /// Build the index. Counts only mentions whose entity id matches
    /// some known Bible entity (character / setting / object) — a
    /// stale link to a deleted entity isn't tracked.
    public static func build(for project: Project, scenes: [UUID: Scene]) -> MentionIndex {
        let knownIds: Set<UUID> = {
            var ids: Set<UUID> = []
            ids.formUnion(project.bible.characters.map(\.id))
            ids.formUnion(project.bible.settings.map(\.id))
            ids.formUnion(project.bible.objects.map(\.id))
            return ids
        }()

        var totals: [UUID: Int] = [:]
        var perScene: [UUID: [UUID: Int]] = [:]

        for (sceneId, scene) in scenes {
            let references = EntityReference.scan(in: scene.prose)
            for ref in references where knownIds.contains(ref.id) {
                totals[ref.id, default: 0] += 1
                perScene[ref.id, default: [:]][sceneId, default: 0] += 1
            }
        }

        return MentionIndex(totalsByEntityId: totals, perSceneByEntityId: perScene)
    }
}

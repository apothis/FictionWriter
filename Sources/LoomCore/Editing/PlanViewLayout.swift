import Foundation

/// Phase 3 §E — pure-data card model the Plan view renders. Each
/// card carries the scene id (for click → selectScene routing) and
/// the surface-level data the card cell displays.
public struct PlanSceneCard: Equatable {
    public let sceneId: UUID
    public let title: String
    public let wordCount: Int
    public let status: SceneStatus
    public let summary: String
    /// "Untitled" for orphan scenes; otherwise the chapter title.
    /// The first iteration of Plan view uses this as a leading
    /// chip on each card; the polished card-grid groups by this
    /// field as a section header.
    public let groupTitle: String

    public init(
        sceneId: UUID,
        title: String,
        wordCount: Int,
        status: SceneStatus,
        summary: String,
        groupTitle: String
    ) {
        self.sceneId = sceneId
        self.title = title
        self.wordCount = wordCount
        self.status = status
        self.summary = summary
        self.groupTitle = groupTitle
    }
}

/// Projection from a Project + its in-memory Scenes to the ordered
/// list of cards the Plan view renders. Walks the manuscript
/// hierarchy depth-first (Part → Chapter → Scene) and appends
/// orphaned scenes at the end so an unstructured project still
/// renders a sensible flat list.
public struct PlanViewLayout: Equatable {
    public let cards: [PlanSceneCard]

    public init(cards: [PlanSceneCard] = []) {
        self.cards = cards
    }

    public static func build(for project: Project, scenes: [UUID: Scene]) -> PlanViewLayout {
        var cards: [PlanSceneCard] = []
        for part in project.manuscript.parts {
            for chapter in part.chapters {
                for sceneId in chapter.sceneIds {
                    guard let scene = scenes[sceneId] else { continue }
                    cards.append(makeCard(scene: scene, groupTitle: chapter.title))
                }
            }
        }
        for sceneId in project.manuscript.orphanedSceneIds {
            guard let scene = scenes[sceneId] else { continue }
            cards.append(makeCard(scene: scene, groupTitle: "Untitled"))
        }
        return PlanViewLayout(cards: cards)
    }

    private static func makeCard(scene: Scene, groupTitle: String) -> PlanSceneCard {
        PlanSceneCard(
            sceneId: scene.id,
            title: scene.title,
            wordCount: WordCount.count(scene.prose),
            status: scene.status,
            summary: scene.summary,
            groupTitle: groupTitle
        )
    }
}

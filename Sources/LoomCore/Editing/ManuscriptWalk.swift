import Foundation

/// Phase 3 §C — pure-data helpers to traverse the manuscript tree
/// + fold scene-level word counts up to chapter / part / project
/// totals. The Plan-view rendering surface (§E) and the Phase 2 #11
/// sparkline both read these; keeping the projection here means the
/// view layer stays a thin draw + click forwarder.
public extension Manuscript {
    /// Scenes in manuscript order: Parts → their Chapters → their
    /// scene ids, followed by `orphanedSceneIds`. Trashed scenes
    /// are intentionally excluded — they're not in the manuscript.
    var flatSceneIds: [UUID] {
        var out: [UUID] = []
        for part in parts {
            for chapter in part.chapters {
                out.append(contentsOf: chapter.sceneIds)
            }
        }
        out.append(contentsOf: orphanedSceneIds)
        return out
    }
}

/// Word counts at every level of the manuscript hierarchy (Part /
/// Chapter / Project total). Scene-level counts are not collected —
/// the editor already exposes per-scene counts on demand via
/// `WordCount.count(scene.prose)`.
public struct ManuscriptWordCount: Equatable {
    public let totalWords: Int
    public let byPartId: [UUID: Int]
    public let byChapterId: [UUID: Int]

    public init(
        totalWords: Int = 0,
        byPartId: [UUID: Int] = [:],
        byChapterId: [UUID: Int] = [:]
    ) {
        self.totalWords = totalWords
        self.byPartId = byPartId
        self.byChapterId = byChapterId
    }

    public static func compute(
        for project: Project,
        scenes: [UUID: Scene]
    ) -> ManuscriptWordCount {
        var byChapter: [UUID: Int] = [:]
        var byPart: [UUID: Int] = [:]
        var total = 0
        for part in project.manuscript.parts {
            var partTotal = 0
            for chapter in part.chapters {
                var chTotal = 0
                for sceneId in chapter.sceneIds {
                    guard let scene = scenes[sceneId] else { continue }
                    chTotal += WordCount.count(scene.prose)
                }
                byChapter[chapter.id] = chTotal
                partTotal += chTotal
            }
            byPart[part.id] = partTotal
            total += partTotal
        }
        // Orphan scenes contribute to the project total but no
        // Part/Chapter bucket — Plan view (§E) renders them under
        // an implicit "Untitled" group.
        for sceneId in project.manuscript.orphanedSceneIds {
            guard let scene = scenes[sceneId] else { continue }
            total += WordCount.count(scene.prose)
        }
        return ManuscriptWordCount(
            totalWords: total,
            byPartId: byPart,
            byChapterId: byChapter
        )
    }
}

import Foundation

/// Planned Project mode — the deterministic outline allocator.
///
/// Turns a target word count into scene and chapter counts and an
/// act distribution. Research is emphatic that these counts must be
/// computed in code, not asked of the LLM: a model told to "generate
/// scenes" drifts off any requested count, so the outline generator
/// instead fills a fixed number of pre-computed slots
/// (LOOM_PLANNED_PROJECT.md §4).
///
/// Heuristics: scenes run ~1,500 words; chapters hold ~4 scenes; the
/// three-act split is 25 / 50 / 25 of the scene count. A scenario
/// that would yield ≤1 chapter is flat (no chapter layer at all).
public struct OutlineSizing: Equatable {
    public let totalWords: Int
    public let sceneCount: Int
    /// 0 ⇒ a flat scene list with no chapter layer.
    public let chapterCount: Int
    public let perSceneWords: Int
    public let act1SceneCount: Int
    public let act2SceneCount: Int
    public let act3SceneCount: Int

    public var isFlat: Bool { chapterCount == 0 }

    private static let wordsPerScene = 1_500.0
    private static let scenesPerChapter = 4.0

    public static func plan(for scenario: LengthScenario) -> OutlineSizing {
        plan(totalWords: scenario.targetWordCount)
    }

    public static func plan(totalWords: Int) -> OutlineSizing {
        let words = max(1, totalWords)
        let scenes = max(1, Int((Double(words) / wordsPerScene).rounded()))
        // ≤1 chapter adds no structure — collapse to a flat list.
        let rawChapters = Int((Double(scenes) / scenesPerChapter).rounded())
        let chapters = rawChapters <= 1 ? 0 : rawChapters
        // Act 1 + 3 take 25% each; act 2 absorbs the remainder so the
        // three always sum back to the scene count exactly.
        let act1 = Int((Double(scenes) * 0.25).rounded())
        let act3 = Int((Double(scenes) * 0.25).rounded())
        let act2 = scenes - act1 - act3
        return OutlineSizing(
            totalWords: words,
            sceneCount: scenes,
            chapterCount: chapters,
            perSceneWords: words / scenes,
            act1SceneCount: act1,
            act2SceneCount: act2,
            act3SceneCount: act3
        )
    }
}

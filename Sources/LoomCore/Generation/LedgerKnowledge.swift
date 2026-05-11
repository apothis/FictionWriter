import Foundation

/// Phase 4 #7 sub-task 6 — pure-data KNOWS / DOES NOT KNOW query.
/// Implements the SymbolicToM-style scene-exposure derivation
/// described in LOOM_STORY_BIBLE §3.5 + LOOM_LEDGER_SPIKE §8.3:
/// `unknown` is NOT something the model extracts (the spike confirmed
/// 0/2 recall on negative knowledge); it's set-differenced from
/// per-scene exposure at query time. The extractor emits `asserted`
/// only; the bible accumulates those across scenes, and this query
/// walks the manuscript chronologically and asks: for each fact
/// extracted in scene S, was C present in S?
///
/// Result format: two flat `KnownFact` arrays — `knows` and
/// `unknowns`. The prompt-layer renderer (sub-task 7) formats them
/// as the `[KNOWLEDGE-LEDGER]` block.
public enum LedgerKnowledge {

    public struct Result: Equatable {
        public let knows: [KnownFact]
        public let unknowns: [KnownFact]
        public init(knows: [KnownFact], unknowns: [KnownFact]) {
            self.knows = knows
            self.unknowns = unknowns
        }
    }

    /// Walk scenes chronologically up to and including `asOfSceneId`;
    /// for each in-scope scene S, bucket every fact extracted from S
    /// (across all characters' ledgers) into `knows` if `characterId`
    /// was present in S, otherwise `unknowns`.
    ///
    /// Chronological order is `manuscript.flatSceneIds` (narrative
    /// order). Phase 4.x can swap in SceneTime-based chronological
    /// order when the flashback-heavy case lands; the §11 design doc
    /// flagged that as a deferred call.
    ///
    /// If `asOfSceneId` isn't in `flatSceneIds` (orphan or stranger
    /// id), treat ALL scenes as in scope — a draft scene the user
    /// hasn't placed yet still gets the full project's ledger context.
    public static func compute(
        characterId: UUID,
        asOfSceneId: UUID,
        in project: Project,
        scenes: [UUID: Scene],
        mentions: MentionIndex? = nil
    ) -> Result {
        let mentionIndex = mentions ?? MentionIndex.build(for: project, scenes: scenes)
        let flatIds = project.manuscript.flatSceneIds
        let scopeIds: [UUID]
        if let idx = flatIds.firstIndex(of: asOfSceneId) {
            scopeIds = Array(flatIds[0...idx])
        } else {
            scopeIds = flatIds
        }
        guard let character = project.bible.characters.first(where: { $0.id == characterId }) else {
            return Result(knows: [], unknowns: [])
        }
        var knows: [KnownFact] = []
        var unknowns: [KnownFact] = []
        for sceneId in scopeIds {
            guard let scene = scenes[sceneId] else { continue }
            let present = ScenePresence.isPresent(
                characterId: characterId,
                in: scene,
                character: character,
                mentions: mentionIndex
            )
            for owner in project.bible.characters {
                guard let facts = owner.knownFactsBySceneId[sceneId] else { continue }
                if present {
                    knows.append(contentsOf: facts)
                } else {
                    unknowns.append(contentsOf: facts)
                }
            }
        }
        return Result(knows: knows, unknowns: unknowns)
    }
}

import Foundation

/// Phase 4.5 §5.2 — the JSON contract for Swift→JS push over the
/// WKScriptMessageHandler bridge. Built from `Project` + `scenes` +
/// `LedgerSuggestionsQueue`, encoded to JSON, pushed to the web
/// renderer via `webView.evaluateJavaScript("window.loom.applySnapshot(...)")`.
///
/// Snapshots are full-replace, not diff. Bibles are small (typically
/// <50KB JSON for a working novel); diffing isn't worth the
/// complexity at this scale. If it ever is, the bridge can switch
/// to a patch protocol without changing this type.
///
/// See [LOOM_BIBLE_WORKSPACE.md §5.2-§5.3] for the bridge contract
/// and persistence flow.
public struct BibleWorkspaceSnapshot: Codable, Equatable {
    public let projectTitle: String
    public let characters: [Character]
    public let lorebook: [LorebookEntry]
    public let scenes: [SceneSummary]
    public let suggestions: [PendingSuggestion]

    public init(
        projectTitle: String,
        characters: [Character],
        lorebook: [LorebookEntry],
        scenes: [SceneSummary],
        suggestions: [PendingSuggestion]
    ) {
        self.projectTitle = projectTitle
        self.characters = characters
        self.lorebook = lorebook
        self.scenes = scenes
        self.suggestions = suggestions
    }

    /// Builds a snapshot from the current `ProjectSession` state.
    /// Ordering is stable: characters in `bible.characters` order,
    /// lorebook in `bible.lorebook` order, scenes in
    /// `manuscript.flatSceneIds` order, suggestions flattened across
    /// characters in `bible.characters` order then per-character
    /// insertion order.
    public static func build(
        project: Project,
        scenes: [UUID: Scene],
        suggestionsQueue: LedgerSuggestionsQueue
    ) -> BibleWorkspaceSnapshot {
        let sceneSummaries: [SceneSummary] = project.manuscript.flatSceneIds.compactMap { id in
            guard let scene = scenes[id] else { return nil }
            return SceneSummary(id: scene.id, title: scene.title)
        }
        var pending: [PendingSuggestion] = []
        for character in project.bible.characters {
            for suggestion in suggestionsQueue.suggestions(forCharacter: character.id) {
                pending.append(PendingSuggestion(
                    factId: suggestion.fact.id,
                    characterId: suggestion.characterId,
                    factText: suggestion.fact.fact,
                    certainty: suggestion.fact.certainty.rawValue,
                    evidenceQuote: suggestion.evidenceQuote,
                    sourceSceneId: suggestion.fact.sourceSceneId
                ))
            }
        }
        return BibleWorkspaceSnapshot(
            projectTitle: project.title,
            characters: project.bible.characters,
            lorebook: project.bible.lorebook,
            scenes: sceneSummaries,
            suggestions: pending
        )
    }
}

/// Lightweight scene projection — just id + title. The full `Scene`
/// type carries the prose blob + frontmatter we deliberately don't
/// ship across the bridge (the workspace doesn't display prose;
/// it only needs to label suggestions / facts by their source
/// scene).
public struct SceneSummary: Codable, Equatable {
    public let id: UUID
    public let title: String

    public init(id: UUID, title: String) {
        self.id = id
        self.title = title
    }
}

/// Flat projection of `LedgerSuggestion` for the bridge. The web
/// side renders suggestions as a per-character list; the nested
/// `KnownFact` shape would force JSX into `suggestion.fact.fact` /
/// `suggestion.fact.certainty.rawValue`, which is ugly and brittle
/// against future schema drift. Flat is friendlier.
///
/// `factId` is the canonical id used to accept/reject this
/// suggestion via the intent channel (Session 2).
public struct PendingSuggestion: Codable, Equatable {
    public let factId: UUID
    public let characterId: UUID
    public let factText: String
    public let certainty: String
    public let evidenceQuote: String
    public let sourceSceneId: UUID?

    public init(
        factId: UUID,
        characterId: UUID,
        factText: String,
        certainty: String,
        evidenceQuote: String,
        sourceSceneId: UUID?
    ) {
        self.factId = factId
        self.characterId = characterId
        self.factText = factText
        self.certainty = certainty
        self.evidenceQuote = evidenceQuote
        self.sourceSceneId = sourceSceneId
    }
}

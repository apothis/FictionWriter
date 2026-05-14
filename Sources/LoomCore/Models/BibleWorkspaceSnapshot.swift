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
    public let characters: [SnapshotCharacter]
    public let lorebook: [LorebookEntry]
    public let scenes: [SceneSummary]
    public let suggestions: [PendingSuggestion]
    /// Phase 5 production A2.1 — reference texts available to the
    /// style-RAG retriever. Populated by the caller (typically
    /// `BibleWorkspaceWindowController`) via
    /// `ProjectSession.listReferenceSnapshots()`, which enumerates
    /// the `references/` directory on disk. The list comes in
    /// here as an explicit parameter rather than read from disk
    /// inside `build(...)` to keep this function pure-data and
    /// preserve the existing Phase 4.5 testing pattern.
    public let references: [SnapshotReference]
    /// Phase 7.b.5 — template scenes for the `.generateFromTemplate`
    /// mode. Populated by the caller via
    /// `ProjectSession.listTemplateSceneSnapshots()`. Mirrors the
    /// references slot pattern.
    public let templateScenes: [SnapshotTemplateScene]
    /// Templates with a Pass-A beat extraction currently in flight.
    /// Transient state (not persisted) — populated by
    /// `BibleWorkspaceWindowController` from `AppState`'s in-flight
    /// set on each snapshot push. The React UI uses it to flip the
    /// template editor's button to "Extracting…" + disable while
    /// the Ollama gemma4_2b call is pending.
    ///
    /// Encoded as a JSON array of uppercase UUID strings so the JS
    /// side can `Array.includes(id)` against `template.id` directly.
    public let extractingTemplateIds: [UUID]
    /// Whether the underlying project is persisted on disk. False for
    /// "Untitled" in-memory sessions where `ProjectSession.url` is nil.
    /// References + TemplateScenes are file-system entities; their
    /// `addReference` / `addTemplateScene` paths silently drop on
    /// in-memory sessions. The UI inspects this flag to disable the
    /// corresponding Add buttons rather than firing intents that
    /// no-op.
    ///
    /// Default true on legacy decode so older payloads (no field)
    /// preserve the previous "always allow Add" behaviour.
    public let isProjectOnDisk: Bool

    public init(
        projectTitle: String,
        characters: [SnapshotCharacter],
        lorebook: [LorebookEntry],
        scenes: [SceneSummary],
        suggestions: [PendingSuggestion],
        references: [SnapshotReference] = [],
        templateScenes: [SnapshotTemplateScene] = [],
        isProjectOnDisk: Bool = true,
        extractingTemplateIds: [UUID] = []
    ) {
        self.projectTitle = projectTitle
        self.characters = characters
        self.lorebook = lorebook
        self.scenes = scenes
        self.suggestions = suggestions
        self.references = references
        self.templateScenes = templateScenes
        self.isProjectOnDisk = isProjectOnDisk
        self.extractingTemplateIds = extractingTemplateIds
    }

    private enum CodingKeys: String, CodingKey {
        case projectTitle, characters, lorebook, scenes, suggestions
        case references, templateScenes, isProjectOnDisk
        case extractingTemplateIds
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.projectTitle = try c.decode(String.self, forKey: .projectTitle)
        self.characters = try c.decode([SnapshotCharacter].self, forKey: .characters)
        self.lorebook = try c.decode([LorebookEntry].self, forKey: .lorebook)
        self.scenes = try c.decode([SceneSummary].self, forKey: .scenes)
        self.suggestions = try c.decode([PendingSuggestion].self, forKey: .suggestions)
        self.references = try c.decodeIfPresent([SnapshotReference].self, forKey: .references) ?? []
        self.templateScenes = try c.decodeIfPresent([SnapshotTemplateScene].self, forKey: .templateScenes) ?? []
        self.isProjectOnDisk = try c.decodeIfPresent(Bool.self, forKey: .isProjectOnDisk) ?? true
        // Wire format is `[String]` — uppercase UUID strings so the
        // JS side can do `Array.includes(template.id)` directly.
        let idStrings = try c.decodeIfPresent([String].self, forKey: .extractingTemplateIds) ?? []
        self.extractingTemplateIds = idStrings.compactMap(UUID.init(uuidString:))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(projectTitle, forKey: .projectTitle)
        try c.encode(characters, forKey: .characters)
        try c.encode(lorebook, forKey: .lorebook)
        try c.encode(scenes, forKey: .scenes)
        try c.encode(suggestions, forKey: .suggestions)
        try c.encode(references, forKey: .references)
        try c.encode(templateScenes, forKey: .templateScenes)
        try c.encode(isProjectOnDisk, forKey: .isProjectOnDisk)
        // Emit uppercase UUID strings — UUID.uuidString is uppercase
        // by default, matching the rest of the wire contract.
        try c.encode(extractingTemplateIds.map(\.uuidString), forKey: .extractingTemplateIds)
    }

    /// Builds a snapshot from the current `ProjectSession` state.
    /// Ordering is stable: characters in `bible.characters` order,
    /// lorebook in `bible.lorebook` order, scenes in
    /// `manuscript.flatSceneIds` order, suggestions flattened across
    /// characters in `bible.characters` order then per-character
    /// insertion order. References are caller-ordered (typically
    /// alphabetical-by-name, since the disk enumeration is unordered).
    public static func build(
        project: Project,
        scenes: [UUID: Scene],
        references: [SnapshotReference] = [],
        templateScenes: [SnapshotTemplateScene] = [],
        isProjectOnDisk: Bool = true,
        extractingTemplateIds: [UUID] = [],
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
            characters: project.bible.characters.map(SnapshotCharacter.init(from:)),
            lorebook: project.bible.lorebook,
            scenes: sceneSummaries,
            suggestions: pending,
            references: references,
            templateScenes: templateScenes,
            isProjectOnDisk: isProjectOnDisk,
            extractingTemplateIds: extractingTemplateIds
        )
    }
}

/// Bridge-specific projection of `TemplateScene`. Mirrors
/// `SnapshotReference` shape: id + metadata + body + a derived
/// `beatCount` that's nil when the .beats.json sidecar hasn't been
/// generated yet (UI surfaces a "needs Extract" prompt). The full
/// body is shipped so the React editor's textarea can edit it
/// in place.
public struct SnapshotTemplateScene: Codable, Equatable {
    public let id: UUID
    public var name: String
    public var nsfw: Bool
    public var createdAt: Date
    public var body: String
    public var beatCount: Int?

    public init(from scene: TemplateScene, beatCount: Int?) {
        self.id = scene.id
        self.name = scene.name
        self.nsfw = scene.nsfw
        self.createdAt = scene.createdAt
        self.body = scene.body
        self.beatCount = beatCount
    }

    // Custom encode so a nil `beatCount` ships as JSON `null` rather
    // than being omitted (Swift's default Codable uses
    // `encodeIfPresent` for optionals). The React UI relies on
    // strict `=== null` checks for the "no sidecar yet" state; an
    // omitted key arrives as `undefined` and falls through to the
    // "have count" branch (renders "undefined beats on disk" +
    // "Re-extract" instead of "Not yet extracted" + "Extract").
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(nsfw, forKey: .nsfw)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(body, forKey: .body)
        try c.encode(beatCount, forKey: .beatCount) // emits null when nil
    }
}

/// Bridge-specific projection of `ReferenceText`. The `body` field
/// passes through unchanged — the React side renders an editable
/// `<Textarea>` for it; truncating would force a round-trip on every
/// edit. `chunkCount` is the derived "ingest state" signal: nil means
/// "no `.index` sidecar exists yet" (the UI prompts to ingest);
/// non-nil means the chunked vectors are on disk. `createdAt` is
/// surfaced for the UI's "added X days ago" hint.
public struct SnapshotReference: Codable, Equatable {
    public let id: UUID
    public var name: String
    public var nsfw: Bool
    public var createdAt: Date
    public var body: String
    public var chunkCount: Int?

    public init(from ref: ReferenceText, chunkCount: Int?) {
        self.id = ref.id
        self.name = ref.name
        self.nsfw = ref.nsfw
        self.createdAt = ref.createdAt
        self.body = ref.body
        self.chunkCount = chunkCount
    }

    // Same explicit-null-on-nil contract as SnapshotTemplateScene
    // — keeps the React UI's `chunkCount === null` check working
    // for newly-created references.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(nsfw, forKey: .nsfw)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(body, forKey: .body)
        try c.encode(chunkCount, forKey: .chunkCount)
    }
}

/// Bridge-specific projection of `Character`. The on-disk Codable
/// shape of `Character` encodes `knownFactsBySceneId: [UUID: [KnownFact]]`
/// as a flat JSON array (`[uuid, [facts], uuid, [facts], ...]`) —
/// `JSONEncoder` only emits JSON-object form for dictionaries with
/// `String` or `Int` keys. The web side needs an object the JSX can
/// index by scene-id string, so this projection re-keys the dict to
/// `[String: [KnownFact]]` before encoding.
///
/// Every other field passes through unchanged. Future bridge-only
/// derived fields (e.g., resolved POV name strings, scene-presence
/// counts) can land here too without polluting the on-disk schema.
public struct SnapshotCharacter: Codable, Equatable {
    public let id: UUID
    public var name: String
    public var aliases: [String]
    public var role: CharacterRole
    public var oneLine: String
    public var description: String
    public var personality: String
    public var appearance: String
    public var voice: String
    public var goals: String
    public var relationships: [Relationship]
    public var avatarPath: String?
    /// Re-keyed from `[UUID: [KnownFact]]` to `[String: [KnownFact]]`
    /// so JSONEncoder emits a JS-friendly object (not a flat array).
    /// The web side's TS type `Character.knownFactsBySceneId` is
    /// `Record<string, KnownFact[]>`.
    public var knownFactsBySceneId: [String: [KnownFact]]
    public var canonBrief: String?
    public var customFields: [CharacterCustomField]
    public var injectionMode: InjectionMode

    public init(from character: Character) {
        self.id = character.id
        self.name = character.name
        self.aliases = character.aliases
        self.role = character.role
        self.oneLine = character.oneLine
        self.description = character.description
        self.personality = character.personality
        self.appearance = character.appearance
        self.voice = character.voice
        self.goals = character.goals
        self.relationships = character.relationships
        self.avatarPath = character.avatarPath
        self.knownFactsBySceneId = Dictionary(
            uniqueKeysWithValues: character.knownFactsBySceneId.map { ($0.key.uuidString, $0.value) }
        )
        self.canonBrief = character.canonBrief
        self.customFields = character.customFields
        self.injectionMode = character.injectionMode
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

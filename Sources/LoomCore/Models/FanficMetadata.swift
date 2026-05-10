import Foundation

/// Fanfic-mode metadata. Populated only when `Project.kind == .fanfic`;
/// nil otherwise.
///
/// Phase 2 #2 ships the schema (HANDOFF §9.1). The fanfic UI lands
/// in Phase 5.b-c (LOOM_FANFIC.md §9) — the schema sits here now so
/// the migration cost is one-time and existing projects forward-load
/// cleanly.
///
/// AO3 tag taxonomy is the foundation; we don't reinvent the wheel
/// — we use the wheel that millions of fanfic readers already
/// understand (LOOM_FANFIC.md §3.1).
public struct FanficMetadata: Codable, Equatable {
    public var fandoms: [Fandom]
    public var attg: ATTG
    public var rating: AO3Rating
    public var warnings: [AO3Warning]
    public var category: AO3Category
    public var ships: [Ship]
    public var primaryCharacters: [UUID]
    public var tropes: [Trope]
    public var aus: [AU]

    public init(
        fandoms: [Fandom] = [],
        attg: ATTG = ATTG(),
        rating: AO3Rating = .general,
        warnings: [AO3Warning] = [.noArchiveWarningsApply],
        category: AO3Category = .gen,
        ships: [Ship] = [],
        primaryCharacters: [UUID] = [],
        tropes: [Trope] = [],
        aus: [AU] = []
    ) {
        self.fandoms = fandoms
        self.attg = attg
        self.rating = rating
        self.warnings = warnings
        self.category = category
        self.ships = ships
        self.primaryCharacters = primaryCharacters
        self.tropes = tropes
        self.aus = aus
    }
}

/// AO3 Rating tag. The four canonical AO3 ratings; UI for picking
/// these lands Phase 5.c.
public enum AO3Rating: String, Codable, Equatable, CaseIterable {
    case general    // General Audiences
    case teen       // Teen And Up Audiences
    case mature
    case explicit
}

/// AO3 Archive Warning tags. Multi-select on a fanfic project.
public enum AO3Warning: String, Codable, Equatable, CaseIterable {
    case noArchiveWarningsApply
    case graphicDepictionsOfViolence
    case majorCharacterDeath
    case rapeNonCon
    case underage
    case chooseNotToWarn
}

/// AO3 Category — relationship-shape tag for the project.
public enum AO3Category: String, Codable, Equatable, CaseIterable {
    case gen        // no central relationship
    case ff         // F/F
    case fm         // F/M
    case mm         // M/M
    case multi
    case other
}

/// A fandom the project draws from. Multi-fandom (crossover) projects
/// carry multiple entries; LOOM_FANFIC.md §11.
public struct Fandom: Codable, Equatable {
    public let id: UUID
    public var name: String
    public var canonicalName: String
    public var aliases: [String]
    public var fandomWikiURL: URL?
    public var canonReferences: [UUID]

    public init(
        id: UUID = UUID(),
        name: String,
        canonicalName: String,
        aliases: [String] = [],
        fandomWikiURL: URL? = nil,
        canonReferences: [UUID] = []
    ) {
        self.id = id
        self.name = name
        self.canonicalName = canonicalName
        self.aliases = aliases
        self.fandomWikiURL = fandomWikiURL
        self.canonReferences = canonReferences
    }
}

/// NovelAI Erato Author/Title/Tags/Genre header. Injected above the
/// cache boundary at the top of the prompt per LOOM_FANFIC.md §3.3.
/// Stays cache-stable across generations.
public struct ATTG: Codable, Equatable {
    public var author: String
    public var title: String
    public var fandom: String
    public var tags: [String]
    public var rating: String
    public var genre: String
    public var category: String
    public var relationship: String
    /// Erato "story stage" 2–4; defaults to 3 for established
    /// projects and 2 for opening scenes (LOOM_FANFIC.md §3.3).
    public var storyStage: Int

    public init(
        author: String = "",
        title: String = "",
        fandom: String = "",
        tags: [String] = [],
        rating: String = "",
        genre: String = "",
        category: String = "",
        relationship: String = "",
        storyStage: Int = 3
    ) {
        self.author = author
        self.title = title
        self.fandom = fandom
        self.tags = tags
        self.rating = rating
        self.genre = genre
        self.category = category
        self.relationship = relationship
        self.storyStage = storyStage
    }
}

/// Relationship pairing (or group) — first-class because fanfic
/// conventions structure prose around the Ship.
public struct Ship: Codable, Equatable {
    public let id: UUID
    public var characters: [UUID]
    public var kind: ShipKind
    public var canonicalForm: String
    public var dynamic: ShipDynamic
    public var notes: String

    public init(
        id: UUID = UUID(),
        characters: [UUID] = [],
        kind: ShipKind = .romantic,
        canonicalForm: String = "",
        dynamic: ShipDynamic = .established,
        notes: String = ""
    ) {
        self.id = id
        self.characters = characters
        self.kind = kind
        self.canonicalForm = canonicalForm
        self.dynamic = dynamic
        self.notes = notes
    }
}

public enum ShipKind: String, Codable, Equatable, CaseIterable {
    case romantic, sexual, platonic, familial, antagonistic, friendship
}

public enum ShipDynamic: String, Codable, Equatable, CaseIterable {
    case established
    case slowBurn
    case mutualPining
    case enemiesToLovers
    case friendsToLovers
    case fakeMarriage
    case soulmates
    case otherWorks
}

/// Named pattern of fictional convention — fanfic communities share
/// hundreds (LOOM_FANFIC.md §5.1).
public struct Trope: Codable, Equatable {
    public let id: UUID
    public var name: String
    public var aliases: [String]
    public var category: TropeCategory
    public var description: String
    public var typicalLength: TropeLength?
    public var generationHints: TropeHints

    public init(
        id: UUID = UUID(),
        name: String,
        aliases: [String] = [],
        category: TropeCategory = .structural,
        description: String = "",
        typicalLength: TropeLength? = nil,
        generationHints: TropeHints = TropeHints()
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.category = category
        self.description = description
        self.typicalLength = typicalLength
        self.generationHints = generationHints
    }
}

public enum TropeCategory: String, Codable, Equatable, CaseIterable {
    case pacing, relationship, setup, resolution, kink, structural, au, character
}

public struct TropeLength: Codable, Equatable {
    public var minChapters: Int
    public var maxChapters: Int
    public var minWords: Int
    public var maxWords: Int

    public init(minChapters: Int, maxChapters: Int, minWords: Int, maxWords: Int) {
        self.minChapters = minChapters
        self.maxChapters = maxChapters
        self.minWords = minWords
        self.maxWords = maxWords
    }
}

public struct TropeHints: Codable, Equatable {
    public var pacingNote: String
    public var avoidances: [String]
    public var beatPatterns: [String]

    public init(pacingNote: String = "", avoidances: [String] = [], beatPatterns: [String] = []) {
        self.pacingNote = pacingNote
        self.avoidances = avoidances
        self.beatPatterns = beatPatterns
    }
}

/// Alternate Universe shift (LOOM_FANFIC.md §5.4). The retained /
/// changed / added split drives system-prompt-level AU compliance.
public struct AU: Codable, Equatable {
    public let id: UUID
    public var name: String
    public var description: String
    public var setting: String
    public var canonRetained: [String]
    public var canonChanged: [String]
    public var addedElements: [String]

    public init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        setting: String = "",
        canonRetained: [String] = [],
        canonChanged: [String] = [],
        addedElements: [String] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.setting = setting
        self.canonRetained = canonRetained
        self.canonChanged = canonChanged
        self.addedElements = addedElements
    }
}

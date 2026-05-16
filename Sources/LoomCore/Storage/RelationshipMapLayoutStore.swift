import Foundation

/// On-disk sidecar for the relationship-map view layout — the x/y
/// position the user dragged each character node to. This is view
/// state, not bible data, so it lives in its own sidecar rather than
/// on `Character`. Load is tolerant of missing/malformed JSON.
///
/// File layout: `<project>/relationship-map/layout.json`.

public struct RelationshipMapPosition: Codable, Equatable {
    public var characterId: UUID
    public var x: Double
    public var y: Double

    public init(characterId: UUID, x: Double, y: Double) {
        self.characterId = characterId
        self.x = x
        self.y = y
    }
}

public struct RelationshipMapLayoutPayload: Codable, Equatable {
    public var positions: [RelationshipMapPosition]
    public var updatedAt: Date

    public init(positions: [RelationshipMapPosition], updatedAt: Date) {
        self.positions = positions
        self.updatedAt = updatedAt
    }
}

public enum RelationshipMapLayoutStore {
    public static let directoryName = "relationship-map"
    public static let fileName = "layout.json"

    public static func directoryURL(in projectURL: URL) -> URL {
        projectURL.appendingPathComponent(directoryName, isDirectory: true)
    }

    public static func fileURL(in projectURL: URL) -> URL {
        directoryURL(in: projectURL).appendingPathComponent(fileName)
    }

    /// Returns nil on missing-file or malformed-JSON — the caller
    /// falls back to an auto-layout and the next save rewrites cleanly.
    public static func load(in projectURL: URL) -> RelationshipMapLayoutPayload? {
        guard let data = try? Data(contentsOf: fileURL(in: projectURL)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(RelationshipMapLayoutPayload.self, from: data)
    }

    public static func save(_ payload: RelationshipMapLayoutPayload, in projectURL: URL) throws {
        let dir = directoryURL(in: projectURL)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(payload).write(to: fileURL(in: projectURL))
    }

    /// Upsert one node's position — replaces the prior entry for that
    /// character, leaves every other position untouched.
    public static func setPosition(
        characterId: UUID,
        x: Double,
        y: Double,
        in projectURL: URL
    ) throws {
        let existing = load(in: projectURL)
            ?? RelationshipMapLayoutPayload(positions: [], updatedAt: Date())
        var positions = existing.positions.filter { $0.characterId != characterId }
        positions.append(RelationshipMapPosition(characterId: characterId, x: x, y: y))
        try save(
            RelationshipMapLayoutPayload(positions: positions, updatedAt: Date()),
            in: projectURL
        )
    }
}

import Foundation

// Phase 8.b.x — per-template persistence of the Write-Scene-From-
// Template menu's fields. Stored as a JSON sidecar at
// `<project>/template-gen-state/<templateId>.json`. The menu loads
// when the user picks a template + writes on Generate.
//
// Design rationale (per smoke feedback 2026-05-15): users iterate on
// templated generation by tweaking the cast/hint/toggle and re-
// running. Re-typing 200+ chars of cast description every time was
// the friction surface. Per-template (not global) so a project with
// multiple templates remembers each independently.

public struct TemplateGenState: Codable, Equatable {
    public var castMapping: String
    public var extraInstruction: String
    public var imitateContent: Bool
    public var savedAt: Date

    public init(
        castMapping: String,
        extraInstruction: String,
        imitateContent: Bool,
        savedAt: Date
    ) {
        self.castMapping = castMapping
        self.extraInstruction = extraInstruction
        self.imitateContent = imitateContent
        self.savedAt = savedAt
    }
}

public enum TemplateGenStateStore {
    /// Directory name under the project URL where per-template state
    /// lives. Mirrors the `templates/` + `references/` storage layout.
    public static let directoryName = "template-gen-state"

    public static func directoryURL(in projectURL: URL) -> URL {
        return projectURL.appendingPathComponent(directoryName, isDirectory: true)
    }

    public static func fileURL(templateId: UUID, in projectURL: URL) -> URL {
        return directoryURL(in: projectURL)
            .appendingPathComponent("\(templateId.uuidString).json")
    }

    /// Returns nil when the sidecar is absent OR malformed. Malformed
    /// cases shouldn't be a hard error — the menu falls back to empty
    /// fields and the next Save overwrites the bad file cleanly.
    public static func load(templateId: UUID, in projectURL: URL) -> TemplateGenState? {
        let url = fileURL(templateId: templateId, in: projectURL)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(TemplateGenState.self, from: data)
    }

    public static func save(_ state: TemplateGenState, templateId: UUID, in projectURL: URL) throws {
        let dir = directoryURL(in: projectURL)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: fileURL(templateId: templateId, in: projectURL))
    }

    /// Restore-with-fallback. Tries the sidecar first; when absent,
    /// scans the project's `generation-log/` for the most recent
    /// entry whose `templateGenerationInfo.templateId` matches and
    /// synthesizes a `TemplateGenState` from its captured
    /// castMapping (+ the two newer fields if they're present on
    /// the entry; legacy entries default both to safe values).
    ///
    /// Motivated by the 2026-05-15 smoke: the sidecar mechanism
    /// landed AFTER several gens had already run, so users opening
    /// the menu after the rebuild saw empty fields despite having
    /// generated previously. The gen-log already carries the cast
    /// mapping — recover from it.
    public static func loadOrBackfill(templateId: UUID, in projectURL: URL) -> TemplateGenState? {
        if let state = load(templateId: templateId, in: projectURL) {
            return state
        }
        let log = GenerationLogStore()
        let entries = log.list(in: projectURL)
        let matches = entries.compactMap { entry -> (Date, TemplateGenerationInfo)? in
            guard let info = entry.templateGenerationInfo, info.templateId == templateId else {
                return nil
            }
            return (entry.timestamp, info)
        }
        guard let (timestamp, info) = matches.max(by: { $0.0 < $1.0 }) else { return nil }
        return TemplateGenState(
            castMapping: info.castMapping,
            extraInstruction: info.extraInstruction ?? "",
            imitateContent: info.imitateContent ?? false,
            savedAt: timestamp
        )
    }
}

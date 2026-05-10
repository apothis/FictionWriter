import Foundation

/// Global app-level settings. Persisted at
/// `~/Library/Application Support/Loom/settings.json`. Phase 1 ships
/// only server profiles + default; Phase 2+ adds cross-project
/// preferences (theme, font scale, default sampler tweaks). Per-project
/// settings live on `Project.settings` and are scoped to that project's
/// `.loom` bundle.
public struct AppSettings: Codable, Equatable {
    public var schemaVersion: Int
    public var servers: [ServerProfile]
    public var defaultServerId: UUID?

    public init(
        schemaVersion: Int = 1,
        servers: [ServerProfile] = [],
        defaultServerId: UUID? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.servers = servers
        self.defaultServerId = defaultServerId
    }

    public static let defaults = AppSettings()

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.servers = try c.decodeIfPresent([ServerProfile].self, forKey: .servers) ?? []
        self.defaultServerId = try c.decodeIfPresent(UUID.self, forKey: .defaultServerId)
    }
}

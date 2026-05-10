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
    /// Recently-opened project bundle URLs, newest first, capped at 5.
    /// Surfaced in `File → Open Recent` (1.m). Persists across launches
    /// via the same settings.json round-trip.
    public var recentProjectURLs: [URL]

    public static let recentProjectsCap = 5

    public init(
        schemaVersion: Int = 1,
        servers: [ServerProfile] = [],
        defaultServerId: UUID? = nil,
        recentProjectURLs: [URL] = []
    ) {
        self.schemaVersion = schemaVersion
        self.servers = servers
        self.defaultServerId = defaultServerId
        self.recentProjectURLs = recentProjectURLs
    }

    public static let defaults = AppSettings()

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.servers = try c.decodeIfPresent([ServerProfile].self, forKey: .servers) ?? []
        self.defaultServerId = try c.decodeIfPresent(UUID.self, forKey: .defaultServerId)
        self.recentProjectURLs = try c.decodeIfPresent([URL].self, forKey: .recentProjectURLs) ?? []
    }

    /// Push a URL to the front of the recents list. Removes any
    /// existing duplicate (by path equality) so the URL surfaces once
    /// at top; trims to `recentProjectsCap`.
    public mutating func pushRecentProject(_ url: URL) {
        recentProjectURLs.removeAll { $0.path == url.path }
        recentProjectURLs.insert(url, at: 0)
        if recentProjectURLs.count > Self.recentProjectsCap {
            recentProjectURLs = Array(recentProjectURLs.prefix(Self.recentProjectsCap))
        }
    }
}

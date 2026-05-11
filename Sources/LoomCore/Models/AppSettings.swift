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
    /// Phase 4 #7 — id of the role-routed extractor profile (typically
    /// an Ollama-kind entry running gemma4_2b for the knowledge-ledger
    /// pipeline). Nil when the user hasn't designated an extractor;
    /// the ledger side-call is then disabled. Independent of
    /// `defaultServerId`, which always names the writer.
    public var extractorServerId: UUID?
    /// Recently-opened project bundle URLs, newest first, capped at 5.
    /// Surfaced in `File → Open Recent` (1.m). Persists across launches
    /// via the same settings.json round-trip.
    public var recentProjectURLs: [URL]

    public static let recentProjectsCap = 5

    public init(
        schemaVersion: Int = 1,
        servers: [ServerProfile] = [],
        defaultServerId: UUID? = nil,
        extractorServerId: UUID? = nil,
        recentProjectURLs: [URL] = []
    ) {
        self.schemaVersion = schemaVersion
        self.servers = servers
        self.defaultServerId = defaultServerId
        self.extractorServerId = extractorServerId
        self.recentProjectURLs = recentProjectURLs
    }

    public static let defaults = AppSettings()

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.servers = try c.decodeIfPresent([ServerProfile].self, forKey: .servers) ?? []
        self.defaultServerId = try c.decodeIfPresent(UUID.self, forKey: .defaultServerId)
        self.extractorServerId = try c.decodeIfPresent(UUID.self, forKey: .extractorServerId)
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

    // MARK: - Server mutations (Phase 2 Settings UI)

    /// Append a server profile. If this is the first profile in the
    /// list, it's auto-promoted to default so the user doesn't have
    /// to explicitly mark it. Caller is responsible for uniqueness
    /// of `profile.id` (always satisfied when constructed via the
    /// default `ServerProfile.init(id: UUID(), ...)`).
    public mutating func addServer(_ profile: ServerProfile) {
        servers.append(profile)
        if defaultServerId == nil {
            defaultServerId = profile.id
        }
    }

    /// Remove a server profile by id. If the removed profile WAS the
    /// default, the default falls to the first remaining server
    /// (or nil when the list empties). If it was the extractor, the
    /// extractor role unsets entirely (no implicit fallback — a
    /// missing extractor is a valid state). Unknown ids are a no-op.
    public mutating func removeServer(id: UUID) {
        guard let idx = servers.firstIndex(where: { $0.id == id }) else { return }
        servers.remove(at: idx)
        if defaultServerId == id {
            defaultServerId = servers.first?.id
        }
        if extractorServerId == id {
            extractorServerId = nil
        }
    }

    /// Set the default-server id. Returns true if the id matches an
    /// existing server; false (with no state change) otherwise — the
    /// UI shouldn't be able to point default at a server that was
    /// deleted in another window, etc.
    @discardableResult
    public mutating func setDefault(id: UUID) -> Bool {
        guard servers.contains(where: { $0.id == id }) else { return false }
        defaultServerId = id
        return true
    }

    /// Replace an existing server profile (matched by id) with new
    /// field values. Returns true if the profile was found, false
    /// otherwise. The id is preserved across the edit.
    @discardableResult
    public mutating func updateServer(_ profile: ServerProfile) -> Bool {
        guard let idx = servers.firstIndex(where: { $0.id == profile.id }) else { return false }
        servers[idx] = profile
        return true
    }

    // MARK: - Role resolution (Phase 4 #7)

    /// The server profile that should handle writer-role generation
    /// (Continue / Expand / Rewrite). Returns nil when no default is
    /// set or the default points at a stale id.
    public func writerServer() -> ServerProfile? {
        guard let id = defaultServerId else { return nil }
        return servers.first { $0.id == id }
    }

    /// The server profile that should handle extractor-role side-calls
    /// (Phase 4 #7 knowledge-ledger extraction). Returns nil when no
    /// extractor is designated. Callers check nil and skip the side-
    /// call rather than falling back to the writer — running an
    /// extraction prompt against the heavy creative-writing model is
    /// the failure mode the LOOM_LEDGER_SPIKE.md §9.4 model-swap was
    /// specifically built to avoid.
    public func extractorServer() -> ServerProfile? {
        guard let id = extractorServerId else { return nil }
        return servers.first { $0.id == id }
    }

    /// Designate (or clear, with `nil`) the extractor profile.
    /// Returns true when the operation was valid. Setting nil always
    /// succeeds; setting a non-nil id requires that id to be in the
    /// servers list (defensive against stale UI bindings).
    @discardableResult
    public mutating func setExtractor(id: UUID?) -> Bool {
        guard let id = id else {
            extractorServerId = nil
            return true
        }
        guard servers.contains(where: { $0.id == id }) else { return false }
        extractorServerId = id
        return true
    }
}

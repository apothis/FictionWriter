import Foundation

/// Owns one `KoboldClient` per `ServerProfile`, keyed by profile id.
///
/// Phase 1 has no role routing — RPClient's general / summarizer /
/// extractor / embeddings split is irrelevant here, since Loom Phase 1
/// only fires Continue/Expand from a single endpoint. The registry
/// exists so the per-profile URLSession state and any future per-client
/// caches survive lookups (we'd otherwise mint a new KoboldClient per
/// generation request).
///
/// Thread model: settings updates and lookups happen on the main thread.
/// If that ever changes, add a lock around `cache`/`profiles`.
public final class KoboldClientRegistry {
    private var profiles: [ServerProfile]
    private var defaultId: UUID?
    private var cache: [UUID: KoboldClient] = [:]
    private let fallbackURL = URL(string: "http://localhost:5001")!
    private static let fallbackKey = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))

    public init(profiles: [ServerProfile] = [], defaultServerId: UUID? = nil) {
        self.profiles = profiles
        self.defaultId = defaultServerId
    }

    /// Replace the registry's view of the world with a fresh AppSettings.
    /// Cached clients for now-removed profiles are evicted; cached
    /// clients whose profile still exists keep their identity (and have
    /// their `baseURL` updated in place if it changed).
    public func updateProfiles(_ profiles: [ServerProfile], defaultServerId: UUID?) {
        self.profiles = profiles
        self.defaultId = defaultServerId
        let liveIds = Set(profiles.map(\.id))
        for id in cache.keys where id != Self.fallbackKey && !liveIds.contains(id) {
            cache.removeValue(forKey: id)
        }
        for profile in profiles {
            if let existing = cache[profile.id], existing.baseURL != profile.baseURL {
                existing.setBaseURL(profile.baseURL)
            }
        }
    }

    /// Look up the client for a specific profile. Falls back to the
    /// localhost sentinel when the profile id doesn't match any live
    /// profile (e.g. a project carrying a stale serverProfileId).
    public func client(forProfileId id: UUID?) -> KoboldClient {
        if let id = id, let profile = profiles.first(where: { $0.id == id }) {
            return cachedClient(for: profile)
        }
        return cachedFallback()
    }

    /// Convenience: client for the AppSettings.defaultServerId, or the
    /// localhost fallback.
    public func clientForDefault() -> KoboldClient {
        client(forProfileId: defaultId)
    }

    /// Test hook — total cached clients including the fallback. (The
    /// fallback occupies one slot once it's lazily created.)
    public var cachedCount: Int {
        cache.filter { $0.key != Self.fallbackKey }.count
    }

    // MARK: - Internals

    private func cachedClient(for profile: ServerProfile) -> KoboldClient {
        if let existing = cache[profile.id] {
            if existing.baseURL != profile.baseURL { existing.setBaseURL(profile.baseURL) }
            return existing
        }
        let c = KoboldClient(baseURL: profile.baseURL)
        cache[profile.id] = c
        return c
    }

    /// Sentinel client used when there's no live default. Stored under
    /// a stable nil-UUID key so repeated calls return the same instance
    /// rather than minting a new client per lookup.
    private func cachedFallback() -> KoboldClient {
        if let existing = cache[Self.fallbackKey] { return existing }
        let c = KoboldClient(baseURL: fallbackURL)
        cache[Self.fallbackKey] = c
        return c
    }
}

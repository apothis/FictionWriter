import Foundation
@testable import LoomCore

/// Sub-step 1.c — registry caches one KoboldClient per ServerProfile, the
/// same client identity survives URL changes (so connection-state caches
/// don't churn), and removed profiles get evicted from the cache.
///
/// Phase 1 has no role routing — the registry is just `id → client`.
/// `clientForDefault()` returns the live `defaultServerId` profile's
/// client, falling back to a hard-coded localhost when the settings are
/// empty or corrupt.
func phase1KoboldClientRegistryTests() -> TestSuite {
    let s = TestSuite("Phase1KoboldClientRegistry")

    s.test("client(forProfileId:) returns the same instance on repeat lookup") {
        let p = ServerProfile(name: "Local", baseURL: URL(string: "http://localhost:5001")!)
        let registry = KoboldClientRegistry(profiles: [p], defaultServerId: p.id)
        let a = registry.client(forProfileId: p.id)
        let b = registry.client(forProfileId: p.id)
        try expectTrue(a === b, "same profile id should return the same client instance")
    }

    s.test("baseURL change preserves client identity but updates URL") {
        let id = UUID()
        let pA = ServerProfile(id: id, name: "Local", baseURL: URL(string: "http://localhost:5001")!)
        let pB = ServerProfile(id: id, name: "Local", baseURL: URL(string: "http://localhost:5002")!)
        let registry = KoboldClientRegistry(profiles: [pA], defaultServerId: id)
        let before = registry.client(forProfileId: id)
        registry.updateProfiles([pB], defaultServerId: id)
        let after = registry.client(forProfileId: id)
        try expectTrue(before === after, "client instance should be reused")
        try expectEqual(after.baseURL, pB.baseURL)
    }

    s.test("removed profile is evicted from cache on update") {
        let p = ServerProfile(name: "Local", baseURL: URL(string: "http://localhost:5001")!)
        let registry = KoboldClientRegistry(profiles: [p], defaultServerId: p.id)
        _ = registry.client(forProfileId: p.id)   // populate cache
        try expectEqual(registry.cachedCount, 1)
        registry.updateProfiles([], defaultServerId: nil)
        try expectEqual(registry.cachedCount, 0)
    }

    s.test("clientForDefault falls back to localhost when no live default") {
        let registry = KoboldClientRegistry(profiles: [], defaultServerId: nil)
        let fallback = registry.clientForDefault()
        try expectEqual(fallback.baseURL.host, "localhost")
        // Repeat lookup yields the same cached fallback (so URLSession state
        // and any token-count cache survive between calls).
        let again = registry.clientForDefault()
        try expectTrue(fallback === again)
    }

    return s
}

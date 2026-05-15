import Foundation
@testable import LoomCore

// Phase 8.c — compiled-mlpackage cache. Apple's
// `MLModel.compileModel(at:)` drops a fresh `.mlmodelc` into a
// system-chosen temp dir on every call and never cleans up; with
// ~237 MB per compile and a test suite that loads the embedder on
// every run, the TMPDIR balloons to multi-GB. `CoreMLCompileCache`
// gives us a stable cache location keyed by the source `.mlpackage`
// fingerprint so a) the compile only happens when the source
// changes and b) stale siblings get reclaimed.
//
// These tests exercise just the file-management logic. The
// integration test in Phase8cCoreMLEmbeddingClientTests covers
// the end-to-end MLModel path against the real bundle.

func phase8cCoreMLCompileCacheTests() -> TestSuite {
    let s = TestSuite("Phase8cCoreMLCompileCache")

    s.test("fingerprint is stable across calls with unchanged contents") {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let pkg = tmp.appendingPathComponent("Style.mlpackage")
        try createFakeMLPackage(at: pkg, manifest: "v1", payloadSize: 100)
        let fp1 = try CoreMLCompileCache.fingerprint(pkgURL: pkg)
        let fp2 = try CoreMLCompileCache.fingerprint(pkgURL: pkg)
        try expectEqual(fp1, fp2)
        try expectTrue(!fp1.isEmpty, "fingerprint empty")
    }

    s.test("fingerprint differs when payload changes") {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let pkg = tmp.appendingPathComponent("Style.mlpackage")
        try createFakeMLPackage(at: pkg, manifest: "v1", payloadSize: 100)
        let fpA = try CoreMLCompileCache.fingerprint(pkgURL: pkg)
        // Overwrite with bigger payload.
        try FileManager.default.removeItem(at: pkg)
        try createFakeMLPackage(at: pkg, manifest: "v1", payloadSize: 250)
        let fpB = try CoreMLCompileCache.fingerprint(pkgURL: pkg)
        try expectTrue(fpA != fpB, "fingerprint did not change: \(fpA) vs \(fpB)")
    }

    s.test("reserveCachedURL returns needsCompile when cache is empty") {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let pkg = tmp.appendingPathComponent("Style.mlpackage")
        try createFakeMLPackage(at: pkg, manifest: "v1", payloadSize: 100)
        let cache = tmp.appendingPathComponent("cache")
        let outcome = try CoreMLCompileCache.reserveCachedURL(pkgURL: pkg, cacheDir: cache)
        switch outcome {
        case .cached:
            throw TestFailure(message: "expected .needsCompile, got .cached", file: #file, line: #line)
        case .needsCompile(let target):
            try expectEqual(target.pathExtension, "mlmodelc")
            try expectEqual(target.deletingLastPathComponent().path, cache.path)
            try expectFalse(FileManager.default.fileExists(atPath: target.path),
                            "target should not exist yet")
            // Cache dir must exist (caller will move compiled output into target).
            try expectTrue(FileManager.default.fileExists(atPath: cache.path),
                           "cache dir should be created")
        }
    }

    s.test("reserveCachedURL returns cached when target exists") {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let pkg = tmp.appendingPathComponent("Style.mlpackage")
        try createFakeMLPackage(at: pkg, manifest: "v1", payloadSize: 100)
        let cache = tmp.appendingPathComponent("cache")

        guard case .needsCompile(let target) = try CoreMLCompileCache.reserveCachedURL(pkgURL: pkg, cacheDir: cache) else {
            throw TestFailure(message: "first call should be .needsCompile", file: #file, line: #line)
        }
        // Simulate a successful compile.
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        let outcome2 = try CoreMLCompileCache.reserveCachedURL(pkgURL: pkg, cacheDir: cache)
        switch outcome2 {
        case .cached(let url):
            try expectEqual(url.path, target.path)
        case .needsCompile:
            throw TestFailure(message: "second call should be .cached", file: #file, line: #line)
        }
    }

    s.test("reserveCachedURL removes stale sibling .mlmodelc dirs") {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let pkg = tmp.appendingPathComponent("Style.mlpackage")
        try createFakeMLPackage(at: pkg, manifest: "v1", payloadSize: 100)
        let cache = tmp.appendingPathComponent("cache")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)

        let stale = cache.appendingPathComponent("OldFingerprint.mlmodelc")
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)

        guard case .needsCompile(let target) = try CoreMLCompileCache.reserveCachedURL(pkgURL: pkg, cacheDir: cache) else {
            throw TestFailure(message: "expected .needsCompile", file: #file, line: #line)
        }
        try expectFalse(FileManager.default.fileExists(atPath: stale.path),
                        "stale sibling should have been removed")
        try expectTrue(target.path != stale.path,
                       "new target must differ from stale")
    }

    s.test("reserveCachedURL preserves matching cached dir when a stale sibling is also present") {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let pkg = tmp.appendingPathComponent("Style.mlpackage")
        try createFakeMLPackage(at: pkg, manifest: "v1", payloadSize: 100)
        let cache = tmp.appendingPathComponent("cache")

        // Prime the cache with a real "compile".
        guard case .needsCompile(let target) = try CoreMLCompileCache.reserveCachedURL(pkgURL: pkg, cacheDir: cache) else {
            throw TestFailure(message: "first call should be .needsCompile", file: #file, line: #line)
        }
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        // Drop a stale sibling alongside.
        let stale = cache.appendingPathComponent("OldFingerprint.mlmodelc")
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)

        // Second call must keep the matching target and remove the stale one.
        let outcome = try CoreMLCompileCache.reserveCachedURL(pkgURL: pkg, cacheDir: cache)
        guard case .cached(let url) = outcome else {
            throw TestFailure(message: "expected .cached", file: #file, line: #line)
        }
        try expectEqual(url.path, target.path)
        try expectTrue(FileManager.default.fileExists(atPath: target.path),
                       "matching cache dir was wrongly removed")
        try expectFalse(FileManager.default.fileExists(atPath: stale.path),
                        "stale sibling should have been removed")
    }

    return s
}

private func makeTempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("LoomCompileCacheTest-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Builds a minimal `.mlpackage`-shaped directory. We don't need a
/// valid CoreML payload — `CoreMLCompileCache` only walks files for
/// the fingerprint, and the tests never call `MLModel.compileModel`.
private func createFakeMLPackage(at url: URL, manifest: String, payloadSize: Int) throws {
    let fm = FileManager.default
    try fm.createDirectory(at: url, withIntermediateDirectories: true)
    try Data(manifest.utf8).write(to: url.appendingPathComponent("Manifest.json"))
    let dataDir = url.appendingPathComponent("Data/com.apple.CoreML", isDirectory: true)
    try fm.createDirectory(at: dataDir, withIntermediateDirectories: true)
    let payload = Data(repeating: 0x42, count: payloadSize)
    try payload.write(to: dataDir.appendingPathComponent("model.mlmodel"))
}

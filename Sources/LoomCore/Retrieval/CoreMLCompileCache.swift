import Foundation
import CryptoKit

/// Phase 8.c — stable on-disk cache for `MLModel.compileModel(at:)`
/// output.
///
/// Apple's `MLModel.compileModel(at:)` writes a fresh `.mlmodelc`
/// into a system-chosen temp directory on every call and never
/// cleans up. With a ~237 MB Wegmann bundle and the embedder being
/// re-instantiated on every app launch / test run, the TMPDIR grows
/// without bound (a single dev machine accumulated 30 leaked copies
/// = 6.9 GB before this was caught).
///
/// The cache keys the compiled output by a content fingerprint of
/// the source `.mlpackage`, so re-runs reuse the prior compile and
/// stale siblings (older fingerprints) get reclaimed on the next
/// reserve call.
///
/// The cache only manages file paths; the caller still owns the
/// `MLModel.compileModel(at:)` invocation and the move into place.
/// This keeps the type free of `CoreML` dependencies and unit-
/// testable without invoking the actual compiler.
public enum CoreMLCompileCache {
    public enum CompileOutcome {
        /// `.mlmodelc` already exists at `url`; caller can load it directly.
        case cached(URL)
        /// Caller must `MLModel.compileModel(at:)` then move the result to `target`.
        case needsCompile(target: URL)
    }

    /// Default cache root: `~/Library/Caches/com.loom.fictionwriter/CompiledModels/`.
    public static func defaultCacheDir() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("com.loom.fictionwriter", isDirectory: true)
            .appendingPathComponent("CompiledModels", isDirectory: true)
    }

    /// Content fingerprint of a `.mlpackage` directory. Stable across
    /// machines (depends only on relative file paths + sizes), so the
    /// cache survives clean rebuilds where mtimes shift.
    public static func fingerprint(pkgURL: URL) throws -> String {
        let entries = try walk(pkgURL: pkgURL)
        var hasher = SHA256()
        for (rel, size) in entries {
            hasher.update(data: Data(rel.utf8))
            hasher.update(data: Data([0]))
            var s = UInt64(size).littleEndian
            withUnsafeBytes(of: &s) { hasher.update(data: Data($0)) }
        }
        let digest = hasher.finalize()
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    public static func reserveCachedURL(pkgURL: URL, cacheDir: URL) throws -> CompileOutcome {
        let fm = FileManager.default
        try fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let fp = try fingerprint(pkgURL: pkgURL)
        let target = cacheDir.appendingPathComponent("\(fp).mlmodelc", isDirectory: true)
        let targetExists = fm.fileExists(atPath: target.path)

        // Reclaim stale siblings — any other `.mlmodelc` under cacheDir
        // is from a previous fingerprint and won't be touched again.
        if let children = try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil) {
            for child in children where child.pathExtension == "mlmodelc" && child.lastPathComponent != target.lastPathComponent {
                try? fm.removeItem(at: child)
            }
        }

        if targetExists {
            return .cached(target)
        }
        return .needsCompile(target: target)
    }

    /// Walk the package directory and return `(relativePath, size)`
    /// tuples, sorted by path for deterministic ordering.
    private static func walk(pkgURL: URL) throws -> [(String, Int)] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: pkgURL, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else {
            return []
        }
        var results: [(String, Int)] = []
        let base = pkgURL.path
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { continue }
            let rel = String(url.path.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            results.append((rel, values.fileSize ?? 0))
        }
        results.sort { $0.0 < $1.0 }
        return results
    }
}

// swift-tools-version:5.9
import PackageDescription

// Loom — local-LLM-powered fiction writing app for macOS.
// Phase 1 ships a minimal Swift Package: LoomCore (library), Loom (app),
// LoomCoreTests (TestKit harness). Future phases may add smoke runners
// matching RPClient's per-surface harness pattern.
//
// macOS 14 minimum matches RPClient. The user's reference platform is
// macOS 26 Tahoe / Liquid Glass; the floor is set by the Swift toolchain
// available on the user's CLT install, not by AppKit features used.
let package = Package(
    name: "Loom",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Loom",
            dependencies: ["LoomCore"],
            path: "Sources/Loom"
        ),
        .target(
            name: "LoomCore",
            path: "Sources/LoomCore",
            // Phase 4.5 — bundle the Bible Workspace WKWebView assets
            // (Vite/React build output). `scripts/build-bible-workspace.sh`
            // syncs `web/bible-workspace/dist/` into this directory
            // before `swift build`; the dist content is gitignored.
            // See LOOM_BIBLE_WORKSPACE.md §5.5.
            resources: [
                .copy("Resources/BibleWorkspace"),
            ],
            swiftSettings: [
                // Enables `@testable import LoomCore` from the test runner
                // in debug builds. Scoped to debug so release (.app) is
                // unaffected.
                .unsafeFlags(["-enable-testing"], .when(configuration: .debug)),
            ]
        ),
        .executableTarget(
            name: "LoomCoreTests",
            dependencies: ["LoomCore"],
            path: "Tests/LoomCoreTests",
            // Bundle the fixture JSON so the eval runner (LedgerSpike,
            // declared below) can resolve `Bundle.module` to read it.
            // The LedgerSpike target imports LoomCore for the
            // extraction module and re-reads the fixture from disk.
            exclude: ["Fixtures"]
        ),
        // One-off network-y eval runners ("spike" targets). These hit
        // a live local-LLM server and emit a markdown report; they're
        // not part of the standard test suite. Run on demand:
        //   `swift run LedgerSpike` (requires the Qwen3.6-27B
        //   summariser-role server reachable at the configured URL).
        .executableTarget(
            name: "LedgerSpike",
            dependencies: ["LoomCore"],
            path: "Tools/LedgerSpike"
        ),
        // Phase 5 RAG-for-style spike runner (LOOM_RAG_SPIKE.md §6).
        // Reads the fixture, hits Kobold + Ollama for Paths A/B/C,
        // and consumes the Python sidecar's vectors.json for Paths
        // D + E. Run with `swift run RagSpike --smoke`.
        .executableTarget(
            name: "RagSpike",
            dependencies: ["LoomCore"],
            path: "Tools/RagSpike",
            exclude: ["Python"]
        ),
    ]
)

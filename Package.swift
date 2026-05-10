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
            path: "Tests/LoomCoreTests"
        ),
    ]
)

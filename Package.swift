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
    // huggingface/swift-transformers 1.0 (2025-09-26) gives us the
    // RoBERTa BPE tokenizer in pure Swift so the Wegmann CoreML
    // bundle can be driven without a Python subprocess. macOS 13+;
    // we're on 14. Tokenizers product only — skips the Generation /
    // Models products that would drag CoreML build steps in.
    dependencies: [
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "Loom",
            dependencies: ["LoomCore"],
            path: "Sources/Loom"
        ),
        .target(
            name: "LoomCore",
            dependencies: [
                .product(name: "Tokenizers", package: "swift-transformers"),
            ],
            path: "Sources/LoomCore",
            // Bundle the Bible Workspace WKWebView assets (Vite/React
            // build output) and the Wegmann CoreML inference bundle.
            // Both directories are gitignored — regenerated locally
            // before `swift build` by:
            //   scripts/build-bible-workspace.sh
            //   Tools/CoreMLProbe/build_mlpackage.py
            // See LOOM_BIBLE_WORKSPACE.md §5.5 +
            // Tools/CoreMLProbe/build_mlpackage.py.
            resources: [
                .copy("Resources/BibleWorkspace"),
                .copy("Resources/StyleEmbedding"),
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
        // Phase 7.a Scene-Template Generation spike runner
        // (LOOM_SCENE_TEMPLATE.md §9). Reads fixtures, hits the Ollama
        // gemma4_2b extractor for Pass A beat extraction, and emits
        // Markdown reports for hand-grading. Run with:
        //   swift run SceneTemplateSpike --extract <fixture.md>
        //   swift run SceneTemplateSpike --extract-all
        .executableTarget(
            name: "SceneTemplateSpike",
            dependencies: ["LoomCore"],
            path: "Tools/SceneTemplateSpike",
            exclude: ["Fixtures", "last-run"]
        ),
        // Phase 8.a §6.1 embedder discrimination spike runner
        // (LOOM_SCENE_EXEMPLAR.md §6.1 + LOOM_SCENE_EXEMPLAR_RESEARCH.md).
        // Loads the 20-fixture register/style set, embeds each fixture
        // with each candidate embedder (StyleDistance / Wegmann / LUAR /
        // mxbai), and emits a per-embedder cosine matrix + separation
        // score to LOOM_SCENE_EXEMPLAR_SPIKE.md.
        //   swift run SceneExemplarSpike cosine-matrix --embedder=<id>
        .executableTarget(
            name: "SceneExemplarSpike",
            dependencies: ["LoomCore"],
            path: "Tools/SceneExemplarSpike",
            exclude: ["fixtures", "last-run"]
        ),
    ]
)

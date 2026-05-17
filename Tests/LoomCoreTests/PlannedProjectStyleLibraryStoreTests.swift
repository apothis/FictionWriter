import Foundation
@testable import LoomCore

/// Planned Project mode — `StyleLibraryStore`: the app-level
/// `styles.json` library, seeded with built-in starter styles on
/// first run and writer-owned thereafter. LOOM_PLANNED_PROJECT.md §5.
func plannedProjectStyleLibraryStoreTests() -> TestSuite {
    let s = TestSuite("PlannedProjectStyleLibraryStore")

    func tempRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("loom-styles-test-\(UUID().uuidString)", isDirectory: true)
    }

    s.test("load on a fresh install returns the built-in starter styles") {
        let store = StyleLibraryStore(rootDir: tempRoot())
        let styles = store.load()
        try expectTrue(!styles.isEmpty)
        try expectEqual(styles, StyleLibrary.builtInStarters)
    }

    s.test("save then load round-trips a custom library") {
        let store = StyleLibraryStore(rootDir: tempRoot())
        let custom = [
            Style(name: "My Genre", type: .genre, descriptor: "d"),
            Style(name: "My Register", type: .register, descriptor: "r"),
        ]
        try store.save(custom)
        try expectEqual(store.load(), custom)
    }

    s.test("an explicitly saved empty library is not re-seeded") {
        // Empty is a real state — the writer deleted everything.
        let store = StyleLibraryStore(rootDir: tempRoot())
        try store.save([])
        try expectEqual(store.load(), [])
    }

    s.test("a corrupt styles.json falls back to the built-in starters") {
        let root = tempRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: root.appendingPathComponent("styles.json"))
        let store = StyleLibraryStore(rootDir: root)
        try expectEqual(store.load(), StyleLibrary.builtInStarters)
    }

    s.test("every built-in starter is flagged isBuiltIn and has a descriptor") {
        try expectTrue(!StyleLibrary.builtInStarters.isEmpty)
        for style in StyleLibrary.builtInStarters {
            try expectTrue(style.isBuiltIn, "\(style.name) should be flagged built-in")
            try expectTrue(!style.descriptor.isEmpty, "\(style.name) needs a descriptor")
        }
    }

    s.test("the built-in library is a broad, well-formed selection") {
        let starters = StyleLibrary.builtInStarters
        let genres = starters.filter { $0.type == .genre }
        let registers = starters.filter { $0.type == .register }
        try expectTrue(genres.count >= 10, "expected a broad genre selection, got \(genres.count)")
        try expectTrue(registers.count >= 8, "expected a broad register selection, got \(registers.count)")
        // Names are unique (case-insensitively).
        let names = starters.map { $0.name.lowercased() }
        try expectEqual(Set(names).count, names.count)
        // Every starter carries at least one concrete constraint.
        for style in starters {
            try expectTrue(!style.constraints.isEmpty, "\(style.name) needs constraints")
        }
    }

    return s
}

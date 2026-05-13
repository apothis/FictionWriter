import Foundation
@testable import LoomCore

/// Smoke test for the Phase 5 RAG-for-style spike fixture
/// (LOOM_RAG_SPIKE.md §4). Reads the fixture from disk via the same
/// relative-path convention as `Tools/LedgerSpike`, decodes it, and
/// pins the grid shape so a future hand-edit can't accidentally
/// break the eval-runner contract.
func phase5RagFixtureTests() -> TestSuite {
    let s = TestSuite("Phase5RagFixture")

    let fixtureRelativePath = "Tests/LoomCoreTests/Fixtures/RagSpike/fixture.json"

    struct Fixture: Decodable {
        let version: Int
        let styles: [String: String]
        let topics: [String: String]
        let excerpts: [Excerpt]
        let queries: [Excerpt]
    }
    struct Excerpt: Decodable {
        let id: Int
        let style: String
        let topic: String
        let nsfw: Bool
        let text: String
    }

    func loadFixture() throws -> Fixture {
        let cwd = FileManager.default.currentDirectoryPath
        let url = URL(fileURLWithPath: cwd).appendingPathComponent(fixtureRelativePath)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Fixture.self, from: data)
    }

    s.test("fixture decodes successfully") {
        _ = try loadFixture()
    }

    s.test("fixture has 12 excerpts and 4 queries") {
        let f = try loadFixture()
        try expectEqual(f.excerpts.count, 12)
        try expectEqual(f.queries.count, 4)
    }

    s.test("fixture covers the full 4 styles × 3 topics grid") {
        let f = try loadFixture()
        var grid: Set<String> = []
        for e in f.excerpts {
            grid.insert("\(e.style)-\(e.topic)")
        }
        var expected: Set<String> = []
        for style in ["S1", "S2", "S3", "S4"] {
            for topic in ["T1", "T2", "T3"] {
                expected.insert("\(style)-\(topic)")
            }
        }
        try expectEqual(grid, expected)
    }

    s.test("excerpts have unique ids 1...12") {
        let f = try loadFixture()
        let ids = Set(f.excerpts.map { $0.id })
        try expectEqual(ids, Set(1...12))
    }

    s.test("queries have unique ids 101...104") {
        let f = try loadFixture()
        let ids = Set(f.queries.map { $0.id })
        try expectEqual(ids, Set(101...104))
    }

    s.test("NSFW coverage matches the LOOM_RAG_SPIKE §4 plan: 8 of 12 excerpts") {
        let f = try loadFixture()
        let nsfwCount = f.excerpts.filter { $0.nsfw }.count
        try expectEqual(nsfwCount, 8)
    }

    s.test("T1 (sexual encounter) is 100% NSFW per the plan") {
        let f = try loadFixture()
        let t1 = f.excerpts.filter { $0.topic == "T1" }
        try expectEqual(t1.count, 4)
        try expectTrue(t1.allSatisfy { $0.nsfw })
    }

    s.test("all 4 query scenes are NSFW (project strategic anchor)") {
        let f = try loadFixture()
        try expectTrue(f.queries.allSatisfy { $0.nsfw })
    }

    s.test("every excerpt has at least 200 words (lower bound for stylistic signal)") {
        let f = try loadFixture()
        for e in f.excerpts {
            let words = e.text.split(whereSeparator: { $0.isWhitespace }).count
            try expectTrue(
                words >= 200,
                "excerpt \(e.id) (\(e.style)/\(e.topic)) has only \(words) words"
            )
        }
    }

    s.test("every excerpt fits within ~512 token budget (stay under mxbai/bge truncation)") {
        // Rough heuristic: prose ≈ 1.3 tokens/word. 384-word ceiling
        // ≈ 500 tokens, leaving headroom for embedder special tokens.
        let f = try loadFixture()
        for e in f.excerpts {
            let words = e.text.split(whereSeparator: { $0.isWhitespace }).count
            try expectTrue(
                words <= 400,
                "excerpt \(e.id) (\(e.style)/\(e.topic)) has \(words) words, may truncate"
            )
        }
    }

    return s
}

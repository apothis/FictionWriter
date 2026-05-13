import Foundation
@testable import LoomCore

/// Smoke test for the narrative-mode classifier gold fixture
/// (LOOM_NARRATIVE_MODE_SPIKE.md §3.1). Pins composition + every
/// modality string parses to a valid NarrativeMode + every chunk
/// has a non-empty text body.
func phase5NarrativeModeGoldTests() -> TestSuite {
    let s = TestSuite("Phase5NarrativeModeGold")

    let fixturePath = "Tests/LoomCoreTests/Fixtures/NarrativeModeSpike/gold.json"

    struct Gold: Decodable {
        let version: Int
        let chunks: [GoldChunk]
    }
    struct GoldChunk: Decodable {
        let id: Int
        let source: String
        let nsfw: Bool
        let modality: String
        let text: String
    }

    func loadGold() throws -> Gold {
        let cwd = FileManager.default.currentDirectoryPath
        let url = URL(fileURLWithPath: cwd).appendingPathComponent(fixturePath)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Gold.self, from: data)
    }

    s.test("gold loads and decodes") {
        _ = try loadGold()
    }

    s.test("gold has at least 50 chunks (spike-spec target)") {
        let g = try loadGold()
        try expectTrue(g.chunks.count >= 50, "got \(g.chunks.count)")
    }

    s.test("every chunk's modality maps to a valid NarrativeMode") {
        let g = try loadGold()
        for c in g.chunks {
            try expectNotNil(NarrativeMode(rawValue: c.modality))
        }
    }

    s.test("every modality is represented at least 4 times (eval-stat-power floor)") {
        let g = try loadGold()
        var counts: [String: Int] = [:]
        for c in g.chunks {
            counts[c.modality, default: 0] += 1
        }
        for mode in NarrativeMode.allCases {
            let n = counts[mode.rawValue] ?? 0
            try expectTrue(
                n >= 4,
                "modality \(mode.rawValue) has only \(n) chunks; need ≥ 4 for stable per-category metrics"
            )
        }
    }

    s.test("NSFW coverage ≥ 24% per spike §3.1 strategic-anchor floor") {
        let g = try loadGold()
        let nsfw = g.chunks.filter { $0.nsfw }.count
        let pct = Double(nsfw) / Double(g.chunks.count)
        try expectTrue(pct >= 0.24, "NSFW coverage \(pct) below 0.24 floor")
    }

    s.test("every chunk has non-empty text") {
        let g = try loadGold()
        for c in g.chunks {
            try expectFalse(c.text.isEmpty, "chunk \(c.id) has empty text")
        }
    }

    s.test("chunk ids are unique") {
        let g = try loadGold()
        try expectEqual(Set(g.chunks.map { $0.id }).count, g.chunks.count)
    }

    return s
}

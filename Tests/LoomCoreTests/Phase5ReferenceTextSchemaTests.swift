import Foundation
@testable import LoomCore

/// Pure-data schema tests for Phase 5 reference texts (scope-lock #3
/// per LOOM_PLAN.md §5). Reference texts are the user's curated style
/// corpus — chunked + embedded via D + E at ingest time, retrieved at
/// generation time. On-disk format mirrors `scenes/<id>.md`: a YAML
/// frontmatter block + prose body, with a sidecar `<id>.index` JSON
/// file holding the per-chunk vectors.
func phase5ReferenceTextSchemaTests() -> TestSuite {
    let s = TestSuite("Phase5ReferenceTextSchema")

    // MARK: - ReferenceText Codable

    s.test("ReferenceText round-trips through JSONEncoder.loomPretty") {
        let id = UUID()
        let ref = ReferenceText(
            id: id,
            name: "Hemingway sample",
            nsfw: false,
            createdAt: LoomISO8601.roundedToMillisecond(Date(timeIntervalSince1970: 1_700_000_000)),
            extraFrontmatter: [:],
            body: "He walked to the door."
        )
        let data = try JSONEncoder.loomPretty.encode(ref)
        let decoded = try JSONDecoder.loom.decode(ReferenceText.self, from: data)
        try expectEqual(decoded.id, ref.id)
        try expectEqual(decoded.name, ref.name)
        try expectEqual(decoded.nsfw, ref.nsfw)
        try expectEqual(decoded.createdAt, ref.createdAt)
        // body is runtime-only; not persisted in JSON form
        try expectEqual(decoded.body, "")
    }

    s.test("ReferenceText.contentPath is derived from id") {
        let id = UUID()
        let ref = ReferenceText(id: id, name: "x")
        try expectEqual(ref.contentPath, "references/\(id.uuidString).md")
    }

    s.test("ReferenceText.indexPath is derived from id") {
        let id = UUID()
        let ref = ReferenceText(id: id, name: "x")
        try expectEqual(ref.indexPath, "references/\(id.uuidString).index")
    }

    s.test("ReferenceText nsfw default is false (content-neutrality — user opts in explicitly)") {
        let ref = ReferenceText(id: UUID(), name: "x")
        try expectFalse(ref.nsfw)
    }

    // MARK: - ReferenceTextIndex Codable

    s.test("ReferenceTextIndex with no chunks round-trips") {
        let idx = ReferenceTextIndex(
            schemaVersion: 1,
            dModel: nil, eModel: nil,
            chunks: []
        )
        let data = try JSONEncoder.loomPretty.encode(idx)
        let decoded = try JSONDecoder.loom.decode(ReferenceTextIndex.self, from: data)
        try expectEqual(decoded, idx)
    }

    s.test("ReferenceTextIndex with both vectors per chunk round-trips") {
        let chunk = ReferenceTextIndex.Chunk(
            text: "He walked to the door.",
            wordRangeStart: 0,
            wordRangeEnd: 5,
            modality: nil,
            dVec: [0.1, 0.2, -0.3],
            eVec: [1.5, -1.5, 0.0]
        )
        let idx = ReferenceTextIndex(
            schemaVersion: 1,
            dModel: ReferenceTextIndex.ModelFingerprint(id: "StyleDistance/styledistance (mlx-fp16)", dim: 3),
            eModel: ReferenceTextIndex.ModelFingerprint(id: "loom/funcword-z-top150", dim: 3),
            chunks: [chunk]
        )
        let data = try JSONEncoder.loomPretty.encode(idx)
        let decoded = try JSONDecoder.loom.decode(ReferenceTextIndex.self, from: data)
        try expectEqual(decoded, idx)
    }

    s.test("ReferenceTextIndex Chunk with no vectors models the pre-embed state") {
        // After ingest, before the embed pass runs, chunks exist but
        // vectors are nil. The schema accommodates this — the embed
        // pass fills in dVec/eVec later.
        let chunk = ReferenceTextIndex.Chunk(
            text: "He walked.",
            wordRangeStart: 0, wordRangeEnd: 2,
            modality: nil, dVec: nil, eVec: nil
        )
        let idx = ReferenceTextIndex(schemaVersion: 1, dModel: nil, eModel: nil, chunks: [chunk])
        let data = try JSONEncoder.loomPretty.encode(idx)
        let decoded = try JSONDecoder.loom.decode(ReferenceTextIndex.self, from: data)
        try expectNil(decoded.chunks[0].dVec)
        try expectNil(decoded.chunks[0].eVec)
        try expectEqual(decoded.chunks[0].text, "He walked.")
    }

    s.test("ReferenceTextIndex Chunk with modality persists the scene-type tag") {
        // Phase 5 scope-lock #5 — per-scene-type retrieval. Tagging
        // policy (LLM vs user) is undecided, but the schema slot is
        // here so once policy lands the storage doesn't need a
        // migration.
        let chunk = ReferenceTextIndex.Chunk(
            text: "Bullets cracked the windshield.",
            wordRangeStart: 0, wordRangeEnd: 4,
            modality: "action",
            dVec: nil, eVec: nil
        )
        let idx = ReferenceTextIndex(schemaVersion: 1, dModel: nil, eModel: nil, chunks: [chunk])
        let data = try JSONEncoder.loomPretty.encode(idx)
        let decoded = try JSONDecoder.loom.decode(ReferenceTextIndex.self, from: data)
        try expectEqual(decoded.chunks[0].modality, "action")
    }

    s.test("ReferenceTextIndex schemaVersion = 1 today; forward-load anchors here") {
        // Schema-version anchor per the TDD memory: schema migrations
        // include the forward-load case. v1 readers must reject (or
        // log + skip) higher schemaVersion writes; this test pins the
        // floor for future migration tests.
        let data = """
        {
          "schemaVersion": 1,
          "chunks": []
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder.loom.decode(ReferenceTextIndex.self, from: data)
        try expectEqual(decoded.schemaVersion, 1)
        try expectEqual(decoded.chunks.count, 0)
        try expectNil(decoded.dModel)
        try expectNil(decoded.eModel)
    }

    return s
}

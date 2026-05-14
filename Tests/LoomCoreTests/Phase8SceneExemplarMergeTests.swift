import Foundation
@testable import LoomCore

// Phase 8.b.1 — pure-data projection that merges existing
// References + Templates into a single "Scene Exemplar" view per
// LOOM_SCENE_EXEMPLAR.md §5.1 Option C ("rename + soft-merge").
//
// The Phase 8.b ingest action (8.b.2) writes a Reference + a Template
// with a SHARED UUID; the merge collapses those into one card.
// Legacy items (a Reference with no matching-UUID Template, or vice
// versa) surface as orphan cards with one sidecar missing, so the
// user can re-ingest to fill in the gap.

private func ref(_ name: String, id: UUID = UUID()) -> ReferenceText {
    return ReferenceText(id: id, name: name, body: "")
}
private func tmpl(_ name: String, id: UUID = UUID()) -> TemplateScene {
    return TemplateScene(id: id, name: name, body: "")
}

func phase8SceneExemplarMergeTests() -> TestSuite {
    let s = TestSuite("Phase8SceneExemplarMerge")

    s.test("Reference + Template with shared UUID merge into one exemplar") {
        let sharedId = UUID()
        let merged = SceneExemplarComposer.merge(
            references: [ref("Scene A (ref)", id: sharedId)],
            templates: [tmpl("Scene A", id: sharedId)],
            indexedReferenceIds: [sharedId],
            skeletonTemplateIds: [sharedId]
        )
        try expectEqual(merged.count, 1)
        let one = merged[0]
        try expectEqual(one.id, sharedId)
        // Template name wins (it's the more curated artefact in
        // Phase 7 — references were anonymous chunks).
        try expectEqual(one.name, "Scene A")
        try expectEqual(one.hasIndex, true)
        try expectEqual(one.hasBeats, true)
    }

    s.test("Reference without matching Template surfaces as hasBeats=false") {
        let r = ref("standalone ref")
        let merged = SceneExemplarComposer.merge(
            references: [r],
            templates: [],
            indexedReferenceIds: [r.id],
            skeletonTemplateIds: []
        )
        try expectEqual(merged.count, 1)
        try expectEqual(merged[0].id, r.id)
        try expectEqual(merged[0].name, "standalone ref")
        try expectEqual(merged[0].hasIndex, true)
        try expectEqual(merged[0].hasBeats, false)
    }

    s.test("Template without matching Reference surfaces as hasIndex=false") {
        let t = tmpl("standalone tmpl")
        let merged = SceneExemplarComposer.merge(
            references: [],
            templates: [t],
            indexedReferenceIds: [],
            skeletonTemplateIds: [t.id]
        )
        try expectEqual(merged.count, 1)
        try expectEqual(merged[0].id, t.id)
        try expectEqual(merged[0].name, "standalone tmpl")
        try expectEqual(merged[0].hasIndex, false)
        try expectEqual(merged[0].hasBeats, true)
    }

    s.test("multiple items: merged by shared UUID, orphans appear separately") {
        let sharedId = UUID()
        let r = ref("orphan ref")
        let t = tmpl("orphan tmpl")
        let merged = SceneExemplarComposer.merge(
            references: [
                ref("Scene A (ref)", id: sharedId),
                r,
            ],
            templates: [
                tmpl("Scene A", id: sharedId),
                t,
            ],
            indexedReferenceIds: [sharedId, r.id],
            skeletonTemplateIds: [sharedId, t.id]
        )
        try expectEqual(merged.count, 3)
        let bySharedId = merged.first { $0.id == sharedId }
        try expectEqual(bySharedId?.hasIndex, true)
        try expectEqual(bySharedId?.hasBeats, true)
        try expectEqual(merged.first { $0.id == r.id }?.hasBeats, false)
        try expectEqual(merged.first { $0.id == t.id }?.hasIndex, false)
    }

    s.test("ingested-state booleans honour the id-set arguments") {
        // A Reference exists on disk but hasn't been ingested yet
        // (no .index sidecar). Same for a Template missing its
        // .beats.json. The id-set arguments are the source of truth
        // — the merge doesn't probe storage.
        let rId = UUID()
        let tId = UUID()
        let merged = SceneExemplarComposer.merge(
            references: [ref("not ingested", id: rId)],
            templates: [tmpl("not extracted", id: tId)],
            indexedReferenceIds: [],     // no .index sidecar
            skeletonTemplateIds: []      // no .beats.json
        )
        try expectEqual(merged.count, 2)
        for m in merged {
            try expectEqual(m.hasIndex, false)
            try expectEqual(m.hasBeats, false)
        }
    }

    return s
}

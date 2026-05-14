import Foundation
@testable import LoomCore

// Phase 8.b.1 — ProjectSession surface for unified scene-exemplar
// CRUD. `addSceneExemplar(name:body:nsfw:)` creates a Reference + a
// Template with a SHARED UUID; the new pane reads them back via
// `listSceneExemplars()` which composes the two storage surfaces
// into the unified projection.

private func makeTempProject() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("loom-exemplar-session-\(UUID().uuidString)")
    let storage = ProjectStorage()
    let project = try storage.createNewProject(at: url, title: "T", author: nil)
    try storage.saveProject(project, at: url)
    return url
}

func phase8SceneExemplarSessionTests() -> TestSuite {
    let s = TestSuite("Phase8SceneExemplarSession")

    s.test("addSceneExemplar persists a Reference + Template with shared UUID + body") {
        let url = try makeTempProject()
        defer { try? FileManager.default.removeItem(at: url) }

        let session = ProjectSession(project: Project(title: "T"), url: url)
        let exemplar = try expectNotNil(session.addSceneExemplar(
            name: "Twilight scene",
            body: "She walked into the kitchen. The light was dim.",
            nsfw: false
        ))
        try expectEqual(exemplar.name, "Twilight scene")
        try expectFalse(exemplar.nsfw)

        // Reference on disk under shared UUID with the given body.
        let ref = try ReferenceStorage.loadReference(id: exemplar.id, in: url)
        try expectEqual(ref.name, "Twilight scene")
        try expectTrue(ref.body.contains("walked into the kitchen"))

        // Template on disk under same UUID with same body.
        let tmpl = try TemplateSceneStorage.loadTemplate(id: exemplar.id, in: url)
        try expectEqual(tmpl.name, "Twilight scene")
        try expectTrue(tmpl.body.contains("walked into the kitchen"))
    }

    s.test("addSceneExemplar with nsfw=true tags both Reference and Template") {
        let url = try makeTempProject()
        defer { try? FileManager.default.removeItem(at: url) }
        let session = ProjectSession(project: Project(title: "T"), url: url)
        let exemplar = try expectNotNil(session.addSceneExemplar(
            name: "explicit scene", body: "body", nsfw: true
        ))
        try expectTrue(exemplar.nsfw)
        let ref = try ReferenceStorage.loadReference(id: exemplar.id, in: url)
        let tmpl = try TemplateSceneStorage.loadTemplate(id: exemplar.id, in: url)
        try expectTrue(ref.nsfw)
        try expectTrue(tmpl.nsfw)
    }

    s.test("listSceneExemplars merges Reference + Template by UUID; orphans show with one flag false") {
        let url = try makeTempProject()
        defer { try? FileManager.default.removeItem(at: url) }
        let session = ProjectSession(project: Project(title: "T"), url: url)

        // 1. New unified exemplar (both sidecars to be created at ingest).
        let merged = try expectNotNil(session.addSceneExemplar(
            name: "merged", body: "x", nsfw: false
        ))
        // 2. Orphan reference (legacy Phase 5 ingest with no template).
        let orphanRef = try expectNotNil(session.addReference(name: "orphan ref"))
        // 3. Orphan template (legacy Phase 7 add).
        let orphanTmpl = try expectNotNil(session.addTemplateScene(name: "orphan tmpl"))

        let exemplars = session.listSceneExemplars()
        try expectEqual(exemplars.count, 3)
        // None are "ingested" yet — addSceneExemplar/addReference/
        // addTemplateScene don't fire Pass-A or chunk+embed pipelines.
        let mergedView = try expectNotNil(exemplars.first { $0.id == merged.id })
        try expectEqual(mergedView.hasIndex, false)
        try expectEqual(mergedView.hasBeats, false)
        // Orphans surface with one side present-on-disk but the
        // sidecar still missing (no ingest yet).
        try expectNotNil(exemplars.first { $0.id == orphanRef.id })
        try expectNotNil(exemplars.first { $0.id == orphanTmpl.id })
    }

    s.test("addSceneExemplar no-ops for in-memory session") {
        let session = ProjectSession(project: Project(title: "T"), url: nil)
        try expectNil(session.addSceneExemplar(name: "x", body: "y", nsfw: false))
    }

    return s
}

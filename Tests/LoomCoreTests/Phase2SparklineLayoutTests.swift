import Foundation
@testable import LoomCore

/// Phase 2.5 (#11 follow-on) — pure-data layout for the per-entity
/// mention sparkline (LOOM_DESIGN_LANGUAGE.md §14.5.1: thin bar with
/// marker dots at scenes the entity is mentioned in). Given a
/// scene-id ordering + a per-scene mention count, produces the list
/// of markers to render — each marker carries its x-ratio along the
/// bar (0..1) + the scene id so the rendering view can hit-test
/// clicks and route them back through `session.selectScene(id:)`.
func phase2SparklineLayoutTests() -> TestSuite {
    let s = TestSuite("Phase2SparklineLayout")

    s.test("no scenes → no markers") {
        let layout = MentionSparklineLayout.build(sceneOrder: [], mentionsBySceneId: [:])
        try expectEqual(layout.markers.count, 0)
        try expectEqual(layout.totalScenes, 0)
    }

    s.test("scenes without mentions → no markers") {
        let s1 = UUID(); let s2 = UUID()
        let layout = MentionSparklineLayout.build(sceneOrder: [s1, s2], mentionsBySceneId: [:])
        try expectEqual(layout.markers, [])
        try expectEqual(layout.totalScenes, 2)
    }

    s.test("a single mention in a single scene lands at the midpoint of its slot") {
        let s1 = UUID()
        let layout = MentionSparklineLayout.build(
            sceneOrder: [s1],
            mentionsBySceneId: [s1: 1]
        )
        try expectEqual(layout.markers.count, 1)
        try expectEqual(layout.markers[0].sceneId, s1)
        // One scene → x-ratio at the centre of the only slot = 0.5.
        try expectEqual(layout.markers[0].xRatio, 0.5)
        try expectEqual(layout.markers[0].count, 1)
    }

    s.test("multiple scenes: markers land at slot midpoints in manuscript order") {
        let a = UUID(); let b = UUID(); let c = UUID(); let d = UUID()
        let layout = MentionSparklineLayout.build(
            sceneOrder: [a, b, c, d],
            mentionsBySceneId: [a: 2, c: 1]
        )
        try expectEqual(layout.markers.count, 2)
        // 4 scenes → slots: [0, 0.25), [0.25, 0.5), [0.5, 0.75), [0.75, 1)
        // Midpoints: 0.125, 0.375, 0.625, 0.875.
        try expectEqual(layout.markers[0].sceneId, a)
        try expectEqual(layout.markers[0].xRatio, 0.125)
        try expectEqual(layout.markers[0].count, 2)
        try expectEqual(layout.markers[1].sceneId, c)
        try expectEqual(layout.markers[1].xRatio, 0.625)
        try expectEqual(layout.markers[1].count, 1)
    }

    s.test("hitTest(_:) returns the closest marker within tolerance, else nil") {
        let a = UUID(); let b = UUID(); let c = UUID(); let d = UUID()
        let layout = MentionSparklineLayout.build(
            sceneOrder: [a, b, c, d],
            mentionsBySceneId: [a: 1, c: 1]
        )
        // Hit near a's marker (0.125).
        try expectEqual(layout.hitTest(xRatio: 0.13, tolerance: 0.05)?.sceneId, a)
        // Hit near c's marker (0.625).
        try expectEqual(layout.hitTest(xRatio: 0.61, tolerance: 0.05)?.sceneId, c)
        // Far away from any marker → nil.
        try expectNil(layout.hitTest(xRatio: 0.4, tolerance: 0.05))
    }

    return s
}

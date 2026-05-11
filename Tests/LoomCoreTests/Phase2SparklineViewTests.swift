import Foundation
import AppKit
@testable import LoomCore

/// Phase 2.5 (#11 follow-on) — `MentionSparklineView` smoke. The
/// view's draw code is honest UI; this suite pins the public
/// state + click routing the inspector consumes.
func phase2SparklineViewTests() -> TestSuite {
    let s = TestSuite("Phase2SparklineView")

    s.test("setLayout(_:) updates the view's known marker count") {
        let view = MentionSparklineView()
        try expectEqual(view.markerCountForTesting, 0)
        let s1 = UUID(); let s2 = UUID()
        view.setLayout(MentionSparklineLayout.build(
            sceneOrder: [s1, s2],
            mentionsBySceneId: [s1: 1]
        ))
        try expectEqual(view.markerCountForTesting, 1)
    }

    s.test("simulateClickForTesting(xRatio:) calls onMarkerClicked with the matched scene") {
        let view = MentionSparklineView()
        view.setFrameSize(NSSize(width: 200, height: 12))
        let s1 = UUID(); let s2 = UUID()
        view.setLayout(MentionSparklineLayout.build(
            sceneOrder: [s1, s2],
            mentionsBySceneId: [s1: 1, s2: 1]
        ))
        var clicked: UUID?
        view.onMarkerClicked = { clicked = $0 }
        // s1's marker sits at xRatio = 0.25 (1st of 2 slots, midpoint).
        view.simulateClickForTesting(xRatio: 0.25)
        try expectEqual(clicked, s1)
        // s2's marker sits at 0.75.
        view.simulateClickForTesting(xRatio: 0.75)
        try expectEqual(clicked, s2)
    }

    s.test("clicks away from any marker do not fire onMarkerClicked") {
        let view = MentionSparklineView()
        let s1 = UUID(); let s2 = UUID(); let s3 = UUID(); let s4 = UUID()
        view.setLayout(MentionSparklineLayout.build(
            sceneOrder: [s1, s2, s3, s4],
            mentionsBySceneId: [s1: 1, s4: 1]
        ))
        var clicked: UUID?
        view.onMarkerClicked = { clicked = $0 }
        // No markers near xRatio = 0.5 (s1 at 0.125, s4 at 0.875).
        view.simulateClickForTesting(xRatio: 0.5)
        try expectNil(clicked)
    }

    return s
}

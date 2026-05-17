import Foundation
@testable import LoomCore

/// Planned Project mode — Phase 4. The guided-creation wizard runs in
/// its own webview bundle; at boot the host pushes a
/// `PlannedProjectSnapshot` carrying the app style library (for the
/// style-assignment step + the style editor) and the available story
/// frameworks. This suite pins the wire shape.
func plannedProjectSnapshotTests() -> TestSuite {
    let s = TestSuite("PlannedProjectSnapshot")

    s.test("build projects the style library and the framework registry") {
        let styles = [
            Style(name: "Noir", type: .genre, descriptor: "Shadows."),
            Style(name: "Terse", type: .register, descriptor: "Short."),
        ]
        let snap = PlannedProjectSnapshot.build(styles: styles)
        try expectEqual(snap.styles.count, 2)
        try expectEqual(snap.styles.first?.name, "Noir")
        // v1 ships exactly the Save the Cat framework.
        try expectEqual(snap.frameworks.count, StoryFrameworks.all.count)
        try expectEqual(snap.frameworks.first?.id, "save-the-cat")
        try expectEqual(snap.frameworks.first?.displayName, "Save the Cat")
    }

    s.test("snapshot round-trips through Codable") {
        let snap = PlannedProjectSnapshot.build(
            styles: [Style(name: "Noir", type: .genre)]
        )
        let data = try JSONEncoder().encode(snap)
        let back = try JSONDecoder().decode(PlannedProjectSnapshot.self, from: data)
        try expectEqual(back, snap)
    }

    return s
}

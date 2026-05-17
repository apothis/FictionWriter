import Foundation

/// Planned Project mode — Phase 4. The JSON contract pushed from the
/// Swift host to the guided-creation wizard's webview bundle. Unlike
/// `BibleWorkspaceSnapshot` (project-bound), this snapshot is
/// pre-project: it carries the app-level style library — for the
/// wizard's style-assignment step and the style-library editor — and
/// the registered story frameworks.
///
/// Full-replace, not diff (the style library is small). Pushed via
/// `window.loom.applyPlannedSnapshot(...)`.
public struct PlannedProjectSnapshot: Codable, Equatable {
    /// The app style library (built-in starters plus writer-created).
    public let styles: [Style]
    /// The story frameworks available to scaffold an outline.
    public let frameworks: [PlannedSnapshotFramework]

    public init(styles: [Style], frameworks: [PlannedSnapshotFramework]) {
        self.styles = styles
        self.frameworks = frameworks
    }

    /// Build a snapshot from the style library. Frameworks always
    /// come from the `StoryFrameworks` registry — v1 ships exactly
    /// Save the Cat.
    public static func build(styles: [Style]) -> PlannedProjectSnapshot {
        PlannedProjectSnapshot(
            styles: styles,
            frameworks: StoryFrameworks.all.map {
                PlannedSnapshotFramework(id: $0.id, displayName: $0.displayName)
            }
        )
    }
}

/// A story framework projected for the webview — the `StoryFramework`
/// protocol itself isn't `Codable`, so the wizard sees this flat form.
public struct PlannedSnapshotFramework: Codable, Equatable {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

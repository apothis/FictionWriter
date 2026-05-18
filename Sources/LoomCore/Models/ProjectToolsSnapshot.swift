import Foundation

/// P2 — the JSON contract for the project-tools webview bundle, which
/// hosts two small surfaces: the per-scene framing editor and the
/// anti-slop phrase-list editor. One bundle, two window modes; the
/// `tool` discriminator tells the React side which to render.
public struct ProjectToolsSnapshot: Codable, Equatable {
    /// `"framing"` or `"antislop"`.
    public let tool: String
    /// Framing tool only — the scene being edited (uppercase UUID).
    public let sceneId: String?
    /// Framing tool only — the scene's title, for the header.
    public let sceneTitle: String
    /// Framing tool only — the current `Scene.framing` text.
    public let framing: String
    /// Anti-slop tool only — the project's curated phrase list.
    public let antiSlopPhrases: [String]
    public let projectTitle: String

    public init(
        tool: String,
        sceneId: String? = nil,
        sceneTitle: String = "",
        framing: String = "",
        antiSlopPhrases: [String] = [],
        projectTitle: String = ""
    ) {
        self.tool = tool
        self.sceneId = sceneId
        self.sceneTitle = sceneTitle
        self.framing = framing
        self.antiSlopPhrases = antiSlopPhrases
        self.projectTitle = projectTitle
    }

    /// Build the snapshot for the scene-framing tool.
    public static func framing(scene: Scene, projectTitle: String) -> ProjectToolsSnapshot {
        ProjectToolsSnapshot(
            tool: "framing",
            sceneId: scene.id.uuidString,
            sceneTitle: scene.title,
            framing: scene.framing,
            projectTitle: projectTitle
        )
    }

    /// Build the snapshot for the anti-slop tool.
    public static func antiSlop(project: Project) -> ProjectToolsSnapshot {
        ProjectToolsSnapshot(
            tool: "antislop",
            antiSlopPhrases: project.settings.antiSlopPhrases,
            projectTitle: project.title
        )
    }
}

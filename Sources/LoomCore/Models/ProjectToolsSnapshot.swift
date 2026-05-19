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
    /// Framing tool only — the project's characters (for the
    /// per-character undress markers).
    public let sceneCharacters: [ToolsCharacter]
    /// Framing tool only — characters marked undressed in this scene
    /// (uppercase UUID strings).
    public let undressedCharacterIds: [String]
    /// Work-framing tool only — the project's framed content elements.
    public let workFraming: [FramedElement]

    public init(
        tool: String,
        sceneId: String? = nil,
        sceneTitle: String = "",
        framing: String = "",
        antiSlopPhrases: [String] = [],
        projectTitle: String = "",
        sceneCharacters: [ToolsCharacter] = [],
        undressedCharacterIds: [String] = [],
        workFraming: [FramedElement] = []
    ) {
        self.tool = tool
        self.sceneId = sceneId
        self.sceneTitle = sceneTitle
        self.framing = framing
        self.antiSlopPhrases = antiSlopPhrases
        self.projectTitle = projectTitle
        self.sceneCharacters = sceneCharacters
        self.undressedCharacterIds = undressedCharacterIds
        self.workFraming = workFraming
    }

    /// Build the snapshot for the scene-framing tool.
    public static func framing(
        scene: Scene,
        characters: [Character],
        projectTitle: String
    ) -> ProjectToolsSnapshot {
        ProjectToolsSnapshot(
            tool: "framing",
            sceneId: scene.id.uuidString,
            sceneTitle: scene.title,
            framing: scene.framing,
            projectTitle: projectTitle,
            sceneCharacters: characters.map {
                ToolsCharacter(id: $0.id.uuidString, name: $0.name)
            },
            undressedCharacterIds: scene.undressedCharacterIds.map(\.uuidString)
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

    /// Build the snapshot for the work-framing tool.
    public static func workFraming(project: Project) -> ProjectToolsSnapshot {
        ProjectToolsSnapshot(
            tool: "workframing",
            projectTitle: project.title,
            workFraming: project.settings.workFraming
        )
    }
}

/// Minimal character projection for the project-tools webview.
public struct ToolsCharacter: Codable, Equatable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

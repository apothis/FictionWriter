import Foundation

/// Loom is a document-shaped app: each `<title>.loom/` directory is a
/// self-contained project. ProjectStorage is the read/write façade over
/// that directory shape (per LOOM_DATA_MODEL.md §7).
///
/// Phase 1 layout:
///
///     <project>.loom/
///     ├── project.json             # Project struct minus per-scene prose
///     ├── scenes/<id>.md           # frontmatter + prose body
///     └── generation-log/          # populated 1.k+ — empty in 1.b
///
/// Bible directories (`bible/characters/<id>.json` etc) and per-scene
/// sidecar JSON arrive when the corresponding sub-steps need them. Phase 1
/// inlines characters into project.json for compactness.
public final class ProjectStorage {
    private let fm: FileManager

    public init(fileManager: FileManager = .default) {
        self.fm = fileManager
    }

    // MARK: - Lifecycle

    /// Create a fresh `.loom/` directory at `url`. Throws on collision —
    /// the caller (file picker UI) is expected to confirm overwrite if
    /// the user picked an existing path.
    @discardableResult
    public func createNewProject(at url: URL, title: String, author: String?) throws -> Project {
        if fm.fileExists(atPath: url.path) {
            throw ProjectStorageError.directoryAlreadyExists(url)
        }
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        try fm.createDirectory(at: url.appendingPathComponent("scenes"), withIntermediateDirectories: true)
        try fm.createDirectory(at: url.appendingPathComponent("generation-log"), withIntermediateDirectories: true)

        let project = Project(title: title, author: author)
        try saveProject(project, at: url)
        DebugLog.shared.write("[project] created: \(url.lastPathComponent) at=\(url.path)")
        return project
    }

    // MARK: - Project metadata

    public func saveProject(_ project: Project, at url: URL) throws {
        let projectJSON = url.appendingPathComponent("project.json")
        let data = try JSONEncoder.loomPretty.encode(project)
        try atomicWrite(data, to: projectJSON)
        DebugLog.shared.write("[storage] wrote project.json (\(data.count) bytes) at=\(url.lastPathComponent)")
    }

    /// Load a project from disk. Returns the Project struct AND a map of
    /// loaded scenes keyed by id (prose lives in scene .md files, not in
    /// project.json — runtime must merge). Loading a scene .md whose id
    /// isn't referenced from project.json's manuscript is silently
    /// skipped; loading a manuscript scene whose .md is missing throws.
    public func loadProject(from url: URL) throws -> LoadedProject {
        let projectJSON = url.appendingPathComponent("project.json")
        guard fm.fileExists(atPath: projectJSON.path) else {
            throw ProjectStorageError.missingProjectJSON(url)
        }
        let data = try Data(contentsOf: projectJSON)
        let project = try JSONDecoder.loom.decode(Project.self, from: data)

        var scenes: [UUID: Scene] = [:]
        let scenesDir = url.appendingPathComponent("scenes")
        if fm.fileExists(atPath: scenesDir.path) {
            for sceneId in project.manuscript.orphanedSceneIds {
                let path = scenesDir.appendingPathComponent("\(sceneId.uuidString).md")
                guard fm.fileExists(atPath: path.path) else {
                    throw ProjectStorageError.missingSceneFile(sceneId, path)
                }
                let text = try String(contentsOf: path, encoding: .utf8)
                let relativeContentPath = "scenes/\(sceneId.uuidString).md"
                let scene = try SceneFile.decode(text, contentPath: relativeContentPath)
                scenes[scene.id] = scene
            }
        }
        DebugLog.shared.write("[project] loaded: \(project.title) scenes=\(scenes.count) characters=\(project.bible.characters.count)")
        return LoadedProject(project: project, scenes: scenes)
    }

    // MARK: - Scenes

    public func saveScene(_ scene: Scene, in projectURL: URL) throws {
        let path = projectURL.appendingPathComponent(scene.contentPath)
        try fm.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        let text = SceneFile.encode(scene)
        try atomicWrite(Data(text.utf8), to: path)
        DebugLog.shared.write("[storage] wrote scene id=\(scene.id) bytes=\(text.utf8.count)")
    }

    public func loadScene(id: UUID, from projectURL: URL) throws -> Scene {
        let path = projectURL.appendingPathComponent("scenes").appendingPathComponent("\(id.uuidString).md")
        let text = try String(contentsOf: path, encoding: .utf8)
        return try SceneFile.decode(text, contentPath: "scenes/\(id.uuidString).md")
    }

    // MARK: - Internals

    /// Atomic write: write to a sibling temp file, then rename. Avoids
    /// torn writes if the process dies mid-save. Mirrors RPClient's
    /// Storage.swift atomicWrite.
    private func atomicWrite(_ data: Data, to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

public struct LoadedProject {
    public var project: Project
    public var scenes: [UUID: Scene]

    public init(project: Project, scenes: [UUID: Scene]) {
        self.project = project
        self.scenes = scenes
    }
}

public enum ProjectStorageError: Error, Equatable {
    case directoryAlreadyExists(URL)
    case missingProjectJSON(URL)
    case missingSceneFile(UUID, URL)
}

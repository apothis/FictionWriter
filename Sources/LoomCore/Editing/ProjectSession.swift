import Foundation

/// In-memory mutable wrapper around a Project + the loaded Scenes
/// dictionary. Sidebar / Editor / Inspector all read from and write to
/// the same session; the underlying `changeCounter` ticks on every
/// mutation so observers can refresh on `didChange` notifications
/// without a per-mutation event vocabulary.
///
/// Phase 1 keeps mutations synchronous and main-thread only — there's
/// only ever one window per project, so no contention. Phase 2+ may
/// migrate to a per-session NotificationCenter if multi-window editing
/// arrives.
public final class ProjectSession {
    public private(set) var project: Project
    public private(set) var scenes: [UUID: Scene]
    public private(set) var changeCounter: Int = 0

    /// Posted on every mutation. The notification's `object` is the
    /// session that changed.
    public static let didChangeNotification = Notification.Name("LoomProjectSession.didChange")

    public init(project: Project, scenes: [UUID: Scene] = [:]) {
        self.project = project
        self.scenes = scenes
    }

    // MARK: - Sidebar mutations

    /// Append a new empty scene to the manuscript. The default title
    /// follows the "Scene N" pattern matching the design language §14.3
    /// empty-state copy. Caller may immediately rename via `renameScene`.
    @discardableResult
    public func addScene(title: String? = nil) -> Scene {
        let next = nextDefaultSceneIndex()
        let resolvedTitle = title ?? "Scene \(next)"
        let scene = Scene(id: UUID(), title: resolvedTitle)
        scenes[scene.id] = scene
        project.manuscript.orphanedSceneIds.append(scene.id)
        markChanged()
        DebugLog.shared.write("[project] addScene id=\(scene.id) title=\(resolvedTitle)")
        return scene
    }

    public func renameScene(id: UUID, to title: String) {
        guard var scene = scenes[id] else { return }
        scene.title = title
        scenes[id] = scene
        markChanged()
        DebugLog.shared.write("[project] renameScene id=\(id) title=\(title)")
    }

    /// Move a scene out of the manuscript and into the trash. The Scene
    /// struct stays in the `scenes` map so undelete is a cheap pointer
    /// swap. Phase 6 polish may add an "empty trash" path that drops
    /// the struct.
    public func deleteScene(id: UUID) {
        let manuscript = project.manuscript
        guard manuscript.orphanedSceneIds.contains(id) else { return }
        project.manuscript.orphanedSceneIds = SceneListOperations.delete(id, from: manuscript.orphanedSceneIds)
        project.manuscript.trashedSceneIds.append(id)
        markChanged()
        DebugLog.shared.write("[project] deleteScene id=\(id) → trash")
    }

    public func restoreFromTrash(id: UUID) {
        let manuscript = project.manuscript
        guard manuscript.trashedSceneIds.contains(id) else { return }
        project.manuscript.trashedSceneIds = SceneListOperations.delete(id, from: manuscript.trashedSceneIds)
        project.manuscript.orphanedSceneIds.append(id)
        markChanged()
        DebugLog.shared.write("[project] restoreFromTrash id=\(id)")
    }

    public func reorderScenes(from: Int, to: Int) {
        project.manuscript.orphanedSceneIds = SceneListOperations.move(
            project.manuscript.orphanedSceneIds, from: from, to: to)
        markChanged()
    }

    // MARK: - Internals

    private func markChanged() {
        changeCounter += 1
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    /// Compute the next "Scene N" suffix by scanning existing scenes
    /// (manuscript + trash) for the highest "Scene N" title. Avoids
    /// title collisions when scenes are deleted then re-added.
    private func nextDefaultSceneIndex() -> Int {
        let allIds = project.manuscript.orphanedSceneIds + project.manuscript.trashedSceneIds
        let titles = allIds.compactMap { scenes[$0]?.title }
        var maxIndex = 0
        for title in titles {
            // Match leading "Scene <int>" prefix.
            let scanner = Scanner(string: title)
            guard scanner.scanString("Scene ") != nil,
                  let n = scanner.scanInt() else { continue }
            if n > maxIndex { maxIndex = n }
        }
        return maxIndex + 1
    }
}

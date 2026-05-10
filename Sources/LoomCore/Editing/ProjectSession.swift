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
    /// Currently-active scene — the one the editor is showing. Set by
    /// the sidebar on row selection. May be nil briefly (empty project,
    /// or after deleting the last scene).
    public private(set) var currentSceneId: UUID?
    /// On-disk location of the project, or nil for in-memory ("Untitled")
    /// sessions. Set by AppState on create / open / save-as. When nil,
    /// `flushSave` is a no-op.
    public var url: URL?
    /// True iff there's been a mutation since the last successful save
    /// (or since session creation, for never-saved sessions). Cleared
    /// by `flushSave`.
    public private(set) var isDirty: Bool = false

    /// Posted on every mutation. The notification's `object` is the
    /// session that changed.
    public static let didChangeNotification = Notification.Name("LoomProjectSession.didChange")

    /// Posted only when `currentSceneId` changes. The editor listens
    /// for this and swaps its text-storage to the new scene's prose.
    public static let selectionDidChangeNotification = Notification.Name("LoomProjectSession.selectionDidChange")

    /// Posted after `replace(...)` swaps the entire project. Lets UIs
    /// (sidebar, editor, inspector) re-render against the new content.
    public static let didReplaceNotification = Notification.Name("LoomProjectSession.didReplace")

    /// Posted on transitions of `isDirty` (clean→dirty AND dirty→clean).
    /// Distinct from `didChange` so the window-title document-edited
    /// indicator refreshes without forcing the sidebar to reload.
    public static let didChangeDirtyStateNotification = Notification.Name("LoomProjectSession.didChangeDirtyState")

    private var saveDebounceTimer: Timer?
    private let storage: ProjectStorage

    public init(
        project: Project,
        scenes: [UUID: Scene] = [:],
        url: URL? = nil,
        storage: ProjectStorage = ProjectStorage()
    ) {
        self.project = project
        self.scenes = scenes
        self.url = url
        self.storage = storage
    }

    deinit {
        saveDebounceTimer?.invalidate()
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
        // Auto-select if nothing is currently selected — the user
        // expects to start typing into the new scene immediately.
        if currentSceneId == nil {
            currentSceneId = scene.id
            postSelectionDidChange()
        }
        markChanged()
        DebugLog.shared.write("[project] addScene id=\(scene.id) title=\(resolvedTitle)")
        return scene
    }

    /// Set the active scene. No-op if `id` doesn't refer to a known
    /// scene. Posts `selectionDidChangeNotification` on a real change.
    public func selectScene(id: UUID) {
        guard scenes[id] != nil else { return }
        guard id != currentSceneId else { return }
        currentSceneId = id
        postSelectionDidChange()
        DebugLog.shared.write("[project] selectScene id=\(id)")
    }

    /// Update the prose body of a scene. Called by the editor on text
    /// change. Doesn't bump the changeCounter — the editor already has
    /// the new text, and the sidebar doesn't render prose. Does mark
    /// the session dirty so auto-save picks it up.
    public func updateProse(id: UUID, prose: String) {
        guard var scene = scenes[id] else { return }
        scene.prose = prose
        scenes[id] = scene
        markDirty()
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
        if currentSceneId == id {
            currentSceneId = nil
            postSelectionDidChange()
        }
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

    // MARK: - Bible mutations (Phase 1: characters only)

    @discardableResult
    public func addCharacter(name: String) -> Character {
        let character = Character(name: name)
        project.bible.characters.append(character)
        markChanged()
        DebugLog.shared.write("[bible] addCharacter id=\(character.id) name=\(name)")
        return character
    }

    public func updateCharacter(_ character: Character) {
        guard let idx = project.bible.characters.firstIndex(where: { $0.id == character.id }) else { return }
        project.bible.characters[idx] = character
        markChanged()
        DebugLog.shared.write("[bible] updateCharacter id=\(character.id)")
    }

    public func deleteCharacter(id: UUID) {
        guard let idx = project.bible.characters.firstIndex(where: { $0.id == id }) else { return }
        project.bible.characters.remove(at: idx)
        markChanged()
        DebugLog.shared.write("[bible] deleteCharacter id=\(id)")
    }

    // MARK: - Notes + inspector tab

    public func updateNotes(_ notes: String) {
        project.notes = notes
        // Notes are inspector-only — no reason to fan out a didChange
        // notification (sidebar, editor, status strip don't render notes).
    }

    public func setSelectedInspectorTab(_ tab: InspectorTab) {
        project.selectedInspectorTab = tab
    }

    // MARK: - Internals

    private func markChanged() {
        changeCounter += 1
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        markDirty()
    }

    /// Marks the session dirty + schedules a debounced auto-save.
    /// Used by structural mutations (markChanged path) AND by prose
    /// updates that don't need a UI fan-out but still need to persist.
    /// Posts `didChangeDirtyStateNotification` only on the clean→dirty
    /// transition (not on every dirty mutation).
    private func markDirty() {
        let wasClean = !isDirty
        isDirty = true
        scheduleAutoSave()
        if wasClean {
            NotificationCenter.default.post(name: Self.didChangeDirtyStateNotification, object: self)
        }
    }

    private func postSelectionDidChange() {
        NotificationCenter.default.post(name: Self.selectionDidChangeNotification, object: self)
    }

    // MARK: - Persistence

    /// Schedule a debounced save 500ms from now. Each new mutation
    /// resets the timer — bursts of edits (like typing prose) collapse
    /// into a single write. Timer fires on the main run loop; under
    /// XCTest / TestKit harness runs (where the run loop isn't pumped),
    /// the timer never fires and tests must call `flushSave` explicitly.
    private func scheduleAutoSave() {
        saveDebounceTimer?.invalidate()
        guard url != nil else { return }
        saveDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            try? self?.flushSave()
        }
    }

    /// Synchronous save. No-op when the session has no URL (in-memory
    /// "Untitled" mode). Writes the project.json then every loaded
    /// scene's .md file. Errors propagate; caller decides how to
    /// surface them (Phase 1.m wires error UI).
    public func flushSave() throws {
        guard let url = url, isDirty else { return }
        try storage.saveProject(project, at: url)
        for (_, scene) in scenes {
            try storage.saveScene(scene, in: url)
        }
        isDirty = false
        NotificationCenter.default.post(name: Self.didChangeDirtyStateNotification, object: self)
        DebugLog.shared.write("[storage] auto-saved \(project.title) → \(url.lastPathComponent)")
    }

    /// Replace the entire in-memory state. Used by AppState on Open /
    /// Create — preserves the session reference so existing observers
    /// (sidebar, editor, inspector) stay valid; they re-render via
    /// `didReplaceNotification`.
    public func replace(project: Project, scenes: [UUID: Scene], url: URL?) {
        saveDebounceTimer?.invalidate()
        self.project = project
        self.scenes = scenes
        self.url = url
        self.isDirty = false
        // Pick the first orphaned scene as the active one (or nil if
        // the project has no scenes — the editor will show empty state).
        self.currentSceneId = project.manuscript.orphanedSceneIds.first
        self.changeCounter += 1
        NotificationCenter.default.post(name: Self.didReplaceNotification, object: self)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        postSelectionDidChange()
    }

    /// Test hook — manually mark clean without performing an actual
    /// save. Used to verify dirty-flag transitions in unit tests.
    func markCleanForTest() {
        isDirty = false
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

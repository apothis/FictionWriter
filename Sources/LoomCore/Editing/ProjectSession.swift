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

    /// Phase 4.5 Session 4 — remove a single accepted ledger fact
    /// from a character's per-scene bucket. Closes the §15.9 audit
    /// gap (facts were invisible + unremovable post-acceptance).
    /// No-op (and no notification) if any of characterId / sceneId
    /// / factId is stale; cleans up an empty per-scene bucket so
    /// the dict doesn't accumulate empty keys over time.
    public func removeKnownFact(characterId: UUID, sceneId: UUID, factId: UUID) {
        guard let charIdx = project.bible.characters.firstIndex(where: { $0.id == characterId }) else { return }
        var character = project.bible.characters[charIdx]
        guard var bucket = character.knownFactsBySceneId[sceneId] else { return }
        guard let factIdx = bucket.firstIndex(where: { $0.id == factId }) else { return }
        bucket.remove(at: factIdx)
        if bucket.isEmpty {
            character.knownFactsBySceneId.removeValue(forKey: sceneId)
        } else {
            character.knownFactsBySceneId[sceneId] = bucket
        }
        project.bible.characters[charIdx] = character
        markChanged()
        DebugLog.shared.write("[bible] removeKnownFact character=\(characterId) scene=\(sceneId) fact=\(factId)")
    }

    // MARK: - Bible mutations (Phase 2 #5: settings + objects)

    @discardableResult
    public func addSetting(name: String) -> Setting {
        let setting = Setting(name: name)
        project.bible.settings.append(setting)
        markChanged()
        DebugLog.shared.write("[bible] addSetting id=\(setting.id) name=\(name)")
        return setting
    }

    public func updateSetting(_ setting: Setting) {
        guard let idx = project.bible.settings.firstIndex(where: { $0.id == setting.id }) else { return }
        project.bible.settings[idx] = setting
        markChanged()
        DebugLog.shared.write("[bible] updateSetting id=\(setting.id)")
    }

    public func deleteSetting(id: UUID) {
        guard let idx = project.bible.settings.firstIndex(where: { $0.id == id }) else { return }
        project.bible.settings.remove(at: idx)
        markChanged()
        DebugLog.shared.write("[bible] deleteSetting id=\(id)")
    }

    @discardableResult
    public func addObject(name: String) -> BibleObject {
        let object = BibleObject(name: name)
        project.bible.objects.append(object)
        markChanged()
        DebugLog.shared.write("[bible] addObject id=\(object.id) name=\(name)")
        return object
    }

    public func updateObject(_ object: BibleObject) {
        guard let idx = project.bible.objects.firstIndex(where: { $0.id == object.id }) else { return }
        project.bible.objects[idx] = object
        markChanged()
        DebugLog.shared.write("[bible] updateObject id=\(object.id)")
    }

    public func deleteObject(id: UUID) {
        guard let idx = project.bible.objects.firstIndex(where: { $0.id == id }) else { return }
        project.bible.objects.remove(at: idx)
        markChanged()
        DebugLog.shared.write("[bible] deleteObject id=\(id)")
    }

    // MARK: - Snapshots (Phase 2 #9)

    /// Captures the current prose of `sceneId` as a snapshot file on
    /// disk (`<project>/snapshots/<ts>-<uuid>.json`). Returns the
    /// persisted record, or nil when no work was done — either
    /// the session is in-memory (`url == nil`) or the scene id is
    /// stale.
    @discardableResult
    public func captureSnapshot(sceneId: UUID, label: String?) -> PersistedSnapshot? {
        guard let projectURL = url else {
            DebugLog.shared.write("[snapshot] capture skipped: in-memory session")
            return nil
        }
        guard let scene = scenes[sceneId] else {
            DebugLog.shared.write("[snapshot] capture skipped: stale sceneId \(sceneId)")
            return nil
        }
        let snap = PersistedSnapshot(
            sceneId: sceneId,
            takenAt: Date(),
            label: label,
            contentSnapshot: scene.prose
        )
        do {
            try SnapshotStore().write(snap, in: projectURL)
            return snap
        } catch {
            DebugLog.shared.write("[snapshot] write failed: \(error)")
            return nil
        }
    }

    /// Captures a "Before Rewrite" snapshot if the mode is part of the
    /// rewrite family (LOOM_DATA_MODEL.md §5: rewrite / rewriteVoice /
    /// rewriteTense / rewritePOV / rewriteLength — all destructive,
    /// they replace selected prose in place). No-op for non-rewrite
    /// modes. Designed to be called by GenerationCoordinator.start()
    /// before the network request kicks off.
    @discardableResult
    public func captureBeforeRewriteIfNeeded(mode: GenerationMode, sceneId: UUID) -> PersistedSnapshot? {
        guard SnapshotPolicy.shouldSnapshot(beforeMode: mode) else { return nil }
        return captureSnapshot(sceneId: sceneId, label: "Before Rewrite")
    }

    // MARK: - Target word counts (Phase 3 §F)

    public func setProjectTargetWordCount(_ count: Int?) {
        project.settings.targetWordCount = count
        markDirty()
    }

    public func setChapterTargetWordCount(id: UUID, to count: Int?) {
        for pIdx in project.manuscript.parts.indices {
            if let cIdx = project.manuscript.parts[pIdx].chapters.firstIndex(where: { $0.id == id }) {
                project.manuscript.parts[pIdx].chapters[cIdx].targetWordCount = count
                markChanged()
                return
            }
        }
    }

    public func setSceneTargetWordCount(id: UUID, to count: Int?) {
        guard var scene = scenes[id] else { return }
        scene.targetWordCount = count
        scenes[id] = scene
        markDirty()
    }

    // MARK: - Scene metadata mutations (Phase 3 §E)

    public func setSceneStatus(id: UUID, to status: SceneStatus) {
        guard var scene = scenes[id] else { return }
        scene.status = status
        scenes[id] = scene
        markDirty()
        DebugLog.shared.write("[scene] status id=\(id) → \(status.rawValue)")
    }

    public func setSceneSummary(id: UUID, to summary: String) {
        guard var scene = scenes[id] else { return }
        scene.summary = summary
        scenes[id] = scene
        markDirty()
    }

    /// Phase 4 #7 adjacent — assigns the scene's POV character (or
    /// clears it when `pov == nil`). The `[KNOWLEDGE-LEDGER]` prompt
    /// layer (sub-task 7) gates on `Scene.pov` being a non-nil bible
    /// character id, so without this setter the layer never fires in
    /// production. Stale scene id is a no-op, matching the sibling
    /// scene-metadata setters above.
    public func setScenePOV(id: UUID, to pov: UUID?) {
        guard var scene = scenes[id] else { return }
        scene.pov = pov
        scenes[id] = scene
        markDirty()
        DebugLog.shared.write("[scene] pov id=\(id) → \(pov?.uuidString ?? "nil")")
    }

    // MARK: - Manuscript hierarchy mutations (Phase 3 §B)

    @discardableResult
    public func addPart(title: String) -> Part {
        let part = Part(title: title)
        project.manuscript.parts.append(part)
        markChanged()
        DebugLog.shared.write("[manuscript] addPart id=\(part.id) title=\(title)")
        return part
    }

    /// Overload that takes an explicit Part (used when seeding a
    /// part with chapters that already exist — e.g. import / undo).
    public func addPart(_ part: Part) {
        project.manuscript.parts.append(part)
        markChanged()
        DebugLog.shared.write("[manuscript] addPart id=\(part.id) (with \(part.chapters.count) chapters)")
    }

    public func updatePart(_ part: Part) {
        guard let idx = project.manuscript.parts.firstIndex(where: { $0.id == part.id }) else { return }
        project.manuscript.parts[idx] = part
        markChanged()
        DebugLog.shared.write("[manuscript] updatePart id=\(part.id)")
    }

    /// Removes a Part. Chapters inside it are dissolved — their
    /// scene ids fall back into `orphanedSceneIds` so the user
    /// can re-place them. The Phase 1 "scenes-without-chapters"
    /// fallback means no scene id ever disappears from the
    /// manuscript by accident.
    public func deletePart(id: UUID) {
        guard let idx = project.manuscript.parts.firstIndex(where: { $0.id == id }) else { return }
        let part = project.manuscript.parts.remove(at: idx)
        for chap in part.chapters {
            for sceneId in chap.sceneIds where !project.manuscript.orphanedSceneIds.contains(sceneId) {
                project.manuscript.orphanedSceneIds.append(sceneId)
            }
        }
        markChanged()
        DebugLog.shared.write("[manuscript] deletePart id=\(id)")
    }

    public func reorderParts(from: Int, to: Int) {
        var parts = project.manuscript.parts
        guard from != to, from >= 0, from < parts.count, to >= 0, to < parts.count else { return }
        let moved = parts.remove(at: from)
        parts.insert(moved, at: to)
        project.manuscript.parts = parts
        markChanged()
        DebugLog.shared.write("[manuscript] reorderParts \(from) → \(to)")
    }

    @discardableResult
    public func addChapter(title: String, in partId: UUID) -> Chapter? {
        guard let pIdx = project.manuscript.parts.firstIndex(where: { $0.id == partId }) else {
            DebugLog.shared.write("[manuscript] addChapter: stale partId \(partId)")
            return nil
        }
        let chap = Chapter(title: title)
        project.manuscript.parts[pIdx].chapters.append(chap)
        markChanged()
        DebugLog.shared.write("[manuscript] addChapter id=\(chap.id) in part=\(partId)")
        return chap
    }

    /// Overload that takes an explicit Chapter (mirrors addPart).
    public func addChapter(_ chapter: Chapter, in partId: UUID) {
        guard let pIdx = project.manuscript.parts.firstIndex(where: { $0.id == partId }) else { return }
        project.manuscript.parts[pIdx].chapters.append(chapter)
        markChanged()
    }

    public func updateChapter(_ chapter: Chapter) {
        for pIdx in project.manuscript.parts.indices {
            if let cIdx = project.manuscript.parts[pIdx].chapters.firstIndex(where: { $0.id == chapter.id }) {
                project.manuscript.parts[pIdx].chapters[cIdx] = chapter
                markChanged()
                DebugLog.shared.write("[manuscript] updateChapter id=\(chapter.id)")
                return
            }
        }
    }

    public func deleteChapter(id: UUID) {
        for pIdx in project.manuscript.parts.indices {
            if let cIdx = project.manuscript.parts[pIdx].chapters.firstIndex(where: { $0.id == id }) {
                let removed = project.manuscript.parts[pIdx].chapters.remove(at: cIdx)
                for sceneId in removed.sceneIds where !project.manuscript.orphanedSceneIds.contains(sceneId) {
                    project.manuscript.orphanedSceneIds.append(sceneId)
                }
                markChanged()
                DebugLog.shared.write("[manuscript] deleteChapter id=\(id)")
                return
            }
        }
    }

    /// Moves a scene id into the target chapter, removing it from
    /// any current chapter or from `orphanedSceneIds`. No-op when
    /// the chapter id is stale.
    public func placeScene(_ sceneId: UUID, in chapterId: UUID) {
        var targetPIdx: Int? = nil
        var targetCIdx: Int? = nil
        for pIdx in project.manuscript.parts.indices {
            if let cIdx = project.manuscript.parts[pIdx].chapters.firstIndex(where: { $0.id == chapterId }) {
                targetPIdx = pIdx
                targetCIdx = cIdx
                break
            }
        }
        guard let pIdx = targetPIdx, let cIdx = targetCIdx else { return }
        // Strip from any current location.
        for p in project.manuscript.parts.indices {
            for c in project.manuscript.parts[p].chapters.indices {
                project.manuscript.parts[p].chapters[c].sceneIds.removeAll(where: { $0 == sceneId })
            }
        }
        project.manuscript.orphanedSceneIds.removeAll(where: { $0 == sceneId })
        // Add to destination if not already there (the removeAll above
        // already cleared it).
        project.manuscript.parts[pIdx].chapters[cIdx].sceneIds.append(sceneId)
        markChanged()
        DebugLog.shared.write("[manuscript] placeScene \(sceneId) in chapter=\(chapterId)")
    }

    /// Moves a scene id out of any chapter back into orphanedSceneIds.
    public func unplaceScene(_ sceneId: UUID) {
        for p in project.manuscript.parts.indices {
            for c in project.manuscript.parts[p].chapters.indices {
                project.manuscript.parts[p].chapters[c].sceneIds.removeAll(where: { $0 == sceneId })
            }
        }
        if !project.manuscript.orphanedSceneIds.contains(sceneId) {
            project.manuscript.orphanedSceneIds.append(sceneId)
        }
        markChanged()
        DebugLog.shared.write("[manuscript] unplaceScene \(sceneId)")
    }

    // MARK: - Lorebook mutations (Phase 2 #8)

    @discardableResult
    public func addLorebookEntry(name: String) -> LorebookEntry {
        let entry = LorebookEntry(name: name)
        project.bible.lorebook.append(entry)
        markChanged()
        DebugLog.shared.write("[bible] addLorebookEntry id=\(entry.id) name=\(name)")
        return entry
    }

    public func updateLorebookEntry(_ entry: LorebookEntry) {
        guard let idx = project.bible.lorebook.firstIndex(where: { $0.id == entry.id }) else { return }
        project.bible.lorebook[idx] = entry
        markChanged()
        DebugLog.shared.write("[bible] updateLorebookEntry id=\(entry.id)")
    }

    public func deleteLorebookEntry(id: UUID) {
        guard let idx = project.bible.lorebook.firstIndex(where: { $0.id == id }) else { return }
        project.bible.lorebook.remove(at: idx)
        markChanged()
        DebugLog.shared.write("[bible] deleteLorebookEntry id=\(id)")
    }

    /// Phase 4 §14.1 #8 / LOOM_NSFW §2.5 — install (or top up) the
    /// Sphiratrioth starter pack. Additive by entry name: any pack
    /// entry whose `name` is NOT already present in the project's
    /// lorebook gets appended. Returns the number of entries added.
    /// Re-running is safe; user-deleted entries DO come back on the
    /// next install (no tombstones — install is "fill what's missing,"
    /// not "honour past deletions").
    @discardableResult
    public func installSphiratriothStarterPack() -> Int {
        let existingNames = Set(project.bible.lorebook.map { $0.name })
        var added = 0
        for template in SphiratriothStarterPack.entries where !existingNames.contains(template.name) {
            // Allocate a fresh UUID per install so the entry is the
            // user's to own (rename / delete / edit). The starter
            // pack template's UUID is per-process and not stable.
            var copy = template
            copy = LorebookEntry(
                id: UUID(),
                name: template.name,
                content: template.content,
                activationMode: template.activationMode,
                keys: template.keys,
                secondaryKeys: template.secondaryKeys,
                enabled: template.enabled,
                priority: template.priority,
                positionMode: template.positionMode,
                depth: template.depth,
                maxRecentScenesScanned: template.maxRecentScenesScanned,
                group: template.group,
                weight: template.weight,
                sticky: template.sticky
            )
            project.bible.lorebook.append(copy)
            added += 1
        }
        if added > 0 {
            markChanged()
            DebugLog.shared.write("[bible] installSphiratriothStarterPack added=\(added)")
        }
        return added
    }

    /// Phase 2 #7 — sets the prompt-injection mode for a Bible
    /// entity, irrespective of category. No-op if the ref is stale.
    public func setInjectionMode(_ mode: InjectionMode, for ref: BibleEntityRef) {
        switch ref.category {
        case .characters:
            guard var c = project.bible.characters.first(where: { $0.id == ref.id }) else { return }
            c.injectionMode = mode
            updateCharacter(c)
        case .settings:
            guard var s = project.bible.settings.first(where: { $0.id == ref.id }) else { return }
            s.injectionMode = mode
            updateSetting(s)
        case .objects:
            guard var o = project.bible.objects.first(where: { $0.id == ref.id }) else { return }
            o.injectionMode = mode
            updateObject(o)
        case .lorebook:
            // Phase 4 §14.1 #10. The popup never produces
            // `.vectorised` (Phase 5 R&D); map InjectionMode 1:1.
            guard var e = project.bible.lorebook.first(where: { $0.id == ref.id }) else { return }
            switch mode {
            case .constant: e.activationMode = .constant
            case .keyed:    e.activationMode = .keyed
            }
            updateLorebookEntry(e)
        }
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

    // MARK: - Project settings (Phase 2 Settings UI)

    public func setMemory(_ memory: String) {
        project.settings.memory = memory
        markDirty()
    }

    public func setAuthorsNote(_ note: String) {
        project.settings.authorsNote = note
        markDirty()
    }

    public func setAuthorsNoteDepthLines(_ lines: Int) {
        project.settings.authorsNoteDepthLines = max(0, lines)
        markDirty()
    }

    public func setContextBudgetTokens(_ tokens: Int) {
        project.settings.contextBudgetTokens = tokens
        markDirty()
    }

    public func setMaxOutputTokens(_ tokens: Int) {
        project.settings.generationDefaults.maxOutputTokens = tokens
        markDirty()
    }

    // MARK: - Project narrative-style + writing direction (Phase 2 #6)

    public func setPOV(_ pov: POVStyle) {
        project.settings.pov = pov
        markDirty()
    }

    public func setTense(_ tense: NarrativeTense) {
        project.settings.tense = tense
        markDirty()
    }

    public func setWritingDirectionKind(_ kind: DirectionKind) {
        project.settings.writingDirection.kind = kind
        markDirty()
    }

    public func setWritingDirectionRegister(_ register: VocabularyRegister) {
        project.settings.writingDirection.register = register
        markDirty()
    }

    public func setWritingDirectionExplicitness(_ level: ExplicitnessLevel) {
        project.settings.writingDirection.explicitnessLevel = level
        markDirty()
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

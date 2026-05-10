import Foundation
@testable import LoomCore

/// Sub-step 1.m — backup-on-save + recovery path. ProjectStorage
/// writes `project.json.bak` alongside `project.json` on every save;
/// when loadProject encounters a corrupt main file, the caller
/// (AppDelegate) inspects the backup and offers to restore.
func phase1ProjectCorruptionTests() -> TestSuite {
    let s = TestSuite("Phase1ProjectCorruption")

    s.test("saveProject writes a project.json.bak alongside project.json") {
        let dir = makeTempProjectURL()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = ProjectStorage()
        let project = try storage.createNewProject(at: dir, title: "WithBackup", author: nil)

        // First save creates project.json (no backup yet — nothing to back up).
        // Second save creates the backup from the previous project.json.
        try storage.saveProject(project, at: dir)

        let main = dir.appendingPathComponent("project.json")
        let backup = dir.appendingPathComponent("project.json.bak")
        try expectTrue(FileManager.default.fileExists(atPath: main.path))
        try expectTrue(FileManager.default.fileExists(atPath: backup.path))
    }

    s.test("loadProjectWithRecovery falls back to backup when main file is corrupt") {
        let dir = makeTempProjectURL()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = ProjectStorage()
        let project = try storage.createNewProject(at: dir, title: "Recovery", author: "K.A.")
        // Save once more so a backup exists.
        try storage.saveProject(project, at: dir)

        // Corrupt the main project.json.
        let main = dir.appendingPathComponent("project.json")
        try Data("{ this is not valid json }".utf8).write(to: main)

        // Plain loadProject must throw on the corrupt main.
        try expectThrows {
            _ = try storage.loadProject(from: dir)
        }

        // Recovery path: returns the backup-loaded Project.
        let recovered = try storage.loadProjectWithRecovery(from: dir)
        try expectEqual(recovered.project.title, "Recovery")
    }

    return s
}

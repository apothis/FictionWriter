import Foundation
@testable import LoomCore

/// Sub-step 1.l — pure tests for MarkdownExporter. Phase 1 ships a
/// flat scene list (no Parts/Chapters); each scene becomes a `## Title`
/// section with a YAML frontmatter at the top of the file.
func phase1MarkdownExportTests() -> TestSuite {
    let s = TestSuite("Phase1MarkdownExport")

    s.test("frontmatter has title, author, exportedAt") {
        var project = Project(title: "MyNovel", author: "K. Appleyard")
        project.manuscript.orphanedSceneIds = []
        let date = Date(timeIntervalSinceReferenceDate: 800_000_000)   // deterministic
        let out = MarkdownExporter.export(project: project, scenes: [:], exportedAt: date)
        try expectTrue(out.hasPrefix("---\n"), "must open with frontmatter")
        try expectTrue(out.contains("title: \"MyNovel\""))
        try expectTrue(out.contains("author: \"K. Appleyard\""))
        try expectTrue(out.contains("exportedAt: \""))
    }

    s.test("scenes appear in manuscript order") {
        var project = Project(title: "T")
        let s1 = Scene(id: UUID(), title: "Opening", prose: "First scene prose.")
        let s2 = Scene(id: UUID(), title: "Middle", prose: "Second scene prose.")
        let s3 = Scene(id: UUID(), title: "Ending", prose: "Third scene prose.")
        project.manuscript.orphanedSceneIds = [s1.id, s2.id, s3.id]
        let scenes = [s1.id: s1, s2.id: s2, s3.id: s3]

        let out = MarkdownExporter.export(project: project, scenes: scenes)
        let openIdx = try expectNotNil(out.range(of: "First scene prose.")?.lowerBound)
        let midIdx  = try expectNotNil(out.range(of: "Second scene prose.")?.lowerBound)
        let endIdx  = try expectNotNil(out.range(of: "Third scene prose.")?.lowerBound)
        try expectTrue(openIdx < midIdx)
        try expectTrue(midIdx < endIdx)
    }

    s.test("scene title is used as the section heading") {
        var project = Project(title: "T")
        let scene = Scene(id: UUID(), title: "Mia at the Door", prose: "She opened it.")
        project.manuscript.orphanedSceneIds = [scene.id]
        let out = MarkdownExporter.export(project: project, scenes: [scene.id: scene])
        try expectTrue(out.contains("## Mia at the Door"))
    }

    s.test("empty manuscript yields frontmatter only (no scene sections)") {
        let project = Project(title: "Empty")
        let out = MarkdownExporter.export(project: project, scenes: [:])
        try expectFalse(out.contains("## "))
    }

    s.test("missing author omits the author field from frontmatter") {
        var project = Project(title: "Anon", author: nil)
        project.manuscript.orphanedSceneIds = []
        let out = MarkdownExporter.export(project: project, scenes: [:])
        try expectFalse(out.contains("author:"))
        try expectTrue(out.contains("title: \"Anon\""))
    }

    s.test("scene prose preserved verbatim including blank lines") {
        var project = Project(title: "T")
        let prose = "First paragraph.\n\nSecond paragraph.\n\nThird paragraph."
        let scene = Scene(id: UUID(), title: "Multi", prose: prose)
        project.manuscript.orphanedSceneIds = [scene.id]
        let out = MarkdownExporter.export(project: project, scenes: [scene.id: scene])
        try expectTrue(out.contains(prose))
    }

    s.test("trailing newline after every scene so subsequent sections separate cleanly") {
        var project = Project(title: "T")
        let s1 = Scene(id: UUID(), title: "A", prose: "no newline at end")
        let s2 = Scene(id: UUID(), title: "B", prose: "another scene")
        project.manuscript.orphanedSceneIds = [s1.id, s2.id]
        let out = MarkdownExporter.export(project: project, scenes: [s1.id: s1, s2.id: s2])
        // Between the two scenes' headings, the prose of the first
        // must end with a newline so "## B" begins on its own line.
        let aHeader = out.range(of: "## A")!
        let bHeader = out.range(of: "## B")!
        let between = out[aHeader.upperBound..<bHeader.lowerBound]
        try expectTrue(between.contains("\n\n"), "scenes must be separated by blank lines")
    }

    return s
}

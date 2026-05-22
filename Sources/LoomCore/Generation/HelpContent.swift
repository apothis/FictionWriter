import Foundation

/// In-app help system — table-of-contents registry + markdown loader
/// for the help WKWebView panel.
///
/// **Design:** TOCs live inline in Swift (this file). Markdown bodies
/// live as bundled resources under
/// `Sources/LoomCore/Resources/help-content/{user,technical}/<id>.md`.
/// Adding a new section is a two-step change — register it here AND
/// drop a `.md` next to its peers. The author of the section owns
/// both steps; this lets the TOC carry per-section metadata (title,
/// order, group) the markdown body can't express.
///
/// **Why not frontmatter.** YAML-in-markdown lets non-engineers
/// reorder a TOC without touching Swift, but the only authors of
/// these docs are engineers, and inline-Swift gives us type-checked
/// registration + zero parse cost at load time.
public enum HelpContent {

    // MARK: - TOCs

    /// User Help — Getting Started + Reference halves per
    /// `docs/REFERENCE_PLAN.md` §"Book 1 — User Help".
    ///
    /// Phase B ships a single placeholder section. Real content lands
    /// in Phase C, where each section gets its own `.md` file and a
    /// new entry here.
    public static let userHelpTOC: [HelpSection] = [
        HelpSection(
            id: "welcome",
            title: "Welcome to Loom",
            book: .userHelp,
            order: 0,
            group: nil
        ),
        HelpSection(
            id: "getting-started-what-is-loom",
            title: "What Loom is",
            book: .userHelp,
            order: 1,
            group: "Getting Started"
        ),
        HelpSection(
            id: "getting-started-install",
            title: "Install + first launch",
            book: .userHelp,
            order: 2,
            group: "Getting Started"
        ),
        HelpSection(
            id: "getting-started-configure-servers",
            title: "Configure your model servers",
            book: .userHelp,
            order: 3,
            group: "Getting Started"
        ),
        HelpSection(
            id: "getting-started-first-project",
            title: "Your first project",
            book: .userHelp,
            order: 4,
            group: "Getting Started"
        ),
        HelpSection(
            id: "getting-started-first-scene",
            title: "Your first scene + first generation",
            book: .userHelp,
            order: 5,
            group: "Getting Started"
        ),
        HelpSection(
            id: "getting-started-when-generation-feels-off",
            title: "When generation refuses or feels off",
            book: .userHelp,
            order: 6,
            group: "Getting Started"
        ),
        HelpSection(
            id: "getting-started-where-files-live",
            title: "Where your work lives on disk",
            book: .userHelp,
            order: 7,
            group: "Getting Started"
        ),
        HelpSection(
            id: "editor-surface",
            title: "Editor surface",
            book: .userHelp,
            order: 90,
            group: "Reference"
        ),
        HelpSection(
            id: "generation-modes",
            title: "Generation modes",
            book: .userHelp,
            order: 100,
            group: "Reference"
        ),
        HelpSection(
            id: "authors-note-direction",
            title: "Author's Note, instructions, writing direction",
            book: .userHelp,
            order: 105,
            group: "Reference"
        ),
        HelpSection(
            id: "story-bible-entities",
            title: "Story Bible — Characters, Settings, Objects",
            book: .userHelp,
            order: 110,
            group: "Reference"
        ),
        HelpSection(
            id: "story-bible-lorebook",
            title: "Story Bible — Lorebook entries",
            book: .userHelp,
            order: 120,
            group: "Reference"
        ),
        HelpSection(
            id: "story-bible-dynamics",
            title: "Story Bible — Dynamics",
            book: .userHelp,
            order: 130,
            group: "Reference"
        ),
        HelpSection(
            id: "knowledge-ledger",
            title: "Knowledge ledger",
            book: .userHelp,
            order: 140,
            group: "Reference"
        ),
        HelpSection(
            id: "entity-discovery",
            title: "Entity discovery",
            book: .userHelp,
            order: 150,
            group: "Reference"
        ),
        HelpSection(
            id: "references",
            title: "References (style ingestion)",
            book: .userHelp,
            order: 160,
            group: "Reference"
        ),
        HelpSection(
            id: "scene-exemplars",
            title: "Scene exemplars + templates",
            book: .userHelp,
            order: 170,
            group: "Reference"
        ),
        HelpSection(
            id: "project-structure",
            title: "Project structure — Parts, Chapters, Scenes, Corkboard",
            book: .userHelp,
            order: 180,
            group: "Reference"
        ),
        HelpSection(
            id: "snapshots",
            title: "Snapshots + version history",
            book: .userHelp,
            order: 185,
            group: "Reference"
        ),
        HelpSection(
            id: "nsfw-posture",
            title: "NSFW / dark-fiction posture",
            book: .userHelp,
            order: 200,
            group: "Reference"
        ),
        HelpSection(
            id: "settings",
            title: "Settings — app-level + per-project",
            book: .userHelp,
            order: 210,
            group: "Reference"
        ),
        HelpSection(
            id: "anti-slop",
            title: "Anti-slop phrases",
            book: .userHelp,
            order: 220,
            group: "Reference"
        ),
        HelpSection(
            id: "sphiratrioth-power-user",
            title: "Sphiratrioth pack + power-user resources",
            book: .userHelp,
            order: 230,
            group: "Reference"
        ),
        HelpSection(
            id: "troubleshooting",
            title: "Troubleshooting",
            book: .userHelp,
            order: 900,
            group: "Reference"
        ),
    ]

    /// Technical Reference — engineer-facing architectural + per-
    /// subsystem documentation per `docs/REFERENCE_PLAN.md`
    /// §"Book 2 — Technical Reference".
    public static let technicalTOC: [HelpSection] = [
        HelpSection(
            id: "overview",
            title: "Architecture overview + runtime services",
            book: .technical,
            order: 10,
            group: nil
        ),
        HelpSection(
            id: "repo-layout",
            title: "Repo layout + module breakdown",
            book: .technical,
            order: 20,
            group: nil
        ),
        HelpSection(
            id: "data-model",
            title: "Data model",
            book: .technical,
            order: 30,
            group: nil
        ),
        HelpSection(
            id: "generation-pipeline",
            title: "Generation pipeline",
            book: .technical,
            order: 40,
            group: nil
        ),
        HelpSection(
            id: "style-retrieval",
            title: "Style retrieval + [STYLE EXEMPLARS] layer",
            book: .technical,
            order: 50,
            group: nil
        ),
        HelpSection(
            id: "extraction-pipelines",
            title: "Extraction pipelines",
            book: .technical,
            order: 60,
            group: nil
        ),
        HelpSection(
            id: "embeddings",
            title: "Embeddings",
            book: .technical,
            order: 70,
            group: nil
        ),
    ]

    public static func toc(for book: HelpBook) -> [HelpSection] {
        switch book {
        case .userHelp: return userHelpTOC
        case .technical: return technicalTOC
        }
    }

    // MARK: - Snapshot construction

    /// Build a snapshot for a given book + optional selection. The
    /// `markdownLookup` parameter is injectable so tests can supply a
    /// deterministic body without touching the bundle; production
    /// code passes `defaultMarkdownLookup`, which reads from the
    /// bundled `help-content/<book>/<id>.md` resource.
    public static func snapshot(
        book: HelpBook,
        selectedSectionId: String?,
        markdownLookup: (String, HelpBook) -> String? = HelpContent.defaultMarkdownLookup
    ) -> HelpSnapshot {
        let toc = HelpContent.toc(for: book)
        let id = selectedSectionId
        let markdown = id.flatMap { markdownLookup($0, book) }
        return HelpSnapshot(
            book: book,
            toc: toc,
            selectedSectionId: id,
            selectedSectionMarkdown: markdown
        )
    }

    // MARK: - Bundle-backed default loader

    /// Production markdown lookup. Reads
    /// `help-content/<book.rawValue>/<id>.md` from the LoomCore
    /// resource bundle. Returns `nil` for any missing / unreadable
    /// file — the caller (typically `snapshot`) carries the nil
    /// forward so the React side renders an "(no content yet)"
    /// placeholder rather than crashing.
    public static func defaultMarkdownLookup(_ id: String, _ book: HelpBook) -> String? {
        let subdir = "help-content/\(book.rawValue)"
        guard let url = Bundle.module.url(
                forResource: id,
                withExtension: "md",
                subdirectory: subdir),
              let data = try? Data(contentsOf: url),
              let str = String(data: data, encoding: .utf8)
        else { return nil }
        return str
    }
}

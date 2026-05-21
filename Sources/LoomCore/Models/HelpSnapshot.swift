import Foundation

// In-app reference help system — snapshot + intent shapes.
// Mirrors the Phase 4.5 Bible Workspace pattern: a separate WKWebView
// panel (`HelpWindowController`) with its own bridge (`HelpBridge`),
// its own JS global (`window.loomHelp.applySnapshot`), and its own
// message channel back to Swift.
//
// Two "books" live in the same panel — User Help (writers using
// Loom) and Technical Reference (engineers reading the code). The
// React side switches between them via a top-level book selector;
// the TOC re-renders per book, and the content area renders the
// markdown for the currently-selected section.
//
// Markdown content is bundled as `.md` files under
// `Sources/LoomCore/Resources/help-content/{user,technical}/<id>.md`
// — see `HelpContent` for the loader.

/// The two reference books rendered through the help panel.
public enum HelpBook: String, Codable, Equatable, CaseIterable {
    /// Writers using Loom — Getting Started + Reference halves.
    case userHelp = "user"
    /// Engineers reading the code — architecture, data model,
    /// pipelines, conventions.
    case technical = "technical"
}

/// One entry in a book's table of contents. Maps 1:1 to a markdown
/// file on disk (under `Resources/help-content/<book>/<id>.md`).
public struct HelpSection: Codable, Equatable {
    /// Stable section identifier. Used as the markdown filename
    /// (`<id>.md`) and as the React side's routing key. Should be
    /// kebab-case for legibility (e.g. `getting-started-install`).
    public let id: String
    /// User-visible title — what shows in the TOC.
    public let title: String
    /// Which book this section belongs to.
    public let book: HelpBook
    /// Sort order within the book. The TOC walks sections in
    /// ascending order. Different books have independent sequences.
    public let order: Int
    /// Optional grouping label. Sections sharing a group render
    /// under a group header in the TOC. `nil` for ungrouped.
    public let group: String?

    public init(
        id: String,
        title: String,
        book: HelpBook,
        order: Int,
        group: String? = nil
    ) {
        self.id = id
        self.title = title
        self.book = book
        self.order = order
        self.group = group
    }
}

/// The Swift → JS payload — everything the React side needs to
/// render the panel. The host pushes a fresh snapshot whenever the
/// book changes, the user picks a section, or content changes on
/// disk (live-reload during development).
public struct HelpSnapshot: Codable, Equatable {
    /// The currently-active book. The book switcher in the React
    /// side reads this to highlight the right tab.
    public var book: HelpBook
    /// The TOC for `book`, already ordered + filtered.
    public var toc: [HelpSection]
    /// The currently-selected section's id within `book`, or nil
    /// when nothing is selected (first launch or empty book).
    public var selectedSectionId: String?
    /// The markdown body of the currently-selected section, or nil
    /// when no section is selected.
    public var selectedSectionMarkdown: String?

    public init(
        book: HelpBook,
        toc: [HelpSection],
        selectedSectionId: String? = nil,
        selectedSectionMarkdown: String? = nil
    ) {
        self.book = book
        self.toc = toc
        self.selectedSectionId = selectedSectionId
        self.selectedSectionMarkdown = selectedSectionMarkdown
    }
}

/// The JS → Swift payload. The React side posts these to the host
/// via `webkit.messageHandlers.loomHelp.postMessage(...)` when the
/// user picks a section or switches books.
public enum HelpIntent: Codable, Equatable {
    /// User clicked a TOC entry. Carries the `book` so a stale
    /// snapshot (race after a `switchBook` that hasn't been
    /// applied yet) still routes the click correctly.
    case selectSection(sectionId: String, book: HelpBook)
    /// User clicked the book switcher.
    case switchBook(book: HelpBook)

    // Custom Codable: discriminated by a `kind` string field +
    // per-case payload fields. Matches the JS-side convention used
    // by `BibleWorkspaceIntent` so the React bridge has one shape
    // across both webviews.

    private enum CodingKeys: String, CodingKey {
        case kind, sectionId, book
    }

    private enum Kind: String {
        case selectSection
        case switchBook
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .selectSection(let sectionId, let book):
            try c.encode(Kind.selectSection.rawValue, forKey: .kind)
            try c.encode(sectionId, forKey: .sectionId)
            try c.encode(book, forKey: .book)
        case .switchBook(let book):
            try c.encode(Kind.switchBook.rawValue, forKey: .kind)
            try c.encode(book, forKey: .book)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kindStr = try c.decode(String.self, forKey: .kind)
        guard let kind = Kind(rawValue: kindStr) else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: c,
                debugDescription: "unknown HelpIntent kind \"\(kindStr)\"")
        }
        switch kind {
        case .selectSection:
            let sectionId = try c.decode(String.self, forKey: .sectionId)
            let book = try c.decode(HelpBook.self, forKey: .book)
            self = .selectSection(sectionId: sectionId, book: book)
        case .switchBook:
            let book = try c.decode(HelpBook.self, forKey: .book)
            self = .switchBook(book: book)
        }
    }
}

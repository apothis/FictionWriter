import Foundation
@testable import LoomCore

/// In-app help system — the snapshot/intent contract for the
/// `HelpWindowController` + `web/help/` WKWebView panel. Mirrors the
/// Phase 4.5 Bible Workspace pattern (separate webview, separate
/// global, snapshot-push + intent-post round-trip).
///
/// This test suite covers Chunk 1 of Phase B: the value types
/// (`HelpBook`, `HelpSection`, `HelpSnapshot`, `HelpIntent`) +
/// `HelpBridge` encode/decode. No view-controller wiring or webview
/// loading is exercised here — those land in Chunks 4+.
func helpSystemTests() -> TestSuite {
    let s = TestSuite("HelpSystem")

    // MARK: - HelpBook

    s.test("HelpBook has exactly two cases: userHelp + technical") {
        try expectEqual(Set(HelpBook.allCases.map(\.rawValue)),
                        ["user", "technical"])
    }

    s.test("HelpBook round-trips through Codable") {
        for book in HelpBook.allCases {
            let data = try JSONEncoder().encode(book)
            let decoded = try JSONDecoder().decode(HelpBook.self, from: data)
            try expectEqual(decoded, book)
        }
    }

    // MARK: - HelpSection

    s.test("HelpSection round-trips through Codable") {
        let section = HelpSection(
            id: "getting-started-install",
            title: "Install + first launch",
            book: .userHelp,
            order: 1,
            group: "Getting Started"
        )
        let data = try JSONEncoder().encode(section)
        let decoded = try JSONDecoder().decode(HelpSection.self, from: data)
        try expectEqual(decoded, section)
    }

    s.test("HelpSection allows a nil group (ungrouped sections)") {
        let section = HelpSection(
            id: "about",
            title: "About Loom",
            book: .userHelp,
            order: 0,
            group: nil
        )
        let data = try JSONEncoder().encode(section)
        let decoded = try JSONDecoder().decode(HelpSection.self, from: data)
        try expectEqual(decoded.group, nil)
    }

    // MARK: - HelpSnapshot

    s.test("HelpSnapshot round-trips through Codable with content") {
        let toc = [
            HelpSection(id: "a", title: "A", book: .userHelp, order: 0, group: nil),
            HelpSection(id: "b", title: "B", book: .userHelp, order: 1, group: "Group"),
        ]
        let snap = HelpSnapshot(
            book: .userHelp,
            toc: toc,
            selectedSectionId: "a",
            selectedSectionMarkdown: "# A\n\nThe A page."
        )
        let data = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(HelpSnapshot.self, from: data)
        try expectEqual(decoded, snap)
    }

    s.test("HelpSnapshot allows no selection (initial state)") {
        let snap = HelpSnapshot(
            book: .technical,
            toc: [],
            selectedSectionId: nil,
            selectedSectionMarkdown: nil
        )
        let data = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(HelpSnapshot.self, from: data)
        try expectEqual(decoded.selectedSectionId, nil)
        try expectEqual(decoded.selectedSectionMarkdown, nil)
    }

    // MARK: - HelpIntent

    s.test("HelpIntent.selectSection round-trips through Codable") {
        let intent = HelpIntent.selectSection(sectionId: "a", book: .userHelp)
        let data = try JSONEncoder().encode(intent)
        let decoded = try JSONDecoder().decode(HelpIntent.self, from: data)
        try expectEqual(decoded, intent)
    }

    s.test("HelpIntent.switchBook round-trips through Codable") {
        let intent = HelpIntent.switchBook(book: .technical)
        let data = try JSONEncoder().encode(intent)
        let decoded = try JSONDecoder().decode(HelpIntent.self, from: data)
        try expectEqual(decoded, intent)
    }

    // MARK: - HelpBridge encode

    s.test("HelpBridge.encodeSnapshotPush wraps JSON in the loomHelp global call") {
        let snap = HelpSnapshot(
            book: .userHelp,
            toc: [HelpSection(id: "a", title: "A", book: .userHelp, order: 0, group: nil)],
            selectedSectionId: nil,
            selectedSectionMarkdown: nil
        )
        let js = try HelpBridge.encodeSnapshotPush(snap)
        try expectTrue(js.hasPrefix("window.loomHelp.applySnapshot("),
                       "snapshot push must call window.loomHelp.applySnapshot")
        try expectTrue(js.hasSuffix(");"),
                       "snapshot push must end with `);`")
        // JSON payload sanity
        try expectTrue(js.contains("\"book\":\"user\""))
        try expectTrue(js.contains("\"id\":\"a\""))
    }

    s.test("HelpBridge.encodeSnapshotPush escapes U+2028 / U+2029 (pre-ES2019 JS safety)") {
        // Markdown content may legitimately contain these line separators
        // (they appear in some Unicode prose). Pre-ES2019 JS treats them
        // as illegal in string literals; defensive escape avoids breaking
        // the snapshot push if the WebView ever ran the payload through
        // `new Function(...)` or similar.
        let snap = HelpSnapshot(
            book: .userHelp,
            toc: [],
            selectedSectionId: "x",
            selectedSectionMarkdown: "line one\u{2028}line two\u{2029}line three"
        )
        let js = try HelpBridge.encodeSnapshotPush(snap)
        try expectFalse(js.contains("\u{2028}"),
                        "raw U+2028 must be escaped to \\u2028")
        try expectFalse(js.contains("\u{2029}"),
                        "raw U+2029 must be escaped to \\u2029")
        try expectTrue(js.contains("\\u2028"))
        try expectTrue(js.contains("\\u2029"))
    }

    // MARK: - HelpBridge decode

    s.test("HelpBridge.decodeIntent decodes selectSection JSON") {
        let json = #"{"kind":"selectSection","sectionId":"foo","book":"user"}"#
        let data = Data(json.utf8)
        let intent = try HelpBridge.decodeIntent(data)
        try expectEqual(intent, .selectSection(sectionId: "foo", book: .userHelp))
    }

    s.test("HelpBridge.decodeIntent decodes switchBook JSON") {
        let json = #"{"kind":"switchBook","book":"technical"}"#
        let data = Data(json.utf8)
        let intent = try HelpBridge.decodeIntent(data)
        try expectEqual(intent, .switchBook(book: .technical))
    }

    s.test("HelpBridge.decodeIntent throws on unknown kind") {
        let json = #"{"kind":"bogusIntent"}"#
        let data = Data(json.utf8)
        do {
            _ = try HelpBridge.decodeIntent(data)
            try expectFalse(true, "expected a throw on unknown intent kind")
        } catch {}
    }

    // MARK: - HelpContent — TOC + snapshot construction

    s.test("HelpContent.toc(for: .userHelp) returns the user-help TOC") {
        let toc = HelpContent.toc(for: .userHelp)
        try expectTrue(!toc.isEmpty, "user-help TOC must have at least one section")
        try expectTrue(toc.allSatisfy { $0.book == .userHelp },
                       "every entry must declare book == .userHelp")
    }

    s.test("HelpContent.toc(for: .technical) returns the technical TOC") {
        let toc = HelpContent.toc(for: .technical)
        try expectTrue(!toc.isEmpty, "technical TOC must have at least one section")
        try expectTrue(toc.allSatisfy { $0.book == .technical },
                       "every entry must declare book == .technical")
    }

    s.test("HelpContent.toc(for:) entries are sorted by ascending order") {
        for book in HelpBook.allCases {
            let toc = HelpContent.toc(for: book)
            let orders = toc.map(\.order)
            try expectEqual(orders, orders.sorted(),
                            "TOC for \(book.rawValue) must be in ascending order")
        }
    }

    s.test("HelpContent.snapshot with no selection has nil markdown") {
        let snap = HelpContent.snapshot(
            book: .userHelp,
            selectedSectionId: nil,
            markdownLookup: { _, _ in "should-not-be-called" }
        )
        try expectEqual(snap.book, .userHelp)
        try expectEqual(snap.selectedSectionId, nil)
        try expectEqual(snap.selectedSectionMarkdown, nil)
    }

    s.test("HelpContent.snapshot with a selection routes markdown through the injected lookup") {
        var calls: [(String, HelpBook)] = []
        let snap = HelpContent.snapshot(
            book: .userHelp,
            selectedSectionId: "welcome",
            markdownLookup: { id, book in
                calls.append((id, book))
                return "# Welcome\n\nHi."
            }
        )
        try expectEqual(snap.selectedSectionId, "welcome")
        try expectEqual(snap.selectedSectionMarkdown, "# Welcome\n\nHi.")
        try expectEqual(calls.count, 1)
        try expectEqual(calls[0].0, "welcome")
        try expectEqual(calls[0].1, .userHelp)
    }

    s.test("HelpContent.snapshot with a selection that returns nil leaves markdown nil") {
        let snap = HelpContent.snapshot(
            book: .technical,
            selectedSectionId: "missing-section",
            markdownLookup: { _, _ in nil }
        )
        try expectEqual(snap.selectedSectionId, "missing-section")
        try expectEqual(snap.selectedSectionMarkdown, nil)
    }

    s.test("HelpContent.snapshot carries the right TOC for the requested book") {
        let userSnap = HelpContent.snapshot(
            book: .userHelp, selectedSectionId: nil,
            markdownLookup: { _, _ in nil })
        try expectEqual(userSnap.toc, HelpContent.toc(for: .userHelp))
        let techSnap = HelpContent.snapshot(
            book: .technical, selectedSectionId: nil,
            markdownLookup: { _, _ in nil })
        try expectEqual(techSnap.toc, HelpContent.toc(for: .technical))
    }

    s.test("the default markdownLookup loads the user-help welcome section from the bundle") {
        // Production lookup goes through Bundle.module → the bundled
        // help-content/<book>/<id>.md resource. This test verifies the
        // bundling actually shipped a welcome.md for the user-help
        // placeholder section so the default snapshot has real
        // content to render in Phase B's smoke.
        let markdown = HelpContent.defaultMarkdownLookup("welcome", .userHelp)
        try expectNotNil(markdown)
        try expectTrue((markdown ?? "").contains("Welcome"),
                       "welcome.md must include the word 'Welcome'")
    }

    s.test("the default markdownLookup loads the technical overview section from the bundle") {
        let markdown = HelpContent.defaultMarkdownLookup("overview", .technical)
        try expectNotNil(markdown)
        try expectTrue((markdown ?? "").lowercased().contains("architecture") ||
                       (markdown ?? "").lowercased().contains("overview"),
                       "technical overview.md must include 'architecture' or 'overview'")
    }

    s.test("the default markdownLookup returns nil for a missing section") {
        let markdown = HelpContent.defaultMarkdownLookup("definitely-does-not-exist", .userHelp)
        try expectNil(markdown)
    }

    return s
}

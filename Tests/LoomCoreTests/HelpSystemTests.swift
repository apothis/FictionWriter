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

    return s
}

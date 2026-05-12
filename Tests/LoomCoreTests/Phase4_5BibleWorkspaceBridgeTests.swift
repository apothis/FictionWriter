import Foundation
@testable import LoomCore

/// Phase 4.5 §5.2 — Swift→JS push leg of the WKWebView bridge. The
/// snapshot is serialized to JSON and embedded directly as a JS
/// object literal inside a `window.loom.applySnapshot(...)` call.
/// JSON is a subset of valid JS object-literal syntax (modulo
/// U+2028/U+2029 in pre-ES2019, both fine on macOS 14+ WKWebView),
/// so this avoids the string-escaping dance we'd need if we
/// embedded the snapshot as a JS string literal.
///
/// The JS→Swift intent leg lands in Session 2 (CharacterPatch etc.)
/// — this suite only pins the Swift→JS direction.
func phase4_5BibleWorkspaceBridgeTests() -> TestSuite {
    let s = TestSuite("Phase4_5BibleWorkspaceBridge")

    s.test("encodeSnapshotPush wraps the JSON in window.loom.applySnapshot(...)") {
        let snap = BibleWorkspaceSnapshot(
            projectTitle: "Test", characters: [], lorebook: [], scenes: [], suggestions: []
        )
        let js = try BibleWorkspaceBridge.encodeSnapshotPush(snap)
        try expectTrue(js.hasPrefix("window.loom.applySnapshot("),
            "must start with the JS call prefix; got: \(js)")
        try expectTrue(js.hasSuffix(");"),
            "must end with );; got: \(js)")
    }

    s.test("encoded payload is the JSON-encoded snapshot (no extra escaping)") {
        let snap = BibleWorkspaceSnapshot(
            projectTitle: "Test", characters: [], lorebook: [], scenes: [], suggestions: []
        )
        let js = try BibleWorkspaceBridge.encodeSnapshotPush(snap)
        let prefix = "window.loom.applySnapshot("
        let suffix = ");"
        let middle = String(js.dropFirst(prefix.count).dropLast(suffix.count))
        // The middle must parse back as the original snapshot.
        let data = middle.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(BibleWorkspaceSnapshot.self, from: data)
        try expectEqual(decoded, snap)
    }

    s.test("encoded payload preserves character + lorebook content verbatim through round-trip") {
        let charId = UUID()
        let snap = BibleWorkspaceSnapshot(
            projectTitle: "Quoted",
            characters: [Character(
                id: charId,
                name: "Iris O'Brien",
                description: "She said \"hello\" and walked away.\nNew line."
            )],
            lorebook: [LorebookEntry(name: "rule:dialogue", content: "use straight quotes", keys: ["dialogue"])],
            scenes: [],
            suggestions: []
        )
        let js = try BibleWorkspaceBridge.encodeSnapshotPush(snap)
        let prefix = "window.loom.applySnapshot("
        let suffix = ");"
        let middle = String(js.dropFirst(prefix.count).dropLast(suffix.count))
        let data = middle.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(BibleWorkspaceSnapshot.self, from: data)
        try expectEqual(decoded, snap)
    }

    s.test("encoded payload escapes U+2028/U+2029 (legal in JSON, illegal in pre-ES2019 JS)") {
        // Modern WKWebView (macOS 14+, ES2022) accepts these directly,
        // but the encoder still escapes them defensively so older
        // targets and any future eval-via-Function constructor calls
        // don't trip on them. JSONEncoder doesn't escape these by
        // default — the bridge has to.
        let weird = "line1\u{2028}line2\u{2029}line3"
        let snap = BibleWorkspaceSnapshot(
            projectTitle: weird,
            characters: [], lorebook: [], scenes: [], suggestions: []
        )
        let js = try BibleWorkspaceBridge.encodeSnapshotPush(snap)
        try expectFalse(js.contains("\u{2028}"),
            "U+2028 must be replaced with \\u2028 in the payload")
        try expectFalse(js.contains("\u{2029}"),
            "U+2029 must be replaced with \\u2029 in the payload")
        try expectTrue(js.contains("\\u2028"),
            "expected literal \\u2028 escape; got: \(js)")
        try expectTrue(js.contains("\\u2029"),
            "expected literal \\u2029 escape; got: \(js)")
    }

    s.test("encoded payload is single-line (no embedded newlines that would break the JS statement)") {
        // We append `;` at the end and inject via evaluateJavaScript;
        // the call expression itself should be one statement.
        // JSON string values can contain \n in their escaped form,
        // which is fine — what we forbid is raw newlines inside the
        // JS source.
        let snap = BibleWorkspaceSnapshot(
            projectTitle: "Multi\nline\ntitle",
            characters: [], lorebook: [], scenes: [], suggestions: []
        )
        let js = try BibleWorkspaceBridge.encodeSnapshotPush(snap)
        try expectFalse(js.contains("\n"),
            "encoded JS must not contain literal newlines (they're escaped to \\n inside the JSON strings)")
    }

    return s
}

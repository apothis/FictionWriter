import Foundation

/// Phase 4.5 §5.2 — message marshalling for the Bible Workspace
/// WKWebView bridge. Static utilities, no instance state — the
/// instance-level state (web view ref, ProjectSession observer)
/// lives on `BibleWorkspaceWindowController`.
///
/// **Swift → JS** direction is the entire surface for Session 1:
/// `encodeSnapshotPush` produces a one-line JS statement that
/// calls `window.loom.applySnapshot(<json-object-literal>)` with
/// the snapshot inlined. The controller hands this to
/// `webView.evaluateJavaScript(...)`.
///
/// **JS → Swift** intent dispatch (Session 2+) will land here as a
/// `decodeIntent` static, paired with a `BibleWorkspaceIntent`
/// codable enum.
public enum BibleWorkspaceBridge {

    /// Serialise `snapshot` into a one-line JS call statement.
    /// JSON is a syntactic subset of JS object-literal notation,
    /// so we inline the JSON directly rather than embedding it as
    /// a JS string literal (which would force a second layer of
    /// escaping).
    ///
    /// JSONEncoder doesn't escape U+2028 / U+2029 by default; these
    /// are legal in JSON but illegal in pre-ES2019 JS string
    /// literals. Modern WKWebView (macOS 14+) targets ES2022 and
    /// accepts them, but we escape them defensively so the same
    /// payload would survive any future `new Function(...)` /
    /// `Function('return ' + payload)` use site too.
    public static func encodeSnapshotPush(_ snapshot: BibleWorkspaceSnapshot) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(snapshot)
        var json = String(data: data, encoding: .utf8) ?? "{}"
        json = json.replacingOccurrences(of: "\u{2028}", with: "\\u2028")
        json = json.replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        return "window.loom.applySnapshot(\(json));"
    }
}

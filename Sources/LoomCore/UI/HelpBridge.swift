import Foundation

/// Message marshalling for the in-app Help panel's WKWebView bridge.
/// Mirrors `BibleWorkspaceBridge` — static utilities, no instance
/// state. The window controller owns the instance-level state (web
/// view ref, observers); this enum is the wire-format codec.
///
/// **Swift → JS:** `encodeSnapshotPush` produces a one-line JS
/// statement that calls `window.loomHelp.applySnapshot(<json>)` with
/// the snapshot inlined as a JS object literal. The window controller
/// hands this to `webView.evaluateJavaScript(...)`.
///
/// **JS → Swift:** `decodeIntent` parses a JSON payload posted from
/// the React side via the `loomHelp` `WKScriptMessageHandler` and
/// returns a typed `HelpIntent`. JSON wire format uses a `kind`
/// discriminator + per-case payload fields, matching the convention
/// used by `BibleWorkspaceBridge` so the JS-side bridge code shares a
/// shape across both webviews.
public enum HelpBridge {

    /// Serialise `snapshot` into a one-line JS call statement.
    /// JSON is a syntactic subset of JS object-literal notation, so
    /// we inline the JSON directly rather than embedding it as a JS
    /// string literal (which would force a second layer of
    /// escaping).
    ///
    /// JSONEncoder doesn't escape U+2028 / U+2029 by default; these
    /// are legal in JSON but illegal in pre-ES2019 JS string
    /// literals. We escape them defensively so the payload would
    /// survive any future `new Function(...)` use site, even though
    /// modern WKWebView (macOS 14+) accepts them.
    public static func encodeSnapshotPush(_ snapshot: HelpSnapshot) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(snapshot)
        var json = String(data: data, encoding: .utf8) ?? "{}"
        json = json.replacingOccurrences(of: "\u{2028}", with: "\\u2028")
        json = json.replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        return "window.loomHelp.applySnapshot(\(json));"
    }

    /// Decode a JSON payload received from the WKWebView's `loomHelp`
    /// message handler into a typed intent. Throws on missing /
    /// unknown `kind` discriminator or malformed payload. The caller
    /// (the window controller's `userContentController(_:didReceive:)`)
    /// catches + logs decoding errors rather than crashing — the JS
    /// side might send malformed intents during development or after
    /// a schema mismatch, neither of which should kill the app.
    public static func decodeIntent(_ data: Data) throws -> HelpIntent {
        try JSONDecoder().decode(HelpIntent.self, from: data)
    }
}

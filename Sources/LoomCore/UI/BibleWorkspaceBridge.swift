import Foundation

/// Phase 4.5 §5.2 — message marshalling for the Bible Workspace
/// WKWebView bridge. Static utilities, no instance state — the
/// instance-level state (web view ref, ProjectSession observer)
/// lives on `BibleWorkspaceWindowController`.
///
/// **Swift → JS**: `encodeSnapshotPush` produces a one-line JS
/// statement that calls `window.loom.applySnapshot(<json-object-literal>)`
/// with the snapshot inlined. The controller hands this to
/// `webView.evaluateJavaScript(...)`.
///
/// **JS → Swift**: `decodeIntent` parses a JSON payload posted from
/// the web side via `WKScriptMessageHandler` and returns a typed
/// `BibleWorkspaceIntent`. The controller dispatches each case to
/// the appropriate `ProjectSession` mutator. JSON wire format uses
/// a `kind` discriminator string + per-case payload fields, matching
/// the JS-side convention in `web/bible-workspace/src/bridge.ts`.
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

    /// Decode a JSON payload received from the WKWebView's
    /// `loom` message handler into a typed intent. Throws on
    /// missing/unknown `kind` discriminator or malformed
    /// case-specific payload. The caller (`BibleWorkspaceWindowController.userContentController(_:didReceive:)`)
    /// catches + logs decoding errors rather than crashing — the
    /// JS side might send malformed intents during development
    /// or after a schema mismatch, neither of which should kill
    /// the app.
    public static func decodeIntent(_ data: Data) throws -> BibleWorkspaceIntent {
        try JSONDecoder().decode(BibleWorkspaceIntent.self, from: data)
    }
}

/// Phase 4.5 §5.2 — typed intents posted from the React side back
/// to Swift. Each case maps to a `ProjectSession` mutator (or a
/// queue mutator in the case of suggestions). Session 2 ships
/// `.patchCharacter`; subsequent sessions extend the enum.
///
/// Wire format uses a `kind: String` discriminator + per-case
/// fields at the top level (rather than the Swift-synthesized
/// `{"caseName": {...}}` form), because (a) it's the conventional
/// shape for JS/TypeScript discriminated unions and (b) it matches
/// what `web/bible-workspace/src/bridge.ts` builds.
public enum BibleWorkspaceIntent: Codable, Equatable {
    case patchCharacter(id: UUID, patch: CharacterPatch)

    private enum CodingKeys: String, CodingKey {
        case kind, id, patch
    }

    private enum Kind: String {
        case patchCharacter
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .patchCharacter(let id, let patch):
            try c.encode(Kind.patchCharacter.rawValue, forKey: .kind)
            try c.encode(id, forKey: .id)
            try c.encode(patch, forKey: .patch)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawKind = try c.decode(String.self, forKey: .kind)
        guard let kind = Kind(rawValue: rawKind) else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown BibleWorkspaceIntent kind: \(rawKind)"
                )
            )
        }
        switch kind {
        case .patchCharacter:
            let id = try c.decode(UUID.self, forKey: .id)
            let patch = try c.decode(CharacterPatch.self, forKey: .patch)
            self = .patchCharacter(id: id, patch: patch)
        }
    }
}

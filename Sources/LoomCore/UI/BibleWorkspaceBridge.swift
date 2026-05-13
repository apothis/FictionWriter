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
    case patchLorebookEntry(id: UUID, patch: LorebookEntryPatch)
    case addLorebookEntry(name: String)
    case deleteLorebookEntry(id: UUID)
    case deleteKnownFact(characterId: UUID, sceneId: UUID, factId: UUID)
    case acceptSuggestion(factId: UUID)
    case rejectSuggestion(factId: UUID)
    // Phase 5 production A2.1 — reference-text CRUD + ingest trigger.
    case createReference(name: String)
    case patchReference(id: UUID, patch: ReferencePatch)
    case deleteReference(id: UUID)
    case ingestReference(id: UUID)
    // Phase 7.b.5 — template-scene CRUD + extract trigger.
    case createTemplateScene(name: String)
    case patchTemplateScene(id: UUID, patch: TemplateScenePatch)
    case deleteTemplateScene(id: UUID)
    case extractTemplateScene(id: UUID)

    private enum CodingKeys: String, CodingKey {
        case kind, id, patch, name, characterId, sceneId, factId
    }

    private enum Kind: String {
        case patchCharacter
        case patchLorebookEntry
        case addLorebookEntry
        case deleteLorebookEntry
        case deleteKnownFact
        case acceptSuggestion
        case rejectSuggestion
        case createReference
        case patchReference
        case deleteReference
        case ingestReference
        case createTemplateScene
        case patchTemplateScene
        case deleteTemplateScene
        case extractTemplateScene
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .patchCharacter(let id, let patch):
            try c.encode(Kind.patchCharacter.rawValue, forKey: .kind)
            try c.encode(id, forKey: .id)
            try c.encode(patch, forKey: .patch)
        case .patchLorebookEntry(let id, let patch):
            try c.encode(Kind.patchLorebookEntry.rawValue, forKey: .kind)
            try c.encode(id, forKey: .id)
            try c.encode(patch, forKey: .patch)
        case .addLorebookEntry(let name):
            try c.encode(Kind.addLorebookEntry.rawValue, forKey: .kind)
            try c.encode(name, forKey: .name)
        case .deleteLorebookEntry(let id):
            try c.encode(Kind.deleteLorebookEntry.rawValue, forKey: .kind)
            try c.encode(id, forKey: .id)
        case .deleteKnownFact(let characterId, let sceneId, let factId):
            try c.encode(Kind.deleteKnownFact.rawValue, forKey: .kind)
            try c.encode(characterId, forKey: .characterId)
            try c.encode(sceneId, forKey: .sceneId)
            try c.encode(factId, forKey: .factId)
        case .acceptSuggestion(let factId):
            try c.encode(Kind.acceptSuggestion.rawValue, forKey: .kind)
            try c.encode(factId, forKey: .factId)
        case .rejectSuggestion(let factId):
            try c.encode(Kind.rejectSuggestion.rawValue, forKey: .kind)
            try c.encode(factId, forKey: .factId)
        case .createReference(let name):
            try c.encode(Kind.createReference.rawValue, forKey: .kind)
            try c.encode(name, forKey: .name)
        case .patchReference(let id, let patch):
            try c.encode(Kind.patchReference.rawValue, forKey: .kind)
            try c.encode(id, forKey: .id)
            try c.encode(patch, forKey: .patch)
        case .deleteReference(let id):
            try c.encode(Kind.deleteReference.rawValue, forKey: .kind)
            try c.encode(id, forKey: .id)
        case .ingestReference(let id):
            try c.encode(Kind.ingestReference.rawValue, forKey: .kind)
            try c.encode(id, forKey: .id)
        case .createTemplateScene(let name):
            try c.encode(Kind.createTemplateScene.rawValue, forKey: .kind)
            try c.encode(name, forKey: .name)
        case .patchTemplateScene(let id, let patch):
            try c.encode(Kind.patchTemplateScene.rawValue, forKey: .kind)
            try c.encode(id, forKey: .id)
            try c.encode(patch, forKey: .patch)
        case .deleteTemplateScene(let id):
            try c.encode(Kind.deleteTemplateScene.rawValue, forKey: .kind)
            try c.encode(id, forKey: .id)
        case .extractTemplateScene(let id):
            try c.encode(Kind.extractTemplateScene.rawValue, forKey: .kind)
            try c.encode(id, forKey: .id)
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
        case .patchLorebookEntry:
            let id = try c.decode(UUID.self, forKey: .id)
            let patch = try c.decode(LorebookEntryPatch.self, forKey: .patch)
            self = .patchLorebookEntry(id: id, patch: patch)
        case .addLorebookEntry:
            let name = try c.decode(String.self, forKey: .name)
            self = .addLorebookEntry(name: name)
        case .deleteLorebookEntry:
            let id = try c.decode(UUID.self, forKey: .id)
            self = .deleteLorebookEntry(id: id)
        case .deleteKnownFact:
            let characterId = try c.decode(UUID.self, forKey: .characterId)
            let sceneId = try c.decode(UUID.self, forKey: .sceneId)
            let factId = try c.decode(UUID.self, forKey: .factId)
            self = .deleteKnownFact(characterId: characterId, sceneId: sceneId, factId: factId)
        case .acceptSuggestion:
            let factId = try c.decode(UUID.self, forKey: .factId)
            self = .acceptSuggestion(factId: factId)
        case .rejectSuggestion:
            let factId = try c.decode(UUID.self, forKey: .factId)
            self = .rejectSuggestion(factId: factId)
        case .createReference:
            let name = try c.decode(String.self, forKey: .name)
            self = .createReference(name: name)
        case .patchReference:
            let id = try c.decode(UUID.self, forKey: .id)
            let patch = try c.decode(ReferencePatch.self, forKey: .patch)
            self = .patchReference(id: id, patch: patch)
        case .deleteReference:
            let id = try c.decode(UUID.self, forKey: .id)
            self = .deleteReference(id: id)
        case .ingestReference:
            let id = try c.decode(UUID.self, forKey: .id)
            self = .ingestReference(id: id)
        case .createTemplateScene:
            let name = try c.decode(String.self, forKey: .name)
            self = .createTemplateScene(name: name)
        case .patchTemplateScene:
            let id = try c.decode(UUID.self, forKey: .id)
            let patch = try c.decode(TemplateScenePatch.self, forKey: .patch)
            self = .patchTemplateScene(id: id, patch: patch)
        case .deleteTemplateScene:
            let id = try c.decode(UUID.self, forKey: .id)
            self = .deleteTemplateScene(id: id)
        case .extractTemplateScene:
            let id = try c.decode(UUID.self, forKey: .id)
            self = .extractTemplateScene(id: id)
        }
    }
}

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

    /// Planned Project mode — the Swift→JS snapshot push for the
    /// guided-creation wizard bundle. Mirrors `encodeSnapshotPush`
    /// (JSON inlined as a JS object literal) but targets the wizard's
    /// namespaced global, `window.loomWizard.applyPlannedSnapshot`.
    public static func encodePlannedSnapshotPush(
        _ snapshot: PlannedProjectSnapshot
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(snapshot)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        return "window.loomWizard.applyPlannedSnapshot(\(escapeSeparators(json)));"
    }

    /// P2 project-tools bundle — Swift→JS snapshot push for the
    /// scene-framing / anti-slop webview. Targets the bundle's
    /// namespaced global, `window.loomTools.applyToolsSnapshot`.
    public static func encodeProjectToolsSnapshotPush(
        _ snapshot: ProjectToolsSnapshot
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(snapshot)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        return "window.loomTools.applyToolsSnapshot(\(escapeSeparators(json)));"
    }

    /// Phase 4 — the Swift→JS reply leg for request/reply intents
    /// (`generateOutline`, `createPlannedProject`). Produces a
    /// one-line `window.loomWizard.resolveReply(<envelope>)` call; the JS
    /// bridge's promise map keys off `requestId`. Success carries a
    /// JSON-encoded `value`; the wrapping object is built so the JSON
    /// is inlined as a JS object literal, the same way
    /// `encodeSnapshotPush` avoids a string-literal escaping layer.
    public static func encodeReply<V: Encodable>(
        requestId: String, value: V
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let valueData = try encoder.encode(value)
        let valueJSON = String(data: valueData, encoding: .utf8) ?? "null"
        let envelope = """
        {"requestId":\(jsStringLiteral(requestId)),"ok":true,"value":\(valueJSON)}
        """
        return "window.loomWizard.resolveReply(\(escapeSeparators(envelope)));"
    }

    /// The failure counterpart of `encodeReply` — `ok:false` with a
    /// human-readable `error` message. Non-throwing: the message is
    /// the only dynamic part and is escaped as a JSON string.
    public static func encodeReplyError(requestId: String, message: String) -> String {
        let envelope = """
        {"requestId":\(jsStringLiteral(requestId)),"ok":false,"error":\(jsStringLiteral(message))}
        """
        return "window.loomWizard.resolveReply(\(escapeSeparators(envelope)));"
    }

    /// Encode a Swift string as a JSON string literal (quotes +
    /// escaping). Routed through JSONEncoder so control characters,
    /// quotes and backslashes are handled correctly.
    private static func jsStringLiteral(_ s: String) -> String {
        let data = (try? JSONEncoder().encode(s)) ?? Data("\"\"".utf8)
        return String(data: data, encoding: .utf8) ?? "\"\""
    }

    /// U+2028/U+2029 are legal JSON but unsafe in pre-ES2019 JS — the
    /// same defensive escape `encodeSnapshotPush` applies.
    private static func escapeSeparators(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
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
    // P2b — Dynamic Sheet CRUD from the bible-workspace webview.
    case addDynamicSheet(name: String)
    case patchDynamicSheet(id: UUID, patch: DynamicSheetPatch)
    case deleteDynamicSheet(id: UUID)
    // P2 project-tools webview — per-scene framing + anti-slop list.
    case setSceneFraming(sceneId: UUID, framing: String)
    case setAntiSlopPhrases(phrases: [String])
    // Per-scene deterministic undress markers (intimate-anatomy gate).
    case setSceneUndressed(sceneId: UUID, characterIds: [UUID])
    // AO3-style work framing — content elements + authorial stance.
    case setWorkFraming(elements: [FramedElement])
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
    // Phase 8.b.6 — unified scene-exemplar surface. Each operation
    // touches BOTH the Reference and the Template under the shared
    // UUID. `create` writes new disk objects; `patch` applies the
    // same field change to both; `delete` removes both; `ingest`
    // fans out to ingestReference + extractTemplateScene.
    case createSceneExemplar(name: String, body: String, nsfw: Bool)
    case patchSceneExemplar(id: UUID, patch: SceneExemplarPatch)
    case deleteSceneExemplar(id: UUID)
    case ingestSceneExemplar(id: UUID)
    // Phase 9 entity-discovery — accept/reject a proposed entity
    // from the EntityProposalsQueue webview. Accept commits the
    // proposal as a real Character or Setting (with any user edits
    // applied) and attaches its facts to the bible row; reject
    // drops the proposal from the store.
    case acceptEntityProposal(proposalId: UUID, accepted: ProposedEntityAcceptance)
    case rejectEntityProposal(proposalId: UUID)
    // Phase 10 Part B/2 — accept/reject a proposed relationship from
    // the RelationshipProposalsQueue webview. Accept resolves the
    // proposal's from/to names to bible Character UUIDs, merges the
    // edge via `RelationshipConflict.applyAccepted`, and removes the
    // proposal. `demoteConflicting` carries the user's answer to the
    // demote-prior-partner confirm dialog.
    case acceptRelationshipProposal(proposalId: UUID, demoteConflicting: Bool)
    case rejectRelationshipProposal(proposalId: UUID)
    // Relationship-map mapper — the user dragged a character node to
    // a new position. Persisted to the relationship-map-layout
    // sidecar; not echoed back in a snapshot (view-owned state).
    case setRelationshipNodePosition(characterId: UUID, x: Double, y: Double)
    // Relationship-map mapper — create or update a directed edge by
    // drawing/editing it on the map. Upserts on the from-character
    // via `RelationshipConflict.applyAccepted` (so a manual romantic
    // edge demotes a prior current one, same as accepting a proposal).
    case setRelationshipEdge(
        fromCharacterId: UUID, toCharacterId: UUID,
        edgeKind: String, status: String, notes: String
    )
    // Relationship-map mapper — remove the directed edge identified
    // by (from, to, kind).
    case deleteRelationshipEdge(fromCharacterId: UUID, toCharacterId: UUID, edgeKind: String)
    // Planned Project mode Phase 4 — the guided-creation wizard.
    // Both carry a `requestId` so the JS `postRequest` promise map
    // can pair the async `resolveReply` (the existing intents are
    // fire-and-forget + snapshot-echo; these are request/reply).
    // `generateOutline` runs the staged outline pipeline on the
    // writer model and replies with a `GeneratedOutline`;
    // `createPlannedProject` carries the user-edited outline to disk.
    case generateOutline(requestId: String, config: PlannedProjectConfig)
    case createPlannedProject(
        requestId: String, title: String,
        config: PlannedProjectConfig, outline: OutlineGeneration.GeneratedOutline
    )
    // Planned Project mode Phase 4 item 4 — the style-library editor.
    // Fire-and-forget CRUD against the app-level style library
    // (`styles.json`); `upsertStyle` creates or replaces by id. The
    // wizard window re-pushes its snapshot after applying.
    case upsertStyle(style: Style)
    case deleteStyle(id: UUID)
    // Posted by the style-library editor's "Done" button when it runs
    // as a standalone window (opened from the menu, not inside the
    // wizard). The host closes the window.
    case closeWizardWindow

    private enum CodingKeys: String, CodingKey {
        case kind, id, patch, name, characterId, sceneId, factId
        case body, nsfw, framing, phrases, characterIds, workFraming
        case proposalId, accepted, demoteConflicting
        case x, y
        case fromCharacterId, toCharacterId, edgeKind, status, notes
        case requestId, config, title, outline
        case style
    }

    private enum Kind: String {
        case patchCharacter
        case patchLorebookEntry
        case addLorebookEntry
        case deleteLorebookEntry
        case addDynamicSheet
        case patchDynamicSheet
        case deleteDynamicSheet
        case setSceneFraming
        case setAntiSlopPhrases
        case setSceneUndressed
        case setWorkFraming
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
        case createSceneExemplar
        case patchSceneExemplar
        case deleteSceneExemplar
        case ingestSceneExemplar
        case acceptEntityProposal
        case rejectEntityProposal
        case acceptRelationshipProposal
        case rejectRelationshipProposal
        case setRelationshipNodePosition
        case setRelationshipEdge
        case deleteRelationshipEdge
        case generateOutline
        case createPlannedProject
        case upsertStyle
        case deleteStyle
        case closeWizardWindow
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
        case .addDynamicSheet(let name):
            try c.encode(Kind.addDynamicSheet.rawValue, forKey: .kind)
            try c.encode(name, forKey: .name)
        case .patchDynamicSheet(let id, let patch):
            try c.encode(Kind.patchDynamicSheet.rawValue, forKey: .kind)
            try c.encode(id, forKey: .id)
            try c.encode(patch, forKey: .patch)
        case .deleteDynamicSheet(let id):
            try c.encode(Kind.deleteDynamicSheet.rawValue, forKey: .kind)
            try c.encode(id, forKey: .id)
        case .setSceneFraming(let sceneId, let framing):
            try c.encode(Kind.setSceneFraming.rawValue, forKey: .kind)
            try c.encode(sceneId, forKey: .sceneId)
            try c.encode(framing, forKey: .framing)
        case .setAntiSlopPhrases(let phrases):
            try c.encode(Kind.setAntiSlopPhrases.rawValue, forKey: .kind)
            try c.encode(phrases, forKey: .phrases)
        case .setSceneUndressed(let sceneId, let characterIds):
            try c.encode(Kind.setSceneUndressed.rawValue, forKey: .kind)
            try c.encode(sceneId, forKey: .sceneId)
            try c.encode(characterIds, forKey: .characterIds)
        case .setWorkFraming(let elements):
            try c.encode(Kind.setWorkFraming.rawValue, forKey: .kind)
            try c.encode(elements, forKey: .workFraming)
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
        case .createSceneExemplar(let name, let body, let nsfw):
            try c.encode(Kind.createSceneExemplar.rawValue, forKey: .kind)
            try c.encode(name, forKey: .name)
            try c.encode(body, forKey: .body)
            try c.encode(nsfw, forKey: .nsfw)
        case .patchSceneExemplar(let id, let patch):
            try c.encode(Kind.patchSceneExemplar.rawValue, forKey: .kind)
            try c.encode(id, forKey: .id)
            try c.encode(patch, forKey: .patch)
        case .deleteSceneExemplar(let id):
            try c.encode(Kind.deleteSceneExemplar.rawValue, forKey: .kind)
            try c.encode(id, forKey: .id)
        case .ingestSceneExemplar(let id):
            try c.encode(Kind.ingestSceneExemplar.rawValue, forKey: .kind)
            try c.encode(id, forKey: .id)
        case .acceptEntityProposal(let proposalId, let accepted):
            try c.encode(Kind.acceptEntityProposal.rawValue, forKey: .kind)
            try c.encode(proposalId, forKey: .proposalId)
            try c.encode(accepted, forKey: .accepted)
        case .rejectEntityProposal(let proposalId):
            try c.encode(Kind.rejectEntityProposal.rawValue, forKey: .kind)
            try c.encode(proposalId, forKey: .proposalId)
        case .acceptRelationshipProposal(let proposalId, let demoteConflicting):
            try c.encode(Kind.acceptRelationshipProposal.rawValue, forKey: .kind)
            try c.encode(proposalId, forKey: .proposalId)
            try c.encode(demoteConflicting, forKey: .demoteConflicting)
        case .rejectRelationshipProposal(let proposalId):
            try c.encode(Kind.rejectRelationshipProposal.rawValue, forKey: .kind)
            try c.encode(proposalId, forKey: .proposalId)
        case .setRelationshipNodePosition(let characterId, let x, let y):
            try c.encode(Kind.setRelationshipNodePosition.rawValue, forKey: .kind)
            try c.encode(characterId, forKey: .characterId)
            try c.encode(x, forKey: .x)
            try c.encode(y, forKey: .y)
        case .setRelationshipEdge(let fromId, let toId, let edgeKind, let status, let notes):
            try c.encode(Kind.setRelationshipEdge.rawValue, forKey: .kind)
            try c.encode(fromId, forKey: .fromCharacterId)
            try c.encode(toId, forKey: .toCharacterId)
            try c.encode(edgeKind, forKey: .edgeKind)
            try c.encode(status, forKey: .status)
            try c.encode(notes, forKey: .notes)
        case .deleteRelationshipEdge(let fromId, let toId, let edgeKind):
            try c.encode(Kind.deleteRelationshipEdge.rawValue, forKey: .kind)
            try c.encode(fromId, forKey: .fromCharacterId)
            try c.encode(toId, forKey: .toCharacterId)
            try c.encode(edgeKind, forKey: .edgeKind)
        case .generateOutline(let requestId, let config):
            try c.encode(Kind.generateOutline.rawValue, forKey: .kind)
            try c.encode(requestId, forKey: .requestId)
            try c.encode(config, forKey: .config)
        case .createPlannedProject(let requestId, let title, let config, let outline):
            try c.encode(Kind.createPlannedProject.rawValue, forKey: .kind)
            try c.encode(requestId, forKey: .requestId)
            try c.encode(title, forKey: .title)
            try c.encode(config, forKey: .config)
            try c.encode(outline, forKey: .outline)
        case .upsertStyle(let style):
            try c.encode(Kind.upsertStyle.rawValue, forKey: .kind)
            try c.encode(style, forKey: .style)
        case .deleteStyle(let id):
            try c.encode(Kind.deleteStyle.rawValue, forKey: .kind)
            try c.encode(id, forKey: .id)
        case .closeWizardWindow:
            try c.encode(Kind.closeWizardWindow.rawValue, forKey: .kind)
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
        case .addDynamicSheet:
            let name = try c.decode(String.self, forKey: .name)
            self = .addDynamicSheet(name: name)
        case .patchDynamicSheet:
            let id = try c.decode(UUID.self, forKey: .id)
            let patch = try c.decode(DynamicSheetPatch.self, forKey: .patch)
            self = .patchDynamicSheet(id: id, patch: patch)
        case .deleteDynamicSheet:
            let id = try c.decode(UUID.self, forKey: .id)
            self = .deleteDynamicSheet(id: id)
        case .setSceneFraming:
            let sceneId = try c.decode(UUID.self, forKey: .sceneId)
            let framing = try c.decode(String.self, forKey: .framing)
            self = .setSceneFraming(sceneId: sceneId, framing: framing)
        case .setAntiSlopPhrases:
            let phrases = try c.decode([String].self, forKey: .phrases)
            self = .setAntiSlopPhrases(phrases: phrases)
        case .setSceneUndressed:
            let sceneId = try c.decode(UUID.self, forKey: .sceneId)
            let characterIds = try c.decode([UUID].self, forKey: .characterIds)
            self = .setSceneUndressed(sceneId: sceneId, characterIds: characterIds)
        case .setWorkFraming:
            let elements = try c.decode([FramedElement].self, forKey: .workFraming)
            self = .setWorkFraming(elements: elements)
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
        case .createSceneExemplar:
            let name = try c.decode(String.self, forKey: .name)
            let body = try c.decode(String.self, forKey: .body)
            let nsfw = try c.decode(Bool.self, forKey: .nsfw)
            self = .createSceneExemplar(name: name, body: body, nsfw: nsfw)
        case .patchSceneExemplar:
            let id = try c.decode(UUID.self, forKey: .id)
            let patch = try c.decode(SceneExemplarPatch.self, forKey: .patch)
            self = .patchSceneExemplar(id: id, patch: patch)
        case .deleteSceneExemplar:
            let id = try c.decode(UUID.self, forKey: .id)
            self = .deleteSceneExemplar(id: id)
        case .ingestSceneExemplar:
            let id = try c.decode(UUID.self, forKey: .id)
            self = .ingestSceneExemplar(id: id)
        case .acceptEntityProposal:
            let proposalId = try c.decode(UUID.self, forKey: .proposalId)
            let accepted = try c.decode(ProposedEntityAcceptance.self, forKey: .accepted)
            self = .acceptEntityProposal(proposalId: proposalId, accepted: accepted)
        case .rejectEntityProposal:
            let proposalId = try c.decode(UUID.self, forKey: .proposalId)
            self = .rejectEntityProposal(proposalId: proposalId)
        case .acceptRelationshipProposal:
            let proposalId = try c.decode(UUID.self, forKey: .proposalId)
            let demoteConflicting = try c.decode(Bool.self, forKey: .demoteConflicting)
            self = .acceptRelationshipProposal(
                proposalId: proposalId, demoteConflicting: demoteConflicting
            )
        case .rejectRelationshipProposal:
            let proposalId = try c.decode(UUID.self, forKey: .proposalId)
            self = .rejectRelationshipProposal(proposalId: proposalId)
        case .setRelationshipNodePosition:
            let characterId = try c.decode(UUID.self, forKey: .characterId)
            let x = try c.decode(Double.self, forKey: .x)
            let y = try c.decode(Double.self, forKey: .y)
            self = .setRelationshipNodePosition(characterId: characterId, x: x, y: y)
        case .setRelationshipEdge:
            let fromId = try c.decode(UUID.self, forKey: .fromCharacterId)
            let toId = try c.decode(UUID.self, forKey: .toCharacterId)
            let edgeKind = try c.decode(String.self, forKey: .edgeKind)
            let status = try c.decode(String.self, forKey: .status)
            let notes = try c.decode(String.self, forKey: .notes)
            self = .setRelationshipEdge(
                fromCharacterId: fromId, toCharacterId: toId,
                edgeKind: edgeKind, status: status, notes: notes
            )
        case .deleteRelationshipEdge:
            let fromId = try c.decode(UUID.self, forKey: .fromCharacterId)
            let toId = try c.decode(UUID.self, forKey: .toCharacterId)
            let edgeKind = try c.decode(String.self, forKey: .edgeKind)
            self = .deleteRelationshipEdge(
                fromCharacterId: fromId, toCharacterId: toId, edgeKind: edgeKind
            )
        case .generateOutline:
            let requestId = try c.decode(String.self, forKey: .requestId)
            let config = try c.decode(PlannedProjectConfig.self, forKey: .config)
            self = .generateOutline(requestId: requestId, config: config)
        case .createPlannedProject:
            let requestId = try c.decode(String.self, forKey: .requestId)
            let title = try c.decode(String.self, forKey: .title)
            let config = try c.decode(PlannedProjectConfig.self, forKey: .config)
            let outline = try c.decode(
                OutlineGeneration.GeneratedOutline.self, forKey: .outline
            )
            self = .createPlannedProject(
                requestId: requestId, title: title, config: config, outline: outline
            )
        case .upsertStyle:
            let style = try c.decode(Style.self, forKey: .style)
            self = .upsertStyle(style: style)
        case .deleteStyle:
            let id = try c.decode(UUID.self, forKey: .id)
            self = .deleteStyle(id: id)
        case .closeWizardWindow:
            self = .closeWizardWindow
        }
    }
}

/// Payload accompanying `acceptEntityProposal`. The webview form
/// captures the user's final view of the canonical name + aliases
/// + one-line — these may differ from what the LLM proposed if the
/// user edited the fields before clicking Accept. AppState applies
/// these values rather than reading back from the original
/// `ProposedEntity`.
public struct ProposedEntityAcceptance: Codable, Equatable {
    public var canonicalName: String
    public var aliases: [String]
    public var oneLine: String

    public init(canonicalName: String, aliases: [String], oneLine: String) {
        self.canonicalName = canonicalName
        self.aliases = aliases
        self.oneLine = oneLine
    }
}

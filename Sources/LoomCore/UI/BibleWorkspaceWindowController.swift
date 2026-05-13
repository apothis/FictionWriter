import AppKit
import WebKit

/// Phase 4.5 — second NSWindow for deep entity editing. Hosts a
/// WKWebView whose contents come from the `web/bible-workspace/dist`
/// bundle (Vite/React/TS/Tailwind/shadcn). See
/// [LOOM_BIBLE_WORKSPACE.md §5] for the architecture.
///
/// Session 1 scope:
/// - AppKit shell + WKWebView wiring
/// - `WKScriptMessageHandler` registered under name `"loom"`
/// - Snapshot push on `ProjectSession.didChangeNotification`
/// - Read-only entity list rendered by the React side
/// - Stub intent-handler for Session 2 to extend
///
/// The window's contents are loaded from
/// `Bundle.module/BibleWorkspace/index.html`. Until the web bundle
/// lands (later in Session 1), the controller falls back to an
/// inline placeholder HTML so the AppKit shell can be verified in
/// isolation.
public final class BibleWorkspaceWindowController: NSWindowController, WKScriptMessageHandler, WKNavigationDelegate {

    public let session: ProjectSession
    private let appState: AppState
    private let webView: WKWebView
    private var didChangeObserver: NSObjectProtocol?
    private var didReplaceObserver: NSObjectProtocol?
    private var suggestionsObserver: NSObjectProtocol?

    public init(session: ProjectSession, appState: AppState) {
        self.session = session
        self.appState = appState

        // Bridge plumbing — message handler name "loom" mirrors the
        // JS-side global `window.loom`. Bridge contract pinned in
        // LOOM_BIBLE_WORKSPACE.md §5.2.
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        config.userContentController = controller
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        self.webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 1024, height: 700),
            configuration: config
        )
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        // Phase 4.5 Session 1 — enable Safari Web Inspector against
        // this webview. macOS 13.3+. Right-click → Inspect Element
        // opens the dev tools (or Safari → Develop menu → Loom →
        // Bible Workspace if right-click is suppressed). Kept on
        // unconditionally during the pilot for diagnostics; can flip
        // off post-stability if needed.
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        // Initial snapshot push is gated on navigation-finished —
        // see WKNavigationDelegate hookup below super.init.

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1024, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Bible Workspace — \(session.project.title)"
        window.contentView = webView
        window.minSize = NSSize(width: 720, height: 480)
        window.setFrameAutosaveName("Loom.BibleWorkspaceWindow")
        super.init(window: window)

        // The message handler + navigation delegate registrations
        // have to happen AFTER super.init so `self` is fully
        // constructed.
        controller.add(self, name: "loom")
        webView.navigationDelegate = self

        loadContent()

        // Push a fresh snapshot whenever the session mutates.
        didChangeObserver = NotificationCenter.default.addObserver(
            forName: ProjectSession.didChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            self?.pushSnapshot()
        }
        didReplaceObserver = NotificationCenter.default.addObserver(
            forName: ProjectSession.didReplaceNotification,
            object: session,
            queue: .main
        ) { [weak self, weak session] _ in
            guard let self = self, let session = session else { return }
            self.window?.title = "Bible Workspace — \(session.project.title)"
            self.pushSnapshot()
        }
        // Phase 4.5 Session 5 — the suggestions queue is mutated
        // through AppState's accept/reject API which posts its own
        // notification (NOT ProjectSession.didChange). Without this
        // observer, rejecting a suggestion from the workspace
        // wouldn't trigger a snapshot push and the row would
        // linger until the next session edit.
        suggestionsObserver = NotificationCenter.default.addObserver(
            forName: AppState.ledgerSuggestionsDidChangeNotification,
            object: appState,
            queue: .main
        ) { [weak self] _ in
            self?.pushSnapshot()
        }
    }

    @available(*, unavailable) public required init?(coder: NSCoder) { nil }

    deinit {
        if let o = didChangeObserver { NotificationCenter.default.removeObserver(o) }
        if let o = didReplaceObserver { NotificationCenter.default.removeObserver(o) }
        if let o = suggestionsObserver { NotificationCenter.default.removeObserver(o) }
    }

    // MARK: - Content loading

    /// Loads the bundled web bundle (`BibleWorkspace/index.html` via
    /// `Bundle.module`) when available; otherwise renders an inline
    /// placeholder that still exercises the bridge (registers
    /// `window.loom.applySnapshot` + a `<pre>` dump of the most
    /// recent snapshot). The placeholder is what runs during early
    /// Session 1 development before the Vite build lands.
    private func loadContent() {
        // Initial snapshot push deferred to `webView(_:didFinish:)`
        // (WKNavigationDelegate). The previous heuristic
        // `DispatchQueue.main.asyncAfter(... 0.15s ...)` raced WKWebView's
        // async HTML load on cold-start and produced empty placeholders
        // until the user happened to trigger a session mutation that
        // re-pushed.
        if let url = bundledIndexURL() {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            DebugLog.shared.write("[workspace] loaded bundled index.html from \(url.path)")
            return
        }
        webView.loadHTMLString(placeholderHTML(), baseURL: nil)
        DebugLog.shared.write("[workspace] loaded inline placeholder (no bundled web/dist found)")
    }

    /// Resolve the bundled `index.html` via `Bundle.module`. SPM
    /// generates `Bundle.module` because `Package.swift` declares a
    /// `.copy("Resources/BibleWorkspace")` entry on the LoomCore
    /// target; `scripts/build-bible-workspace.sh` populates that
    /// directory with Vite's `dist/` output before `swift build`.
    /// Returns nil only when the build script hasn't been run — the
    /// placeholder HTML is the safety net for that case.
    private func bundledIndexURL() -> URL? {
        Bundle.module.url(
            forResource: "index",
            withExtension: "html",
            subdirectory: "BibleWorkspace"
        )
    }

    private func placeholderHTML() -> String {
        // Minimal HTML that registers the same `window.loom` API the
        // React build will. Dumps incoming snapshots into a <pre>
        // so the bridge can be eyeballed in isolation before any
        // framework code lands.
        return """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <title>Bible Workspace (placeholder)</title>
        <style>
          html, body { margin: 0; padding: 16px; font-family: -apple-system, system-ui; background: #1c1c1e; color: #f2f2f7; }
          h1 { font-size: 14px; margin: 0 0 12px; color: #9d9da3; font-weight: 500; }
          pre { font-size: 11px; white-space: pre-wrap; word-break: break-word; background: #2c2c2e; padding: 12px; border-radius: 8px; max-height: calc(100vh - 80px); overflow: auto; }
        </style>
        </head>
        <body>
          <h1>Bible Workspace — placeholder (React build not yet bundled)</h1>
          <pre id="snap">(awaiting first snapshot...)</pre>
          <script>
            window.loom = window.loom || {};
            window.loom.applySnapshot = function (snap) {
              document.getElementById("snap").textContent = JSON.stringify(snap, null, 2);
            };
          </script>
        </body></html>
        """
    }

    // MARK: - Snapshot push

    private func pushSnapshot() {
        let snap = BibleWorkspaceSnapshot.build(
            project: session.project,
            scenes: session.scenes,
            references: session.listReferenceSnapshots(),
            suggestionsQueue: appState.ledgerSuggestionsQueue
        )
        do {
            let js = try BibleWorkspaceBridge.encodeSnapshotPush(snap)
            webView.evaluateJavaScript(js) { _, error in
                if let error = error {
                    DebugLog.shared.write("[workspace] snapshot push failed: \(error)")
                }
            }
        } catch {
            DebugLog.shared.write("[workspace] snapshot encode failed: \(error)")
        }
    }

    // MARK: - WKScriptMessageHandler (JS → Swift intent dispatch)

    public func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        // The WKScriptMessage body is whatever the JS side passed
        // to `postMessage(...)`. The JS bridge sends plain objects
        // (already JSON-compatible). We serialize back to Data via
        // JSONSerialization and let `BibleWorkspaceBridge.decodeIntent`
        // parse it. Decoding errors are logged + swallowed —
        // schema-mismatched intents shouldn't crash the app.
        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: message.body, options: [])
        } catch {
            DebugLog.shared.write("[workspace] intent message body wasn't JSON-serializable: \(error); body=\(String(describing: message.body))")
            return
        }
        let intent: BibleWorkspaceIntent
        do {
            intent = try BibleWorkspaceBridge.decodeIntent(data)
        } catch {
            DebugLog.shared.write("[workspace] intent decode failed: \(error); raw=\(String(data: data, encoding: .utf8) ?? "?")")
            return
        }
        dispatch(intent)
    }

    /// Apply an intent to the underlying `ProjectSession`. Each
    /// case maps to a single session mutator; the resulting
    /// `didChangeNotification` triggers a fresh snapshot push back
    /// to the web side, closing the loop.
    private func dispatch(_ intent: BibleWorkspaceIntent) {
        switch intent {
        case .patchCharacter(let id, let patch):
            guard var character = session.project.bible.characters.first(where: { $0.id == id }) else {
                DebugLog.shared.write("[workspace] patchCharacter ignored — stale id=\(id)")
                return
            }
            character = patch.apply(to: character)
            session.updateCharacter(character)
            DebugLog.shared.write("[workspace] patchCharacter applied id=\(id) fields=\(patchFieldSummary(patch))")
        case .patchLorebookEntry(let id, let patch):
            guard var entry = session.project.bible.lorebook.first(where: { $0.id == id }) else {
                DebugLog.shared.write("[workspace] patchLorebookEntry ignored — stale id=\(id)")
                return
            }
            entry = patch.apply(to: entry)
            session.updateLorebookEntry(entry)
            DebugLog.shared.write("[workspace] patchLorebookEntry applied id=\(id) fields=\(lorebookPatchFieldSummary(patch))")
        case .addLorebookEntry(let name):
            let entry = session.addLorebookEntry(name: name)
            DebugLog.shared.write("[workspace] addLorebookEntry id=\(entry.id) name=\(name)")
        case .deleteLorebookEntry(let id):
            session.deleteLorebookEntry(id: id)
            DebugLog.shared.write("[workspace] deleteLorebookEntry id=\(id)")
        case .deleteKnownFact(let characterId, let sceneId, let factId):
            session.removeKnownFact(characterId: characterId, sceneId: sceneId, factId: factId)
            DebugLog.shared.write("[workspace] deleteKnownFact character=\(characterId) scene=\(sceneId) fact=\(factId)")
        case .acceptSuggestion(let factId):
            // Look up the LedgerSuggestion by factId across all
            // character buckets. The queue's flat surface
            // (suggestions(forCharacter:) per id) means we have to
            // sweep; for working-novel scale (<100 pending
            // suggestions) this is fine. If it ever becomes hot,
            // add a flat `all()` accessor.
            var found: LedgerSuggestion? = nil
            for character in session.project.bible.characters {
                if let match = appState.ledgerSuggestionsQueue.suggestions(forCharacter: character.id).first(where: { $0.fact.id == factId }) {
                    found = match
                    break
                }
            }
            if let suggestion = found {
                appState.acceptLedgerSuggestion(suggestion)
                DebugLog.shared.write("[workspace] acceptSuggestion factId=\(factId)")
            } else {
                DebugLog.shared.write("[workspace] acceptSuggestion ignored — stale factId=\(factId)")
            }
        case .rejectSuggestion(let factId):
            appState.rejectLedgerSuggestion(factId: factId)
            DebugLog.shared.write("[workspace] rejectSuggestion factId=\(factId)")
        case .createReference(let name):
            if let ref = session.addReference(name: name) {
                DebugLog.shared.write("[workspace] createReference id=\(ref.id) name=\(name)")
            } else {
                DebugLog.shared.write("[workspace] createReference dropped — in-memory session or write failed")
            }
        case .patchReference(let id, let patch):
            guard let url = session.url else {
                DebugLog.shared.write("[workspace] patchReference dropped — in-memory session id=\(id)")
                return
            }
            guard var ref = try? ReferenceStorage.loadReference(id: id, in: url) else {
                DebugLog.shared.write("[workspace] patchReference ignored — stale id=\(id)")
                return
            }
            ref = patch.apply(to: ref)
            session.updateReference(ref)
            DebugLog.shared.write("[workspace] patchReference applied id=\(id) fields=\(referencePatchFieldSummary(patch))")
        case .deleteReference(let id):
            session.deleteReference(id: id)
            DebugLog.shared.write("[workspace] deleteReference id=\(id)")
        case .ingestReference(let id):
            appState.ingestReference(id: id)
            DebugLog.shared.write("[workspace] ingestReference id=\(id) kicked off")
        }
    }

    /// Compact log-friendly summary of which reference-patch fields
    /// were non-nil.
    private func referencePatchFieldSummary(_ patch: ReferencePatch) -> String {
        var fields: [String] = []
        if patch.name != nil { fields.append("name") }
        if patch.nsfw != nil { fields.append("nsfw") }
        if patch.body != nil { fields.append("body") }
        return fields.isEmpty ? "<empty>" : fields.joined(separator: ",")
    }

    /// Compact log-friendly summary of which lorebook-patch fields
    /// were non-nil.
    private func lorebookPatchFieldSummary(_ patch: LorebookEntryPatch) -> String {
        var fields: [String] = []
        if patch.name != nil { fields.append("name") }
        if patch.content != nil { fields.append("content") }
        if patch.activationMode != nil { fields.append("activationMode") }
        if patch.keys != nil { fields.append("keys") }
        if patch.secondaryKeys != nil { fields.append("secondaryKeys") }
        if patch.enabled != nil { fields.append("enabled") }
        if patch.priority != nil { fields.append("priority") }
        if patch.positionMode != nil { fields.append("positionMode") }
        if patch.depth != nil { fields.append("depth") }
        if patch.maxRecentScenesScanned != nil { fields.append("maxRecentScenesScanned") }
        if patch.group != nil { fields.append("group") }
        if patch.weight != nil { fields.append("weight") }
        if patch.sticky != nil { fields.append("sticky") }
        return fields.isEmpty ? "<empty>" : fields.joined(separator: ",")
    }

    /// Compact log-friendly summary of which patch fields were
    /// non-nil — useful when triaging "did the patch include the
    /// field I expected" without dumping the whole struct.
    private func patchFieldSummary(_ patch: CharacterPatch) -> String {
        var fields: [String] = []
        if patch.name != nil { fields.append("name") }
        if patch.aliases != nil { fields.append("aliases") }
        if patch.role != nil { fields.append("role") }
        if patch.oneLine != nil { fields.append("oneLine") }
        if patch.description != nil { fields.append("description") }
        if patch.personality != nil { fields.append("personality") }
        if patch.appearance != nil { fields.append("appearance") }
        if patch.voice != nil { fields.append("voice") }
        if patch.goals != nil { fields.append("goals") }
        if patch.relationships != nil { fields.append("relationships") }
        if patch.canonBrief != nil { fields.append("canonBrief") }
        if patch.customFields != nil { fields.append("customFields") }
        if patch.injectionMode != nil { fields.append("injectionMode") }
        return fields.isEmpty ? "<empty>" : fields.joined(separator: ",")
    }

    // MARK: - WKNavigationDelegate

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Page has finished loading and `window.loom.applySnapshot`
        // is registered by the page's inline script — safe to push
        // the first snapshot now. Fires for both the bundled
        // index.html and the inline placeholder, so this is the
        // single chokepoint for initial population.
        DebugLog.shared.write("[workspace] webView didFinish navigation; pushing initial snapshot")
        pushSnapshot()
    }

    // MARK: - Public surface

    public func showAndActivate() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

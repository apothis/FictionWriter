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
    }

    @available(*, unavailable) public required init?(coder: NSCoder) { nil }

    deinit {
        if let o = didChangeObserver { NotificationCenter.default.removeObserver(o) }
        if let o = didReplaceObserver { NotificationCenter.default.removeObserver(o) }
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
        // Session 2 lands the BibleWorkspaceIntent decoding +
        // dispatch here. For now: log + drop.
        DebugLog.shared.write("[workspace] received intent message (Session 1 stub): \(String(describing: message.body))")
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

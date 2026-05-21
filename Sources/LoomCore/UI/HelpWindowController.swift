import AppKit
import WebKit

/// Standalone NSWindow for the in-app reference help panel. Hosts a
/// WKWebView whose content comes from the `Help/help.html` bundle
/// (built by `scripts/build-bible-workspace.sh` with
/// `LOOM_BUNDLE=help`). Mirrors `BibleWorkspaceWindowController`'s
/// AppKit + WKWebView + WKScriptMessageHandler shape.
///
/// Unlike the Bible Workspace, this window has no project context —
/// it's app-level. The state it carries is small: which book the
/// user is reading (`currentBook`), and which section is selected
/// inside that book. Both are mutated by intents posted from the
/// React side; each mutation re-pushes a fresh snapshot.
///
/// One instance per app — typically owned by `AppDelegate` and
/// lazily created on first menu invocation, kept alive thereafter.
public final class HelpWindowController: NSWindowController,
                                         WKScriptMessageHandler,
                                         WKNavigationDelegate {

    private let webView: WKWebView
    /// Current book on display. Toggled by `HelpIntent.switchBook`.
    private var currentBook: HelpBook
    /// Selected section within `currentBook`, or nil when nothing is
    /// selected (only possible if the book has an empty TOC).
    private var selectedSectionId: String?
    /// True once `webView(_:didFinish:)` fires for the bundled HTML
    /// load. Snapshot pushes before this race the page load and
    /// silently fail because `window.loomHelp` doesn't exist yet.
    /// The deferred-until-navigation-finished pattern mirrors the
    /// Bible Workspace controller's fix for the same cold-start race.
    private var didFinishInitialLoad = false

    public init() {
        // Bridge plumbing — message handler name "loom" mirrors the
        // outgoing-handler convention used by the bible-workspace +
        // plannedProject + projectTools webviews (per-bundle JS
        // global on the way in, shared `loom` handler on the way
        // out). The Swift side routes by which WKScriptMessageHandler
        // instance received the message.
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        config.userContentController = controller
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        self.webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 1024, height: 720),
            configuration: config
        )
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }

        // Default initial state — User Help, first section selected.
        self.currentBook = .userHelp
        self.selectedSectionId = HelpContent.toc(for: .userHelp).first?.id

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1024, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Loom Help"
        window.contentView = webView
        window.minSize = NSSize(width: 720, height: 480)
        window.setFrameAutosaveName("Loom.HelpWindow")
        super.init(window: window)

        // Message handler + navigation delegate registrations must
        // happen AFTER super.init so `self` is fully constructed.
        controller.add(self, name: "loom")
        webView.navigationDelegate = self

        loadContent()
    }

    @available(*, unavailable) public required init?(coder: NSCoder) { nil }

    // MARK: - Content loading

    private func loadContent() {
        if let url = bundledIndexURL() {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            DebugLog.shared.write("[help] loaded bundled help.html from \(url.path)")
            return
        }
        webView.loadHTMLString(placeholderHTML(), baseURL: nil)
        DebugLog.shared.write("[help] loaded inline placeholder (no bundled Help/help.html found)")
    }

    /// Resolve the bundled `help.html` via `Bundle.module`. Returns
    /// nil only when the build script hasn't run — the inline
    /// placeholder is the safety net for that case.
    private func bundledIndexURL() -> URL? {
        Bundle.module.url(
            forResource: "help",
            withExtension: "html",
            subdirectory: "Help"
        )
    }

    private func placeholderHTML() -> String {
        // Same shape as the Bible Workspace placeholder — registers
        // the per-bundle global the React side would, dumps incoming
        // snapshots into a <pre> for eyeballing in isolation.
        return """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <title>Loom Help (placeholder)</title>
        <style>
          html, body { margin: 0; padding: 16px; font-family: -apple-system, system-ui; background: #1c1c1e; color: #f2f2f7; }
          h1 { font-size: 14px; margin: 0 0 12px; color: #9d9da3; font-weight: 500; }
          pre { font-size: 11px; white-space: pre-wrap; word-break: break-word; background: #2c2c2e; padding: 12px; border-radius: 8px; max-height: calc(100vh - 80px); overflow: auto; }
        </style>
        </head>
        <body>
          <h1>Loom Help — placeholder (web bundle not built — run scripts/build-bible-workspace.sh)</h1>
          <pre id="snap">(awaiting first snapshot...)</pre>
          <script>
            window.loomHelp = window.loomHelp || {};
            window.loomHelp.applySnapshot = function (snap) {
              document.getElementById("snap").textContent = JSON.stringify(snap, null, 2);
            };
          </script>
        </body></html>
        """
    }

    // MARK: - WKNavigationDelegate

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didFinishInitialLoad = true
        pushSnapshot()
    }

    // MARK: - Snapshot push

    private func pushSnapshot() {
        guard didFinishInitialLoad else { return }
        let snap = HelpContent.snapshot(
            book: currentBook,
            selectedSectionId: selectedSectionId
        )
        do {
            let js = try HelpBridge.encodeSnapshotPush(snap)
            webView.evaluateJavaScript(js) { _, error in
                if let error = error {
                    DebugLog.shared.write("[help] snapshot push failed: \(error)")
                }
            }
        } catch {
            DebugLog.shared.write("[help] snapshot encode failed: \(error)")
        }
    }

    // MARK: - WKScriptMessageHandler — JS → Swift intents

    public func userContentController(_ ucc: WKUserContentController,
                                      didReceive message: WKScriptMessage) {
        // The shared "loom" handler is used by multiple webviews —
        // route by `kind`; an unrecognised payload (a bible-workspace
        // or wizard intent landing on the help controller's handler)
        // is logged and ignored, not crashed on.
        guard let body = message.body as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: body)
        else {
            DebugLog.shared.write("[help] message body not a JSON dict — ignored")
            return
        }
        let intent: HelpIntent
        do {
            intent = try HelpBridge.decodeIntent(data)
        } catch {
            // Quietly ignore — the bible-workspace + wizard + tools
            // bundles all post to `loom` too; their intents will land
            // here when those windows are open, and the help
            // controller has nothing to do with them.
            return
        }
        switch intent {
        case .selectSection(let sectionId, let book):
            // Defensive: a stale-snapshot click on the *other* book
            // shouldn't fire here, but if it does, switch books too.
            if book != currentBook {
                currentBook = book
            }
            selectedSectionId = sectionId
            DebugLog.shared.write("[help] selectSection book=\(book.rawValue) id=\(sectionId)")
            pushSnapshot()
        case .switchBook(let book):
            currentBook = book
            // Select the new book's first section so the panel isn't
            // empty on switch. If the new book has no TOC, the
            // selection stays nil and the React side renders a
            // "pick a section" empty state.
            selectedSectionId = HelpContent.toc(for: book).first?.id
            DebugLog.shared.write("[help] switchBook → \(book.rawValue) section=\(selectedSectionId ?? "nil")")
            pushSnapshot()
        }
    }
}

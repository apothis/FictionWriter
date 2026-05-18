import AppKit
import WebKit

/// P2 — the thin AppKit shell for the project-tools webview bundle
/// (`Resources/ProjectTools`). One bundle hosts two small surfaces;
/// `Mode` selects which, and the pushed `ProjectToolsSnapshot` carries
/// the `tool` discriminator the React side routes on.
///
/// Modelled on `PlannedProjectWindowController` — deliberately thin per
/// the webview-first UI direction. Unlike that controller this one
/// owns a `ProjectSession` (both tools mutate project state).
public final class ProjectToolsWindowController: NSWindowController,
    WKScriptMessageHandler, WKNavigationDelegate {

    public enum Mode {
        /// Edit one scene's `framing` block.
        case sceneFraming(sceneId: UUID)
        /// Edit the project's anti-slop phrase list.
        case antiSlop
    }

    private let session: ProjectSession
    private let mode: Mode
    private let webView: WKWebView

    public init(session: ProjectSession, mode: Mode) {
        self.session = session
        self.mode = mode

        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        config.userContentController = controller
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        self.webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 620, height: 560),
            configuration: config
        )
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        switch mode {
        case .sceneFraming:
            window.title = "Scene Framing"
            window.setFrameAutosaveName("Loom.SceneFramingWindow")
        case .antiSlop:
            window.title = "Anti-slop List"
            window.setFrameAutosaveName("Loom.AntiSlopWindow")
        }
        window.contentView = webView
        window.minSize = NSSize(width: 480, height: 400)
        super.init(window: window)

        controller.add(self, name: "loom")
        webView.navigationDelegate = self
        loadContent()
    }

    @available(*, unavailable) public required init?(coder: NSCoder) { nil }

    private func loadContent() {
        if let url = Bundle.module.url(
            forResource: "projectTools", withExtension: "html",
            subdirectory: "ProjectTools"
        ) {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            DebugLog.shared.write("[tools] loaded project-tools bundle from \(url.path)")
        } else {
            webView.loadHTMLString(
                "<h1>Project-tools bundle not built — run scripts/build-bible-workspace.sh</h1>",
                baseURL: nil
            )
            DebugLog.shared.write("[tools] project-tools bundle missing — placeholder shown")
        }
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pushSnapshot()
    }

    private func pushSnapshot() {
        let snap: ProjectToolsSnapshot
        switch mode {
        case .sceneFraming(let sceneId):
            guard let scene = session.scenes[sceneId] else {
                DebugLog.shared.write("[tools] pushSnapshot — scene \(sceneId) missing")
                return
            }
            snap = .framing(scene: scene, projectTitle: session.project.title)
        case .antiSlop:
            snap = .antiSlop(project: session.project)
        }
        do {
            let js = try BibleWorkspaceBridge.encodeProjectToolsSnapshotPush(snap)
            webView.evaluateJavaScript(js) { _, error in
                if let error = error {
                    DebugLog.shared.write("[tools] snapshot push failed: \(error)")
                }
            }
        } catch {
            DebugLog.shared.write("[tools] snapshot encode failed: \(error)")
        }
    }

    // MARK: - WKScriptMessageHandler (JS → Swift)

    public func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: message.body, options: [])
        } catch {
            DebugLog.shared.write("[tools] intent body not JSON-serializable: \(error)")
            return
        }
        let intent: BibleWorkspaceIntent
        do {
            intent = try BibleWorkspaceBridge.decodeIntent(data)
        } catch {
            DebugLog.shared.write("[tools] intent decode failed: \(error)")
            return
        }
        switch intent {
        case .setSceneFraming(let sceneId, let framing):
            session.setSceneFraming(id: sceneId, to: framing)
            DebugLog.shared.write("[tools] setSceneFraming scene=\(sceneId)")
        case .setAntiSlopPhrases(let phrases):
            session.setAntiSlopPhrases(phrases)
            DebugLog.shared.write("[tools] setAntiSlopPhrases count=\(phrases.count)")
        default:
            DebugLog.shared.write("[tools] ignoring non-tools intent")
        }
    }

    public func showAndActivate() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

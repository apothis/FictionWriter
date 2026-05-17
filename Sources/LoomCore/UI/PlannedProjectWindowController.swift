import AppKit
import WebKit

/// Planned Project mode — Phase 4 item 5. The thin AppKit entry point
/// for the guided-creation wizard: a standalone NSWindow hosting the
/// wizard's WKWebView bundle (`Resources/PlannedProject`).
///
/// Unlike `BibleWorkspaceWindowController` this controller is
/// pre-project — it owns no `ProjectSession`. It pushes a
/// `PlannedProjectSnapshot` (the app style library + frameworks) once
/// the page loads, and dispatches the two request/reply wizard
/// intents:
///
/// - `generateOutline` runs the staged outline pipeline on the writer
///   model (`OutlineGenerator` over a `KoboldCallProvider`) and
///   replies with the `GeneratedOutline`.
/// - `createPlannedProject` picks a `.loom` save location, writes the
///   bundle via `AppState.createPlannedProject`, then closes itself.
///
/// Per LOOM_PLANNED_PROJECT.md §2 the webview-heavy decision keeps
/// this AppKit surface deliberately thin.
public final class PlannedProjectWindowController: NSWindowController,
    WKScriptMessageHandler, WKNavigationDelegate {

    private let appState: AppState
    private let webView: WKWebView

    public init(appState: AppState) {
        self.appState = appState

        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        config.userContentController = controller
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        self.webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 780, height: 680),
            configuration: config
        )
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "New Planned Project"
        window.contentView = webView
        window.minSize = NSSize(width: 640, height: 520)
        window.setFrameAutosaveName("Loom.PlannedProjectWindow")
        super.init(window: window)

        controller.add(self, name: "loom")
        webView.navigationDelegate = self
        loadContent()
    }

    @available(*, unavailable) public required init?(coder: NSCoder) { nil }

    // MARK: - Content loading

    private func loadContent() {
        if let url = Bundle.module.url(
            forResource: "plannedProject", withExtension: "html",
            subdirectory: "PlannedProject"
        ) {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            DebugLog.shared.write("[planned] loaded wizard bundle from \(url.path)")
        } else {
            webView.loadHTMLString(
                "<h1>Planned Project wizard bundle not built — run scripts/build-bible-workspace.sh</h1>",
                baseURL: nil
            )
            DebugLog.shared.write("[planned] wizard bundle missing — placeholder shown")
        }
    }

    // MARK: - Snapshot push

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let snap = PlannedProjectSnapshot.build(styles: StyleLibraryStore().load())
        do {
            let js = try BibleWorkspaceBridge.encodePlannedSnapshotPush(snap)
            webView.evaluateJavaScript(js) { _, error in
                if let error = error {
                    DebugLog.shared.write("[planned] snapshot push failed: \(error)")
                }
            }
        } catch {
            DebugLog.shared.write("[planned] snapshot encode failed: \(error)")
        }
    }

    // MARK: - WKScriptMessageHandler (JS → Swift intent dispatch)

    public func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: message.body, options: [])
        } catch {
            DebugLog.shared.write("[planned] intent body not JSON-serializable: \(error)")
            return
        }
        let intent: BibleWorkspaceIntent
        do {
            intent = try BibleWorkspaceBridge.decodeIntent(data)
        } catch {
            DebugLog.shared.write("[planned] intent decode failed: \(error)")
            return
        }
        switch intent {
        case .generateOutline(let requestId, let config):
            runGenerateOutline(requestId: requestId, config: config)
        case .createPlannedProject(let requestId, let title, let config, let outline):
            runCreatePlannedProject(
                requestId: requestId, title: title, config: config, outline: outline
            )
        default:
            // The wizard window only handles the planned-project
            // request/reply intents; anything else is misrouted.
            DebugLog.shared.write("[planned] ignoring non-wizard intent")
        }
    }

    // MARK: - Intent handlers

    private func runGenerateOutline(requestId: String, config: PlannedProjectConfig) {
        let provider = KoboldCallProvider(client: appState.registry.clientForDefault())
        let generator = OutlineGenerator(provider: provider)
        let framework = StoryFrameworks.framework(id: config.frameworkId)
            ?? StoryFrameworks.default
        DebugLog.shared.write("[planned] generateOutline requestId=\(requestId)")
        generator.generate(
            premise: config.premise,
            characterSketch: config.characterSketch,
            lengthScenario: config.lengthScenario,
            framework: framework
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let outline):
                    self.reply(requestId: requestId, value: outline)
                case .failure(let error):
                    self.replyError(
                        requestId: requestId,
                        message: "Outline generation failed: \(error)"
                    )
                }
            }
        }
    }

    private func runCreatePlannedProject(
        requestId: String,
        title: String,
        config: PlannedProjectConfig,
        outline: OutlineGeneration.GeneratedOutline
    ) {
        let panel = NSSavePanel()
        panel.title = "Save Planned Project"
        panel.message = "Choose a location for the new .loom project bundle."
        let safeTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        panel.nameFieldStringValue = (safeTitle.isEmpty ? "MyNovel" : safeTitle) + ".loom"
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard let self = self else { return }
            guard response == .OK, let url = panel.url else {
                self.replyError(requestId: requestId, message: "Save cancelled.")
                return
            }
            let projectTitle = safeTitle.isEmpty
                ? url.deletingPathExtension().lastPathComponent
                : safeTitle
            do {
                try self.appState.createPlannedProject(
                    at: url, title: projectTitle, config: config, outline: outline
                )
                self.reply(requestId: requestId, value: true)
                DebugLog.shared.write("[planned] created project at \(url.lastPathComponent)")
                self.window?.close()
            } catch {
                self.replyError(
                    requestId: requestId,
                    message: "Couldn’t create the project: \(error.localizedDescription)"
                )
            }
        }
    }

    // MARK: - Reply leg

    private func reply<V: Encodable>(requestId: String, value: V) {
        do {
            let js = try BibleWorkspaceBridge.encodeReply(requestId: requestId, value: value)
            webView.evaluateJavaScript(js, completionHandler: nil)
        } catch {
            replyError(requestId: requestId, message: "Reply encode failed: \(error)")
        }
    }

    private func replyError(requestId: String, message: String) {
        let js = BibleWorkspaceBridge.encodeReplyError(requestId: requestId, message: message)
        webView.evaluateJavaScript(js, completionHandler: nil)
        DebugLog.shared.write("[planned] replyError requestId=\(requestId): \(message)")
    }

    // MARK: - Public surface

    public func showAndActivate() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

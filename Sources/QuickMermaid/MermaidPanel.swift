import AppKit
import WebKit
import UniformTypeIdentifiers

/// A floating panel that can become key and is closed by Esc (`cancelOperation`).
final class QuickPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { close() }
}

/// Renders mermaid text in a WKWebView and displays it in a floating panel.
/// A single panel/webview is reused (not released when closed).
final class MermaidPanelController: NSObject, WKNavigationDelegate, WKScriptMessageHandler, NSWindowDelegate {
    private var panel: QuickPanel?
    private var webView: WKWebView!

    private var pendingCode: String?
    private var didFinishLoad = false
    private var selfTestMode = false
    private var resultHandler: ((Bool, String) -> Void)?
    private var pendingTest = false
    private var testCompletion: ((String) -> Void)?

    // Used when exporting only the diagram as PNG via offscreen rendering
    private var exportWindow: NSWindow?
    private var exportWebView: WKWebView?
    private var exportCompletion: ((NSImage?) -> Void)?

    /// Called when the panel is closed (e.g., quit the app in CLI single-use viewer mode). Ignored if nil.
    var onClose: (() -> Void)?

    /// Called when the user requests Settings from the panel (⌘,). Ignored if nil.
    var onOpenSettings: (() -> Void)?

    /// Skip the next focus-loss auto-close once (e.g. when our own Settings window takes focus).
    private var ignoreResignOnce = false

    // MARK: - Public

    func show(code: String) {
        selfTestMode = false
        let cleaned = Self.stripCodeFences(code)
        // History is recorded only after a successful render (see the "result" handler).
        ensurePanel(offscreen: false)
        guard let panel else { return }
        loadOrRender(code: cleaned)
        positionCenter(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func runSelfTest(code: String, completion: @escaping (Bool, String) -> Void) {
        selfTestMode = true
        resultHandler = completion
        ensurePanel(offscreen: true)
        loadOrRender(code: code)
        // Safety timeout in case the render result message never arrives
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self, let handler = self.resultHandler else { return }
            self.resultHandler = nil
            handler(false, "timeout waiting for render result")
        }
    }

    /// Loads the renderer offscreen and runs its JS test suite (`window.__test`).
    func runTests(completion: @escaping (String) -> Void) {
        selfTestMode = true
        pendingTest = true
        testCompletion = completion
        ensurePanel(offscreen: true)
        guard let url = Self.rendererURL() else { completion("{\"error\":\"renderer not found\",\"failed\":[\"renderer\"]}"); return }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self, let c = self.testCompletion else { return }
            self.testCompletion = nil
            c("{\"error\":\"timeout\",\"failed\":[\"timeout\"]}")
        }
    }

    // MARK: - Panel setup

    private func ensurePanel(offscreen: Bool) {
        if panel != nil { return }

        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "result")
        config.userContentController.add(self, name: "copyPNG")
        config.userContentController.add(self, name: "savePNG")
        config.userContentController.add(self, name: "openSettings")
        config.userContentController.add(self, name: "testResult")
        config.userContentController.add(self, name: "deleteHistory")
        let frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        webView = WKWebView(frame: frame, configuration: config)
        webView.navigationDelegate = self
        webView.autoresizingMask = [.width, .height]
        // Intentional KVC on the undocumented `drawsBackground` so the html background shows
        // instead of WKWebView's default white. Do not "clean up" — there is no public API for this.
        webView.setValue(false, forKey: "drawsBackground")

        let p = QuickPanel(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Standard (draggable) title bar above the web toolbar. We do NOT use
        // fullSizeContentView: the web content must not cover the title bar, or
        // there would be no native region to drag the window by.
        p.title = "QuickMermaid"
        p.titleVisibility = .hidden
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.delegate = self
        p.contentView?.addSubview(webView)

        if offscreen {
            p.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        }
        self.panel = p
    }

    private func positionCenter(_ panel: NSPanel) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )
        panel.setFrameOrigin(origin)
    }

    // MARK: - Render

    private func loadOrRender(code: String) {
        pendingCode = code
        if didFinishLoad {
            injectRender()
        } else {
            guard let url = Self.rendererURL() else {
                deliverResult(false, "renderer.html not found in bundle")
                return
            }
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    private func injectRender() {
        guard let code = pendingCode else { return }
        // Safely escape as a JSON array and extract [0] in JS
        let json: String
        if let data = try? JSONSerialization.data(withJSONObject: [code]),
           let str = String(data: data, encoding: .utf8) {
            json = str
        } else {
            json = "[\"\"]"
        }
        // Self-test renders with defaults (settings-independent); otherwise apply stored theme/zoom/background
        let theme = selfTestMode ? "default" : Settings.theme
        let zoom = selfTestMode ? 100 : Settings.defaultZoom
        let bg = selfTestMode ? "#FFFFFF" : Settings.backgroundColor
        let lang = selfTestMode ? "en" : L10n.lang
        webView.evaluateJavaScript("window.render(\(json)[0], '\(theme)', \(zoom), '\(bg)', '\(lang)');", completionHandler: nil)
        if !selfTestMode { injectHistory() }
    }

    private func injectHistory() {
        let items = History.items()
        guard let data = try? JSONSerialization.data(withJSONObject: items),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.setHistory && window.setHistory(\(json));", completionHandler: nil)
    }

    private func deliverResult(_ ok: Bool, _ info: String) {
        guard let handler = resultHandler else { return }
        resultHandler = nil
        handler(ok, info)
    }

    private static func rendererURL() -> URL? {
        Bundle.main.url(forResource: "renderer", withExtension: "html")
    }

    /// Strip a surrounding Markdown code fence (```mermaid … ``` or ``` … ```) if present.
    static func stripCodeFences(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            if let nl = t.firstIndex(of: "\n") {
                t = String(t[t.index(after: nl)...])   // drop the opening ```/```lang line
            } else {
                t = ""
            }
            t = t.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.hasSuffix("```") { t = String(t.dropLast(3)) }
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Copy / Save PNG (offscreen render of diagram only)

    private func copyPNG() {
        exportImage { [weak self] image in
            guard let image else { return }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([image])
            self?.webView.evaluateJavaScript("window.copied && window.copied()", completionHandler: nil)
        }
    }

    private func savePNG() {
        exportImage { [weak self] image in
            guard let image, let data = Self.pngData(from: image) else { return }
            let save = NSSavePanel()
            save.allowedContentTypes = [.png]
            save.nameFieldStringValue = "diagram.png"
            save.canCreateDirectories = true
            // Present as a standalone modal dialog (not a sheet): the render panel is a
            // non-activating floating panel, so a sheet attached to it would not appear.
            NSApp.activate(ignoringOtherApps: true)
            if save.runModal() == .OK, let url = save.url {
                try? data.write(to: url)
                self?.webView.evaluateJavaScript("window.saved && window.saved()", completionHandler: nil)
            }
        }
    }

    /// Extracts only the current diagram's SVG at its natural size, renders it alone in an offscreen WebView, then takes a snapshot.
    /// → Captures only the diagram, without toolbar or margins, regardless of the current screen zoom.
    private func exportImage(completion: @escaping (NSImage?) -> Void) {
        // One export at a time: ignore re-entrant calls while one is in flight.
        guard exportCompletion == nil, exportWebView == nil else { return }
        webView.evaluateJavaScript("window.exportData()") { [weak self] result, _ in
            guard let self else { completion(nil); return }
            guard let json = result as? String,
                  let data = json.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let svg = dict["svg"] as? String,
                  let w = dict["w"] as? Double, let h = dict["h"] as? Double,
                  w > 1, h > 1 else { completion(nil); return }
            let bg = (dict["bg"] as? String) ?? "#ffffff"
            self.renderSVGOffscreen(svg: svg, w: w, h: h, bg: bg, completion: completion)
        }
    }

    private func renderSVGOffscreen(svg: String, w: Double, h: Double, bg: String,
                                    completion: @escaping (NSImage?) -> Void) {
        // Render at 2x for sharpness, but cap the longest edge (to avoid snapshot/canvas limits)
        let maxDim = 8192.0
        var s = 2.0
        if max(w, h) * s > maxDim { s = max(1.0, maxDim / max(w, h)) }
        let pw = w * s, ph = h * s
        let html = """
        <!doctype html><html><head><meta charset='utf-8'><style>
        html,body{margin:0;padding:0;background:\(bg);}
        svg{display:block;width:\(pw)px;height:\(ph)px;}
        </style></head><body>\(svg)</body></html>
        """
        let frame = NSRect(x: 0, y: 0, width: pw, height: ph)
        let wv = WKWebView(frame: frame)
        wv.navigationDelegate = self
        // Place in an offscreen window to secure a backing store (snapshot stability)
        let win = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: pw, height: ph),
                           styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = wv
        self.exportWindow = win
        self.exportWebView = wv
        self.exportCompletion = completion
        wv.loadHTMLString(html, baseURL: Bundle.main.resourceURL)
        // Safety: if the offscreen load never finishes, don't hang/leak.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, self.exportWebView === wv, self.exportCompletion != nil else { return }
            self.finishExport(nil)
        }
    }

    private func finishExport(_ image: NSImage?) {
        let done = exportCompletion
        exportCompletion = nil
        exportWebView = nil
        exportWindow = nil
        done?(image)
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === exportWebView {
            // Take the snapshot on the next run-loop iteration for render stability
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self, let wv = self.exportWebView else { return }
                wv.takeSnapshot(with: WKSnapshotConfiguration()) { image, _ in
                    self.finishExport(image)
                }
            }
            return
        }
        if pendingTest {
            pendingTest = false
            // __test runs async and posts its summary back via the "testResult" handler.
            webView.evaluateJavaScript("window.__test();", completionHandler: nil)
            return
        }
        didFinishLoad = true
        injectRender()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if webView === exportWebView { finishExport(nil); return }
        deliverResult(false, "navigation failed: \(error.localizedDescription)")
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "copyPNG":
            copyPNG()
        case "savePNG":
            savePNG()
        case "openSettings":
            ignoreResignOnce = true   // opening Settings steals key focus; don't auto-close the panel
            onOpenSettings?()
        case "testResult":
            let c = testCompletion
            testCompletion = nil
            c?(message.body as? String ?? "{\"failed\":[\"no body\"]}")
        case "deleteHistory":
            if let code = message.body as? String { History.remove(code); injectHistory() }
        case "result":
            let dict = message.body as? [String: Any]
            let ok = (dict?["ok"] as? Bool) ?? false
            let info = (dict?["info"] as? String) ?? ""
            if selfTestMode {
                deliverResult(ok, info)
            } else if ok, let code = dict?["code"] as? String {
                // Record only successful renders; re-inject so the history overlay reflects it.
                History.add(code)
                injectHistory()
            }
        default:
            break
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        // Do not close during self-test (offscreen).
        if selfTestMode { return }
        // Skip once when our own Settings window took focus.
        if ignoreResignOnce { ignoreResignOnce = false; return }
        // Based on settings: close when focus is lost (default) or keep open
        if Settings.closeOnFocusLoss { panel?.close() }
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

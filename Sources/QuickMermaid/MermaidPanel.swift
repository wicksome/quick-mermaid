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

    // Used when exporting only the diagram as PNG via offscreen rendering
    private var exportWindow: NSWindow?
    private var exportWebView: WKWebView?
    private var exportCompletion: ((NSImage?) -> Void)?

    /// Called when the panel is closed (e.g., quit the app in CLI single-use viewer mode). Ignored if nil.
    var onClose: (() -> Void)?

    // MARK: - Public

    func show(code: String) {
        selfTestMode = false
        ensurePanel(offscreen: false)
        guard let panel else { return }
        loadOrRender(code: code)
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

    // MARK: - Panel setup

    private func ensurePanel(offscreen: Bool) {
        if panel != nil { return }

        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "result")
        config.userContentController.add(self, name: "copyPNG")
        config.userContentController.add(self, name: "savePNG")
        let frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        webView = WKWebView(frame: frame, configuration: config)
        webView.navigationDelegate = self
        webView.autoresizingMask = [.width, .height]
        webView.setValue(false, forKey: "drawsBackground") // use html background instead of transparency

        let p = QuickPanel(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.title = "QuickMermaid"
        p.titleVisibility = .hidden            // prevent the title text from being drawn over the toolbar
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = false
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
        webView.evaluateJavaScript("window.render(\(json)[0], '\(theme)', \(zoom), '\(bg)');", completionHandler: nil)
    }

    private func deliverResult(_ ok: Bool, _ info: String) {
        guard let handler = resultHandler else { return }
        resultHandler = nil
        handler(ok, info)
    }

    private static func rendererURL() -> URL? {
        Bundle.main.url(forResource: "renderer", withExtension: "html")
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
            let onResult: (NSApplication.ModalResponse) -> Void = { resp in
                guard resp == .OK, let url = save.url else { return }
                try? data.write(to: url)
                self?.webView.evaluateJavaScript("window.saved && window.saved()", completionHandler: nil)
            }
            if let win = self?.panel {
                save.beginSheetModal(for: win, completionHandler: onResult)
            } else {
                onResult(save.runModal())
            }
        }
    }

    /// Extracts only the current diagram's SVG at its natural size, renders it alone in an offscreen WebView, then takes a snapshot.
    /// → Captures only the diagram, without toolbar or margins, regardless of the current screen zoom.
    private func exportImage(completion: @escaping (NSImage?) -> Void) {
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
        case "result":
            let dict = message.body as? [String: Any]
            let ok = (dict?["ok"] as? Bool) ?? false
            let info = (dict?["info"] as? String) ?? ""
            deliverResult(ok, info)
        default:
            break
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        // Do not close during self-test (offscreen).
        if selfTestMode { return }
        // Based on settings: close when focus is lost (default) or keep open
        if Settings.closeOnFocusLoss { panel?.close() }
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

import AppKit
import WebKit

/// Renders the currently-shown diagram's SVG to a PNG offscreen, at natural size — so the
/// result is the diagram only (no toolbar/margins) and complete regardless of the on-screen
/// zoom/scroll. Owns its own offscreen window/web view; runs one export at a time.
final class DiagramExporter: NSObject, WKNavigationDelegate {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var completion: ((NSImage?) -> Void)?

    /// Reads `window.exportData()` from `source`, renders that SVG offscreen, and returns a
    /// snapshot image (nil on failure / if an export is already in flight).
    func export(from source: WKWebView, completion: @escaping (NSImage?) -> Void) {
        guard self.completion == nil, webView == nil else { return }   // one at a time
        source.evaluateJavaScript("window.exportData()") { [weak self] result, _ in
            guard let self else { completion(nil); return }
            guard let json = result as? String,
                  let data = json.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let svg = dict["svg"] as? String,
                  let w = dict["w"] as? Double, let h = dict["h"] as? Double,
                  w > 1, h > 1 else { completion(nil); return }
            self.render(svg: svg, w: w, h: h, bg: (dict["bg"] as? String) ?? "#ffffff", completion: completion)
        }
    }

    static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - Private

    private func render(svg: String, w: Double, h: Double, bg: String,
                        completion: @escaping (NSImage?) -> Void) {
        // Render at 2x for sharpness, but cap the longest edge (snapshot/canvas limits)
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
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: pw, height: ph))
        wv.navigationDelegate = self
        // Host in an offscreen window to secure a backing store (snapshot stability)
        let win = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: pw, height: ph),
                           styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = wv
        self.window = win
        self.webView = wv
        self.completion = completion
        wv.loadHTMLString(html, baseURL: Bundle.main.resourceURL)
        // Safety: if the offscreen load never finishes, don't hang/leak.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, self.webView === wv, self.completion != nil else { return }
            self.finish(nil)
        }
    }

    private func finish(_ image: NSImage?) {
        let done = completion
        completion = nil
        webView = nil
        window = nil
        done?(image)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Snapshot on the next run-loop iteration for render stability.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, let wv = self.webView else { return }
            wv.takeSnapshot(with: WKSnapshotConfiguration()) { image, _ in self.finish(image) }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(nil)
    }
}

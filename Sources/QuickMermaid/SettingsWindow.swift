import AppKit
import WebKit

/// Native window for configuring the default theme, zoom level, and focus behavior.
/// Changes are saved to UserDefaults immediately, and the preview WKWebView at the bottom re-renders the sample with the new settings.
final class SettingsWindowController: NSObject, NSWindowDelegate, WKNavigationDelegate {
    private var window: NSWindow?
    private let themePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let zoomField = NSTextField()
    private let zoomStepper = NSStepper()
    private let bgWell = NSColorWell()
    private let shortcutCheck = NSButton(checkboxWithTitle: L10n.t("settings.shortcut"), target: nil, action: nil)
    private let recorderButton = NSButton(title: "", target: nil, action: nil)
    private var recordingMonitor: Any?
    private let keepOpenCheck = NSButton(checkboxWithTitle: L10n.t("settings.keepOpen"), target: nil, action: nil)
    private var webView: WKWebView!
    private var previewLoaded = false

    /// Called when the window is closed (e.g., quit the app in CLI --settings mode). Ignored if nil.
    var onClose: (() -> Void)?

    private static let sample = """
    graph LR
      A[Start] --> B{OK?}
      B -->|Yes| C[Process]
      B -->|No| D[End]
    """

    func show() {
        if window == nil { build() }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    private func build() {
        let W: CGFloat = 480, H: CGFloat = 540
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: W, height: H),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = L10n.t("settings.title")
        win.delegate = self
        win.isReleasedWhenClosed = false

        let content = NSView(frame: NSRect(x: 0, y: 0, width: W, height: H))

        // Theme
        let themeLabel = makeLabel(L10n.t("settings.theme"), x: 20, y: H - 36, w: 120)
        themePopup.frame = NSRect(x: 130, y: H - 40, width: 200, height: 26)
        themePopup.addItems(withTitles: Settings.themes)
        themePopup.selectItem(withTitle: Settings.theme)
        themePopup.target = self
        themePopup.action = #selector(themeChanged)

        // Default zoom level
        let zoomLabel = makeLabel(L10n.t("settings.zoom"), x: 20, y: H - 72, w: 120)
        zoomField.frame = NSRect(x: 130, y: H - 76, width: 70, height: 24)
        zoomField.integerValue = Settings.defaultZoom
        zoomField.target = self
        zoomField.action = #selector(zoomFieldChanged)
        zoomStepper.frame = NSRect(x: 204, y: H - 78, width: 20, height: 28)
        zoomStepper.minValue = 10; zoomStepper.maxValue = 800; zoomStepper.increment = 10
        zoomStepper.integerValue = Settings.defaultZoom
        zoomStepper.target = self
        zoomStepper.action = #selector(zoomStepperChanged)

        // Background color
        let bgLabel = makeLabel(L10n.t("settings.bg"), x: 20, y: H - 108, w: 120)
        bgWell.frame = NSRect(x: 130, y: H - 112, width: 60, height: 24)
        bgWell.color = color(fromHex: Settings.backgroundColor)
        bgWell.target = self
        bgWell.action = #selector(bgChanged)

        // Global shortcut (checkbox + recorder). Default OFF — enabling it prompts for Accessibility permission.
        shortcutCheck.frame = NSRect(x: 18, y: H - 146, width: 250, height: 20)
        shortcutCheck.state = Settings.shortcutEnabled ? .on : .off
        shortcutCheck.target = self
        shortcutCheck.action = #selector(shortcutEnabledChanged)
        recorderButton.frame = NSRect(x: 270, y: H - 150, width: 110, height: 26)
        recorderButton.bezelStyle = .rounded
        recorderButton.title = Settings.shortcutDisplay
        recorderButton.target = self
        recorderButton.action = #selector(startRecording)

        // Keep open when focus is lost (default is to close → checkbox unchecked)
        keepOpenCheck.frame = NSRect(x: 18, y: H - 182, width: 320, height: 20)
        keepOpenCheck.state = Settings.closeOnFocusLoss ? .off : .on
        keepOpenCheck.target = self
        keepOpenCheck.action = #selector(keepOpenChanged)

        let previewLabel = makeLabel(L10n.t("settings.preview"), x: 20, y: H - 212, w: 120)
        previewLabel.textColor = .secondaryLabelColor

        // Preview WebView (renderer.html#preview — render without toolbar)
        let frame = NSRect(x: 16, y: 16, width: W - 32, height: H - 236)
        webView = WKWebView(frame: frame)
        webView.navigationDelegate = self
        webView.wantsLayer = true
        webView.layer?.borderColor = NSColor.separatorColor.cgColor
        webView.layer?.borderWidth = 1
        webView.layer?.cornerRadius = 8
        webView.layer?.masksToBounds = true
        if let url = Bundle.main.url(forResource: "renderer", withExtension: "html") {
            var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            comps?.fragment = "preview"
            let target = comps?.url ?? url
            webView.loadFileURL(target, allowingReadAccessTo: url.deletingLastPathComponent())
        }

        [themeLabel, themePopup, zoomLabel, zoomField, zoomStepper,
         bgLabel, bgWell, shortcutCheck, recorderButton,
         keepOpenCheck, previewLabel, webView].forEach { content.addSubview($0) }
        win.contentView = content
        self.window = win
    }

    private func makeLabel(_ text: String, x: CGFloat, y: CGFloat, w: CGFloat) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.frame = NSRect(x: x, y: y, width: w, height: 18)
        return l
    }

    private func updatePreview() {
        guard previewLoaded else { return }
        let json: String
        if let data = try? JSONSerialization.data(withJSONObject: [Self.sample]),
           let str = String(data: data, encoding: .utf8) {
            json = str
        } else {
            json = "[\"\"]"
        }
        webView.evaluateJavaScript("window.render(\(json)[0], '\(Settings.theme)', \(Settings.defaultZoom), '\(Settings.backgroundColor)');", completionHandler: nil)
    }

    // MARK: - Hex <-> NSColor

    private func color(fromHex hex: String) -> NSColor {
        var s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return .white }
        return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                       green: CGFloat((v >> 8) & 0xFF) / 255,
                       blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
    private func hex(from color: NSColor) -> String {
        let c = color.usingColorSpace(.sRGB) ?? color
        return String(format: "#%02X%02X%02X",
                      Int(round(c.redComponent * 255)),
                      Int(round(c.greenComponent * 255)),
                      Int(round(c.blueComponent * 255)))
    }

    // MARK: - Actions

    @objc private func themeChanged() {
        Settings.theme = themePopup.titleOfSelectedItem ?? "default"
        updatePreview()
    }
    @objc private func zoomFieldChanged() {
        let v = max(10, min(800, zoomField.integerValue))
        zoomField.integerValue = v; zoomStepper.integerValue = v
        Settings.defaultZoom = v
        updatePreview()
    }
    @objc private func zoomStepperChanged() {
        let v = zoomStepper.integerValue
        zoomField.integerValue = v
        Settings.defaultZoom = v
        updatePreview()
    }
    @objc private func keepOpenChanged() {
        // Checked = "keep open" → closeOnFocusLoss = false
        Settings.closeOnFocusLoss = (keepOpenCheck.state == .off)
    }

    // MARK: - Shortcut

    @objc private func shortcutEnabledChanged() {
        Settings.shortcutEnabled = (shortcutCheck.state == .on)
        postShortcutChanged()
    }

    /// Recorder button click → captures the next key combination and saves it as the shortcut.
    @objc private func startRecording() {
        recorderButton.title = L10n.t("settings.recording")
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { self.endRecording(); return nil } // Esc → cancel
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !mods.isEmpty else { return nil } // at least one modifier required
            Settings.shortcutKeyCode = Int(event.keyCode)
            Settings.shortcutModifiers = Int(mods.rawValue)
            Settings.shortcutDisplay = Self.displayString(mods: mods, chars: event.charactersIgnoringModifiers, keyCode: event.keyCode)
            self.endRecording()
            self.postShortcutChanged()
            return nil
        }
    }

    private func endRecording() {
        if let m = recordingMonitor { NSEvent.removeMonitor(m); recordingMonitor = nil }
        recorderButton.title = Settings.shortcutDisplay
    }

    private static func displayString(mods: NSEvent.ModifierFlags, chars: String?, keyCode: UInt16) -> String {
        var s = ""
        if mods.contains(.control) { s += "⌃" }
        if mods.contains(.option)  { s += "⌥" }
        if mods.contains(.shift)   { s += "⇧" }
        if mods.contains(.command) { s += "⌘" }
        let key = (chars?.isEmpty == false) ? chars!.uppercased() : "key\(keyCode)"
        return s + key
    }

    /// Notifies the resident app of a shortcut settings change so it re-registers the hotkey.
    private func postShortcutChanged() {
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name(Settings.changedNotification), object: nil,
            userInfo: nil, deliverImmediately: true)
    }
    @objc private func bgChanged() {
        Settings.backgroundColor = hex(from: bgWell.color)
        updatePreview()
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        previewLoaded = true
        updatePreview()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

import AppKit
import WebKit

/// Native settings window with a sectioned, modern layout. Changes are saved to
/// UserDefaults immediately; the preview WKWebView re-renders the sample with the
/// new settings. On open it checks GitHub Releases for a newer version.
final class SettingsWindowController: NSObject, NSWindowDelegate, WKNavigationDelegate {
    private var window: NSWindow?

    // Controls
    private let languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let themePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let zoomField = NSTextField()
    private let zoomStepper = NSStepper()
    private let bgWell = NSColorWell()
    private let shortcutCheck = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let recorderButton = NSButton(title: "", target: nil, action: nil)
    private let keepOpenCheck = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let releasesButton = NSButton(title: "", target: nil, action: nil)

    // Section headers
    private let secAppearance = NSTextField(labelWithString: "")
    private let secShortcut = NSTextField(labelWithString: "")
    private let secWindow = NSTextField(labelWithString: "")
    private let secAbout = NSTextField(labelWithString: "")
    private let previewHeader = NSTextField(labelWithString: "")

    // Row labels
    private let languageLabel = NSTextField(labelWithString: "")
    private let themeLabel = NSTextField(labelWithString: "")
    private let zoomLabel = NSTextField(labelWithString: "")
    private let bgLabel = NSTextField(labelWithString: "")
    private let versionLabel = NSTextField(labelWithString: "")
    private let updateStatusLabel = NSTextField(labelWithString: "")

    private var webView: WKWebView!
    private var previewLoaded = false
    private var recordingMonitor: Any?
    private var knownNewer: String?   // newer version found by the update check, if any

    /// Called when the window is closed (e.g., quit the app in CLI --settings mode). Ignored if nil.
    var onClose: (() -> Void)?

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private static let sample = """
    graph LR
      A[Start] --> B{OK?}
      B -->|Yes| C[Process]
      B -->|No| D[End]
    """

    func show() {
        if window == nil { build() }
        window?.level = .floating   // float above the render panel
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        checkForUpdate()
    }

    private func build() {
        let W: CGFloat = 520, H: CGFloat = 680
        let LX: CGFloat = 28, CX: CGFloat = 176, CW: CGFloat = 300
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: W, height: H),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.delegate = self
        win.isReleasedWhenClosed = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: W, height: H))

        var y = H - 22
        func section(_ lbl: NSTextField) {
            lbl.font = .systemFont(ofSize: 11, weight: .semibold)
            lbl.textColor = .tertiaryLabelColor
            lbl.frame = NSRect(x: LX, y: y - 15, width: W - 2 * LX, height: 15)
            content.addSubview(lbl); y -= 15 + 8
        }
        func sep() {
            let b = NSBox(frame: NSRect(x: LX, y: y - 1, width: W - 2 * LX, height: 1))
            b.boxType = .separator
            content.addSubview(b); y -= 1 + 16
        }
        func row(_ h: CGFloat) -> CGFloat { let fy = y - h; y -= h + 12; return fy }
        func label(_ l: NSTextField, _ fy: CGFloat) {
            l.frame = NSRect(x: LX, y: fy + 4, width: 140, height: 18); content.addSubview(l)
        }

        // Appearance
        section(secAppearance)
        var fy = row(26); label(languageLabel, fy)
        languagePopup.frame = NSRect(x: CX, y: fy, width: CW, height: 26)
        languagePopup.addItems(withTitles: [L10n.t("settings.langSystem"), "English", "한국어"])
        languagePopup.selectItem(at: Settings.language == "en" ? 1 : Settings.language == "ko" ? 2 : 0)
        languagePopup.target = self; languagePopup.action = #selector(languageChanged)
        content.addSubview(languagePopup)

        fy = row(26); label(themeLabel, fy)
        themePopup.frame = NSRect(x: CX, y: fy, width: CW, height: 26)
        themePopup.addItems(withTitles: Settings.themes)
        themePopup.selectItem(withTitle: Settings.theme)
        themePopup.target = self; themePopup.action = #selector(themeChanged)
        content.addSubview(themePopup)

        fy = row(26); label(bgLabel, fy)
        bgWell.frame = NSRect(x: CX, y: fy + 1, width: 60, height: 24)
        bgWell.color = color(fromHex: Settings.backgroundColor)
        bgWell.target = self; bgWell.action = #selector(bgChanged)
        content.addSubview(bgWell)

        fy = row(28); label(zoomLabel, fy)
        zoomField.frame = NSRect(x: CX, y: fy + 2, width: 70, height: 24)
        zoomField.integerValue = Settings.defaultZoom
        zoomField.target = self; zoomField.action = #selector(zoomFieldChanged)
        zoomStepper.frame = NSRect(x: CX + 74, y: fy, width: 20, height: 28)
        zoomStepper.minValue = 10; zoomStepper.maxValue = 800; zoomStepper.increment = 10
        zoomStepper.integerValue = Settings.defaultZoom
        zoomStepper.target = self; zoomStepper.action = #selector(zoomStepperChanged)
        content.addSubview(zoomField); content.addSubview(zoomStepper)

        sep()

        // Shortcut
        section(secShortcut)
        fy = row(28)
        shortcutCheck.frame = NSRect(x: LX, y: fy + 4, width: 300, height: 20)
        shortcutCheck.state = Settings.shortcutEnabled ? .on : .off
        shortcutCheck.target = self; shortcutCheck.action = #selector(shortcutEnabledChanged)
        recorderButton.frame = NSRect(x: W - LX - 130, y: fy, width: 130, height: 26)
        recorderButton.bezelStyle = .rounded
        recorderButton.title = Settings.shortcutDisplay
        recorderButton.target = self; recorderButton.action = #selector(startRecording)
        content.addSubview(shortcutCheck); content.addSubview(recorderButton)

        sep()

        // Window
        section(secWindow)
        fy = row(22)
        keepOpenCheck.frame = NSRect(x: LX, y: fy + 2, width: W - 2 * LX, height: 20)
        keepOpenCheck.state = Settings.closeOnFocusLoss ? .off : .on
        keepOpenCheck.target = self; keepOpenCheck.action = #selector(keepOpenChanged)
        content.addSubview(keepOpenCheck)

        sep()

        // About
        section(secAbout)
        fy = row(24)
        versionLabel.frame = NSRect(x: LX, y: fy + 3, width: 220, height: 18)
        versionLabel.textColor = .secondaryLabelColor
        releasesButton.frame = NSRect(x: W - LX - 150, y: fy - 2, width: 150, height: 26)
        releasesButton.bezelStyle = .rounded
        releasesButton.target = self; releasesButton.action = #selector(openReleases)
        content.addSubview(versionLabel); content.addSubview(releasesButton)
        fy = row(18)
        updateStatusLabel.frame = NSRect(x: LX, y: fy + 1, width: W - 2 * LX, height: 16)
        updateStatusLabel.font = .systemFont(ofSize: 11)
        content.addSubview(updateStatusLabel)

        sep()

        // Preview
        section(previewHeader)
        webView = WKWebView(frame: NSRect(x: LX, y: 16, width: W - 2 * LX, height: max(120, y - 16)))
        webView.navigationDelegate = self
        webView.wantsLayer = true
        webView.layer?.borderColor = NSColor.separatorColor.cgColor
        webView.layer?.borderWidth = 1
        webView.layer?.cornerRadius = 8
        webView.layer?.masksToBounds = true
        if let url = Bundle.main.url(forResource: "renderer", withExtension: "html") {
            var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            comps?.fragment = "preview"
            webView.loadFileURL(comps?.url ?? url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        content.addSubview(webView)

        win.contentView = content
        self.window = win
        relabel()
    }

    /// Re-apply localized strings (build time + on language change).
    private func relabel() {
        window?.title = L10n.t("settings.title")
        secAppearance.stringValue = L10n.t("settings.secAppearance")
        secShortcut.stringValue = L10n.t("settings.secShortcut")
        secWindow.stringValue = L10n.t("settings.secWindow")
        secAbout.stringValue = L10n.t("settings.secAbout")
        previewHeader.stringValue = L10n.t("settings.preview")
        languageLabel.stringValue = L10n.t("settings.language")
        languagePopup.item(at: 0)?.title = L10n.t("settings.langSystem")
        themeLabel.stringValue = L10n.t("settings.theme")
        zoomLabel.stringValue = L10n.t("settings.zoom")
        bgLabel.stringValue = L10n.t("settings.bg")
        shortcutCheck.title = L10n.t("settings.shortcut")
        keepOpenCheck.title = L10n.t("settings.keepOpen")
        versionLabel.stringValue = "\(L10n.t("settings.version")) \(Self.appVersion)"
        releasesButton.title = L10n.t("settings.openReleases")
        applyUpdateStatus()
    }

    private func applyUpdateStatus() {
        if let v = knownNewer {
            updateStatusLabel.stringValue = "\(L10n.t("settings.updateAvailable")): v\(v)"
            updateStatusLabel.textColor = .systemBlue
        } else {
            updateStatusLabel.stringValue = L10n.t("settings.upToDate")
            updateStatusLabel.textColor = .tertiaryLabelColor
        }
    }

    private func checkForUpdate() {
        UpdateCheck.checkNewer(than: Self.appVersion) { [weak self] newer in
            self?.knownNewer = newer
            self?.applyUpdateStatus()
        }
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
        webView.evaluateJavaScript("window.render(\(json)[0], '\(Settings.theme)', \(Settings.defaultZoom), '\(Settings.backgroundColor)', '\(L10n.lang)');", completionHandler: nil)
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

    @objc private func languageChanged() {
        switch languagePopup.indexOfSelectedItem {
        case 1: Settings.language = "en"
        case 2: Settings.language = "ko"
        default: Settings.language = "system"
        }
        relabel()
        updatePreview()
    }
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
        Settings.closeOnFocusLoss = (keepOpenCheck.state == .off)
    }
    @objc private func bgChanged() {
        Settings.backgroundColor = hex(from: bgWell.color)
        updatePreview()
    }
    @objc private func openReleases() {
        if let url = URL(string: UpdateCheck.releasesURL) { NSWorkspace.shared.open(url) }
    }

    // MARK: - Shortcut recorder

    @objc private func shortcutEnabledChanged() {
        Settings.shortcutEnabled = (shortcutCheck.state == .on)
        postShortcutChanged()
    }
    @objc private func startRecording() {
        recorderButton.title = L10n.t("settings.recording")
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { self.endRecording(); return nil } // Esc → cancel
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !mods.isEmpty else { return nil }
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
    private func postShortcutChanged() {
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name(Settings.changedNotification), object: nil,
            userInfo: nil, deliverImmediately: true)
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

import AppKit
import WebKit

/// A top-anchored view so panes can be laid out top-down (y grows downward).
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Native settings window with a toolbar-tabbed layout (General / Appearance /
/// Shortcut / About). The window resizes to each tab's content. Changes are saved
/// to UserDefaults immediately; the Appearance tab hosts a live preview WKWebView.
final class SettingsWindowController: NSObject, NSWindowDelegate, WKNavigationDelegate, NSToolbarDelegate {
    private var window: NSWindow?

    // Controls
    private let languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let themePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let fontPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let zoomField = NSTextField()
    private let zoomStepper = NSStepper()
    private let bgWell = NSColorWell()
    private let shortcutCheck = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let recorderButton = NSButton(title: "", target: nil, action: nil)
    private let keepOpenCheck = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let launchAtLoginCheck = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let releasesButton = NSButton(title: "", target: nil, action: nil)

    // Row labels
    private let languageLabel = NSTextField(labelWithString: "")
    private let themeLabel = NSTextField(labelWithString: "")
    private let fontLabel = NSTextField(labelWithString: "")
    private let zoomLabel = NSTextField(labelWithString: "")
    private let bgLabel = NSTextField(labelWithString: "")
    private let previewHeader = NSTextField(labelWithString: "")
    private let versionLabel = NSTextField(labelWithString: "")
    private let updateStatusLabel = NSTextField(labelWithString: "")

    private var webView: WKWebView!
    private var previewLoaded = false
    private var recordingMonitor: Any?
    private var knownNewer: String?   // newer version found by the update check, if any

    // Tabs
    private enum Tab: String, CaseIterable {
        case general, appearance, shortcut, about
        var labelKey: String {
            switch self {
            case .general: return "settings.secGeneral"
            case .appearance: return "settings.secAppearance"
            case .shortcut: return "settings.secShortcut"
            case .about: return "settings.secAbout"
            }
        }
        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .appearance: return "paintpalette"
            case .shortcut: return "keyboard"
            case .about: return "info.circle"
            }
        }
    }
    private var panes: [Tab: NSView] = [:]
    private var toolbarItems: [Tab: NSToolbarItem] = [:]
    private var current: Tab = .general

    private static let W: CGFloat = 520
    private static let LX: CGFloat = 24, CX: CGFloat = 168, CW: CGFloat = 300

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
        window?.level = .floating   // float above the render panel
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        checkForUpdate()
    }

    // MARK: - Build

    private func build() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.W, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.delegate = self
        win.isReleasedWhenClosed = false
        win.toolbarStyle = .preference

        let toolbar = NSToolbar(identifier: "settingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        win.toolbar = toolbar

        panes = [
            .general: makeGeneralPane(),
            .appearance: makeAppearancePane(),
            .shortcut: makeShortcutPane(),
            .about: makeAboutPane(),
        ]
        self.window = win
        relabel()
        toolbar.selectedItemIdentifier = NSToolbarItem.Identifier(current.rawValue)
        select(current, animate: false)
    }

    private func makeGeneralPane() -> NSView {
        let pane = FlippedView(frame: NSRect(x: 0, y: 0, width: Self.W, height: 10))
        var y: CGFloat = 20

        launchAtLoginCheck.frame = NSRect(x: Self.LX, y: y, width: Self.W - 2 * Self.LX, height: 20)
        launchAtLoginCheck.state = Settings.launchAtLogin ? .on : .off
        launchAtLoginCheck.target = self; launchAtLoginCheck.action = #selector(launchAtLoginChanged)
        pane.addSubview(launchAtLoginCheck); y += 20 + 16

        languageLabel.frame = NSRect(x: Self.LX, y: y + 4, width: 130, height: 18)
        languagePopup.frame = NSRect(x: Self.CX, y: y, width: Self.CW, height: 26)
        languagePopup.addItems(withTitles: [L10n.t("settings.langSystem"), "English", "한국어"])
        languagePopup.selectItem(at: Settings.language == "en" ? 1 : Settings.language == "ko" ? 2 : 0)
        languagePopup.target = self; languagePopup.action = #selector(languageChanged)
        pane.addSubview(languageLabel); pane.addSubview(languagePopup); y += 26 + 16

        keepOpenCheck.frame = NSRect(x: Self.LX, y: y, width: Self.W - 2 * Self.LX, height: 20)
        keepOpenCheck.state = Settings.closeOnFocusLoss ? .off : .on
        keepOpenCheck.target = self; keepOpenCheck.action = #selector(keepOpenChanged)
        pane.addSubview(keepOpenCheck); y += 20 + 20

        pane.frame.size.height = y
        return pane
    }

    private func makeAppearancePane() -> NSView {
        let pane = FlippedView(frame: NSRect(x: 0, y: 0, width: Self.W, height: 10))
        var y: CGFloat = 20

        themeLabel.frame = NSRect(x: Self.LX, y: y + 4, width: 130, height: 18)
        themePopup.frame = NSRect(x: Self.CX, y: y, width: Self.CW, height: 26)
        themePopup.addItems(withTitles: Settings.themes)
        themePopup.selectItem(withTitle: Settings.theme)
        themePopup.target = self; themePopup.action = #selector(themeChanged)
        pane.addSubview(themeLabel); pane.addSubview(themePopup); y += 26 + 16

        fontLabel.frame = NSRect(x: Self.LX, y: y + 4, width: 130, height: 18)
        fontPopup.frame = NSRect(x: Self.CX, y: y, width: Self.CW, height: 26)
        fontPopup.addItem(withTitle: L10n.t("settings.fontDefault"))   // maps to "default"
        fontPopup.item(at: 0)?.representedObject = "default"
        for fam in NSFontManager.shared.availableFontFamilies.sorted() {
            fontPopup.addItem(withTitle: fam)
            fontPopup.lastItem?.representedObject = fam
        }
        let savedFont = Settings.fontFamily
        fontPopup.selectItem(at: savedFont == "default" ? 0
            : (fontPopup.itemTitles.firstIndex(of: savedFont) ?? 0))
        fontPopup.target = self; fontPopup.action = #selector(fontChanged)
        pane.addSubview(fontLabel); pane.addSubview(fontPopup); y += 26 + 16

        bgLabel.frame = NSRect(x: Self.LX, y: y + 3, width: 130, height: 18)
        bgWell.frame = NSRect(x: Self.CX, y: y, width: 60, height: 24)
        bgWell.color = color(fromHex: Settings.backgroundColor)
        bgWell.target = self; bgWell.action = #selector(bgChanged)
        pane.addSubview(bgLabel); pane.addSubview(bgWell); y += 26 + 16

        zoomLabel.frame = NSRect(x: Self.LX, y: y + 4, width: 130, height: 18)
        zoomField.frame = NSRect(x: Self.CX, y: y, width: 70, height: 24)
        zoomField.integerValue = Settings.defaultZoom
        zoomField.target = self; zoomField.action = #selector(zoomFieldChanged)
        zoomStepper.frame = NSRect(x: Self.CX + 74, y: y, width: 20, height: 26)
        zoomStepper.minValue = 10; zoomStepper.maxValue = 800; zoomStepper.increment = 10
        zoomStepper.integerValue = Settings.defaultZoom
        zoomStepper.target = self; zoomStepper.action = #selector(zoomStepperChanged)
        pane.addSubview(zoomLabel); pane.addSubview(zoomField); pane.addSubview(zoomStepper); y += 26 + 18

        previewHeader.font = .systemFont(ofSize: 11, weight: .semibold)
        previewHeader.textColor = .tertiaryLabelColor
        previewHeader.frame = NSRect(x: Self.LX, y: y, width: Self.W - 2 * Self.LX, height: 14)
        pane.addSubview(previewHeader); y += 14 + 6

        let previewH: CGFloat = 200
        webView = WKWebView(frame: NSRect(x: Self.LX, y: y, width: Self.W - 2 * Self.LX, height: previewH))
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
        pane.addSubview(webView); y += previewH + 20

        pane.frame.size.height = y
        return pane
    }

    private func makeShortcutPane() -> NSView {
        let pane = FlippedView(frame: NSRect(x: 0, y: 0, width: Self.W, height: 10))
        var y: CGFloat = 20

        shortcutCheck.frame = NSRect(x: Self.LX, y: y, width: Self.W - 2 * Self.LX, height: 20)
        shortcutCheck.state = Settings.shortcutEnabled ? .on : .off
        shortcutCheck.target = self; shortcutCheck.action = #selector(shortcutEnabledChanged)
        pane.addSubview(shortcutCheck); y += 20 + 14

        recorderButton.frame = NSRect(x: Self.LX, y: y, width: 150, height: 26)
        recorderButton.bezelStyle = .rounded
        recorderButton.title = Settings.shortcutDisplay
        recorderButton.target = self; recorderButton.action = #selector(startRecording)
        pane.addSubview(recorderButton); y += 26 + 20

        pane.frame.size.height = y
        return pane
    }

    private func makeAboutPane() -> NSView {
        let pane = FlippedView(frame: NSRect(x: 0, y: 0, width: Self.W, height: 10))
        var y: CGFloat = 24

        versionLabel.frame = NSRect(x: Self.LX, y: y + 3, width: 240, height: 18)
        versionLabel.textColor = .secondaryLabelColor
        releasesButton.frame = NSRect(x: Self.W - Self.LX - 150, y: y, width: 150, height: 26)
        releasesButton.bezelStyle = .rounded
        releasesButton.target = self; releasesButton.action = #selector(openReleases)
        pane.addSubview(versionLabel); pane.addSubview(releasesButton); y += 26 + 12

        updateStatusLabel.frame = NSRect(x: Self.LX, y: y, width: Self.W - 2 * Self.LX, height: 16)
        updateStatusLabel.font = .systemFont(ofSize: 11)
        pane.addSubview(updateStatusLabel); y += 16 + 20

        pane.frame.size.height = y
        return pane
    }

    // MARK: - Tab switching

    private func select(_ tab: Tab, animate: Bool) {
        guard let win = window, let pane = panes[tab] else { return }
        current = tab
        win.title = L10n.t(tab.labelKey)
        let h = pane.frame.height
        pane.frame = NSRect(x: 0, y: 0, width: Self.W, height: h)
        win.contentView = pane

        // Resize the window to the pane height, keeping the top-left corner fixed.
        var frame = win.frameRect(forContentRect: NSRect(x: 0, y: 0, width: Self.W, height: h))
        let top = win.frame.maxY
        frame.origin.x = win.frame.origin.x
        frame.origin.y = top - frame.height
        win.setFrame(frame, display: true, animate: animate)

        if tab == .appearance { updatePreview() }
    }

    @objc private func toolbarItemSelected(_ sender: NSToolbarItem) {
        guard let tab = Tab(rawValue: sender.itemIdentifier.rawValue) else { return }
        window?.toolbar?.selectedItemIdentifier = sender.itemIdentifier
        select(tab, animate: true)
    }

    // MARK: - NSToolbarDelegate

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let tab = Tab(rawValue: identifier.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: nil)
        item.label = L10n.t(tab.labelKey)
        item.target = self
        item.action = #selector(toolbarItemSelected(_:))
        toolbarItems[tab] = item
        return item
    }

    private var tabIdentifiers: [NSToolbarItem.Identifier] {
        Tab.allCases.map { NSToolbarItem.Identifier($0.rawValue) }
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { tabIdentifiers }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { tabIdentifiers }
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { tabIdentifiers }

    // MARK: - Localized labels

    /// Re-apply localized strings (build time + on language change).
    private func relabel() {
        for (tab, item) in toolbarItems { item.label = L10n.t(tab.labelKey) }
        window?.title = L10n.t(current.labelKey)
        previewHeader.stringValue = L10n.t("settings.preview")
        languageLabel.stringValue = L10n.t("settings.language")
        languagePopup.item(at: 0)?.title = L10n.t("settings.langSystem")
        themeLabel.stringValue = L10n.t("settings.theme")
        fontLabel.stringValue = L10n.t("settings.font")
        fontPopup.item(at: 0)?.title = L10n.t("settings.fontDefault")
        zoomLabel.stringValue = L10n.t("settings.zoom")
        bgLabel.stringValue = L10n.t("settings.bg")
        launchAtLoginCheck.title = L10n.t("settings.launchAtLogin")
        shortcutCheck.title = L10n.t("settings.shortcut")
        keepOpenCheck.title = L10n.t("settings.keepOpen")
        versionLabel.stringValue = "\(L10n.t("settings.version")) \(AppInfo.displayVersion)"
        releasesButton.title = L10n.t("settings.openReleases")
        applyUpdateStatus()
    }

    private func applyUpdateStatus() {
        // A dev build doesn't check for updates (see checkForUpdate), so it can't claim "up to date".
        updateStatusLabel.isHidden = AppInfo.isDevBuild
        if let v = knownNewer {
            updateStatusLabel.stringValue = "\(L10n.t("settings.updateAvailable")): v\(v)"
            updateStatusLabel.textColor = .systemBlue
        } else {
            updateStatusLabel.stringValue = L10n.t("settings.upToDate")
            updateStatusLabel.textColor = .tertiaryLabelColor
        }
    }

    private func checkForUpdate() {
        guard !AppInfo.isDevBuild else { return }
        UpdateCheck.checkNewer(than: AppInfo.version) { [weak self] newer in
            self?.knownNewer = newer
            self?.applyUpdateStatus()
        }
    }

    private func updatePreview() {
        guard previewLoaded else { return }
        let json: String
        if let data = try? JSONSerialization.data(withJSONObject: [Self.sample, Settings.fontFamily]),
           let str = String(data: data, encoding: .utf8) {
            json = str
        } else {
            json = "[\"\",\"default\"]"
        }
        webView.evaluateJavaScript("window.render(\(json)[0], '\(Settings.theme)', \(Settings.defaultZoom), '\(Settings.backgroundColor)', '\(L10n.lang)', \(json)[1]);", completionHandler: nil)
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
    @objc private func fontChanged() {
        // Like theme/background, the font is re-read on the panel's next render — no
        // notification needed (the settings-changed notification only re-registers the hotkey).
        Settings.fontFamily = (fontPopup.selectedItem?.representedObject as? String) ?? "default"
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
    @objc private func launchAtLoginChanged() {
        Settings.launchAtLogin = (launchAtLoginCheck.state == .on)
        // Reflect the real resulting state — registration can fail (then it stays off).
        launchAtLoginCheck.state = Settings.launchAtLogin ? .on : .off
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

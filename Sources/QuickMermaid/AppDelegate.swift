import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let mode: AppMode
    private var statusItem: NSStatusItem?
    private let panel = MermaidPanelController()
    private var services: ServicesProvider?
    private let settings = SettingsWindowController()
    private let hotkey = HotkeyManager()
    /// Set when a quickmermaid:// URL or a diagram file is opened during launch, so the cold-launch
    /// Settings window (which would otherwise pop in front of the rendered diagram)
    /// is suppressed. See `application(_:open:)`.
    private var didOpenURLOnLaunch = false

    init(mode: AppMode) {
        self.mode = mode
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // ⌘, from the render panel opens Settings (used in cli/service modes)
        panel.onOpenSettings = { [weak self] in self?.openSettings() }
        switch mode {
        case .selfTest:
            runSelfTest()
        case .test:
            panel.runTests { json in
                FileHandle.standardError.write(Data("TEST \(json)\n".utf8))
                exit(json.contains("\"failed\":[]") ? 0 : 1)
            }
        case .cli(let code):
            runCLI(code: code)
        case .settings:
            settings.onClose = { NSApp.terminate(nil) }
            settings.show()
        case .service:
            setupStatusItem()
            registerService()
            applyHotkeySettings()
            // Re-register the hotkey when settings change from another process (qmmd --settings)
            DistributedNotificationCenter.default().addObserver(
                self, selector: #selector(settingsChanged),
                name: NSNotification.Name(Settings.changedNotification), object: nil)
            checkForUpdate()
            // Opening the app (Finder/Dock) surfaces Settings, since the app has no
            // main window otherwise. Suppressed for the silent login launch: when
            // launch-at-login is on, a cold launch is the one the system did at
            // login. A manual re-launch while running goes through reopen below.
            // Deferred a tick so a quickmermaid:// cold launch — whose open(_:)
            // arrives right after this — can cancel it (render, don't pop Settings).
            if !Settings.launchAtLogin {
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.didOpenURLOnLaunch else { return }
                    self.openSettings()
                }
            }
        }
    }

    /// Re-opening the app (double-click / Dock) while it's already running surfaces Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if case .service = mode { openSettings() }
        return true
    }

    // MARK: - Opened URLs (quickmermaid:// links, .mmd / .mermaid files)

    /// LaunchServices delivers clicked `quickmermaid://render?data=…` links and
    /// opened `.mmd` / `.mermaid` files (Finder double-click, Open With, `open -a`)
    /// here (cold launch → after didFinishLaunching; running app → routed to this
    /// instance). The source renders just like any other input source.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard case .service = mode else { return }
        for url in urls {
            let source = url.isFileURL
                ? try? String(contentsOf: url, encoding: .utf8)
                : URLScheme.decode(url: url)
            guard let code = source,
                  !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            didOpenURLOnLaunch = true
            panel.show(code: code)
        }
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Check GitHub Releases on launch; if a newer version exists, surface it in the menu.
    private func checkForUpdate() {
        UpdateCheck.checkNewer(than: Self.appVersion) { [weak self] newer in
            guard let self, let newer, let menu = self.statusItem?.menu else { return }
            let title = "\(L10n.t("menu.updateAvailable")) (v\(newer))"
            let item = NSMenuItem(title: title, action: #selector(self.openReleases), keyEquivalent: "")
            item.target = self
            menu.insertItem(item, at: 0)
            menu.insertItem(.separator(), at: 1)
        }
    }

    @objc private func openReleases() {
        if let url = URL(string: UpdateCheck.releasesURL) { NSWorkspace.shared.open(url) }
    }

    // Explicitly declare secure coding for state restoration → suppresses console warnings
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: - Menu bar

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let image = NSImage(systemSymbolName: "chart.bar.doc.horizontal", accessibilityDescription: "QuickMermaid") {
            image.isTemplate = true
            item.button?.image = image
        } else {
            item.button?.title = "M"
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "QuickMermaid", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: L10n.t("menu.settings"), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.t("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        self.statusItem = item
    }

    @objc private func openSettings() {
        settings.onClose = nil  // In the resident app, closing the settings window does not quit the app
        settings.show()
    }

    // MARK: - Services

    private func registerService() {
        let provider = ServicesProvider { [weak self] text in
            // Only show the panel when there is text worth rendering
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            self?.panel.show(code: text)
        }
        NSApp.servicesProvider = provider
        // Refresh the Services menu items dynamically for immediate exposure
        NSUpdateDynamicServices()
        self.services = provider
    }

    // MARK: - Global Shortcut

    @objc private func settingsChanged() {
        applyHotkeySettings()
    }

    private func applyHotkeySettings() {
        hotkey.unregister()
        guard Settings.shortcutEnabled else { return }
        // Copying the selection (⌘C synthesis) requires Accessibility permission → prompts the system dialog if not granted
        if !AXIsProcessTrusted() {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        }
        let mods = HotkeyManager.carbonModifiers(fromNSFlags: Settings.shortcutModifiers)
        hotkey.register(keyCode: UInt32(Settings.shortcutKeyCode), carbonModifiers: mods) { [weak self] in
            self?.onHotkey()
        }
    }

    private func onHotkey() {
        // Priority: selection → clipboard → (if neither) show nothing
        guard let text = SelectionReader.resolveSource() else { return }
        panel.show(code: text)
    }

    // MARK: - CLI (--stdin)

    private func runCLI(code: String) {
        // Exit without showing a window if there is no text worth rendering
        guard !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            exit(0)
        }
        // Single-use viewer that renders once. Closing the panel quits the app.
        panel.onClose = { NSApp.terminate(nil) }
        panel.show(code: code)
    }

    // MARK: - Self test

    private func runSelfTest() {
        let sample = """
        graph TD
          A[Start] --> B{OK?}
          B -->|yes| C[Done]
          B -->|no| A
        """
        panel.runSelfTest(code: sample) { ok, info in
            let line = "SELFTEST \(ok ? "PASS" : "FAIL"): \(info)\n"
            FileHandle.standardError.write(Data(line.utf8))
            exit(ok ? 0 : 1)
        }
    }
}

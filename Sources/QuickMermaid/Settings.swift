import AppKit

/// User settings. Stored in UserDefaults(standard) and shared between the resident app and CLI instances.
/// (All instances run under the same bundle id `me.wickso.quickmermaid`, so they share the same domain.)
enum Settings {
    static let themes = ["default", "dark", "forest", "neutral", "base"]

    private static let d = UserDefaults.standard
    private static let kTheme = "theme"
    private static let kZoom = "defaultZoom"
    private static let kCloseOnFocusLoss = "closeOnFocusLoss"
    private static let kBackground = "backgroundColor"
    private static let kShortcutEnabled = "shortcutEnabled"
    private static let kShortcutKeyCode = "shortcutKeyCode"
    private static let kShortcutModifiers = "shortcutModifiers"
    private static let kShortcutDisplay = "shortcutDisplay"

    /// Name of the distributed notification that informs the resident app of a settings change (for hotkey re-registration).
    static let changedNotification = "me.wickso.quickmermaid.settingsChanged"

    static var theme: String {
        get { themes.contains(d.string(forKey: kTheme) ?? "") ? d.string(forKey: kTheme)! : "default" }
        set { d.set(newValue, forKey: kTheme) }
    }

    /// Default zoom level (%). Defaults to 100 when not set.
    static var defaultZoom: Int {
        get { let v = d.integer(forKey: kZoom); return v == 0 ? 100 : v }
        set { d.set(newValue, forKey: kZoom) }
    }

    /// Whether to automatically close the panel when it loses focus. Defaults to true (close) when not set.
    static var closeOnFocusLoss: Bool {
        get { d.object(forKey: kCloseOnFocusLoss) == nil ? true : d.bool(forKey: kCloseOnFocusLoss) }
        set { d.set(newValue, forKey: kCloseOnFocusLoss) }
    }

    /// Canvas background color (hex, e.g. "#FFFFFF"). Independent of the mermaid theme. Defaults to white when not set.
    static var backgroundColor: String {
        get { d.string(forKey: kBackground) ?? "#FFFFFF" }
        set { d.set(newValue, forKey: kBackground) }
    }

    // MARK: - Global Shortcut

    /// Enable rendering the selected region as a diagram via shortcut. Defaults to false when not set (avoids Accessibility permission prompt).
    static var shortcutEnabled: Bool {
        get { d.bool(forKey: kShortcutEnabled) }
        set { d.set(newValue, forKey: kShortcutEnabled) }
    }

    /// Shortcut key code. Defaults to 'M' (kVK_ANSI_M = 46) when not set.
    static var shortcutKeyCode: Int {
        get { d.object(forKey: kShortcutKeyCode) == nil ? 46 : d.integer(forKey: kShortcutKeyCode) }
        set { d.set(newValue, forKey: kShortcutKeyCode) }
    }

    /// Shortcut modifier flags (NSEvent.ModifierFlags raw value). Defaults to ⌘+⌃ when not set.
    static var shortcutModifiers: Int {
        get {
            if d.object(forKey: kShortcutModifiers) == nil {
                return Int(NSEvent.ModifierFlags([.command, .control]).rawValue)
            }
            return d.integer(forKey: kShortcutModifiers)
        }
        set { d.set(newValue, forKey: kShortcutModifiers) }
    }

    /// Shortcut display string. Defaults to "⌃⌘M" when not set.
    static var shortcutDisplay: String {
        get { d.string(forKey: kShortcutDisplay) ?? "⌃⌘M" }
        set { d.set(newValue, forKey: kShortcutDisplay) }
    }
}

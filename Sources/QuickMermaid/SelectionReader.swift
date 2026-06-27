import AppKit
import Carbon.HIToolbox

/// Resolves the text to render in priority order.
///   1) Selection (copied via ⌘C synthesis) → use it if available
///   2) Otherwise, the text on the clipboard
///   3) If both are empty or not text, return nil (→ caller does not show a window)
/// For ⌘C synthesis to be delivered to another app, this app must have Accessibility permission.
enum SelectionReader {
    static func resolveSource() -> String? {
        let pb = NSPasteboard.general
        let before = pb.changeCount
        let prevString = pb.string(forType: .string)

        // Attempt to copy the current selection via ⌘C synthesis
        let src = CGEventSource(stateID: .combinedSessionState)
        let cDown = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)
        let cUp = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)
        cDown?.flags = .maskCommand
        cUp?.flags = .maskCommand
        cDown?.post(tap: .cghidEventTap)
        cUp?.post(tap: .cghidEventTap)

        // Wait for the clipboard to update (changeCount changes if there is a selection)
        let deadline = Date().addingTimeInterval(0.4)
        while pb.changeCount == before && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }

        let selection: String? = (pb.changeCount != before) ? pb.string(forType: .string) : nil

        // If the selection overwrote the clipboard, restore the previous text (best-effort)
        if pb.changeCount != before, let prevString {
            pb.clearContents()
            pb.setString(prevString, forType: .string)
        }

        // Priority: selection (if non-empty) → clipboard → nil
        return nonEmpty(selection) ?? nonEmpty(prevString)
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return s
    }
}

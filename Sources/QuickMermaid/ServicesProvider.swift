import AppKit

/// macOS Services handler. Matched to `NSServices > NSMessage = renderMermaid` in Info.plist
/// via the selector `renderMermaid:userData:error:`.
/// The OS delivers the selected text directly via the pasteboard, so no Accessibility permission is needed.
final class ServicesProvider: NSObject {
    private let onText: (String) -> Void

    init(onText: @escaping (String) -> Void) {
        self.onText = onText
        super.init()
    }

    @objc func renderMermaid(
        _ pboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        let text = pboard.string(forType: .string) ?? ""
        DispatchQueue.main.async { [onText] in
            onText(text)
        }
    }
}

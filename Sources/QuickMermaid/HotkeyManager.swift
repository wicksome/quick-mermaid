import AppKit
import Carbon.HIToolbox

/// Global shortcut based on Carbon `RegisterEventHotKey`. Registration itself requires no additional permissions.
final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var onPressed: (() -> Void)?
    // 'MQK1' signature
    private let hotKeyID = EventHotKeyID(signature: 0x4D514B31, id: 1)

    /// Converts NSEvent modifier flags (raw) to Carbon modifier bits.
    static func carbonModifiers(fromNSFlags raw: Int) -> UInt32 {
        let f = NSEvent.ModifierFlags(rawValue: UInt(raw))
        var m: UInt32 = 0
        if f.contains(.command) { m |= UInt32(cmdKey) }
        if f.contains(.option)  { m |= UInt32(optionKey) }
        if f.contains(.control) { m |= UInt32(controlKey) }
        if f.contains(.shift)   { m |= UInt32(shiftKey) }
        return m
    }

    func register(keyCode: UInt32, carbonModifiers: UInt32, onPressed: @escaping () -> Void) {
        unregister()
        self.onPressed = onPressed

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData -> OSStatus in
            guard let userData else { return noErr }
            let mgr = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            mgr.onPressed?()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)

        RegisterEventHotKey(keyCode, carbonModifiers, hotKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref); hotKeyRef = nil }
        if let h = eventHandler { RemoveEventHandler(h); eventHandler = nil }
        onPressed = nil
    }
}

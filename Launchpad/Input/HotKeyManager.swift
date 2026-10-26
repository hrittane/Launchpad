import AppKit
import Carbon

/// Carbon `RegisterEventHotKey` does not need Accessibility permission, which
/// makes it the right choice for a menu-bar agent. A single global handler is
/// installed once, and the registered key can be changed at runtime.
final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var isHandlerInstalled = false

    var onPress: (() -> Void)?

    private let hotKeyID = EventHotKeyID(signature: OSType(0x4C504144), id: 1) // 'LPAD'

    init() {
        installHandlerIfNeeded()
    }

    func register(_ shortcut: KeyShortcut) {
        unregister()
        guard shortcut.isValid else { return }
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            Self.carbonModifiers(for: shortcut.modifierFlagsValue),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        if status == noErr {
            hotKeyRef = reference
        } else {
            // F4 and some combinations can already be claimed by the system.
            // The status-menu item remains available as a fallback.
            NSLog("Launchpad: could not register global shortcut %@ (OSStatus %d)", shortcut.displayString, status)
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard !isHandlerInstalled else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                // Carbon delivers hot-key events on the main event loop.
                manager.onPress?()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
        isHandlerInstalled = status == noErr
        if !isHandlerInstalled {
            NSLog("Launchpad: could not install global hot-key handler (OSStatus %d)", status)
        }
    }

    private static func carbonModifiers(for flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return modifiers
    }
}

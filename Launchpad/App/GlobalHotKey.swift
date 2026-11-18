import Carbon.HIToolbox

/// A system-wide keyboard shortcut.
///
/// Carbon's `RegisterEventHotKey` is still the only API that delivers a shortcut
/// while another application is frontmost without asking for Accessibility
/// permission; `NSEvent.addGlobalMonitorForEvents` needs that permission and
/// only observes. The registration is therefore deliberately Carbon, not
/// AppKit — the rest of the app stays AppKit/SwiftUI.
@MainActor
final class GlobalHotKey {
    private static var registry: [UInt32: GlobalHotKey] = [:]
    private static var nextIdentifier: UInt32 = 1

    /// `'LPad'`, the four-character code that identifies our hot keys.
    private static let signature: OSType = 0x4C_50_61_64

    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let identifier: UInt32
    private let action: () -> Void

    /// - Returns: `nil` when the system refuses the shortcut, which happens
    ///   when another application already owns it.
    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        identifier = Self.nextIdentifier
        Self.nextIdentifier += 1

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            globalHotKeyHandler,
            1,
            &eventType,
            nil,
            &eventHandler
        )
        guard handlerStatus == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: identifier)
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        guard registerStatus == noErr, hotKey != nil else {
            if let eventHandler {
                RemoveEventHandler(eventHandler)
            }
            return nil
        }

        Self.registry[identifier] = self
    }

    /// Called from the Carbon handler. The handler runs on the main thread
    /// because it is installed on the application event target, so the work can
    /// step straight back into the main actor.
    nonisolated fileprivate static func activate(identifier: UInt32) {
        MainActor.assumeIsolated {
            registry[identifier]?.action()
        }
    }
}

/// The Carbon event handler that routes a hot-key press to its registration.
private func globalHotKeyHandler(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    GlobalHotKey.activate(identifier: hotKeyID.id)
    return noErr
}

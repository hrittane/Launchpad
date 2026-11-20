import AppKit
import ApplicationServices
import os

/// Records what the blocker sees, so a missing gesture can be diagnosed from
/// `log show` without guessing whether Accessibility or the event stream is at
/// fault.
private let gestureLog = Logger(subsystem: "com.example.Launchpad", category: "gesture")

/// Decides whether the session event tap drops an event.
///
/// Kept separate from the tap so the rules can be tested without Accessibility
/// access or a live window server, and so a future change to the event mask
/// cannot silently swallow scrolling.
struct DockGesturePolicy: Equatable {
    /// `gesture` (29) and `dockControl` (30): the two private event types the
    /// Dock uses for trackpad swipes, Mission Control, Show Desktop and its
    /// app-launcher pinch.
    static let blockedEventTypes: Set<UInt32> = [29, 30]

    /// Only these types are subscribed to, so the tap never sees a keystroke,
    /// a scroll wheel or a mouse click.
    static let eventMask: CGEventMask =
        (1 << CGEventMask(29)) | (1 << CGEventMask(30))

    /// The Dock delivers some of these events on the session stream and posts
    /// others into the annotated session, so a tap is installed at both places.
    /// Missing one location would let a single gesture through.
    static let tapLocations: [CGEventTapLocation] = [
        .cgSessionEventTap,
        .cgAnnotatedSessionEventTap
    ]

    var isBlocking = false

    func shouldSwallow(eventType: UInt32) -> Bool {
        isBlocking && Self.blockedEventTypes.contains(eventType)
    }
}

/// Swallows the Dock's trackpad gestures while Launchpad is on screen.
///
/// The Dock turns a three- or four-finger swipe, a pinch and a spread into
/// private `gesture` (29) and `dockControl` (30) events on the session stream;
/// it then slides the desktop, reveals it, or opens Mission Control. Launchpad
/// needs those gestures to itself, so an active session tap drops every event
/// of those two types for as long as the panel is visible. Two-finger paging
/// arrives as scroll-wheel events and is untouched, and the raw contacts used
/// for pinch-to-open and spread-to-close are read straight from the trackpad,
/// so they keep working while their system equivalents stand down.
///
/// The tap needs Accessibility access. Without it Launchpad still works and the
/// system gestures stay enabled, which is why the settings panel walks the user
/// through the grant.
final class TrackpadGestureBlocker: @unchecked Sendable {
    static let shared = TrackpadGestureBlocker()

    /// One installed tap. The blocker keeps both locations alive together so a
    /// gesture can never slip through the one that was left out.
    private struct TapHandle {
        var tap: CFMachPort
        var source: CFRunLoopSource
        var location: CGEventTapLocation
    }

    private let lock = NSLock()
    private var policy = DockGesturePolicy()
    private var taps: [TapHandle] = []
    private var swallowedCount = 0

    private init() {}

    var isInstalled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !taps.isEmpty
    }

    var isBlocking: Bool {
        lock.lock()
        defer { lock.unlock() }
        return policy.isBlocking
    }

    /// Accessibility is the one permission this feature needs. It is checked
    /// live so the settings window can reflect a grant without a relaunch.
    var isTrusted: Bool { AXIsProcessTrusted() }

    /// Starts or stops dropping Dock gestures. Called as the panel appears and
    /// leaves; the tap itself stays installed between presentations.
    func setBlocking(_ value: Bool) {
        lock.lock()
        let changed = policy.isBlocking != value
        policy.isBlocking = value
        lock.unlock()
        if changed {
            gestureLog.notice("blocking dock gestures: \(value, privacy: .public)")
        }
    }

    /// Removes the taps. Used when the app quits or the user reinstalls it.
    func uninstall() {
        lock.lock()
        let handles = taps
        taps = []
        policy.isBlocking = false
        lock.unlock()

        for handle in handles {
            CGEvent.tapEnable(tap: handle.tap, enable: false)
            CFMachPortInvalidate(handle.tap)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), handle.source, .commonModes)
        }
    }

    /// Installs the taps when Accessibility access has been granted.
    @discardableResult
    func installIfTrusted() -> Bool {
        guard AXIsProcessTrusted() else {
            gestureLog.error("gesture tap not installed: Accessibility not granted")
            if isInstalled { uninstall() }
            return false
        }
        if isInstalled { return true }

        var installed: [TapHandle] = []
        for location in DockGesturePolicy.tapLocations {
            guard let tap = CGEvent.tapCreate(
                tap: location,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: DockGesturePolicy.eventMask,
                callback: trackpadGestureTapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ), let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else {
                gestureLog.error(
                    "gesture tap creation failed at location \(location.rawValue, privacy: .public)"
                )
                continue
            }
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            installed.append(TapHandle(tap: tap, source: source, location: location))
        }

        guard !installed.isEmpty else { return false }

        lock.lock()
        taps = installed
        lock.unlock()
        gestureLog.notice(
            "gesture taps installed: \(installed.count, privacy: .public) locations"
        )
        return true
    }

    // Accessibility is requested only from Settings, never while the panel is
    // being presented or the app is launching. The system's consent dialog is
    // owned by `AccessibilityAccess.grant()`, which runs when the user clicks
    // Enable on the Accessibility row.

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock()
            let handles = taps
            lock.unlock()
            for handle in handles {
                CGEvent.tapEnable(tap: handle.tap, enable: true)
            }
            return pass
        }

        lock.lock()
        let swallow = policy.shouldSwallow(eventType: type.rawValue)
        if swallow {
            swallowedCount += 1
            if swallowedCount == 1 || swallowedCount % 40 == 0 {
                let total = swallowedCount
                gestureLog.notice(
                    "swallowed dock gesture type \(type.rawValue, privacy: .public) (\(total, privacy: .public))"
                )
            }
        }
        lock.unlock()
        return swallow ? nil : pass
    }
}

/// The C callback of the session tap. The singleton outlives the tap, so the
/// unretained pointer stored in `userInfo` is safe to read back here.
private func trackpadGestureTapCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let blocker = Unmanaged<TrackpadGestureBlocker>
        .fromOpaque(UnsafeRawPointer(userInfo))
        .takeUnretainedValue()
    return blocker.handle(type: type, event: event)
}

import Foundation

/// Temporarily turns off macOS's own Launchpad / Spotlight Apps pinch while
/// Launchpad owns the four-finger gesture.
///
/// This follows the **Pinch with four fingers** switch: turning it off lets the
/// Dock's own Apps pinch return. On macOS 26 the former Launchpad pinch opens
/// the Spotlight-based Apps view. The Dock gates that gesture with
/// `showSpotlightGestureEnabled`; older systems use `showLaunchpadGestureEnabled`.
/// Both are private but stable, and they are the only switches that stop the
/// system app-launcher pinch without breaking the separate spread-to-show-desktop
/// gesture. Spotlight's ⌘Space shortcut is unaffected.
@MainActor
final class SystemLaunchpadGesture {
    static let shared = SystemLaunchpadGesture()

    private let domain = "com.apple.dock"

    /// `showSpotlightGestureEnabled` is the macOS 26 key; the Launchpad key is
    /// kept for older systems and for the legacy Dock code path.
    private let keys = [
        "showSpotlightGestureEnabled",
        "showLaunchpadGestureEnabled"
    ]

    private let activeKey = "Launchpad.systemGestureOverrideActive"
    private let originalsKey = "Launchpad.systemGestureOriginalValues"

    /// Storage used before the Spotlight key was known. Read once so an
    /// override left behind by an older build is restored, never stranded.
    private let legacyActiveKey = "Launchpad.systemPinchOverrideActive"
    private let legacyOriginalKey = "Launchpad.systemPinchOriginalValue"

    private let defaults = UserDefaults.standard

    private init() {}

    var isOverrideActive: Bool {
        defaults.bool(forKey: activeKey) || defaults.bool(forKey: legacyActiveKey)
    }

    /// Enables or restores the system pinch. Only restarts the Dock when a
    /// stored value actually changes.
    func setEnabled(_ enabled: Bool) {
        if enabled {
            enableOverride()
        } else {
            restoreOriginal()
        }
    }

    /// Puts Show Desktop back on if an older build left it off.
    ///
    /// Previous versions rewrote `showDesktopGestureEnabled` around every
    /// presentation. A build that was killed while the panel was open could
    /// strand the preference, and a later Dock launch would then read it as
    /// disabled. Show Desktop is now blocked at the event level instead, so the
    /// preference is restored once and never touched again.
    func restoreShowDesktopGestureOnce() {
        let marker = "Launchpad.restoredShowDesktopGesture"
        guard !defaults.bool(forKey: marker) else { return }
        defaults.set(true, forKey: marker)

        // A crash flag means the old build may still need to restore its saved
        // value; leave that case to a person rather than guessing.
        let legacySuppressed = defaults.bool(forKey: "Launchpad.desktopGestureSuppressed")
        guard !legacySuppressed, value(for: "showDesktopGestureEnabled") == 0 else { return }
        write(1, for: "showDesktopGestureEnabled")
        synchronize()
    }

    private func enableOverride() {
        var originals = storedOriginals()
        var didChange = false

        for key in keys {
            if originals[key] == nil {
                originals[key] = originalValue(for: key) ?? 1
            }
            if value(for: key) != 0 {
                write(0, for: key)
                didChange = true
            }
        }

        defaults.set(originals, forKey: originalsKey)
        defaults.set(true, forKey: activeKey)
        migrateLegacyStorage()
        synchronize()

        if didChange {
            restartDock()
        }
    }

    private func restoreOriginal() {
        guard isOverrideActive else { return }
        let originals = storedOriginals()
        var didChange = false

        for key in keys {
            let original = originalValue(for: key) ?? originals[key] ?? 1
            if value(for: key) != original {
                write(original, for: key)
                didChange = true
            }
        }

        synchronize()
        defaults.removeObject(forKey: originalsKey)
        defaults.set(false, forKey: activeKey)
        migrateLegacyStorage()

        if didChange {
            restartDock()
        }
    }

    /// Values saved by the single-key implementation, folded into the
    /// dictionary the current implementation uses.
    private func storedOriginals() -> [String: Int] {
        var originals = defaults.dictionary(forKey: originalsKey) as? [String: Int] ?? [:]
        if originals["showLaunchpadGestureEnabled"] == nil,
           let legacy = defaults.object(forKey: legacyOriginalKey) as? Int {
            originals["showLaunchpadGestureEnabled"] = legacy
        }
        return originals
    }

    /// The value to restore when no saved original exists. The Spotlight key is
    /// absent on a fresh system, where the gesture is enabled by default.
    private func originalValue(for key: String) -> Int? {
        if let stored = storedOriginals()[key] { return stored }
        if key == "showSpotlightGestureEnabled" { return 1 }
        return value(for: key) ?? 1
    }

    private func migrateLegacyStorage() {
        if defaults.object(forKey: legacyOriginalKey) != nil {
            defaults.removeObject(forKey: legacyOriginalKey)
        }
        if defaults.bool(forKey: legacyActiveKey) {
            defaults.set(false, forKey: legacyActiveKey)
        }
    }

    private func value(for key: String) -> Int? {
        let value = CFPreferencesCopyAppValue(key as CFString, domain as CFString)
        return (value as? NSNumber)?.intValue
    }

    private func write(_ value: Int, for key: String) {
        CFPreferencesSetAppValue(
            key as CFString,
            NSNumber(value: value),
            domain as CFString
        )
    }

    private func synchronize() {
        CFPreferencesAppSynchronize(domain as CFString)
    }

    /// The Dock reads the preference at launch. `killall Dock` is the supported
    /// way to make it re-read without logging the user out; the system restarts
    /// it within a second and no windows are lost.
    private func restartDock() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Dock"]
        try? process.run()
    }
}

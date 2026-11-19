/// Keeps macOS's "Show Desktop" gesture pair from colliding with Launchpad.
///
/// The system uses the same four-finger gestures that this app owns: a spread
/// reveals the desktop, and the following pinch puts the windows back. Launchpad
/// also opens on a pinch, so without remembering the pair the gesture that
/// restores the desktop would open the launcher instead.
///
/// The recognizer already emits at most one gesture per contact sequence and
/// requires the fingers to lift between sequences, so a spread is always seen
/// before the restoring pinch. No timeout is involved: a user may spend a long
/// time on the desktop before pinching the windows back, and suppressing that
/// pinch must never depend on how fast they were.
struct DesktopRevealState {
    /// True after a spread with nothing on screen, until its restoring pinch
    /// is consumed.
    private(set) var awaitingRestorePinch = false

    mutating func noteSpread(panelWasVisible: Bool) {
        // While the launcher is up the Dock's gesture events are blocked, so a
        // spread there closes the panel without revealing the desktop. Only a
        // spread with no panel on screen is the native "Show Desktop" gesture.
        awaitingRestorePinch = !panelWasVisible
    }

    /// - Returns: whether this pinch should open Launchpad. The restoring pinch
    ///   of a desktop reveal is consumed here and returns false.
    mutating func shouldOpenLaunchpadOnPinch() -> Bool {
        guard awaitingRestorePinch else { return true }
        awaitingRestorePinch = false
        return false
    }

    /// A deliberate activation (hotkey, menu bar item or hot corner) takes
    /// precedence over any pending desktop restore.
    mutating func reset() {
        awaitingRestorePinch = false
    }
}

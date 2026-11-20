/// Decides when the Dock-gesture block may change state.
///
/// The Dock recognises gestures as contact sequences: it expects a beginning,
/// any number of move events and an end. Switching the block in the middle of
/// one gives it half a gesture. If it saw the beginning but the end was
/// swallowed it stays armed, spends the user's next gesture finishing the old
/// one, and only the gesture after that works again. Switching the block off
/// mid-gesture has the mirror problem and lets the rest of a desktop swipe
/// through.
///
/// So a change is held while the trackpad is touched. A sequence that begins
/// while a change is waiting settles it immediately: that whole sequence is
/// either blocked (the panel is up) or passed through (it closed), never split.
/// The controller also forces a change after a while, so a resting finger
/// cannot strand the block.
struct GestureBlockGate: Equatable {
    /// The state the controller wants.
    private(set) var wanted: Bool
    /// The state last handed to `TrackpadGestureBlocker`.
    private(set) var applied: Bool

    /// True while a wanted change is waiting for a contact boundary.
    var isDeferred: Bool { wanted != applied }

    init(applied: Bool = false) {
        self.wanted = applied
        self.applied = applied
    }

    /// Records a new wanted state.
    /// - Returns: the state to apply now, or nil when it has to wait.
    mutating func request(_ wanted: Bool, contactsActive: Bool) -> Bool? {
        self.wanted = wanted
        guard wanted != applied, !contactsActive else { return nil }
        applied = wanted
        return applied
    }

    /// Applies a waiting change at a contact boundary (or after the controller
    /// gives up waiting for one).
    /// - Returns: the state to apply, or nil when nothing was pending.
    mutating func applyPendingChange() -> Bool? {
        guard wanted != applied else { return nil }
        applied = wanted
        return applied
    }
}

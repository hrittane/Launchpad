import CoreGraphics

/// Turns raw scroll deltas into page turns.
///
/// Trackpad swipes arrive as a stream of scroll events with a phase; a swipe
/// only counts once the whole gesture is released, so one flick turns exactly
/// one page and the inertial tail is ignored. Classic mouse wheels have no
/// phases and much smaller deltas, so they are accumulated separately.
struct PagingGestureInterpreter {
    enum Phase {
        case began
        case changed
        case ended
        case cancelled
        case other
    }

    /// Horizontal travel (points) that counts as a swipe.
    var swipeThreshold: CGFloat = 45
    /// Accumulated wheel delta that counts as one page.
    var wheelThreshold: CGFloat = 6

    private var accumulatedX: CGFloat = 0
    private var accumulatedY: CGFloat = 0
    private var wheelAccumulator: CGFloat = 0

    mutating func reset() {
        accumulatedX = 0
        accumulatedY = 0
        wheelAccumulator = 0
    }

    /// Returns `+1` for the next page, `-1` for the previous one, `0` for none.
    mutating func consume(
        deltaX: CGFloat,
        deltaY: CGFloat,
        isPrecise: Bool,
        phase: Phase
    ) -> Int {
        guard isPrecise else {
            guard abs(deltaX) >= abs(deltaY) else { return 0 }
            wheelAccumulator += deltaX
            guard abs(wheelAccumulator) >= wheelThreshold else { return 0 }
            let step = wheelAccumulator < 0 ? 1 : -1
            wheelAccumulator = 0
            return step
        }

        switch phase {
        case .began:
            accumulatedX = deltaX
            accumulatedY = deltaY
        case .changed:
            accumulatedX += deltaX
            accumulatedY += deltaY
        case .ended, .cancelled:
            let horizontal = accumulatedX
            let vertical = accumulatedY
            accumulatedX = 0
            accumulatedY = 0
            guard abs(horizontal) > abs(vertical), abs(horizontal) >= swipeThreshold else {
                return 0
            }
            return horizontal < 0 ? 1 : -1
        case .other:
            break
        }

        return 0
    }
}

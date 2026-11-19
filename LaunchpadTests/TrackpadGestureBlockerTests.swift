import CoreGraphics
import Testing

@testable import Launchpad

struct DockGesturePolicyTests {
    @Test
    func blockingSwallowsBothDockGestureTypes() {
        var policy = DockGesturePolicy()
        policy.isBlocking = true

        #expect(policy.shouldSwallow(eventType: 29))
        #expect(policy.shouldSwallow(eventType: 30))
    }

    @Test
    func blockingLeavesOtherEventsAlone() {
        var policy = DockGesturePolicy()
        policy.isBlocking = true

        // A two-finger page arrives as a scroll wheel, and a keystroke is not a
        // gesture at all: swallowing either would break the panel.
        #expect(!policy.shouldSwallow(eventType: 22))
        #expect(!policy.shouldSwallow(eventType: 10))
        #expect(!policy.shouldSwallow(eventType: 0))
    }

    @Test
    func nothingIsSwallowedWhileNotBlocking() {
        let policy = DockGesturePolicy()

        #expect(!policy.shouldSwallow(eventType: 29))
        #expect(!policy.shouldSwallow(eventType: 30))
    }

    @Test
    func maskOnlySubscribesToDockGestures() {
        let mask = DockGesturePolicy.eventMask

        #expect(mask & (1 << 29) != 0)
        #expect(mask & (1 << 30) != 0)
        #expect(mask & (1 << 22) == 0)
        #expect(mask & (1 << 0) == 0)
    }

    @Test
    func tapsCoverBothSessionStreams() {
        // The Dock posts desktop swipe and Show Desktop on the session stream but
        // other gesture control events on the annotated one; a tap at only one
        // location leaves half the gestures alive.
        let locations = DockGesturePolicy.tapLocations.map(\.rawValue).sorted()

        #expect(locations == [
            CGEventTapLocation.cgSessionEventTap.rawValue,
            CGEventTapLocation.cgAnnotatedSessionEventTap.rawValue
        ].sorted())
    }
}

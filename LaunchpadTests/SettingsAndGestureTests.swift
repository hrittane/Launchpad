import Foundation
import Testing

@testable import Launchpad

private func makeApp(_ index: Int) -> AppItem {
    AppItem(
        bundleIdentifier: "com.test.app\(index)",
        url: URL(fileURLWithPath: "/Applications/App\(index).app"),
        name: "App \(index)"
    )
}

@MainActor
struct LaunchpadSettingsTests {
    private func makeDefaults() -> UserDefaults? {
        let name = "LaunchpadTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)
        defaults?.removePersistentDomain(forName: name)
        return defaults
    }

    @Test
    func firstRunUsesTheReferenceDefaults() {
        guard let defaults = makeDefaults() else {
            Issue.record("Could not create a scratch UserDefaults suite")
            return
        }
        let settings = LaunchpadSettings(defaults: defaults)

        #expect(settings.columns == 7)
        #expect(settings.rows == 5)
        #expect(settings.iconScale == 1)
        #expect(settings.labelScale == 1)
        #expect(settings.showLabels)
        #expect(settings.blurWallpaper)
        #expect(settings.backgroundDim == 0.22)
        #expect(settings.hotKeyEnabled)
        #expect(!settings.hotCornerEnabled)
        #expect(settings.hotCorner == .topLeft)
        #expect(!settings.pinchEnabled)
        #expect(!settings.tapOnChassisEnabled)
        #expect(settings.suppressDesktopSwipe)
        #expect(settings.showMenuBarIcon)
        #expect(!settings.showInDock)
        #expect(settings.dockIconStyle == .classic)
    }

    @Test
    func valuesPersistAcrossInstances() {
        guard let defaults = makeDefaults() else {
            Issue.record("Could not create a scratch UserDefaults suite")
            return
        }

        let first = LaunchpadSettings(defaults: defaults)
        first.columns = 9
        first.rows = 6
        first.iconScale = 1.15
        first.showLabels = false
        first.hotCornerEnabled = true
        first.hotCorner = .bottomRight
        first.pinchEnabled = true
        first.tapOnChassisEnabled = true
        first.backgroundDim = 0.4
        first.showInDock = true
        first.dockIconStyle = .aurora

        let second = LaunchpadSettings(defaults: defaults)
        #expect(second.columns == 9)
        #expect(second.rows == 6)
        #expect(second.iconScale == 1.15)
        #expect(!second.showLabels)
        #expect(second.hotCornerEnabled)
        #expect(second.hotCorner == .bottomRight)
        #expect(second.pinchEnabled)
        #expect(second.tapOnChassisEnabled)
        #expect(second.backgroundDim == 0.4)
        #expect(second.showInDock)
        #expect(second.dockIconStyle == .aurora)
    }

    @Test
    func invalidStoredValuesFallBackToTheDefaults() {
        guard let defaults = makeDefaults() else {
            Issue.record("Could not create a scratch UserDefaults suite")
            return
        }
        defaults.set(12, forKey: "Launchpad.columns")
        defaults.set(0, forKey: "Launchpad.rows")
        defaults.set(9.5, forKey: "Launchpad.iconScale")
        defaults.set(-1.0, forKey: "Launchpad.backgroundDim")
        defaults.set("unknown", forKey: "Launchpad.dockIconStyle")

        let settings = LaunchpadSettings(defaults: defaults)
        #expect(settings.columns == 7)
        #expect(settings.rows == 5)
        #expect(settings.iconScale == 1.3)
        #expect(settings.backgroundDim == 0)
        #expect(settings.dockIconStyle == .classic)
    }

    @Test
    func resetRestoresEveryDefault() {
        guard let defaults = makeDefaults() else {
            Issue.record("Could not create a scratch UserDefaults suite")
            return
        }
        let settings = LaunchpadSettings(defaults: defaults)
        settings.columns = 8
        settings.showMenuBarIcon = false
        settings.suppressDesktopSwipe = false
        settings.pinchEnabled = true
        settings.tapOnChassisEnabled = true
        settings.showInDock = true
        settings.dockIconStyle = .midnight

        settings.resetToDefaults()

        #expect(settings.columns == 7)
        #expect(settings.showMenuBarIcon)
        #expect(settings.suppressDesktopSwipe)
        #expect(!settings.pinchEnabled)
        #expect(!settings.tapOnChassisEnabled)
        #expect(!settings.showInDock)
        #expect(settings.dockIconStyle == .classic)
    }
}

struct LayoutCapacityTests {
    @Test
    func changingCapacityRepacksEveryItem() {
        let apps = (0..<40).map { makeApp($0) }
        var layout = LauncherLayout(items: apps.map { .app($0.id) }, capacity: 35)
        #expect(layout.pages.map(\.count) == [35, 5])

        layout.setCapacity(20)
        #expect(layout.capacity == 20)
        #expect(layout.pages.map(\.count) == [20, 20])
        #expect(layout.items.count == 40)
    }

    @Test
    func shrinkingCapacitySplitsIntoSeveralPages() {
        let apps = (0..<10).map { makeApp($0) }
        var layout = LauncherLayout(items: apps.map { .app($0.id) }, capacity: 35)
        #expect(layout.pages.count == 1)

        layout.setCapacity(4)
        #expect(layout.pages.map(\.count) == [4, 4, 2])
    }

    @Test
    func capacitySurvivesACodableRoundTrip() throws {
        let apps = (0..<9).map { makeApp($0) }
        let layout = LauncherLayout(items: apps.map { .app($0.id) }, capacity: 4)

        let data = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(LauncherLayout.self, from: data)

        #expect(decoded.capacity == 4)
        #expect(decoded.pages.map(\.count) == [4, 4, 1])
    }

    @Test
    func legacyFlatLayoutMigratesToPages() throws {
        struct LegacyLayout: Codable {
            let items: [LauncherItem]
        }

        let apps = (0..<40).map { makeApp($0) }
        let legacy = LegacyLayout(items: apps.map { .app($0.id) })
        let data = try JSONEncoder().encode(legacy)

        let decoded = try JSONDecoder().decode(LauncherLayout.self, from: data)
        #expect(decoded.capacity == LauncherLayout.defaultPageCapacity)
        #expect(decoded.pages.map(\.count) == [35, 5])
    }
}

struct FourFingerGestureRecognizerTests {
    /// Four contacts on a square of radius `radius` around `center`.
    private func points(
        radius: Float,
        center: PinchPoint = PinchPoint(x: 0.5, y: 0.5)
    ) -> [PinchPoint] {
        [
            PinchPoint(x: center.x - radius, y: center.y - radius),
            PinchPoint(x: center.x + radius, y: center.y - radius),
            PinchPoint(x: center.x - radius, y: center.y + radius),
            PinchPoint(x: center.x + radius, y: center.y + radius)
        ]
    }

    @Test
    func contractingFourFingersFiresPinchOnce() {
        var recognizer = FourFingerGestureRecognizer()

        var gesture = recognizer.process(points: points(radius: 0.2), timestamp: 1.0)
        #expect(gesture == nil)
        gesture = recognizer.process(points: points(radius: 0.18), timestamp: 1.02)
        #expect(gesture == nil)
        gesture = recognizer.process(points: points(radius: 0.15), timestamp: 1.04)
        #expect(gesture == nil)
        gesture = recognizer.process(points: points(radius: 0.14), timestamp: 1.06)
        #expect(gesture == .pinch)

        // The same gesture must not fire twice.
        gesture = recognizer.process(points: points(radius: 0.13), timestamp: 1.08)
        #expect(gesture == nil)
    }

    @Test
    func expandingFourFingersFiresSpread() {
        var recognizer = FourFingerGestureRecognizer()

        var gesture = recognizer.process(points: points(radius: 0.04), timestamp: 5.0)
        #expect(gesture == nil)
        gesture = recognizer.process(points: points(radius: 0.045), timestamp: 5.02)
        #expect(gesture == nil)
        gesture = recognizer.process(points: points(radius: 0.052), timestamp: 5.04)
        #expect(gesture == nil)
        gesture = recognizer.process(points: points(radius: 0.057), timestamp: 5.06)
        #expect(gesture == nil)
        gesture = recognizer.process(points: points(radius: 0.059), timestamp: 5.08)
        #expect(gesture == .spread)

        // The same spread must not fire twice.
        gesture = recognizer.process(points: points(radius: 0.07), timestamp: 5.10)
        #expect(gesture == nil)
    }

    @Test
    func relaxingAfterPinchDoesNotFireSpread() {
        var recognizer = FourFingerGestureRecognizer()

        for (index, radius) in [Float(0.2), 0.18, 0.15, 0.14].enumerated() {
            let gesture = recognizer.process(
                points: points(radius: radius),
                timestamp: 1.0 + Double(index) * 0.02
            )
            if index == 3 {
                #expect(gesture == .pinch)
            } else {
                #expect(gesture == nil)
            }
        }

        // The fingers relax outward without lifting: still the same touch.
        for (index, radius) in [Float(0.18), 0.22, 0.26].enumerated() {
            let gesture = recognizer.process(
                points: points(radius: radius),
                timestamp: 1.1 + Double(index) * 0.02
            )
            #expect(gesture == nil)
        }
    }

    @Test
    func aNewSpreadAfterLiftingFires() {
        var recognizer = FourFingerGestureRecognizer()

        for (index, radius) in [Float(0.2), 0.18, 0.15, 0.14].enumerated() {
            _ = recognizer.process(
                points: points(radius: radius),
                timestamp: 1.0 + Double(index) * 0.02
            )
        }

        // Lift the fingers: three contactless frames end the sequence.
        for index in 0..<3 {
            let gesture = recognizer.process(points: [], timestamp: 1.2 + Double(index) * 0.02)
            #expect(gesture == nil)
        }

        var gesture = recognizer.process(points: points(radius: 0.04), timestamp: 1.4)
        #expect(gesture == nil)
        gesture = recognizer.process(points: points(radius: 0.045), timestamp: 1.42)
        #expect(gesture == nil)
        gesture = recognizer.process(points: points(radius: 0.052), timestamp: 1.44)
        #expect(gesture == nil)
        gesture = recognizer.process(points: points(radius: 0.057), timestamp: 1.46)
        #expect(gesture == nil)
        gesture = recognizer.process(points: points(radius: 0.059), timestamp: 1.48)
        #expect(gesture == .spread)
    }

    @Test
    func fourFingerSwipeDoesNotFire() {
        var recognizer = FourFingerGestureRecognizer()

        for step in 0...8 {
            let offset = Float(step) * 0.01
            let center = PinchPoint(x: 0.4 + offset, y: 0.5)
            let gesture = recognizer.process(
                points: points(radius: 0.18, center: center),
                timestamp: 2.0 + Double(step) * 0.02
            )
            #expect(gesture == nil)
        }
    }

    @Test
    func aMovingSpreadIsTreatedAsASwipe() {
        var recognizer = FourFingerGestureRecognizer()

        for step in 0...6 {
            let progress = Float(step) / 6
            let center = PinchPoint(x: 0.4 + progress * 0.14, y: 0.5)
            let radius = 0.04 + progress * 0.03
            let gesture = recognizer.process(
                points: points(radius: radius, center: center),
                timestamp: 6.0 + Double(step) * 0.02
            )
            #expect(gesture == nil)
        }
    }

    @Test
    func threeFingersDoNotFire() {
        var recognizer = FourFingerGestureRecognizer()
        let three = [
            PinchPoint(x: 0.4, y: 0.4),
            PinchPoint(x: 0.6, y: 0.4),
            PinchPoint(x: 0.5, y: 0.6)
        ]
        let tight = [
            PinchPoint(x: 0.47, y: 0.47),
            PinchPoint(x: 0.53, y: 0.47),
            PinchPoint(x: 0.5, y: 0.53)
        ]

        var gesture = recognizer.process(points: three, timestamp: 3.0)
        #expect(gesture == nil)
        gesture = recognizer.process(points: tight, timestamp: 3.02)
        #expect(gesture == nil)
        gesture = recognizer.process(points: tight, timestamp: 3.04)
        #expect(gesture == nil)
    }

    @Test
    func movingTheWholeHandDoesNotFire() {
        var recognizer = FourFingerGestureRecognizer()

        var gesture = recognizer.process(points: points(radius: 0.2), timestamp: 4.0)
        #expect(gesture == nil)
        let moved = PinchPoint(x: 0.85, y: 0.5)
        gesture = recognizer.process(points: points(radius: 0.12, center: moved), timestamp: 4.02)
        #expect(gesture == nil)
        gesture = recognizer.process(points: points(radius: 0.12, center: moved), timestamp: 4.04)
        #expect(gesture == nil)
    }
}

struct TrackpadSwipeTrackerTests {
    /// Four contacts on a square of radius `radius` around `center`.
    private func points(
        radius: Float = 0.1,
        center: PinchPoint = PinchPoint(x: 0.5, y: 0.5),
        fingerCount: Int = 4
    ) -> [PinchPoint] {
        (0..<fingerCount).map { index in
            let angle = Float(index) / Float(fingerCount) * 2 * .pi
            return PinchPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
        }
    }

    private func horizontalSwipe(
        through tracker: inout TrackpadSwipeTracker,
        from start: Float = 0.25,
        step: Float = 0.03,
        steps: Int = 8,
        fingerCount: Int = 4,
        timestamp: Double = 1.0
    ) -> [TrackpadSwipeEvent] {
        var events: [TrackpadSwipeEvent] = []
        for index in 0...steps {
            let center = PinchPoint(x: start + Float(index) * step, y: 0.5)
            events += tracker.process(
                points: points(center: center, fingerCount: fingerCount),
                timestamp: timestamp + Double(index) * 0.01
            )
        }
        return events
    }

    private func horizontalTravel(_ events: [TrackpadSwipeEvent]) -> Float {
        events.reduce(Float(0)) { total, event in
            if case .changed(let delta) = event { return total + delta }
            return total
        }
    }

    @Test
    func rightwardSwipePagesBackward() {
        var tracker = TrackpadSwipeTracker()
        let events = horizontalSwipe(through: &tracker)

        #expect(tracker.isActive)
        #expect(events.contains(.began))
        #expect(horizontalTravel(events) > 0.2)
    }

    @Test
    func leftwardSwipePagesForward() {
        var tracker = TrackpadSwipeTracker()
        let events = horizontalSwipe(through: &tracker, from: 0.8, step: -0.03)

        #expect(tracker.isActive)
        #expect(horizontalTravel(events) < -0.2)
    }

    @Test
    func threeFingerSwipePagesToo() {
        var tracker = TrackpadSwipeTracker()
        let events = horizontalSwipe(through: &tracker, fingerCount: 3)

        #expect(tracker.isActive)
        #expect(events.contains(.began))
        #expect(horizontalTravel(events) > 0.2)
    }

    @Test
    func fiveFingerSwipePagesToo() {
        var tracker = TrackpadSwipeTracker()
        let events = horizontalSwipe(through: &tracker, fingerCount: 5)

        #expect(tracker.isActive)
        #expect(events.contains(.began))
        #expect(horizontalTravel(events) > 0.2)
    }

    @Test
    func twoFingersStayOnTheScrollPath() {
        var tracker = TrackpadSwipeTracker()
        let events = horizontalSwipe(through: &tracker, fingerCount: 2)

        // Two-finger paging arrives as scroll-wheel events; the contact-based
        // tracker must ignore it or the page would move twice.
        #expect(!tracker.isActive)
        #expect(events.isEmpty)
    }

    @Test
    func liftingEndsTheSwipeWithVelocity() {
        var tracker = TrackpadSwipeTracker()
        _ = horizontalSwipe(through: &tracker)

        let events = tracker.finish(timestamp: 1.1)
        #expect(!tracker.isActive)
        #expect(events.count == 1)
        if case .ended(let velocity) = events[0] {
            #expect(velocity > 0)
        } else {
            Issue.record("Expected the swipe to end")
        }
    }

    @Test
    func verticalSwipeIsNotAPageSwipe() {
        var tracker = TrackpadSwipeTracker()
        var events: [TrackpadSwipeEvent] = []

        for index in 0...8 {
            let center = PinchPoint(x: 0.5, y: 0.3 + Float(index) * 0.03)
            events += tracker.process(
                points: points(center: center),
                timestamp: 2.0 + Double(index) * 0.01
            )
        }

        #expect(!tracker.isActive)
        #expect(events.isEmpty)
    }

    @Test
    func restingFingersDoNotSwipe() {
        var tracker = TrackpadSwipeTracker()
        var events: [TrackpadSwipeEvent] = []

        for index in 0...10 {
            events += tracker.process(points: points(), timestamp: 3.0 + Double(index) * 0.01)
        }

        #expect(!tracker.isActive)
        #expect(events.isEmpty)
    }

    @Test
    func pinchIsNotASwipe() {
        var tracker = TrackpadSwipeTracker()
        var events: [TrackpadSwipeEvent] = []

        for index in 0...8 {
            let radius = 0.2 - Float(index) * 0.015
            events += tracker.process(
                points: points(radius: radius),
                timestamp: 5.0 + Double(index) * 0.01
            )
        }

        #expect(!tracker.isActive)
        #expect(events.isEmpty)
    }

    @Test
    func aNewSwipeWorksAfterLifting() {
        var tracker = TrackpadSwipeTracker()
        _ = horizontalSwipe(through: &tracker)
        _ = tracker.finish(timestamp: 1.1)

        let first = horizontalSwipe(through: &tracker, timestamp: 2.0)
        #expect(first.contains(.began))

        _ = tracker.finish(timestamp: 2.1)
        let second = horizontalSwipe(through: &tracker, timestamp: 3.0)
        #expect(second.contains(.began))
    }

    @Test
    func cancelReportsOnceAndResets() {
        var tracker = TrackpadSwipeTracker()
        _ = horizontalSwipe(through: &tracker)

        let events = tracker.cancel()
        #expect(events == [.cancelled])
        #expect(!tracker.isActive)
        #expect(tracker.cancel().isEmpty)
    }
}

struct HotCornerGeometryTests {
    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1200)

    @Test
    func detectsEachCorner() {
        #expect(HotCornerMonitor.contains(
            CGPoint(x: 2, y: 1198), screen: screen, corner: .topLeft, hitSize: 6
        ))
        #expect(HotCornerMonitor.contains(
            CGPoint(x: 1918, y: 1198), screen: screen, corner: .topRight, hitSize: 6
        ))
        #expect(HotCornerMonitor.contains(
            CGPoint(x: 2, y: 2), screen: screen, corner: .bottomLeft, hitSize: 6
        ))
        #expect(HotCornerMonitor.contains(
            CGPoint(x: 1918, y: 2), screen: screen, corner: .bottomRight, hitSize: 6
        ))
    }

    @Test
    func ignoresPointsOutsideTheCorner() {
        #expect(!HotCornerMonitor.contains(
            CGPoint(x: 40, y: 1160), screen: screen, corner: .topLeft, hitSize: 6
        ))
        #expect(!HotCornerMonitor.contains(
            CGPoint(x: 1918, y: 1160), screen: screen, corner: .bottomRight, hitSize: 6
        ))
    }
}

struct DesktopRevealStateTests {
    @Test
    func restorePinchDoesNotOpenLaunchpad() {
        var state = DesktopRevealState()
        state.noteSpread(panelWasVisible: false)

        // The spread revealed the desktop; this pinch puts the windows back.
        let opens = state.shouldOpenLaunchpadOnPinch()
        #expect(!opens)
    }

    @Test
    func aSecondPinchOpensLaunchpad() {
        var state = DesktopRevealState()
        state.noteSpread(panelWasVisible: false)
        let restored = state.shouldOpenLaunchpadOnPinch()
        #expect(!restored)

        // The restore consumed the pair, so a fresh pinch is a real activation.
        let opens = state.shouldOpenLaunchpadOnPinch()
        #expect(opens)
    }

    @Test
    func spreadThatClosedLaunchpadDoesNotArmTheLatch() {
        var state = DesktopRevealState()
        state.noteSpread(panelWasVisible: true)

        // That spread closed the panel while the Dock was blocked; no desktop
        // was revealed, so the next pinch must still open Launchpad.
        let opens = state.shouldOpenLaunchpadOnPinch()
        #expect(opens)
    }

    @Test
    func manualActivationCancelsAPendingRestore() {
        var state = DesktopRevealState()
        state.noteSpread(panelWasVisible: false)
        state.reset()

        let opens = state.shouldOpenLaunchpadOnPinch()
        #expect(opens)
    }

    @Test
    func workingOnTheDesktopForALongTimeDoesNotExpireTheRestore() {
        var state = DesktopRevealState()
        state.noteSpread(panelWasVisible: false)

        // There is deliberately no timeout: how long the user stays on the
        // desktop must not change what the restoring pinch means.
        let opens = state.shouldOpenLaunchpadOnPinch()
        #expect(!opens)
    }
}

@MainActor
struct AccessibilityBannerStateTests {
    @Test
    func bannerFollowsTheGrantState() {
        let model = AppModel()
        #expect(!model.needsAccessibilityGrant)

        // After an update the ad-hoc build is untrusted while the switch still
        // looks on, so the panel has to say so instead of failing silently.
        model.setAccessibilityGrantNeeded(true)
        #expect(model.needsAccessibilityGrant)

        model.setAccessibilityGrantNeeded(false)
        #expect(!model.needsAccessibilityGrant)
    }
}

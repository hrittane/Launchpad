import CoreFoundation
import Darwin
import Foundation
import os

/// Logs which raw gestures the trackpad produced. Independent of Accessibility,
/// so it can be compared with the blocker's log to tell a missing permission
/// apart from a missing event.
private let gestureMonitorLog = Logger(
    subsystem: "com.example.Launchpad",
    category: "trackpad"
)

/// A normalized trackpad contact, in MultitouchSupport coordinates.
struct PinchPoint: Equatable {
    var x: Float
    var y: Float
}

/// The two gestures the launcher owns.
enum FourFingerGesture: Equatable {
    /// Fingers contract: open Launchpad.
    case pinch
    /// Fingers spread: close Launchpad.
    case spread
}

/// A live multi-finger horizontal swipe.
///
/// `deltaX` and `velocityX` are normalized to the trackpad width, so the panel
/// can map a full-pad swipe onto one page width.
enum TrackpadSwipeEvent: Equatable {
    case began
    case changed(deltaX: Float)
    case ended(velocityX: Float)
    case cancelled
}

/// Turns raw three-, four- or five-finger horizontal travel into a live page
/// swipe.
///
/// The system's own multi-finger swipe switches desktops or full-screen apps,
/// which is exactly what Launchpad does not want. Reading the contacts directly
/// lets the panel page its grid with the same fingers, and the direction matches
/// two-finger paging: fingers moving right bring the previous page back. Two
/// fingers stay on the scroll-event path, so this tracker deliberately needs at
/// least three contacts.
struct TrackpadSwipeTracker {
    private static let minimumFingerCount = 3

    /// Travel needed before a gesture counts, in trackpad widths. Small enough
    /// to feel immediate, large enough to ignore a resting hand.
    private static let activationDistance: Float = 0.02
    /// The horizontal travel must clearly dominate, so a swipe up (Mission
    /// Control) is never read as a horizontal one.
    private static let horizontalDominance: Float = 1.8
    /// How much the finger cloud may contract or expand and still be a swipe.
    private static let maximumSpreadChangeRatio: Float = 0.22
    private static let maximumVerticalDrift: Float = 0.12
    private static let maximumDuration: Double = 1.6
    private static let pauseInterval: Double = 0.20
    private static let endMissingFrames = 3
    private static let velocityWindow: Double = 0.10

    private struct Sample {
        var time: Double
        var x: Float
    }

    private var startCentroid: PinchPoint?
    private var startTimestamp: Double?
    private var startSpread: Float = 0
    private var lastTimestamp: Double?
    private var lastEmittedX: Float = 0
    private var samples: [Sample] = []
    private var missingFrames = 0

    private(set) var isActive = false

    mutating func process(
        points: [PinchPoint],
        timestamp: Double
    ) -> [TrackpadSwipeEvent] {
        if let lastTimestamp, timestamp - lastTimestamp > Self.pauseInterval {
            return finish()
        }
        lastTimestamp = timestamp

        guard points.count >= Self.minimumFingerCount else {
            missingFrames += 1
            if missingFrames >= Self.endMissingFrames {
                return finish()
            }
            return []
        }
        missingFrames = 0

        let centroid = Self.centroid(of: points)
        let spread = Self.averageSpread(of: points, around: centroid)

        guard let startedAt = startTimestamp,
              let initialCentroid = startCentroid else {
            startCentroid = centroid
            startTimestamp = timestamp
            startSpread = spread
            lastEmittedX = centroid.x
            samples = [Sample(time: timestamp, x: centroid.x)]
            return []
        }

        if timestamp - startedAt > Self.maximumDuration {
            return finish()
        }

        let dx = centroid.x - initialCentroid.x
        let dy = centroid.y - initialCentroid.y
        let spreadChange = startSpread > 0 ? abs(spread - startSpread) / startSpread : 1

        if !isActive {
            guard abs(dx) >= Self.activationDistance,
                  abs(dx) >= Self.horizontalDominance * abs(dy),
                  abs(dy) <= Self.maximumVerticalDrift,
                  spreadChange <= Self.maximumSpreadChangeRatio else {
                return []
            }

            isActive = true
            let travel = centroid.x - lastEmittedX
            lastEmittedX = centroid.x
            samples = [Sample(time: timestamp, x: centroid.x)]
            return [.began, .changed(deltaX: travel)]
        }

        // A pinch, a spread or a mainly vertical move takes the gesture back.
        guard spreadChange <= Self.maximumSpreadChangeRatio,
              abs(centroid.y - initialCentroid.y) <= Self.maximumVerticalDrift else {
            return finish()
        }

        record(centroid.x, at: timestamp)
        let delta = centroid.x - lastEmittedX
        lastEmittedX = centroid.x
        return abs(delta) > 0.0005 ? [.changed(deltaX: delta)] : []
    }

    /// Ends the swipe and reports the release velocity.
    mutating func finish(timestamp: Double? = nil) -> [TrackpadSwipeEvent] {
        defer { reset() }
        guard isActive else { return [] }
        return [.ended(velocityX: velocity(at: timestamp ?? lastTimestamp ?? 0))]
    }

    /// Ends the swipe without a velocity, for a gesture that was taken over.
    mutating func cancel() -> [TrackpadSwipeEvent] {
        let wasActive = isActive
        reset()
        return wasActive ? [.cancelled] : []
    }

    mutating func reset() {
        startCentroid = nil
        startTimestamp = nil
        startSpread = 0
        lastTimestamp = nil
        lastEmittedX = 0
        samples = []
        missingFrames = 0
        isActive = false
    }

    private mutating func record(_ x: Float, at time: Double) {
        samples.append(Sample(time: time, x: x))
        let cutoff = time - Self.velocityWindow
        while let first = samples.first, first.time < cutoff {
            samples.removeFirst()
        }
    }

    /// Normalized trackpad widths per second, or zero when the fingers paused
    /// before lifting.
    private func velocity(at time: Double) -> Float {
        guard let first = samples.first, let last = samples.last else { return 0 }
        guard time - last.time < 0.05 else { return 0 }
        let span = max(last.time - first.time, 0.008)
        return max(min((last.x - first.x) / Float(span), 6), -6)
    }

    private static func centroid(of points: [PinchPoint]) -> PinchPoint {
        let sums = points.reduce(into: (x: Float(0), y: Float(0))) {
            $0.x += $1.x
            $0.y += $1.y
        }
        let count = Float(points.count)
        return PinchPoint(x: sums.x / count, y: sums.y / count)
    }

    private static func averageSpread(of points: [PinchPoint], around centroid: PinchPoint) -> Float {
        let total = points.reduce(Float(0)) { result, point in
            result + abs(point.x - centroid.x) + abs(point.y - centroid.y)
        }
        return total / Float(points.count)
    }
}

/// Recognizes a deliberate four-finger pinch or spread from raw trackpad
/// contacts.
///
/// The system has no public API for observing a finger count globally, so the
/// monitor below reads the private MultitouchSupport stream. The recognizer
/// itself is pure geometry: a pinch is a substantial contraction around a fixed
/// centroid, a spread is a substantial expansion. Keeping the centroid steady
/// stops a four-finger swipe from firing either gesture. Only one gesture fires
/// per contact sequence, so relaxing the fingers after a pinch cannot close the
/// launcher that pinch just opened.
struct FourFingerGestureRecognizer {
    private static let minimumFingerCount = 4

    private static let minimumPinchStartingSpread: Float = 0.075
    private static let minimumContraction: Float = 0.012
    private static let pinchTriggerRatio: Float = 0.90

    private static let minimumSpreadStartingSpread: Float = 0.025
    private static let minimumExpansion: Float = 0.018
    private static let spreadTriggerRatio: Float = 1.15
    /// A spread is a still gesture; a swipe that travels is not one.
    private static let maximumSpreadCentroidDrift: Float = 0.08

    private static let maximumCentroidDrift: Float = 0.16
    private static let maximumGestureDuration: Double = 2.0
    private static let newSequenceInterval: Double = 0.30
    private static let stableFrameCount = 2

    private var startingTimestamp: Double?
    private var lastFrameTimestamp: Double?
    private var startingCentroid: PinchPoint?
    private var minimumSpread: Float = .greatestFiniteMagnitude
    private var maximumSpread: Float = 0
    private var stablePinchFrames = 0
    private var stableSpreadFrames = 0
    private var missingFingerFrames = 0
    private var didFire = false

    mutating func process(points: [PinchPoint], timestamp: Double) -> FourFingerGesture? {
        if let lastFrameTimestamp,
           timestamp - lastFrameTimestamp > Self.newSequenceInterval {
            reset()
        }
        lastFrameTimestamp = timestamp

        guard points.count >= Self.minimumFingerCount else {
            if startingTimestamp != nil {
                missingFingerFrames += 1
                if missingFingerFrames >= 3 { reset() }
            }
            return nil
        }

        missingFingerFrames = 0
        let centroid = Self.centroid(of: points)
        let spread = Self.averageSpread(of: points, around: centroid)

        guard let startedAt = startingTimestamp,
              let initialCentroid = startingCentroid else {
            startSequence(spread: spread, centroid: centroid, timestamp: timestamp)
            return nil
        }

        if timestamp - startedAt > Self.maximumGestureDuration {
            // A hand resting on the trackpad is not a gesture: begin again.
            startSequence(spread: spread, centroid: centroid, timestamp: timestamp)
            return nil
        }

        // The fingers have to lift before the same touch can produce a second
        // gesture. This is what stops a release after the opening pinch from
        // being read as a closing spread.
        guard !didFire else { return nil }

        minimumSpread = min(minimumSpread, spread)
        maximumSpread = max(maximumSpread, spread)
        let centroidDrift = Self.distance(centroid, initialCentroid)

        // Pinch: the cloud contracts around a steady centroid.
        let contraction = maximumSpread - spread
        let contractionRatio = maximumSpread > 0 ? spread / maximumSpread : 1
        if maximumSpread >= Self.minimumPinchStartingSpread,
           contraction >= Self.minimumContraction,
           contractionRatio <= Self.pinchTriggerRatio,
           centroidDrift <= Self.maximumCentroidDrift {
            stablePinchFrames += 1
        } else {
            stablePinchFrames = 0
        }

        if stablePinchFrames >= Self.stableFrameCount {
            didFire = true
            return .pinch
        }

        // Spread: the cloud expands around a steady centroid.
        let expansion = spread - minimumSpread
        let expansionRatio = minimumSpread > 0 ? spread / minimumSpread : 1
        if minimumSpread >= Self.minimumSpreadStartingSpread,
           expansion >= Self.minimumExpansion,
           expansionRatio >= Self.spreadTriggerRatio,
           centroidDrift <= Self.maximumSpreadCentroidDrift {
            stableSpreadFrames += 1
        } else {
            stableSpreadFrames = 0
        }

        guard stableSpreadFrames >= Self.stableFrameCount else { return nil }
        didFire = true
        return .spread
    }

    mutating func reset() {
        startingTimestamp = nil
        lastFrameTimestamp = nil
        startingCentroid = nil
        minimumSpread = .greatestFiniteMagnitude
        maximumSpread = 0
        stablePinchFrames = 0
        stableSpreadFrames = 0
        missingFingerFrames = 0
        didFire = false
    }

    private mutating func startSequence(
        spread: Float,
        centroid: PinchPoint,
        timestamp: Double
    ) {
        startingTimestamp = timestamp
        startingCentroid = centroid
        minimumSpread = spread
        maximumSpread = spread
        stablePinchFrames = 0
        stableSpreadFrames = 0
        missingFingerFrames = 0
        didFire = false
    }

    private static func centroid(of points: [PinchPoint]) -> PinchPoint {
        let sums = points.reduce(into: (x: Float(0), y: Float(0))) {
            $0.x += $1.x
            $0.y += $1.y
        }
        let count = Float(points.count)
        return PinchPoint(x: sums.x / count, y: sums.y / count)
    }

    private static func averageSpread(of points: [PinchPoint], around centroid: PinchPoint) -> Float {
        let total = points.reduce(Float(0)) { result, point in
            result + distance(point, centroid)
        }
        return total / Float(points.count)
    }

    private static func distance(_ lhs: PinchPoint, _ rhs: PinchPoint) -> Float {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return sqrt(dx * dx + dy * dy)
    }
}

// MARK: - Private MultitouchSupport bridge

private typealias MTDeviceRef = UnsafeMutableRawPointer
private typealias MTContactCallback = @convention(c) (
    MTDeviceRef?,
    UnsafeMutableRawPointer?,
    Int32,
    Double,
    Int32
) -> Int32
private typealias MTDeviceCreateListFn = @convention(c) () -> CFArray?
private typealias MTDeviceCreateDefaultFn = @convention(c) () -> MTDeviceRef?
private typealias MTDeviceStartFn = @convention(c) (MTDeviceRef, Int32) -> Void
private typealias MTRegisterCallbackFn = @convention(c) (MTDeviceRef, MTContactCallback) -> Void

private struct MTPoint {
    var x: Float
    var y: Float
}

private struct MTVector {
    var position: MTPoint
    var velocity: MTPoint
}

/// The contact layout used by MultitouchSupport on current Intel and Apple
/// Silicon Macs.
private struct MTTouch {
    var frame: Int32
    var timestamp: Double
    var pathIndex: Int32
    var state: UInt32
    var fingerID: Int32
    var handID: Int32
    var normalizedVector: MTVector
    var zTotal: Float
    var field9: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var absoluteVector: MTVector
    var field14: Int32
    var field15: Int32
    var zDensity: Float
}

/// Loads the private framework lazily. The app still launches (and the pinch
/// feature simply reports itself unavailable) if the framework disappears.
private enum Multitouch {
    nonisolated(unsafe) static let handle: UnsafeMutableRawPointer? = {
        let paths = [
            "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",
            "/System/Library/PrivateFrameworks/MultitouchSupport.framework/Versions/A/MultitouchSupport"
        ]
        for path in paths {
            if let handle = dlopen(path, RTLD_NOW) { return handle }
        }
        return dlopen("MultitouchSupport.framework/MultitouchSupport", RTLD_NOW)
    }()

    static let createList: MTDeviceCreateListFn? = load("MTDeviceCreateList")
    static let createDefault: MTDeviceCreateDefaultFn? = load("MTDeviceCreateDefault")
    static let start: MTDeviceStartFn? = load("MTDeviceStart")
    static let registerCallback: MTRegisterCallbackFn? = load("MTRegisterContactFrameCallback")

    static var isAvailable: Bool {
        handle != nil && createList != nil && registerCallback != nil && start != nil
    }

    private static func load<T>(_ name: String) -> T? {
        guard let handle, let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: T.self)
    }
}

nonisolated(unsafe) private let pinchContactCallback: MTContactCallback = {
    _, touches, count, timestamp, _ in
    guard let touches, count > 0 else {
        PinchGestureMonitor.shared.endContactSequence(timestamp: timestamp)
        return 0
    }
    PinchGestureMonitor.shared.process(
        touches: touches,
        count: Int(count),
        timestamp: timestamp
    )
    return 0
}

/// Observes raw trackpad contacts and turns them into the launcher's gestures:
/// a four-finger pinch opens, a four-finger spread closes and a horizontal
/// three-, four- or five-finger swipe pages the grid.
///
/// The callback stays registered for the process lifetime so toggling the
/// setting never races the private framework's start/stop. Recognition always
/// runs; the AppKit side decides whether a pinch is allowed, whether a spread
/// has anything to close and whether a swipe belongs to a visible panel.
/// MultitouchSupport calls back on its own thread, so all shared state is
/// guarded by `lock`.
final class PinchGestureMonitor: @unchecked Sendable {
    static let shared = PinchGestureMonitor()

    private let lock = NSLock()
    private var devices: [MTDeviceRef] = []
    private var deviceList: CFArray?
    private var hasStarted = false
    private var recognizer = FourFingerGestureRecognizer()
    private var swipeTracker = TrackpadSwipeTracker()
    private var onPinch: (@MainActor @Sendable () -> Void)?
    private var onSpread: (@MainActor @Sendable () -> Void)?
    private var onSwipe: (@MainActor @Sendable (TrackpadSwipeEvent) -> Void)?

    private init() {}

    var isAvailable: Bool { Multitouch.isAvailable }

    func start(
        onPinch: @escaping @MainActor @Sendable () -> Void,
        onSpread: @escaping @MainActor @Sendable () -> Void,
        onSwipe: @escaping @MainActor @Sendable (TrackpadSwipeEvent) -> Void
    ) {
        lock.lock()
        self.onPinch = onPinch
        self.onSpread = onSpread
        self.onSwipe = onSwipe
        let shouldStart = !hasStarted
        if shouldStart { hasStarted = true }
        lock.unlock()

        if shouldStart {
            startDevices()
        }
    }

    fileprivate func endContactSequence(timestamp: Double) {
        lock.lock()
        recognizer.reset()
        let events = swipeTracker.finish(timestamp: timestamp)
        let handler = onSwipe
        lock.unlock()

        guard !events.isEmpty, let handler else { return }
        Task { @MainActor in
            for event in events {
                handler(event)
            }
        }
    }

    fileprivate func process(touches: UnsafeMutableRawPointer, count: Int, timestamp: Double) {
        lock.lock()

        let rawTouches = touches.bindMemory(to: MTTouch.self, capacity: count)
        var points: [PinchPoint] = []
        points.reserveCapacity(count)
        for index in 0..<count {
            let touch = rawTouches[index]
            // States 3 and 4 are the stable contact states. Lift/linger frames
            // are ignored so a release cannot complete the pinch.
            guard touch.state == 3 || touch.state == 4 else { continue }
            let position = touch.normalizedVector.position
            points.append(PinchPoint(x: position.x, y: position.y))
        }

        var swipeEvents = swipeTracker.process(points: points, timestamp: timestamp)
        var gesture: FourFingerGesture?

        if swipeTracker.isActive {
            // The swipe owns this contact sequence: a late contraction must not
            // also open or close the launcher.
            recognizer.reset()
        } else {
            gesture = recognizer.process(points: points, timestamp: timestamp)
            if gesture != nil {
                swipeEvents += swipeTracker.cancel()
            }
        }

        let pinchHandler = onPinch
        let spreadHandler = onSpread
        let swipeHandler = onSwipe
        lock.unlock()

        guard gesture != nil || !swipeEvents.isEmpty else { return }
        Task { @MainActor in
            for event in swipeEvents {
                switch event {
                case .began:
                    gestureMonitorLog.notice("multi-finger swipe began")
                case .ended:
                    gestureMonitorLog.notice("multi-finger swipe ended")
                case .changed, .cancelled:
                    break
                }
                swipeHandler?(event)
            }
            switch gesture {
            case .pinch:
                gestureMonitorLog.notice("four-finger pinch")
                pinchHandler?()
            case .spread:
                gestureMonitorLog.notice("four-finger spread")
                spreadHandler?()
            case .none:
                break
            }
        }
    }

    private func startDevices() {
        guard Multitouch.isAvailable else { return }

        var discovered: [MTDeviceRef] = []
        let list = Multitouch.createList?()
        if let list {
            for index in 0..<CFArrayGetCount(list) {
                guard let value = CFArrayGetValueAtIndex(list, index) else { continue }
                let device = UnsafeMutableRawPointer(mutating: value)
                if !discovered.contains(where: { $0 == device }) {
                    discovered.append(device)
                }
            }
        }

        if discovered.isEmpty, let fallback = Multitouch.createDefault?() {
            discovered.append(fallback)
        }

        for device in discovered {
            Multitouch.registerCallback?(device, pinchContactCallback)
            Multitouch.start?(device, 0)
        }

        lock.lock()
        devices = discovered
        deviceList = list
        recognizer.reset()
        lock.unlock()
    }
}

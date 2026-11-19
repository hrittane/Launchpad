import AppKit

/// Watches the mouse for a screen-corner trigger.
///
/// Hot corners are polled from `NSEvent.mouseLocation` instead of a global
/// mouse monitor: polling needs no Accessibility permission, and a corner only
/// has to be noticed within a few frames.
@MainActor
final class HotCornerMonitor {
    private var timer: Timer?
    private var isInside = false
    private var isEnabled = false
    private var corner: LaunchpadSettings.HotCorner = .topLeft
    private var onTrigger: (() -> Void)?

    /// The corner hit area, in points. Corners are deliberately small so the
    /// gesture does not fire when the pointer merely approaches the edge.
    static let hitSize: CGFloat = 6

    func configure(
        enabled: Bool,
        corner: LaunchpadSettings.HotCorner,
        onTrigger: @escaping () -> Void
    ) {
        self.corner = corner
        self.onTrigger = onTrigger
        isEnabled = enabled

        if enabled {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        isInside = false
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        isInside = false
    }

    private func poll() {
        guard isEnabled,
              let screen = Self.screen(containing: NSEvent.mouseLocation) else { return }

        let inside = Self.contains(
            NSEvent.mouseLocation,
            screen: screen.frame,
            corner: corner,
            hitSize: Self.hitSize
        )
        if inside {
            guard !isInside else { return }
            isInside = true
            onTrigger?()
        } else {
            isInside = false
        }
    }

    /// Pure geometry, kept static so it can be tested without a timer.
    nonisolated static func contains(
        _ point: CGPoint,
        screen: CGRect,
        corner: LaunchpadSettings.HotCorner,
        hitSize: CGFloat
    ) -> Bool {
        let xRange: ClosedRange<CGFloat>
        let yRange: ClosedRange<CGFloat>
        switch corner {
        case .topLeft:
            xRange = screen.minX...(screen.minX + hitSize)
            yRange = (screen.maxY - hitSize)...screen.maxY
        case .topRight:
            xRange = (screen.maxX - hitSize)...screen.maxX
            yRange = (screen.maxY - hitSize)...screen.maxY
        case .bottomLeft:
            xRange = screen.minX...(screen.minX + hitSize)
            yRange = screen.minY...(screen.minY + hitSize)
        case .bottomRight:
            xRange = (screen.maxX - hitSize)...screen.maxX
            yRange = screen.minY...(screen.minY + hitSize)
        }
        return xRange.contains(point.x) && yRange.contains(point.y)
    }

    nonisolated static func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
            ?? NSScreen.screens.first
    }
}

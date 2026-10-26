import AppKit

/// Detects a configured hot corner with a 0.3 s dwell time.
///
/// Mouse-moved global monitors are used instead of polling so the app remains
/// idle while hidden. If macOS declines the global monitor (for example
/// because of a managed environment), the local monitor still works whenever
/// the app is active.
final class HotCornerMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var dwellTimer: Timer?
    private var isArmed = true
    private var lastCorner: HotCorner = .disabled

    var onTrigger: (() -> Void)?
    var isSuspended: (() -> Bool)?

    func start(corner: HotCorner) {
        lastCorner = corner
        guard globalMonitor == nil, localMonitor == nil else { return }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.handleMouseMoved(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.handleMouseMoved(event)
            return event
        }
    }

    func update(corner: HotCorner) {
        lastCorner = corner
        if corner == .disabled {
            cancelDwell()
            isArmed = true
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        cancelDwell()
    }

    private func handleMouseMoved(_ event: NSEvent) {
        guard lastCorner != .disabled else { return }
        if isSuspended?() == true {
            isArmed = true
            cancelDwell()
            return
        }

        let location = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(location) }) ?? NSScreen.main else {
            return
        }
        let frame = screen.frame
        let margin = Metrics.hotCornerMargin
        let inCorner: Bool
        switch lastCorner {
        case .disabled:
            inCorner = false
        case .topLeft:
            inCorner = location.x <= frame.minX + margin && location.y >= frame.maxY - margin
        case .topRight:
            inCorner = location.x >= frame.maxX - margin && location.y >= frame.maxY - margin
        case .bottomLeft:
            inCorner = location.x <= frame.minX + margin && location.y <= frame.minY + margin
        case .bottomRight:
            inCorner = location.x >= frame.maxX - margin && location.y <= frame.minY + margin
        }

        if inCorner {
            guard isArmed else { return }
            isArmed = false
            cancelDwell()
            dwellTimer = Timer.scheduledTimer(
                withTimeInterval: Metrics.Durations.hotCornerDwell,
                repeats: false
            ) { [weak self] _ in
                guard let self, self.lastCorner != .disabled else { return }
                self.onTrigger?()
            }
        } else {
            isArmed = true
            cancelDwell()
        }
    }

    private func cancelDwell() {
        dwellTimer?.invalidate()
        dwellTimer = nil
    }
}

import AppKit

/// Borderless overlay window that can become key and forwards scroll events.
final class LaunchpadWindow: NSWindow {
    var scrollHandler: ((NSEvent) -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func scrollWheel(with event: NSEvent) {
        if let scrollHandler {
            scrollHandler(event)
        } else {
            super.scrollWheel(with: event)
        }
    }

    /// Keep standard key handling for events that the local monitor declines.
    override func keyDown(with event: NSEvent) {
        super.keyDown(with: event)
    }
}

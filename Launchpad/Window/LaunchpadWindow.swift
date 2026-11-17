import AppKit

/// Borderless, transparent, full-screen panel that hosts the Launchpad UI.
///
/// It is intentionally *below* the Dock (level 20) so the Dock stays visible,
/// like the reference. The menu bar is hidden with
/// `NSApplication.presentationOptions` while the panel is on screen.
final class LaunchpadWindow: NSWindow {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovable = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        animationBehavior = .none
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

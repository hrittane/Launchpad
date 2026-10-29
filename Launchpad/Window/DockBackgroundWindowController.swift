import AppKit
import SwiftUI

/// A non-interactive window that continues the Launchpad backdrop behind the
/// Dock. It sits one level below the Dock, so the Dock itself remains visible
/// and clickable while the area around it is blurred like the rest of the
/// overlay.
final class DockBackgroundWindowController: NSWindowController {
    init(viewModel: LaunchpadViewModel) {
        let window = DockBackgroundWindow(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isMovable = false
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.animationBehavior = .none
        window.level = WindowLevels.belowDock
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.title = "Launchpad Dock Background"

        super.init(window: window)

        let background = LaunchpadBackgroundView(viewModel: viewModel, role: .dockStrip)
        let hostingView = NSHostingView(rootView: background)
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.autoresizingMask = [.width, .height]
        hostingView.frame = window.contentView?.bounds ?? .zero
        window.contentView = hostingView
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateFrame(_ frame: NSRect) {
        window?.setFrame(frame, display: true)
    }

    func orderFront() {
        window?.orderFrontRegardless()
    }

    func orderOut() {
        window?.orderOut(nil)
    }
}

/// Never becomes key or main; all mouse events pass through to the Dock.
final class DockBackgroundWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

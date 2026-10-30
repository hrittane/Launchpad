import AppKit
import SwiftUI

/// Covers the small menu-bar strip above a left or right Dock.
///
/// The main overlay starts at the Dock's edge, so a side Dock leaves the top
/// corner above it exposed. This patch renders the same backdrop and consumes
/// clicks, preventing the Finder/macOS menu from showing through in that
/// corner. A bottom Dock needs no patch because the main window covers the
/// full width at the top.
final class MenuBarPatchWindowController: NSWindowController {
    private let viewModel: LaunchpadViewModel
    private let hostingView: NSHostingView<LaunchpadBackgroundView>

    init(viewModel: LaunchpadViewModel) {
        self.viewModel = viewModel
        self.hostingView = NSHostingView(
            rootView: LaunchpadBackgroundView(viewModel: viewModel)
        )

        let window = MenuBarPatchWindow(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovable = false
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.animationBehavior = .none
        window.level = WindowLevels.aboveStatusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.title = "Launchpad Menu Bar Patch"

        super.init(window: window)

        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.autoresizingMask = [.width, .height]
        hostingView.frame = window.contentView?.bounds ?? .zero
        window.contentView = hostingView
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateFrame(_ frame: NSRect, screen: NSScreen, viewport: CGRect) {
        window?.setFrame(frame, display: true)
        hostingView.rootView = LaunchpadBackgroundView(
            viewModel: viewModel,
            screen: screen,
            viewport: viewport
        )
    }

    func orderFront() {
        window?.orderFrontRegardless()
    }

    func orderOut() {
        window?.orderOut(nil)
    }
}

/// Swallows clicks in the covered corner so the menu bar cannot be operated
/// through it. It never becomes key or main.
final class MenuBarPatchWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func mouseDown(with event: NSEvent) {
        // Intentionally consume the event.
    }
}

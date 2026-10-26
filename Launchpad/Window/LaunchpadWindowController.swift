import AppKit
import SwiftUI

/// Owns one overlay window and its local event monitors. The primary instance
/// handles keyboard and pointer input; mirror windows on other displays are
/// non-interactive.
///
/// The main window sits above the status bar so it covers the menu bar. It
/// stops at the Dock's edge, and a non-interactive background window fills the
/// Dock strip one level lower. This keeps the Dock visible without adding a
/// separate menu-bar strip over the grid.
final class LaunchpadWindowController: NSWindowController {
    let viewModel: LaunchpadViewModel
    let isInteractive: Bool

    private var keyMonitor: Any?
    private var flagsMonitor: Any?
    private var dockBackground: DockBackgroundWindowController?
    private var menuBarPatch: MenuBarPatchWindowController?

    init(viewModel: LaunchpadViewModel, interactive: Bool) {
        self.viewModel = viewModel
        self.isInteractive = interactive

        let window = LaunchpadWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
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
        window.acceptsMouseMovedEvents = true
        window.animationBehavior = .none
        window.level = WindowLevels.aboveStatusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.ignoresMouseEvents = !interactive
        window.title = "Launchpad"

        super.init(window: window)

        let root = LaunchpadRootView(viewModel: viewModel, isInteractive: interactive)
        let hostingView = NSHostingView(rootView: root)
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.autoresizingMask = [.width, .height]
        hostingView.frame = window.contentView?.bounds ?? .zero
        window.contentView = hostingView

        window.scrollHandler = { [weak viewModel] event in
            guard interactive else { return }
            viewModel?.handleScroll(event)
        }

        if interactive {
            installEventMonitors()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
    }

    func updateFrame(_ screen: NSScreen) {
        let reservation = DockReservation.current(for: screen)
        window?.setFrame(reservation.interactiveFrame(for: screen), display: true)
        updateDockBackground(reservation: reservation, screen: screen)
        updateMenuBarPatch(reservation: reservation, screen: screen)
    }

    func orderFront() {
        guard let window else { return }
        window.orderFrontRegardless()
        if isInteractive {
            window.makeKey()
        }
        dockBackground?.orderFront()
        menuBarPatch?.orderFront()
    }

    func orderOut() {
        menuBarPatch?.orderOut()
        dockBackground?.orderOut()
        window?.orderOut(nil)
    }

    func setInteractive(_ interactive: Bool) {
        window?.ignoresMouseEvents = !interactive
    }

    private func updateDockBackground(
        reservation: DockReservation,
        screen: NSScreen
    ) {
        guard let frame = reservation.backgroundFrame(for: screen) else {
            dockBackground?.orderOut()
            dockBackground = nil
            return
        }

        let background = dockBackground ?? DockBackgroundWindowController(viewModel: viewModel)
        dockBackground = background
        background.updateFrame(frame)
        if window?.isVisible == true {
            background.orderFront()
        }
    }

    private func updateMenuBarPatch(
        reservation: DockReservation,
        screen: NSScreen
    ) {
        guard let frame = reservation.menuBarPatchFrame(for: screen) else {
            menuBarPatch?.orderOut()
            menuBarPatch = nil
            return
        }

        let patch = menuBarPatch ?? MenuBarPatchWindowController(viewModel: viewModel)
        menuBarPatch = patch
        patch.updateFrame(frame)
        if window?.isVisible == true {
            patch.orderFront()
        }
    }

    private func installEventMonitors() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self,
                  self.viewModel.isVisible,
                  event.window === self.window else { return event }
            let isTextEditing = self.window?.firstResponder is NSTextView
            return self.viewModel.handleKeyDown(event, isTextEditing: isTextEditing) ? nil : event
        }

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            guard let self,
                  self.viewModel.isVisible,
                  event.window === self.window else { return event }
            self.viewModel.handleModifierFlags(event)
            return event
        }
    }
}

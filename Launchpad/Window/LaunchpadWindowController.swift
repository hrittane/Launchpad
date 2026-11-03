import AppKit
import SwiftUI

/// Publishes the overlay window's own screen and the slice of that screen the
/// window covers, so the SwiftUI backdrop can blur the right wallpaper and
/// line up with the Dock strip (mirrors included).
@MainActor
final class OverlayScreenContext: ObservableObject {
    @Published var screen: NSScreen?
    @Published var viewport: CGRect?
}

/// Owns one overlay window and its local event monitors. The primary instance
/// handles keyboard and pointer input; mirror windows on other displays are
/// non-interactive.
///
/// The main window sits above the status bar so it covers the menu bar. It
/// stops at the Dock's edge, and a non-interactive background window fills the
/// Dock strip one level lower. This keeps the Dock visible and clickable
/// without adding a separate menu-bar strip over the grid.
final class LaunchpadWindowController: NSWindowController {
    let viewModel: LaunchpadViewModel
    let isInteractive: Bool

    private var keyMonitor: Any?
    private var flagsMonitor: Any?
    private var dragMonitor: Any?
    private var dockBackground: DockBackgroundWindowController?
    private var menuBarPatch: MenuBarPatchWindowController?
    private let screenContext = OverlayScreenContext()

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

        let root = LaunchpadRootView(
            viewModel: viewModel,
            isInteractive: interactive,
            screenContext: screenContext
        )
        let hostingView = OverlayHostingView(rootView: root)
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
        if let dragMonitor { NSEvent.removeMonitor(dragMonitor) }
    }

    func updateFrame(_ screen: NSScreen) {
        // Resolve and blur the wallpaper once, before the window and its
        // SwiftUI body are positioned on this screen. The body only reads the
        // cached result.
        WallpaperBackdrop.prepare(for: screen)

        let reservation = DockReservation.current(for: screen)
        let frame = reservation.interactiveFrame(for: screen)
        screenContext.screen = screen
        screenContext.viewport = reservation.viewport(for: frame, on: screen)
        window?.setFrame(frame, display: true)
        // Preferences derives the usable icon-size range from this size, so
        // keep it accurate even when the overlay has not been shown yet.
        if isInteractive {
            viewModel.setScreenSize(frame.size)
        }
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

    /// Window-level opacity. Animating the window's alpha lets the compositor
    /// cross-fade the whole overlay (including Liquid Glass) for free, instead
    /// of re-rendering every SwiftUI opacity animation frame.
    func setAlpha(_ value: CGFloat) {
        window?.alphaValue = value
        dockBackground?.window?.alphaValue = value
        menuBarPatch?.window?.alphaValue = value
    }

    func animateAlpha(to value: CGFloat, duration: TimeInterval) {
        guard let window else { return }
        let rising = value > window.alphaValue
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(
                name: rising ? .easeOut : .easeIn
            )
            window.animator().alphaValue = value
            dockBackground?.window?.animator().alphaValue = value
            menuBarPatch?.window?.animator().alphaValue = value
        }
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
        background.updateFrame(
            frame,
            screen: screen,
            viewport: reservation.viewport(for: frame, on: screen)
        )
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
        patch.updateFrame(
            frame,
            screen: screen,
            viewport: reservation.viewport(for: frame, on: screen)
        )
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

        // SwiftUI can cancel the tile's DragGesture mid-drag when the hovered
        // tile morphs into a folder preview. The AppKit event stream keeps
        // running even when that happens, so the drag is fed from here too.
        // Without this the floating icon stranded wherever the gesture died
        // and the drop never committed, even though the rest of the overlay was
        // still responsive.
        dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) {
            [weak self] event in
            self?.handleDragMonitorEvent(event)
            return event
        }
    }

    private func handleDragMonitorEvent(_ event: NSEvent) {
        guard viewModel.isVisible,
              viewModel.dragSession != nil,
              event.window === window,
              let contentView = window?.contentView else { return }

        // SwiftUI's "launchpad" space is top-left origin; AppKit window
        // coordinates are bottom-left.
        let point = event.locationInWindow
        let location = CGPoint(x: point.x, y: contentView.bounds.height - point.y)

        switch event.type {
        case .leftMouseDragged:
            viewModel.updateDragFromMonitor(location: location)
        case .leftMouseUp:
            viewModel.endDrag()
        default:
            break
        }
    }
}

/// Accepts the click that activates the overlay. Without this, the first click
/// after Launchpad is shown from another app can be consumed by AppKit window
/// activation and never reach SwiftUI's tap gestures.
private final class OverlayHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

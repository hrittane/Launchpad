import AppKit

/// Creates and coordinates the overlay windows: one on the screen under the
/// cursor, plus optional non-interactive mirrors on every other display.
@MainActor
final class WindowManager {
    private let viewModel: LaunchpadViewModel
    private var primary: LaunchpadWindowController?
    private var mirrors: [LaunchpadWindowController] = []
    private var isShown = false
    private var hideTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?

    var isVisible: Bool { isShown }

    init(viewModel: LaunchpadViewModel) {
        self.viewModel = viewModel
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.screenConfigurationChanged()
            }
        }
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    /// Pre-creates the primary window so the first show does not pay the
    /// NSWindow + NSHostingView setup cost.
    func prepare() {
        guard primary == nil else { return }
        let controller = LaunchpadWindowController(viewModel: viewModel, interactive: true)
        controller.updateFrame(screenUnderCursor())
        primary = controller
    }

    func show() {
        guard !isShown else { return }
        hideTask?.cancel()
        // Keep the cached blur across shows. `updateFrame` compares a cheap
        // wallpaper signature and rebuilds only when the desktop wallpaper or
        // appearance actually changed.
        prepare()
        guard let primary else { return }

        viewModel.prepareForShow()
        let screen = screenUnderCursor()
        primary.updateFrame(screen)
        primary.setInteractive(true)
        primary.setAlpha(0)
        isShown = true
        viewModel.setVisible(true)

        NSApp.activate()
        // `orderFront` also raises the non-interactive Dock backdrop and the
        // side-Dock corner patch, which `makeKeyAndOrderFront` would leave out.
        primary.orderFront()

        updateMirrors(fadeIn: true)

        // Cross-fade the windows themselves. This keeps the show smooth even
        // when the content includes Liquid Glass, which is costly to re-render
        // behind a SwiftUI opacity animation.
        let duration = showFadeDuration
        primary.animateAlpha(to: 1, duration: duration)
        for mirror in mirrors {
            mirror.animateAlpha(to: 1, duration: duration)
        }
    }

    func hide() {
        guard isShown else { return }
        hideTask?.cancel()
        isShown = false
        viewModel.setVisible(false)

        let duration = hideFadeDuration
        primary?.animateAlpha(to: 0, duration: duration)
        mirrors.forEach { $0.animateAlpha(to: 0, duration: duration) }

        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((duration + 0.03) * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.finishHide()
        }
    }

    private var showFadeDuration: TimeInterval {
        viewModel.reduceMotion ? 0.08 : Metrics.Durations.showBackground
    }

    private var hideFadeDuration: TimeInterval {
        viewModel.reduceMotion ? 0.08 : Metrics.Durations.hideBackground
    }

    func toggle() {
        if isShown { hide() } else { show() }
    }

    func updateMirrorVisibility() {
        guard isShown else { return }
        updateMirrors()
    }

    private func finishHide() {
        primary?.orderOut()
        mirrors.forEach { $0.orderOut() }

        let launchpadWindows = Set(NSApp.windows.filter { $0.title == "Launchpad" }.map(ObjectIdentifier.init))
        let hasOtherVisibleWindow = NSApp.windows.contains { window in
            window.isVisible && !launchpadWindows.contains(ObjectIdentifier(window))
        }

        if hasOtherVisibleWindow {
            NSApp.deactivate()
        } else {
            NSApp.hide(nil)
        }
    }

    private func updateMirrors(fadeIn: Bool = false) {
        mirrors.forEach { $0.orderOut() }
        mirrors.removeAll()

        guard viewModel.settings.showOnAllDisplays else { return }
        let mainScreen = screenUnderCursor()
        for screen in NSScreen.screens where screen !== mainScreen {
            let controller = LaunchpadWindowController(viewModel: viewModel, interactive: false)
            controller.updateFrame(screen)
            if fadeIn {
                controller.setAlpha(0)
            }
            controller.orderFront()
            mirrors.append(controller)
        }
    }

    private func screenConfigurationChanged() {
        let screen = screenUnderCursor()
        primary?.updateFrame(screen)
        if isShown {
            updateMirrors()
        }
    }

    private func screenUnderCursor() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}

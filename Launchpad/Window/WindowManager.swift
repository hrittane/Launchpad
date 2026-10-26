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
        prepare()
        guard let primary else { return }

        viewModel.prepareForShow()
        isShown = true

        let screen = screenUnderCursor()
        primary.updateFrame(screen)
        primary.setInteractive(true)

        NSApp.activate(ignoringOtherApps: true)
        // `orderFront` also raises the non-interactive Dock backdrop and the
        // side-Dock corner patch, which `makeKeyAndOrderFront` would leave out.
        primary.orderFront()

        updateMirrors()

        // Let SwiftUI render the hidden state once so the show transition is
        // animated rather than appearing fully formed.
        DispatchQueue.main.async { [weak self] in
            self?.viewModel.setVisible(true)
        }
    }

    func hide() {
        guard isShown else { return }
        hideTask?.cancel()
        isShown = false
        viewModel.setVisible(false)

        let delay = viewModel.reduceMotion ? 0.18 : 0.42
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.finishHide()
        }
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

    private func updateMirrors() {
        mirrors.forEach { $0.orderOut() }
        mirrors.removeAll()

        guard viewModel.settings.showOnAllDisplays else { return }
        let mainScreen = screenUnderCursor()
        for screen in NSScreen.screens where screen !== mainScreen {
            let controller = LaunchpadWindowController(viewModel: viewModel, interactive: false)
            controller.updateFrame(screen)
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

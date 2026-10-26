import AppKit

/// Composition root. Keeping service wiring here means the view model stays
/// testable and has no knowledge of AppKit windows or Carbon hot keys.
@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()

    let viewModel: LaunchpadViewModel
    let windowManager: WindowManager
    let preferencesController: PreferencesWindowController
    let hotKeyManager: HotKeyManager
    let hotCornerMonitor: HotCornerMonitor

    private var started = false
    private var registeredShortcut: KeyShortcut?
    private var mirrorsEnabled = false

    private init() {
        let viewModel = LaunchpadViewModel()
        self.viewModel = viewModel
        self.windowManager = WindowManager(viewModel: viewModel)
        self.preferencesController = PreferencesWindowController(viewModel: viewModel)
        self.hotKeyManager = HotKeyManager()
        self.hotCornerMonitor = HotCornerMonitor()
    }

    func start() {
        guard !started else { return }
        started = true

        viewModel.onRequestClose = { [weak self] in
            self?.windowManager.hide()
        }
        viewModel.onRequestPreferences = { [weak self] in
            self?.openPreferences()
        }
        viewModel.onSettingsChanged = { [weak self] settings in
            self?.apply(settings: settings)
        }

        hotKeyManager.onPress = { [weak self] in
            self?.windowManager.toggle()
        }
        hotCornerMonitor.onTrigger = { [weak self] in
            self?.windowManager.show()
        }
        hotCornerMonitor.isSuspended = { [weak self] in
            self?.windowManager.isVisible ?? false
        }

        hotCornerMonitor.start(corner: viewModel.settings.hotCorner)
        apply(settings: viewModel.settings)
        windowManager.prepare()
        viewModel.start()
    }

#if DEBUG
    /// Headless-ish smoke test used by the README QA process. Debug builds can
    /// run with `--smoke-test` to show the overlay, report window/layout state,
    /// and terminate without requiring Accessibility or Screen Recording.
    func runSmokeTest() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            windowManager.show()
            try? await Task.sleep(nanoseconds: 1_500_000_000)

            let overlayWindows = NSApp.windows.filter { $0.title == "Launchpad" && $0.isVisible }
            let itemCount = viewModel.pages.reduce(0) { $0 + $1.count }
            let frame = overlayWindows.first?.frame ?? .zero
            print("SMOKE overlayWindows=\(overlayWindows.count) pages=\(viewModel.pages.count) items=\(itemCount) frame=\(frame)")
            NSApp.terminate(nil)
        }
    }

#endif

    func openPreferences() {
        NSApp.activate(ignoringOtherApps: true)

        // SwiftUI's Settings scene is opened through the standard action. The
        // selector name changed across macOS releases, so try both.
        if NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            return
        }
        if NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil) {
            return
        }
        preferencesController.show()
    }

    func shutdown() {
        guard started else { return }
        started = false
        hotKeyManager.unregister()
        hotCornerMonitor.stop()
        viewModel.shutdown()
    }

    var isStarted: Bool { started }

    /// Flushes the current layout before the process exits. AppKit's
    /// `terminateLater` reply gives the actor-backed store time to finish its
    /// atomic write, so arrangement changes made just before Quit are durable.
    ///
    /// The flush runs off the main actor because AppKit blocks the main actor
    /// inside its termination run loop; the reply is scheduled back onto the
    /// main run loop in common modes, which that loop still services.
    func shutdownAndFlush(_ completion: @escaping () -> Void) {
        guard started else {
            completion()
            return
        }
        started = false
        hotKeyManager.unregister()
        hotCornerMonitor.stop()
        viewModel.shutdown()
        let flush = viewModel.makeFlushTask()
        Task.detached {
            _ = await flush.value
            // The termination reply must run in a common run-loop mode: AppKit
            // services `terminateLater` in an event-tracking loop, where a
            // plain main-queue block is not guaranteed to be drained.
            RunLoop.main.perform(inModes: [.common]) {
                completion()
            }
        }
    }

    private func apply(settings: AppSettings) {
        if registeredShortcut != settings.shortcut {
            hotKeyManager.register(settings.shortcut)
            registeredShortcut = settings.shortcut
        }

        hotCornerMonitor.update(corner: settings.hotCorner)

        if mirrorsEnabled != settings.showOnAllDisplays {
            mirrorsEnabled = settings.showOnAllDisplays
            windowManager.updateMirrorVisibility()
        }

        if settings.launchAtLogin != LaunchAtLoginService.isEnabled {
            LaunchAtLoginService.setEnabled(settings.launchAtLogin)
        }
    }
}

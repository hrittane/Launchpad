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
            let dockWindows = NSApp.windows.filter {
                $0.title == "Launchpad Dock Background" && $0.isVisible
            }
            let patchWindows = NSApp.windows.filter {
                $0.title == "Launchpad Menu Bar Patch" && $0.isVisible
            }
            let itemCount = viewModel.pages.reduce(0) { $0 + $1.count }
            let displayCount = NSScreen.screens.count
            let expectedWindows = viewModel.settings.showOnAllDisplays ? displayCount : 1

            guard let overlay = overlayWindows.first, let screen = overlay.screen else {
                print("SMOKE overlayWindows=0 displays=\(displayCount) expectedWindows=\(expectedWindows)")
                NSApp.terminate(nil)
                return
            }

            let reservation = DockReservation.current(for: screen)
            let frame = overlay.frame
            let expectedFrame = reservation.interactiveFrame(for: screen)
            let screenFrame = screen.frame
            let level = overlay.level.rawValue
            let frameStopsAtDock = frame == expectedFrame
            let levelIsExpected = level == WindowLevels.aboveStatusBar.rawValue
            let windowCountMatches = overlayWindows.count == expectedWindows
            // A bottom Dock needs one strip behind it; a side Dock needs the
            // strip plus the menu-bar corner patch.
            let dockStripIsPresent = reservation.isEmpty || !dockWindows.isEmpty
            let patchIsPresent = reservation.menuBarPatchFrame(for: screen) == nil
                || !patchWindows.isEmpty
            let dockIsBelowTheOverlay = dockWindows.allSatisfy {
                $0.level == WindowLevels.belowDock
            }
            let wallpaper = SystemWallpaper.resolve(for: screen)
            let wallpaperIsResolved = wallpaper != nil

            print(
                "SMOKE overlayWindows=\(overlayWindows.count) displays=\(displayCount) "
                    + "expectedWindows=\(expectedWindows) pages=\(viewModel.pages.count) "
                    + "items=\(itemCount) frame=\(frame) expectedFrame=\(expectedFrame) "
                    + "screen=\(screenFrame) level=\(level) "
                    + "frameStopsAtDock=\(frameStopsAtDock) windowCountMatches=\(windowCountMatches) "
                    + "dockWindows=\(dockWindows.count) patchWindows=\(patchWindows.count) "
                    + "dockStripIsPresent=\(dockStripIsPresent) patchIsPresent=\(patchIsPresent) "
                    + "belowDockLevel=\(WindowLevels.belowDock.rawValue) "
                    + "dockIsBelowTheOverlay=\(dockIsBelowTheOverlay) "
                    + "wallpaper=\(wallpaper?.identity ?? "none") "
                    + "wallpaperIsResolved=\(wallpaperIsResolved)"
            )
            assert(
                frameStopsAtDock && levelIsExpected && windowCountMatches
                    && dockStripIsPresent && patchIsPresent && dockIsBelowTheOverlay
                    && wallpaperIsResolved,
                "Overlay window or wallpaper source is not configured correctly"
            )
            NSApp.terminate(nil)
        }
    }

#endif

    func openPreferences() {
        NSApp.activate()

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

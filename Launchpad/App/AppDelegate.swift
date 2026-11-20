import AppKit
import Carbon.HIToolbox
import os

private let desktopGestureLog = Logger(
    subsystem: "com.example.Launchpad",
    category: "trackpad"
)

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private let settings = LaunchpadSettings.shared
    /// Remembers a native "Show Desktop" spread so the pinch that restores the
    /// windows does not open Launchpad as well.
    private var desktopReveal = DesktopRevealState()
    private var panelController: LaunchpadPanelController?
    private var statusItemController: StatusItemController?
    private var settingsWindowController: SettingsWindowController?
    private var hotKey: GlobalHotKey?
    private var hotKeyWanted: Bool?
    private var hotCornerMonitor: HotCornerMonitor?
    private var resignObserver: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?
    /// Polls Accessibility while the Apps pinch is taken over, so the Dock is
    /// overridden as soon as the user grants access and restored if it goes.
    private var trustWatch: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = NSApp.setActivationPolicy(.accessory)

        model.catalog.scanIfNeeded()
        model.apply(settings: settings)

        let controller = LaunchpadPanelController(
            model: model,
            settings: settings,
            onGrantPermissions: { [weak self] in
                self?.showSettings(focusAccessibility: true)
            }
        )
        panelController = controller

        // Like the real Launchpad, the panel is modal in spirit: switching to
        // another application dismisses it instead of leaving it on screen.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak controller] _ in
            Task { @MainActor in
                guard let controller, controller.isVisible else { return }
                controller.hide(restoreFocus: false)
            }
        }

        statusItemController = StatusItemController(
            onShow: { [weak self] in self?.showFromManualControl() },
            onSettings: { [weak self] in self?.showSettings() },
            onQuit: { NSApp.terminate(nil) }
        )
        statusItemController?.setVisible(settings.showMenuBarIcon)

        configureHotKey()
        hotCornerMonitor = HotCornerMonitor()
        configureHotCorner()
        configurePinch()

        // If the app was killed while it owned the system pinch, the override
        // flag is still set. Reconcile it at launch: keep macOS's Apps view off
        // when the take-over still applies, and put the Dock back otherwise.
        refreshSystemGestureOwnership()
        SystemLaunchpadGesture.shared.restoreShowDesktopGestureOnce()

        // Every persisted change re-applies the settings. The handlers are all
        // idempotent, so a slider drag is cheap and a toggle needs no special
        // case.
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .launchpadSettingsDidChange,
            object: settings,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applySettings() }
        }

        // Compose and blur the backdrop now: the first panel presentation then
        // only has to hand the finished image to the window.
        BackdropView.preheat()

        #if DEBUG
        if !CommandLine.arguments.contains("--no-panel") {
            controller.show()
        }
        #else
        controller.show()
        #endif

        #if DEBUG
        handleSnapshotRequestIfNeeded(controller: controller)
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
        hotKey?.unregister()
        hotKey = nil
        stopTrustWatch()
        TrackpadGestureBlocker.shared.uninstall()
        SystemLaunchpadGesture.shared.setEnabled(false)
    }

    // MARK: - Settings

    /// - Parameter focusAccessibility: opens Settings on General with the
    ///   Accessibility row highlighted, as requested by the launcher's
    ///   permission banner.
    private func showSettings(focusAccessibility: Bool = false) {
        panelController?.hide(restoreFocus: false)
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                model: model,
                settings: settings
            )
        }
        settingsWindowController?.present(focusAccessibility: focusAccessibility)
    }

    /// Re-applies every setting that has an AppKit side effect.
    private func applySettings() {
        statusItemController?.setVisible(settings.showMenuBarIcon)
        configureHotKey()
        configureHotCorner()
        configurePinch()
        refreshSystemGestureOwnership()
        model.apply(settings: settings)
        panelController?.applySettings()
    }

    private func configureHotKey() {
        // A slider drag posts one notification per step; re-registering the
        // Carbon shortcut on every step would be needless churn.
        guard hotKeyWanted != settings.hotKeyEnabled else { return }
        hotKeyWanted = settings.hotKeyEnabled
        hotKey?.unregister()
        hotKey = nil
        guard settings.hotKeyEnabled else { return }

        // ⌥Space toggles the panel from any application, the way the Launchpad
        // key does. A shortcut that another app already owns cannot be
        // registered; the menu bar item keeps working in that case.
        hotKey = GlobalHotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)) {
            [weak self] in
            self?.toggleFromManualControl()
        }
    }

    // MARK: - Manual activation

    /// Explicit controls always win over a pending desktop restore.
    private func showFromManualControl() {
        desktopReveal.reset()
        panelController?.show()
    }

    private func toggleFromManualControl() {
        desktopReveal.reset()
        panelController?.toggle()
    }

    private func configureHotCorner() {
        guard let hotCornerMonitor else { return }
        hotCornerMonitor.configure(
            enabled: settings.hotCornerEnabled,
            corner: settings.hotCorner
        ) { [weak self] in
            self?.showFromManualControl()
        }
    }

    /// Pinch, spread and the multi-finger page swipe belong to Launchpad only
    /// while the take-over is enabled and macOS actually lets it block the
    /// Dock. Without Accessibility the system pinch stays in charge, so opening
    /// on our recognizer as well would race it.
    private var trackpadTakeoverActive: Bool {
        settings.suppressDesktopSwipe && TrackpadGestureBlocker.shared.isTrusted
    }

    /// macOS's Apps pinch is only taken over when Launchpad's own four-finger
    /// pinch is wanted. Switching that off hands the gesture back, so the Dock
    /// can open the native Apps view again.
    private var wantsSystemAppsGestureSuppressed: Bool {
        settings.pinchEnabled && settings.suppressDesktopSwipe
    }

    /// The Dock is only overridden once the take-over can actually run; without
    /// Accessibility the native Apps view stays available.
    private var systemAppsGestureSuppressed: Bool {
        wantsSystemAppsGestureSuppressed && TrackpadGestureBlocker.shared.isTrusted
    }

    /// Keeps macOS's own Apps view switched off exactly while Launchpad owns
    /// the pinch, and gives it back otherwise. The Dock only re-reads the
    /// preference at launch, so a value change restarts it once; re-applying
    /// the same value is a no-op.
    private func refreshSystemGestureOwnership() {
        setSystemGestureOverride(systemAppsGestureSuppressed)
        if wantsSystemAppsGestureSuppressed {
            startTrustWatchIfNeeded()
        } else {
            stopTrustWatch()
        }
    }

    private func setSystemGestureOverride(_ enabled: Bool) {
        guard SystemLaunchpadGesture.shared.isOverrideActive != enabled else { return }
        SystemLaunchpadGesture.shared.setEnabled(enabled)
    }

    /// Accessibility can be granted or revoked while Launchpad is hidden, and
    /// there is no notification for either. Poll gently while the pinch is
    /// taken over, so the system Apps view is handed over the moment access
    /// arrives and comes back when it is revoked.
    private func startTrustWatchIfNeeded() {
        guard wantsSystemAppsGestureSuppressed, trustWatch == nil else { return }
        trustWatch = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                guard let self, self.wantsSystemAppsGestureSuppressed else { break }
                self.setSystemGestureOverride(self.systemAppsGestureSuppressed)
            }
            self?.trustWatch = nil
        }
    }

    private func stopTrustWatch() {
        trustWatch?.cancel()
        trustWatch = nil
    }

    private func configurePinch() {
        // The monitor is started once and stays on; the AppKit side decides
        // whether the take-over is currently allowed. Spread-to-close and
        // multi-finger paging should work whenever the panel is visible, even
        // when it was opened with ⌥Space.
        PinchGestureMonitor.shared.start(
            onPinch: { [weak self] in
                guard let self, self.trackpadTakeoverActive else { return }
                // Consume a pending Show Desktop restore first, whether or not
                // pinch-to-open is enabled, so it cannot go stale.
                let opensLauncher = self.desktopReveal.shouldOpenLaunchpadOnPinch()
                guard opensLauncher else {
                    desktopGestureLog.notice(
                        "pinch restored the desktop; keeping Launchpad closed"
                    )
                    return
                }
                guard self.settings.pinchEnabled else { return }
                self.panelController?.show()
            },
            onSpread: { [weak self] in
                guard let self, self.trackpadTakeoverActive else { return }
                let panelWasVisible = self.panelController?.isVisible == true
                self.desktopReveal.noteSpread(panelWasVisible: panelWasVisible)
                if panelWasVisible { self.panelController?.hide() }
            },
            onSwipe: { [weak self] event in
                self?.panelController?.handleTrackpadSwipe(event)
            }
        )
    }

    #if DEBUG
    /// `--snapshot <path>` renders one frame to disk and quits, so the UI can be
    /// compared against the reference frames without screen-recording access.
    private func handleSnapshotRequestIfNeeded(controller: LaunchpadPanelController) {
        let arguments = CommandLine.arguments
        guard let flagIndex = arguments.firstIndex(of: "--snapshot"),
              arguments.index(after: flagIndex) < arguments.endIndex else { return }
        let path = arguments[arguments.index(after: flagIndex)]
        let url = URL(fileURLWithPath: path)

        Task { @MainActor in
            // Let the catalog scan, icon loads and entrance animation settle.
            try? await Task.sleep(for: .milliseconds(1800))

            if let pageIndex = integerArgument(after: "--page") {
                model.goToPage(pageIndex)
                try? await Task.sleep(for: .milliseconds(600))
            }

            if CommandLine.arguments.contains("--screen"),
               let image = WindowSnapshot.captureScreen(),
               let data = pngData(from: image, rejectingBlank: true) {
                try? data.write(to: url)
                reportSnapshot(wrote: true, url: url, mode: "full-screen")
                NSApp.terminate(nil)
                return
            }

            if let image = WindowSnapshot.capture(windowNumber: controller.windowNumber),
               let data = pngData(from: image, rejectingBlank: true) {
                try? data.write(to: url)
                reportSnapshot(wrote: true, url: url, mode: "window-server")
                NSApp.terminate(nil)
                return
            }

            controller.prepareForFallbackSnapshot()
            try? await Task.sleep(for: .milliseconds(450))
            let wrote = controller.writeFlattenedSnapshot(to: url)
            reportSnapshot(wrote: wrote, url: url, mode: "offscreen")
            NSApp.terminate(nil)
        }
    }

    /// Screen capture permission can turn blank frames into an all-zero image;
    /// those are rejected so the caller can fall back to offscreen rendering.
    private func pngData(from image: CGImage, rejectingBlank: Bool) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        if rejectingBlank && !containsVisibleContent(rep) { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private func containsVisibleContent(_ rep: NSBitmapImageRep) -> Bool {
        let width = rep.pixelsWide
        let height = rep.pixelsHigh
        guard width > 0, height > 0 else { return false }
        var visible = 0
        var sampled = 0
        for y in stride(from: 0, to: height, by: 24) {
            for x in stride(from: 0, to: width, by: 24) {
                sampled += 1
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.alphaComponent > 0.5,
                   color.redComponent + color.greenComponent + color.blueComponent > 0.15 {
                    visible += 1
                }
            }
        }
        return sampled > 0 && Double(visible) / Double(sampled) > 0.02
    }

    private func reportSnapshot(wrote: Bool, url: URL, mode: String) {
        let message = wrote ? "snapshot (\(mode)): \(url.path)\n" : "snapshot failed\n"
        FileHandle.standardError.write(Data(message.utf8))
    }

    private func integerArgument(after flag: String) -> Int? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag),
              arguments.index(after: index) < arguments.endIndex else { return nil }
        return Int(arguments[arguments.index(after: index)])
    }
    #endif

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

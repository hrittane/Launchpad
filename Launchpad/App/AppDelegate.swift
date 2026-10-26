import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var isTerminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement is also set in Info.plist; setting the policy here keeps
        // debug builds from briefly showing a Dock icon.
        NSApp.setActivationPolicy(.accessory)

        guard !isRunningTests else { return }
        AppEnvironment.shared.start()

        // SwiftUI can restore the Settings scene at launch. A menu-bar agent
        // should start with no visible windows, so hide it once startup settles.
        DispatchQueue.main.async {
            for window in NSApp.windows
            where window.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" {
                window.isRestorable = false
                window.orderOut(nil)
            }
        }

#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--smoke-test") {
            AppEnvironment.shared.runSmokeTest()
        }
#endif
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Tests and already-stopped environments have nothing to flush, so they
        // can terminate synchronously.
        guard !isRunningTests, AppEnvironment.shared.isStarted else {
            return .terminateNow
        }
        // A second termination request while the flush is in flight must not
        // start a second flush or send a second reply. Terminate immediately
        // instead; the pending atomic write cannot corrupt the existing file.
        guard !isTerminating else {
            return .terminateNow
        }
        isTerminating = true
        AppEnvironment.shared.shutdownAndFlush {
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Idempotent fallback: normally `shutdownAndFlush` already stopped the
        // services and wrote the layout.
        AppEnvironment.shared.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            AppEnvironment.shared.windowManager.show()
        }
        return true
    }

    func showLaunchpad() {
        AppEnvironment.shared.windowManager.show()
    }

    func openPreferences() {
        AppEnvironment.shared.openPreferences()
    }

    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
    }
}

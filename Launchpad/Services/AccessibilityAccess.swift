import AppKit
import ApplicationServices

/// Onboarding for the Accessibility grant the trackpad blocker needs.
///
/// macOS only lists an app in Privacy & Security after it has asked for the
/// permission, and an ad-hoc build running from a derived-data folder is hard
/// to identify in that list. These helpers reveal the running bundle, copy it
/// to /Applications and open the exact pane, so granting is a short path.
@MainActor
enum AccessibilityAccess {
    static let installedURL = URL(
        fileURLWithPath: "/Applications/Launchpad.app",
        isDirectory: true
    )

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static var runningURL: URL { Bundle.main.bundleURL }

    /// True when the process was launched from the /Applications copy, where
    /// the grant is easy to find again after a relaunch.
    static var isRunningInstalledCopy: Bool {
        runningURL.resolvingSymlinksInPath().standardizedFileURL.path
            == installedURL.resolvingSymlinksInPath().standardizedFileURL.path
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: installedURL.path)
    }

    /// Shows the system prompt. Safe to call again: macOS simply reopens the
    /// pane when the grant was already declined once.
    static func request() {
        guard !isTrusted else { return }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// The grant the Settings button performs: clear an entry that belongs to
    /// an earlier build, ask again, and open the exact pane.
    ///
    /// An ad-hoc signature is identified by its code hash, so every rebuild
    /// leaves the old Accessibility row pointing at a binary that no longer
    /// exists. System Settings keeps showing the switch as on while
    /// `AXIsProcessTrusted` answers false, which makes the toggle look broken.
    /// Removing that entry lets the prompt record the running build instead.
    static func grant() {
        guard !isTrusted else {
            openSettings()
            return
        }
        clearStaleGrant()
    }

    /// Runs `tccutil reset` for this bundle and then requests access again.
    private static func clearStaleGrant() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task.arguments = ["reset", "Accessibility", bundleIdentifier]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        task.terminationHandler = { _ in
            Task { @MainActor in
                resetTask = nil
                request()
                openSettings()
            }
        }
        resetTask = task
        do {
            try task.run()
        } catch {
            resetTask = nil
            request()
            openSettings()
        }
    }

    /// Holds the reset process so its termination handler always runs.
    private static var resetTask: Process?

    private static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.example.Launchpad"
    }

    static func openSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    /// Opens a Finder window with the app selected, so it can be dragged into
    /// the Accessibility list when the prompt does not add it automatically.
    static func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([runningURL])
    }

    enum InstallError: LocalizedError {
        case copyFailed(String)

        var errorDescription: String? {
            switch self {
            case .copyFailed(let reason):
                return "Could not copy Launchpad to Applications: \(reason)"
            }
        }
    }

    /// Copies the running bundle to /Applications and registers it with
    /// Launch Services, which is what makes it appear in the settings list.
    @discardableResult
    static func installInApplications() throws -> URL {
        if isRunningInstalledCopy { return installedURL }

        let manager = FileManager.default
        do {
            if manager.fileExists(atPath: installedURL.path) {
                try manager.removeItem(at: installedURL)
            }
            try manager.copyItem(at: runningURL, to: installedURL)
        } catch {
            throw InstallError.copyFailed(error.localizedDescription)
        }

        registerWithLaunchServices(installedURL)
        return installedURL
    }

    /// Launches the /Applications copy and quits this one, so the grant sticks
    /// to a path the user can find again.
    static func relaunchFromApplications() {
        guard isInstalled else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(
            at: installedURL,
            configuration: configuration
        ) { _, _ in
            Task { @MainActor in
                NSApp.terminate(nil)
            }
        }
    }

    /// Launch Services owns the list System Settings reads. Registering the
    /// copy is what makes it appear without a logout.
    private static func registerWithLaunchServices(_ url: URL) {
        let task = Process()
        task.executableURL = URL(
            fileURLWithPath: "/System/Library/Frameworks/CoreServices.framework"
                + "/Frameworks/LaunchServices.framework/Support/lsregister"
        )
        task.arguments = ["-f", url.path]
        try? task.run()
    }
}

import AppKit
import os

/// Opens applications from the grid.
enum AppLauncher {
    private static let logger = Logger(subsystem: "com.example.Launchpad", category: "launch")

    /// Launches `item` in the foreground.
    ///
    /// `NSWorkspace` also activates an instance that is already running, so a
    /// click on a running app brings its windows forward instead of failing.
    static func launch(_ item: AppItem) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        NSWorkspace.shared.openApplication(at: item.url, configuration: configuration) { _, error in
            guard let error else { return }
            logger.error("Could not open \(item.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}

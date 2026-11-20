import AppKit

/// Confirms and performs the removal of an application and the data it left
/// in the user's Library folders.
///
/// Apps outside `/Applications` are never offered this by the UI; the guard is
/// repeated here so a wrong call cannot delete a system app.
@MainActor
enum AppUninstaller {
    /// Returns true when the app bundle itself was moved to the Trash.
    @discardableResult
    static func confirmAndTrash(_ app: AppItem) -> Bool {
        guard app.isRemovable else { return false }

        let controller = UninstallDialogController(app: app)
        guard let selection = controller.run(), !selection.isEmpty else { return false }
        return trash(selection, appName: app.name)
    }

    /// The Dock moved the bundle to the Trash before Launchpad could intercept
    /// it. Offer to remove whatever the app left behind; the catalog has
    /// already dropped the app by the time this runs.
    static func cleanUpAfterNativeTrash(_ app: AppItem) {
        guard app.isRemovable,
              !UninstallScanner.components(for: app).isEmpty else {
            return
        }

        let controller = UninstallDialogController(app: app)
        guard let selection = controller.run(), !selection.isEmpty else { return }
        _ = trash(selection, appName: app.name)
    }

    @discardableResult
    private static func trash(
        _ selection: [UninstallComponent],
        appName: String
    ) -> Bool {
        var failures: [String] = []
        var trashedApp = false
        for component in selection {
            // A file can vanish between the scan and the confirmation.
            guard FileManager.default.fileExists(atPath: component.url.path) else {
                continue
            }
            do {
                try FileManager.default.trashItem(at: component.url, resultingItemURL: nil)
                if component.kind == .applicationFiles {
                    trashedApp = true
                }
            } catch {
                failures.append("\(component.name) — \(error.localizedDescription)")
            }
        }

        if !failures.isEmpty {
            presentFailureAlert(appName: appName, failures: failures)
        }

        return trashedApp
    }

    private static func presentFailureAlert(appName: String, failures: [String]) {
        let shown = failures.prefix(6).joined(separator: "\n")
        let remaining = failures.count - min(failures.count, 6)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Some files from “\(appName)” could not be moved to the Trash."
        alert.informativeText = remaining > 0
            ? shown + "\n…and \(remaining) more."
            : shown
        alert.addButton(withTitle: "OK")
        alert.window.level = .floating
        alert.runModal()
    }
}

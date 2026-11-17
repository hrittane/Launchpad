import AppKit

/// Confirms and performs the removal of an application.
///
/// Apps outside `/Applications` are never offered this by the UI; the guard is
/// repeated here so a wrong call cannot delete a system app.
@MainActor
enum AppUninstaller {
    /// Returns true when the app was moved to the Trash.
    @discardableResult
    static func confirmAndTrash(_ app: AppItem) -> Bool {
        guard app.isRemovable else { return false }

        NSRunningApplication.current.activate(
            options: NSApplication.ActivationOptions(rawValue: 1 << 1)
        )

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.icon = NSWorkspace.shared.icon(forFile: app.url.path)
        alert.messageText = "Are you sure you want to delete “\(app.name)”?"
        alert.informativeText = """
            Deleting this app will also delete its data. You can reinstall it from the App Store.
            """
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        alert.window.level = .floating

        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        do {
            try FileManager.default.trashItem(at: app.url, resultingItemURL: nil)
            return true
        } catch {
            let failure = NSAlert()
            failure.alertStyle = .warning
            failure.messageText = "“\(app.name)” could not be deleted."
            failure.informativeText = error.localizedDescription
            failure.addButton(withTitle: "OK")
            failure.runModal()
            return false
        }
    }
}

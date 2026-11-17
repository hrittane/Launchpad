import Foundation

/// A launchable application discovered on disk.
struct AppItem: Identifiable, Hashable, Sendable {
    let bundleIdentifier: String?
    let url: URL
    let name: String

    var id: String { bundleIdentifier ?? url.path }

    /// Apps installed in a system location are not removable.
    var isSystem: Bool {
        url.path.hasPrefix("/System/")
    }

    /// Apps the current user can move to the Trash.
    var isRemovable: Bool {
        !isSystem && (url.path.hasPrefix("/Applications/")
            || url.path.hasPrefix(NSHomeDirectory() + "/Applications/"))
    }
}

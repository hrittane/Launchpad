import Foundation

/// A discovered application bundle.
///
/// `AppItem` is a value type so it can be freely passed between the scanner
/// actor, the layout engine, and SwiftUI without shared mutable state.
struct AppItem: Identifiable, Codable, Hashable, Sendable {
    /// Stable identity: bundle identifier when available, canonical path otherwise.
    let id: String
    let name: String
    let url: URL
    let isSystemApp: Bool
    let bundleIdentifier: String?
    let version: String?

    init(
        id: String? = nil,
        name: String,
        url: URL,
        isSystemApp: Bool,
        bundleIdentifier: String? = nil,
        version: String? = nil
    ) {
        let canonicalURL = url.resolvingSymlinksInPath().standardizedFileURL
        self.id = id ?? bundleIdentifier ?? canonicalURL.path
        self.name = name
        self.url = canonicalURL
        self.isSystemApp = isSystemApp
        self.bundleIdentifier = bundleIdentifier
        self.version = version
    }

    var filePath: String { url.path }

    /// System apps and apps in shared locations are not deletable from Launchpad.
    var isDeletable: Bool {
        !isSystemApp && !url.path.hasPrefix("/System/")
    }
}

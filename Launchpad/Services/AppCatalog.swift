import AppKit
import Observation

/// Discovers installed applications.
///
/// Milestone (a) uses a FileManager scan. Milestone (b) adds a live
/// `NSMetadataQuery` that reports installs/removals while the app is running.
@MainActor
@Observable
final class AppCatalog {
    private(set) var apps: [AppItem] = []
    private(set) var isScanning = false

    private var scanTask: Task<Void, Never>?

    nonisolated private static let selfBundleIdentifier = "com.example.Launchpad"

    init(apps: [AppItem] = []) {
        self.apps = apps
    }

    nonisolated private static var roots: [String] {
        [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
            NSHomeDirectory() + "/Applications",
            "/System/Cryptexes/App/System/Applications"
        ]
    }

    func scanIfNeeded() {
        guard apps.isEmpty, scanTask == nil else { return }
        rescan()
    }

    func rescan() {
        scanTask?.cancel()
        isScanning = true
        scanTask = Task { [weak self] in
            let found = await Task.detached(priority: .userInitiated) {
                Self.scanFileSystem()
            }.value
            guard let self, !Task.isCancelled else { return }
            self.apps = found
            self.isScanning = false
            self.scanTask = nil
        }
    }

    /// Drops an app from the in-memory catalog after it was moved to the Trash.
    func remove(id: String) {
        apps.removeAll { $0.id == id }
    }

    // MARK: - Scanning

    nonisolated private static func scanFileSystem() -> [AppItem] {
        let fm = FileManager.default
        var found: [String: AppItem] = [:]

        func consider(_ url: URL) {
            guard let bundle = Bundle(url: url) else { return }
            let info = bundle.infoDictionary ?? [:]
            if info["LSBackgroundOnly"] as? Bool == true { return }
            if info["LSUIElement"] as? Bool == true { return }

            let identifier = bundle.bundleIdentifier
            if identifier == selfBundleIdentifier { return }

            let key = identifier ?? url.path
            guard found[key] == nil else { return }
            let name = fm.displayName(atPath: url.path)
            found[key] = AppItem(bundleIdentifier: identifier, url: url, name: name)
        }

        func walk(_ directory: String, depth: Int) {
            guard let entries = try? fm.contentsOfDirectory(atPath: directory) else { return }
            for entry in entries where !entry.hasPrefix(".") {
                let path = directory + "/" + entry
                var isDirectory: ObjCBool = false
                guard fm.fileExists(atPath: path, isDirectory: &isDirectory),
                      isDirectory.boolValue else { continue }
                if entry.hasSuffix(".app") {
                    consider(URL(fileURLWithPath: path, isDirectory: true))
                } else if depth == 0 {
                    // Recurse exactly one level (vendor folders inside /Applications).
                    walk(path, depth: 1)
                }
            }
        }

        for root in roots {
            walk(root, depth: 0)
        }

        return found.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}

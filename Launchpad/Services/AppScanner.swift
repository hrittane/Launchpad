import AppKit
import Foundation

/// Authoritative application discovery.
///
/// Spotlight (`NSMetadataQuery`) is only a change signal; this scanner uses
/// FileManager so apps are found even when an indexing gap exists, notably
/// under `/System`.
actor AppScanner {
    private let roots: [URL]
    private let ownBundleIdentifier: String?
    private let ownCanonicalPath: String

    /// Roots are injectable so discovery can be exercised with temporary
    /// folders in tests.
    init(roots: [URL]? = nil, ownBundle: Bundle = .main) {
        self.roots = roots ?? AppScanner.defaultRoots()
        self.ownBundleIdentifier = ownBundle.bundleIdentifier
        self.ownCanonicalPath = ownBundle.bundleURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
    }

    static func defaultRoots() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Utilities", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true)
        ]
        // Keep the advertised order but remove duplicates and missing folders.
        var seen = Set<String>()
        return candidates.filter { url in
            let path = url.standardizedFileURL.path
            guard !seen.contains(path),
                  FileManager.default.fileExists(atPath: path) else { return false }
            seen.insert(path)
            return true
        }
    }

    func scan() -> [AppItem] {
        var byID: [String: AppItem] = [:]

        for root in roots {
            for app in scan(root: root) {
                if let existing = byID[app.id] {
                    // Prefer a user-installed copy over a system copy when the
                    // same bundle identifier appears twice.
                    if existing.isSystemApp && !app.isSystemApp {
                        byID[app.id] = app
                    }
                } else {
                    byID[app.id] = app
                }
            }
        }

        return byID.values.sorted { lhs, rhs in
            let comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return lhs.id < rhs.id
        }
    }

    private func scan(root: URL) -> [AppItem] {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isHiddenKey]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var found: [AppItem] = []
        while let url = enumerator.nextObject() as? URL {
            let depth = enumerator.level
            if url.pathExtension.lowercased() == "app" {
                if depth <= 2, let item = makeItem(at: url) {
                    found.append(item)
                }
                enumerator.skipDescendants()
                continue
            }

            // Recursion limit: the root's children are depth 1, their children
            // are depth 2. Anything deeper is ignored.
            if depth >= 2 {
                enumerator.skipDescendants()
            }
        }
        return found
    }

    private func makeItem(at url: URL) -> AppItem? {
        let canonical = url.resolvingSymlinksInPath().standardizedFileURL
        guard canonical.path != ownCanonicalPath,
              let bundle = Bundle(url: canonical),
              let info = bundle.infoDictionary else { return nil }

        let bundleID = (info["CFBundleIdentifier"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        // Menu-bar helpers and background agents are not launchable apps.
        if bundleID == ownBundleIdentifier { return nil }
        if truthy(info["LSUIElement"]) || truthy(info["LSBackgroundOnly"]) { return nil }

        let displayName = nonEmpty(info["CFBundleDisplayName"] as? String)
            ?? nonEmpty(info["CFBundleName"] as? String)
            ?? canonical.deletingPathExtension().lastPathComponent

        let version = nonEmpty(info["CFBundleShortVersionString"] as? String)
            ?? nonEmpty(info["CFBundleVersion"] as? String)
        let isSystem = canonical.path.hasPrefix("/System/")

        return AppItem(
            name: displayName,
            url: canonical,
            isSystemApp: isSystem,
            bundleIdentifier: nonEmpty(bundleID),
            version: version
        )
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    private func truthy(_ value: Any?) -> Bool {
        switch value {
        case let value as Bool:
            return value
        case let value as NSNumber:
            return value.boolValue
        case let value as String:
            return ["1", "true", "yes"].contains(value.lowercased())
        default:
            return false
        }
    }
}

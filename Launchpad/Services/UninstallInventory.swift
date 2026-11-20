import Foundation

/// One removable piece of an app's on-disk footprint.
struct UninstallComponent: Identifiable, Hashable, Sendable {
    enum Kind: String, CaseIterable, Identifiable, Sendable {
        case applicationFiles
        case applicationSupport
        case caches
        case preferences
        case savedState
        case containers
        case other

        var id: String { rawValue }

        var title: String {
            switch self {
            case .applicationFiles: "Application Files"
            case .applicationSupport: "Application Support"
            case .caches: "Caches"
            case .preferences: "Preferences"
            case .savedState: "Saved State"
            case .containers: "Containers"
            case .other: "Other Data"
            }
        }
    }

    let kind: Kind
    let name: String
    let url: URL

    var id: URL { url }
}

/// Finds the files an app leaves in the usual per-user Library folders.
///
/// Only the app bundle itself and exact bundle-identifier matches (plus the
/// app's display name in Application Support and Caches, where installers
/// commonly use it) are returned. Identifiers with path separators are
/// rejected and every candidate must stay inside its known Library folder, so
/// a malformed bundle cannot point the trash flow at unrelated data.
enum UninstallScanner {
    static func components(
        for app: AppItem,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [UninstallComponent] {
        var components: [UninstallComponent] = []
        var seen = Set<URL>()

        func add(
            _ kind: UninstallComponent.Kind,
            name: String,
            url: URL,
            within root: URL? = nil
        ) {
            let standardized = url.standardizedFileURL
            if let root {
                let rootPath = root.standardizedFileURL.path
                guard standardized.path.hasPrefix(rootPath + "/") else { return }
            }
            guard !seen.contains(standardized),
                  FileManager.default.fileExists(atPath: standardized.path) else {
                return
            }
            seen.insert(standardized)
            components.append(
                UninstallComponent(kind: kind, name: name, url: standardized)
            )
        }

        add(.applicationFiles, name: app.name, url: app.url)

        guard let bundleIdentifier = app.bundleIdentifier,
              isSafeBundleIdentifier(bundleIdentifier) else {
            return components
        }
        let usesDisplayName = isSafeFileName(app.name) && app.name != bundleIdentifier

        let library = home.appendingPathComponent("Library", isDirectory: true)

        let support = library.appendingPathComponent("Application Support", isDirectory: true)
        add(
            .applicationSupport,
            name: bundleIdentifier,
            url: support.appendingPathComponent(bundleIdentifier, isDirectory: true),
            within: support
        )
        if usesDisplayName {
            add(
                .applicationSupport,
                name: app.name,
                url: support.appendingPathComponent(app.name, isDirectory: true),
                within: support
            )
        }

        let caches = library.appendingPathComponent("Caches", isDirectory: true)
        add(
            .caches,
            name: bundleIdentifier,
            url: caches.appendingPathComponent(bundleIdentifier, isDirectory: true),
            within: caches
        )
        if usesDisplayName {
            add(
                .caches,
                name: app.name,
                url: caches.appendingPathComponent(app.name, isDirectory: true),
                within: caches
            )
        }

        let preferences = library.appendingPathComponent("Preferences", isDirectory: true)
        add(
            .preferences,
            name: "\(bundleIdentifier).plist",
            url: preferences.appendingPathComponent("\(bundleIdentifier).plist"),
            within: preferences
        )

        let savedState = library.appendingPathComponent(
            "Saved Application State",
            isDirectory: true
        )
        add(
            .savedState,
            name: "\(bundleIdentifier).savedState",
            url: savedState.appendingPathComponent("\(bundleIdentifier).savedState"),
            within: savedState
        )

        let containers = library.appendingPathComponent("Containers", isDirectory: true)
        add(
            .containers,
            name: bundleIdentifier,
            url: containers.appendingPathComponent(bundleIdentifier, isDirectory: true),
            within: containers
        )
        let groupContainers = library.appendingPathComponent(
            "Group Containers",
            isDirectory: true
        )
        add(
            .containers,
            name: bundleIdentifier,
            url: groupContainers.appendingPathComponent(bundleIdentifier, isDirectory: true),
            within: groupContainers
        )

        let httpStorages = library.appendingPathComponent("HTTPStorages", isDirectory: true)
        add(
            .other,
            name: bundleIdentifier,
            url: httpStorages.appendingPathComponent(bundleIdentifier, isDirectory: true),
            within: httpStorages
        )
        let webKit = library.appendingPathComponent("WebKit", isDirectory: true)
        add(
            .other,
            name: bundleIdentifier,
            url: webKit.appendingPathComponent(bundleIdentifier, isDirectory: true),
            within: webKit
        )
        let applicationScripts = library.appendingPathComponent(
            "Application Scripts",
            isDirectory: true
        )
        add(
            .other,
            name: bundleIdentifier,
            url: applicationScripts.appendingPathComponent(bundleIdentifier, isDirectory: true),
            within: applicationScripts
        )
        let launchAgents = library.appendingPathComponent("LaunchAgents", isDirectory: true)
        add(
            .other,
            name: "\(bundleIdentifier).plist",
            url: launchAgents.appendingPathComponent("\(bundleIdentifier).plist"),
            within: launchAgents
        )
        if isSafeFileName(app.name) {
            let logs = library.appendingPathComponent("Logs", isDirectory: true)
            add(
                .other,
                name: app.name,
                url: logs.appendingPathComponent(app.name, isDirectory: true),
                within: logs
            )
        }

        return components
    }

    private static func isSafeBundleIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value != ".", value != ".." else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        return value.unicodeScalars.allSatisfy(allowed.contains)
    }

    private static func isSafeFileName(_ value: String) -> Bool {
        guard !value.isEmpty, value != ".", value != ".." else { return false }
        return !value.contains("/")
            && !value.contains("\\")
            && !value.contains("\0")
    }
}

/// Recursive, allocation-aware sizes for the confirmation list.
enum UninstallSize {
    private static let keys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .isSymbolicLinkKey,
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey,
        .fileSizeKey
    ]

    static func allocatedSize(of url: URL) -> Int64 {
        guard let root = try? url.resourceValues(forKeys: keys),
              root.isSymbolicLink != true else {
            return 0
        }
        if root.isDirectory != true {
            return byteCount(of: root)
        }

        var total: Int64 = 0
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return 0
        }
        for case let child as URL in enumerator {
            guard let values = try? child.resourceValues(forKeys: keys),
                  values.isSymbolicLink != true else {
                continue
            }
            total += byteCount(of: values)
        }
        return total
    }

    static func formatted(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "Zero KB" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: bytes)
    }

    private static func byteCount(of values: URLResourceValues) -> Int64 {
        let bytes = values.totalFileAllocatedSize
            ?? values.fileAllocatedSize
            ?? values.fileSize
            ?? 0
        return Int64(bytes)
    }
}

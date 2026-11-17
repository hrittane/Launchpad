import Foundation

/// A folder on the grid, holding the identifiers of its applications.
struct AppFolder: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var appIDs: [String]

    init(id: UUID = UUID(), name: String, appIDs: [String]) {
        self.id = id
        self.name = name
        self.appIDs = appIDs
    }
}

/// One slot on the grid: either an application or a folder.
///
/// The layout stores identifiers rather than `AppItem` values so it can be
/// persisted and reconciled when applications are installed or removed.
enum LauncherItem: Identifiable, Codable, Equatable, Sendable {
    case app(String)
    case folder(AppFolder)

    var id: String {
        switch self {
        case .app(let appID): return "app:" + appID
        case .folder(let folder): return "folder:" + folder.id.uuidString
        }
    }

    var folder: AppFolder? {
        if case .folder(let folder) = self { return folder }
        return nil
    }

    var isFolder: Bool {
        folder != nil
    }

    /// Applications this slot shows: one for an app, its children for a folder.
    var appIDs: [String] {
        switch self {
        case .app(let appID): return [appID]
        case .folder(let folder): return folder.appIDs
        }
    }
}

import Foundation

/// A user-created folder containing between 2 and 100 applications.
struct FolderItem: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var apps: [AppItem]

    static let maximumAppCount = 100
    static let defaultName = String(localized: "Untitled Folder", comment: "Default name for a newly created folder")

    init(id: UUID = UUID(), name: String = FolderItem.defaultName, apps: [AppItem] = []) {
        self.id = id
        self.name = name
        self.apps = apps
    }

    /// A folder needs at least two apps; otherwise it is dissolved.
    var isViable: Bool { apps.count >= 2 }

    mutating func add(_ app: AppItem) {
        guard apps.count < Self.maximumAppCount,
              !apps.contains(where: { $0.id == app.id }) else { return }
        apps.append(app)
    }

    mutating func remove(appID: String) {
        apps.removeAll { $0.id == appID }
    }
}

/// Any item that can occupy a grid slot.
enum LaunchpadEntry: Identifiable, Codable, Hashable, Sendable {
    case app(AppItem)
    case folder(FolderItem)

    var id: String {
        switch self {
        case .app(let app): return "app:\(app.id)"
        case .folder(let folder): return "folder:\(folder.id.uuidString)"
        }
    }

    var app: AppItem? {
        if case .app(let app) = self { return app }
        return nil
    }

    var folder: FolderItem? {
        if case .folder(let folder) = self { return folder }
        return nil
    }

    var displayName: String {
        switch self {
        case .app(let app): return app.name
        case .folder(let folder): return folder.name
        }
    }

    var isFolder: Bool { folder != nil }

    // A readable JSON shape makes persisted layouts easy to inspect and migrate.
    private enum CodingKeys: String, CodingKey {
        case type, app, folder
    }

    private enum Kind: String, Codable {
        case app, folder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .app:
            self = .app(try container.decode(AppItem.self, forKey: .app))
        case .folder:
            self = .folder(try container.decode(FolderItem.self, forKey: .folder))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .app(let app):
            try container.encode(Kind.app, forKey: .type)
            try container.encode(app, forKey: .app)
        case .folder(let folder):
            try container.encode(Kind.folder, forKey: .type)
            try container.encode(folder, forKey: .folder)
        }
    }
}

/// One page is a row-ordered list of entries.
typealias PageLayout = [LaunchpadEntry]

/// The on-disk representation of the user's custom arrangement.
struct LayoutDocument: Codable, Equatable {
    static let currentVersion = 1

    var version: Int
    var pages: [PageLayout]
    var updatedAt: Date

    init(pages: [PageLayout], updatedAt: Date = Date()) {
        self.version = Self.currentVersion
        self.pages = pages
        self.updatedAt = updatedAt
    }
}

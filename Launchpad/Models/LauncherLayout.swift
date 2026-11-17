import Foundation

/// The ordered grid contents, persisted as JSON.
///
/// Everything here is pure: the model owns saving and the catalog, so these
/// operations can be unit-tested without a filesystem.
struct LauncherLayout: Codable, Equatable, Sendable {
    var items: [LauncherItem] = []

    // MARK: - Lookup

    func index(of itemID: String) -> Int? {
        items.firstIndex { $0.id == itemID }
    }

    func index(ofFolder folderID: UUID) -> Int? {
        items.firstIndex { $0.folder?.id == folderID }
    }

    func folder(withID folderID: UUID) -> AppFolder? {
        items.compactMap(\.folder).first { $0.id == folderID }
    }

    /// The folder that contains `appID`, if any.
    func folder(containing appID: String) -> AppFolder? {
        items.compactMap(\.folder).first { $0.appIDs.contains(appID) }
    }

    func contains(appID: String) -> Bool {
        items.contains { $0.appIDs.contains(appID) }
    }

    var representedAppIDs: Set<String> {
        Set(items.flatMap(\.appIDs))
    }

    // MARK: - Reconciliation

    /// Merges the stored layout with what is actually installed: missing apps
    /// are dropped, one-app folders collapse back to the app, and newly
    /// installed apps are appended in catalog order.
    mutating func reconcile(with apps: [AppItem]) {
        let installed = Set(apps.map(\.id))
        var seen = Set<String>()
        var result: [LauncherItem] = []

        for item in items {
            switch item {
            case .app(let appID):
                guard installed.contains(appID), seen.insert(appID).inserted else { continue }
                result.append(.app(appID))

            case .folder(var folder):
                var children: [String] = []
                for child in folder.appIDs
                    where installed.contains(child) && seen.insert(child).inserted {
                    children.append(child)
                }
                folder.appIDs = children
                switch children.count {
                case 0:
                    continue
                case 1:
                    result.append(.app(children[0]))
                default:
                    result.append(.folder(folder))
                }
            }
        }

        for app in apps where !seen.contains(app.id) {
            result.append(.app(app.id))
            seen.insert(app.id)
        }

        items = result
    }

    // MARK: - Editing

    /// Moves an item so that it ends up at `slot` (an index in the pre-move
    /// array). Returns whether anything changed.
    @discardableResult
    mutating func move(itemID: String, toSlot slot: Int) -> Bool {
        guard let from = index(of: itemID), !items.isEmpty else { return false }
        let target = min(max(slot, 0), items.count - 1)
        guard from != target else { return false }
        let item = items.remove(at: from)
        items.insert(item, at: target)
        return true
    }

    /// Drops an app onto another app or a folder.
    ///
    /// Returns the identifier of the folder that was touched or created, so the
    /// caller can animate towards it.
    @discardableResult
    mutating func drop(
        draggedID: String,
        onto targetID: String,
        newFolderName: String
    ) -> UUID? {
        guard draggedID != targetID,
              let from = index(of: draggedID),
              let to = index(of: targetID) else { return nil }
        guard case .app(let draggedApp) = items[from] else { return nil }

        switch items[to] {
        case .folder(var folder):
            guard !folder.appIDs.contains(draggedApp) else { return nil }
            folder.appIDs.append(draggedApp)
            items[to] = .folder(folder)
            items.remove(at: from)
            return folder.id

        case .app(let targetApp):
            guard targetApp != draggedApp else { return nil }
            let folder = AppFolder(name: newFolderName, appIDs: [targetApp, draggedApp])
            items[to] = .folder(folder)
            items.remove(at: from)
            return folder.id
        }
    }

    /// Removes a top-level item (an app or a whole folder).
    @discardableResult
    mutating func remove(itemID: String) -> Bool {
        guard let index = index(of: itemID) else { return false }
        items.remove(at: index)
        return true
    }

    /// Removes an app from the grid or from whichever folder holds it. A folder
    /// that loses its last two apps collapses to the surviving app.
    @discardableResult
    mutating func remove(appID: String) -> Bool {
        if let index = items.firstIndex(where: { !$0.isFolder && $0.appIDs == [appID] }) {
            items.remove(at: index)
            return true
        }

        for index in items.indices {
            guard case .folder(var folder) = items[index],
                  let child = folder.appIDs.firstIndex(of: appID) else { continue }

            folder.appIDs.remove(at: child)
            switch folder.appIDs.count {
            case 0:
                items.remove(at: index)
            case 1:
                items[index] = .app(folder.appIDs[0])
            default:
                items[index] = .folder(folder)
            }
            return true
        }

        return false
    }

    mutating func renameFolder(_ folderID: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = index(ofFolder: folderID),
              var folder = folder(withID: folderID) else { return }
        folder.name = String(trimmed.prefix(40))
        items[index] = .folder(folder)
    }

    /// Removes an app from a folder (used by editing inside a folder). The app
    /// is re-inserted at `slot` when it is given one.
    @discardableResult
    mutating func moveAppOutOfFolder(appID: String, toSlot slot: Int?) -> Bool {
        guard let folderIndex = items.firstIndex(where: {
            $0.folder?.appIDs.contains(appID) == true
        }) else { return false }
        guard case .folder(var folder) = items[folderIndex],
              let childIndex = folder.appIDs.firstIndex(of: appID) else { return false }

        let appID = folder.appIDs.remove(at: childIndex)
        switch folder.appIDs.count {
        case 0:
            items.remove(at: folderIndex)
        case 1:
            items[folderIndex] = .app(folder.appIDs[0])
        default:
            items[folderIndex] = .folder(folder)
        }

        if let slot {
            let clamped = min(max(slot, 0), items.count)
            items.insert(.app(appID), at: clamped)
        }
        return true
    }
}

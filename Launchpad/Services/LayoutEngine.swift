import Foundation

/// The result of removing an app from a folder.
enum FolderUpdate: Equatable, Sendable {
    case folder(FolderItem)
    case dissolved([AppItem])
    case empty
}

/// Pure layout and pagination rules. Keeping these functions free of AppKit
/// makes them straightforward to unit test and safe to call from any actor.
enum LayoutEngine {
    // MARK: Pagination math

    static func pageCount(forItemCount count: Int, capacity: Int) -> Int {
        guard count > 0 else { return 1 }
        let capacity = max(1, capacity)
        return Int(ceil(Double(count) / Double(capacity)))
    }

    static func pageIndex(forFlatIndex index: Int, capacity: Int) -> Int {
        guard capacity > 0, index >= 0 else { return 0 }
        return index / capacity
    }

    static func flatIndex(forPage page: Int, slot: Int, capacity: Int) -> Int {
        max(0, page * max(1, capacity) + max(0, slot))
    }

    static func paginate(_ entries: [LaunchpadEntry], capacity: Int) -> [PageLayout] {
        let capacity = max(1, capacity)
        guard !entries.isEmpty else { return [[]] }
        var pages: [PageLayout] = []
        var index = 0
        while index < entries.count {
            let end = min(index + capacity, entries.count)
            pages.append(Array(entries[index..<end]))
            index = end
        }
        return pages
    }

    static func flatten(_ pages: [PageLayout]) -> [LaunchpadEntry] {
        pages.flatMap { $0 }
    }

    /// Every installed app represented in the layout, including folder
    /// contents, deduplicated by app id and sorted for stable presentation.
    static func allApps(in pages: [PageLayout]) -> [AppItem] {
        var seen = Set<String>()
        var apps: [AppItem] = []
        for entry in flatten(pages) {
            switch entry {
            case .app(let app):
                if seen.insert(app.id).inserted { apps.append(app) }
            case .folder(let folder):
                for app in folder.apps where seen.insert(app.id).inserted {
                    apps.append(app)
                }
            }
        }
        return apps
    }

    // MARK: Normalization

    /// Reconciles a persisted layout with the current scan result.
    ///
    /// - Existing order and page breaks are preserved.
    /// - Removed apps disappear; stale folder children are dropped.
    /// - Folders with fewer than two surviving apps dissolve and release their
    ///   apps onto the grid.
    /// - New apps are appended alphabetically at the end of the last page.
    /// - Over-capacity pages are repaginated without losing order.
    static func normalize(
        pages: [PageLayout],
        discovered: [AppItem],
        capacity: Int
    ) -> [PageLayout] {
        let capacity = max(1, capacity)
        var discoveredByID: [String: AppItem] = [:]
        for app in discovered where discoveredByID[app.id] == nil {
            discoveredByID[app.id] = app
        }

        var seenApps = Set<String>()
        var seenFolders = Set<UUID>()
        var released: [AppItem] = []
        var normalized: [PageLayout] = []

        for page in pages {
            var newPage: PageLayout = []
            for entry in page {
                switch entry {
                case .app(let stored):
                    guard let app = discoveredByID[stored.id],
                          seenApps.insert(app.id).inserted else { continue }
                    newPage.append(.app(app))
                case .folder(let stored):
                    guard seenFolders.insert(stored.id).inserted else { continue }
                    // Do not mark folder children as seen until the folder is
                    // known to survive. A dissolved folder's app must be free
                    // to reappear as a top-level entry.
                    var folderIDs = Set<String>()
                    var survivingApps: [AppItem] = []
                    for storedApp in stored.apps {
                        guard let app = discoveredByID[storedApp.id],
                              !seenApps.contains(app.id),
                              folderIDs.insert(app.id).inserted else { continue }
                        survivingApps.append(app)
                    }
                    if survivingApps.count >= 2 {
                        let keptApps = Array(survivingApps.prefix(FolderItem.maximumAppCount))
                        keptApps.forEach { seenApps.insert($0.id) }
                        newPage.append(.folder(FolderItem(
                            id: stored.id,
                            name: stored.name,
                            apps: keptApps
                        )))
                    } else {
                        released.append(contentsOf: survivingApps)
                    }
                }
            }
            normalized.append(newPage)
        }

        // Apps released from dissolved folders keep their relative order and
        // are added before genuinely new apps.
        let newApps = discovered
            .filter { !seenApps.contains($0.id) }
            .sorted { lhs, rhs in
                let comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                if comparison != .orderedSame { return comparison == .orderedAscending }
                return lhs.id < rhs.id
            }
        for app in released + newApps {
            guard seenApps.insert(app.id).inserted else { continue }
            appendApp(app, to: &normalized, capacity: capacity)
        }

        normalized.removeAll { $0.isEmpty }
        if normalized.isEmpty { normalized = [[]] }

        if normalized.contains(where: { $0.count > capacity }) {
            return paginate(flatten(normalized), capacity: capacity)
        }
        return normalized
    }

    /// Appends an app to the last page, creating a page when it is full.
    static func appendApp(_ app: AppItem, to pages: inout [PageLayout], capacity: Int) {
        let capacity = max(1, capacity)
        if pages.isEmpty { pages = [[]] }
        if pages[pages.count - 1].count >= capacity {
            pages.append([.app(app)])
        } else {
            pages[pages.count - 1].append(.app(app))
        }
    }

    // MARK: Mutation helpers

    @discardableResult
    static func remove(entryID: String, from pages: inout [PageLayout]) -> LaunchpadEntry? {
        for pageIndex in pages.indices {
            if let index = pages[pageIndex].firstIndex(where: { $0.id == entryID }) {
                return pages[pageIndex].remove(at: index)
            }
        }
        return nil
    }

    static func insert(
        _ entry: LaunchpadEntry,
        at pageIndex: Int,
        index: Int,
        in pages: inout [PageLayout],
        capacity: Int
    ) {
        let capacity = max(1, capacity)
        if pages.isEmpty { pages = [[]] }
        let page = min(max(pageIndex, 0), pages.count)
        if page == pages.count {
            pages.append([])
        }
        let slot = min(max(index, 0), min(pages[page].count, capacity))
        pages[page].insert(entry, at: slot)
        // Overflow becomes a new page rather than exceeding capacity.
        if pages[page].count > capacity {
            let overflow = Array(pages[page][capacity...])
            pages[page].removeSubrange(capacity...)
            pages.insert(overflow, at: page + 1)
        }
        pages.removeAll { $0.isEmpty }
        if pages.isEmpty { pages = [[]] }
    }

    /// Removes an app wherever it is and returns the entry that was removed.
    /// When the app was inside a folder, the folder is dissolved if fewer than
    /// two apps remain; the surviving app is returned as a released entry.
    @discardableResult
    static func removeApp(appID: String, from pages: inout [PageLayout]) -> [LaunchpadEntry] {
        for pageIndex in pages.indices {
            if let index = pages[pageIndex].firstIndex(where: { entry in
                if let app = entry.app { return app.id == appID }
                return false
            }) {
                if let removed = pages[pageIndex].remove(at: index).app {
                    return [.app(removed)]
                }
                return []
            }
        }
        for pageIndex in pages.indices {
            for entryIndex in pages[pageIndex].indices {
                guard case .folder(var folder) = pages[pageIndex][entryIndex],
                      folder.apps.contains(where: { $0.id == appID }) else { continue }
                folder.remove(appID: appID)
                switch update(for: folder) {
                case .folder(let updated):
                    pages[pageIndex][entryIndex] = .folder(updated)
                    return []
                case .dissolved(let released):
                    pages[pageIndex].remove(at: entryIndex)
                    return released.map(LaunchpadEntry.app)
                case .empty:
                    pages[pageIndex].remove(at: entryIndex)
                    return []
                }
            }
        }
        return []
    }

    /// Dissolves a folder and returns its apps as top-level entries.
    @discardableResult
    static func dissolveFolder(folderID: UUID, in pages: inout [PageLayout]) -> [LaunchpadEntry] {
        for pageIndex in pages.indices {
            if let index = pages[pageIndex].firstIndex(where: { $0.folder?.id == folderID }) {
                guard let folder = pages[pageIndex].remove(at: index).folder else { return [] }
                return folder.apps.map(LaunchpadEntry.app)
            }
        }
        return []
    }

    // MARK: Folder rules

    static func makeFolder(name: String = FolderItem.defaultName, apps: [AppItem]) -> FolderItem? {
        var unique: [AppItem] = []
        var seen = Set<String>()
        for app in apps where seen.insert(app.id).inserted {
            unique.append(app)
            if unique.count == FolderItem.maximumAppCount { break }
        }
        guard unique.count >= 2 else { return nil }
        return FolderItem(name: name, apps: unique)
    }

    static func folder(_ folder: FolderItem, adding app: AppItem) -> FolderItem {
        var updated = folder
        updated.add(app)
        return updated
    }

    /// Result of removing one app from a folder.
    static func update(for folder: FolderItem) -> FolderUpdate {
        if folder.apps.isEmpty { return .empty }
        if folder.apps.count == 1 { return .dissolved(folder.apps) }
        return .folder(folder)
    }

    /// Removes an app from a folder according to the dissolve rules.
    static func folder(_ folder: FolderItem, removingAppID appID: String) -> FolderUpdate {
        var updated = folder
        updated.remove(appID: appID)
        return update(for: updated)
    }
}

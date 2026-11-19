import Foundation

/// The ordered grid contents, persisted as JSON.
///
/// Everything here is pure: the model owns saving and the catalog, so these
/// operations can be unit-tested without a filesystem.
///
/// The grid is stored page by page rather than as one flat list. Pages hold at
/// most `pageCapacity` items and stay packed towards the top-left, but they may
/// be sparse: dragging an icon past the last page creates a page that holds only
/// that icon, so a new page does not need thirty-five icons to exist.
struct LauncherLayout: Codable, Equatable, Sendable {
    /// Slots per page for the default 7 × 5 grid.
    static let defaultPageCapacity = 35

    /// Slots per page for the current grid. The settings can change it, so it
    /// is stored with the layout and used by every page operation.
    private(set) var capacity: Int

    /// One array per page, in display order. Always contains at least one page.
    private(set) var pages: [[LauncherItem]]

    init(pages: [[LauncherItem]] = [[]], capacity: Int = Self.defaultPageCapacity) {
        self.capacity = max(1, capacity)
        self.pages = pages.isEmpty ? [[]] : pages
        normalize()
    }

    init(items: [LauncherItem], capacity: Int = Self.defaultPageCapacity) {
        self.init(pages: Self.packing(items, capacity: capacity), capacity: capacity)
    }

    /// Repacks every item into pages of `newCapacity`. Sparse pages are
    /// compacted, because a page can no longer be laid out with the old width.
    mutating func setCapacity(_ newCapacity: Int) {
        let next = max(1, newCapacity)
        guard next != capacity else { return }
        capacity = next
        pages = Self.packing(items, capacity: next)
    }

    /// Flat list of every item, in grid order. Kept for lookups and for the
    /// tests that do not care how the items are split across pages.
    var items: [LauncherItem] { pages.flatMap { $0 } }

    var pageCount: Int { pages.count }

    func items(onPage page: Int) -> [LauncherItem] {
        guard pages.indices.contains(page) else { return [] }
        return pages[page]
    }

    func item(onPage page: Int, offset: Int) -> LauncherItem? {
        guard pages.indices.contains(page), pages[page].indices.contains(offset) else {
            return nil
        }
        return pages[page][offset]
    }

    // MARK: - Lookup

    func index(of itemID: String) -> Int? {
        var base = 0
        for page in pages {
            if let index = page.firstIndex(where: { $0.id == itemID }) {
                return base + index
            }
            base += page.count
        }
        return nil
    }

    func index(ofFolder folderID: UUID) -> Int? {
        var base = 0
        for page in pages {
            if let index = page.firstIndex(where: { $0.folder?.id == folderID }) {
                return base + index
            }
            base += page.count
        }
        return nil
    }

    func folder(withID folderID: UUID) -> AppFolder? {
        for page in pages {
            for item in page {
                if item.folder?.id == folderID { return item.folder }
            }
        }
        return nil
    }

    /// The folder that contains `appID`, if any.
    func folder(containing appID: String) -> AppFolder? {
        for page in pages {
            for item in page {
                if item.folder?.appIDs.contains(appID) == true { return item.folder }
            }
        }
        return nil
    }

    func contains(appID: String) -> Bool {
        pages.contains { page in page.contains { $0.appIDs.contains(appID) } }
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
        var rebuilt: [[LauncherItem]] = []

        for page in pages {
            var result: [LauncherItem] = []

            for item in page {
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

            // Pages compact when apps disappear, and a page that lost every
            // item is removed.
            if !result.isEmpty { rebuilt.append(result) }
        }

        for app in apps where !seen.contains(app.id) {
            Self.appendToLastPage(.app(app.id), in: &rebuilt, capacity: capacity)
            seen.insert(app.id)
        }

        pages = rebuilt.isEmpty ? [[]] : rebuilt
    }

    // MARK: - Editing

    /// Moves an item so that it ends up at `slot` in the flat list. Used by the
    /// tests and by callers that do not care about page boundaries; the UI uses
    /// `move(itemID:toPage:offset:)` so sparse pages survive.
    @discardableResult
    mutating func move(itemID: String, toSlot slot: Int) -> Bool {
        guard let from = index(of: itemID), !items.isEmpty else { return false }
        var flat = items
        let target = min(max(slot, 0), flat.count - 1)
        guard from != target else { return false }
        let item = flat.remove(at: from)
        flat.insert(item, at: target)
        pages = Self.packing(flat, capacity: capacity)
        return true
    }

    /// Moves an item to the slot under the pointer on `page`. `offset` is the
    /// in-page slot index; it is clamped to the page so a sparse page packs its
    /// items and an empty page accepts its first item.
    @discardableResult
    mutating func move(itemID: String, toPage page: Int, offset: Int) -> Bool {
        guard let source = locate(itemID: itemID) else { return false }
        let target = min(max(page, 0), pages.count - 1)

        if source.page == target {
            let destination = min(max(offset, 0), pages[target].count - 1)
            guard destination != source.index else { return false }
            let item = pages[target].remove(at: source.index)
            pages[target].insert(item, at: destination)
            return true
        }

        let item = pages[source.page].remove(at: source.index)
        var destinationPage = target
        if pages[source.page].isEmpty, pages.count > 1 {
            pages.remove(at: source.page)
            if source.page < destinationPage { destinationPage -= 1 }
        }

        let insertion = min(max(offset, 0), pages[destinationPage].count)
        pages[destinationPage].insert(item, at: insertion)
        splitOverflowPages()
        return true
    }

    /// Inserts a brand-new item (an app lifted out of a folder) on `page`.
    @discardableResult
    mutating func insert(_ item: LauncherItem, onPage page: Int, offset: Int) -> Bool {
        guard !pages.isEmpty else {
            pages = [[item]]
            return true
        }
        let target = min(max(page, 0), pages.count - 1)
        let insertion = min(max(offset, 0), pages[target].count)
        pages[target].insert(item, at: insertion)
        splitOverflowPages()
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
              let dragged = locate(itemID: draggedID),
              let target = locate(itemID: targetID) else { return nil }
        guard case .app(let draggedApp) = pages[dragged.page][dragged.index] else { return nil }

        let folderID: UUID
        switch pages[target.page][target.index] {
        case .folder(var folder):
            guard !folder.appIDs.contains(draggedApp) else { return nil }
            folder.appIDs.append(draggedApp)
            pages[target.page][target.index] = .folder(folder)
            folderID = folder.id

        case .app(let targetApp):
            guard targetApp != draggedApp else { return nil }
            let folder = AppFolder(name: newFolderName, appIDs: [targetApp, draggedApp])
            pages[target.page][target.index] = .folder(folder)
            folderID = folder.id
        }

        removeItem(at: dragged)
        return folderID
    }

    /// Removes a top-level item (an app or a whole folder).
    @discardableResult
    mutating func remove(itemID: String) -> Bool {
        guard let location = locate(itemID: itemID) else { return false }
        removeItem(at: location)
        return true
    }

    /// Removes an app from the grid or from whichever folder holds it. A folder
    /// that loses its last two apps collapses to the surviving app.
    @discardableResult
    mutating func remove(appID: String) -> Bool {
        for pageIndex in pages.indices {
            if let index = pages[pageIndex].firstIndex(where: {
                !$0.isFolder && $0.appIDs == [appID]
            }) {
                pages[pageIndex].remove(at: index)
                removePageIfEmpty(pageIndex)
                return true
            }

            for index in pages[pageIndex].indices {
                guard case .folder(var folder) = pages[pageIndex][index],
                      let child = folder.appIDs.firstIndex(of: appID) else { continue }

                folder.appIDs.remove(at: child)
                switch folder.appIDs.count {
                case 0:
                    pages[pageIndex].remove(at: index)
                    removePageIfEmpty(pageIndex)
                case 1:
                    pages[pageIndex][index] = .app(folder.appIDs[0])
                default:
                    pages[pageIndex][index] = .folder(folder)
                }
                return true
            }
        }

        return false
    }

    mutating func renameFolder(_ folderID: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let location = locateFolder(folderID),
              var folder = folder(withID: folderID) else { return }
        folder.name = String(trimmed.prefix(40))
        pages[location.page][location.index] = .folder(folder)
    }

    /// Reorders an app inside its folder. `slot` is an index into the folder's
    /// current child list, matching the preview the panel draws while dragging.
    @discardableResult
    mutating func moveApp(inFolder folderID: UUID, appID: String, toSlot slot: Int) -> Bool {
        guard let location = locateFolder(folderID),
              case .folder(var folder) = pages[location.page][location.index],
              let from = folder.appIDs.firstIndex(of: appID),
              folder.appIDs.count > 1 else { return false }

        let target = min(max(slot, 0), folder.appIDs.count - 1)
        guard target != from else { return false }

        let child = folder.appIDs.remove(at: from)
        folder.appIDs.insert(child, at: target)
        pages[location.page][location.index] = .folder(folder)
        return true
    }

    /// Removes an app from a folder (used by editing inside a folder). The app
    /// is re-inserted at `slot` when it is given one.
    @discardableResult
    mutating func moveAppOutOfFolder(appID: String, toSlot slot: Int?) -> Bool {
        guard let lifted = layoutLiftingAppOutOfFolder(appID) else { return false }
        var flat = lifted.items
        if let slot {
            let clamped = min(max(slot, 0), flat.count)
            flat.insert(.app(appID), at: clamped)
        }
        pages = Self.packing(flat, capacity: capacity)
        return true
    }

    /// Page-aware counterpart of `moveAppOutOfFolder(appID:toSlot:)`.
    @discardableResult
    mutating func moveAppOutOfFolder(appID: String, toPage page: Int, offset: Int) -> Bool {
        guard var lifted = layoutLiftingAppOutOfFolder(appID) else { return false }
        lifted.insert(.app(appID), onPage: page, offset: offset)
        pages = lifted.pages
        return true
    }

    /// The grid with `appID` lifted out of its folder.
    ///
    /// The folder collapses to its survivor when only one app would remain, or
    /// disappears when empty — exactly as it will once the drop lands, so the
    /// live drag preview and the committed layout agree on every slot.
    ///
    /// - Returns: `nil` when `appID` is not inside a folder.
    func liftingAppOutOfFolder(_ appID: String) -> [LauncherItem]? {
        layoutLiftingAppOutOfFolder(appID)?.items
    }

    /// The full page-aware grid with `appID` lifted out of its folder. The live
    /// drop preview layers the app back in without writing anything.
    func layoutLiftingAppOutOfFolder(_ appID: String) -> LauncherLayout? {
        guard let location = locateFolder(containing: appID),
              case .folder(var folder) = pages[location.page][location.index],
              let child = folder.appIDs.firstIndex(of: appID) else { return nil }

        var lifted = self
        folder.appIDs.remove(at: child)
        switch folder.appIDs.count {
        case 0:
            lifted.pages[location.page].remove(at: location.index)
            lifted.removePageIfEmpty(location.page)
        case 1:
            lifted.pages[location.page][location.index] = .app(folder.appIDs[0])
        default:
            lifted.pages[location.page][location.index] = .folder(folder)
        }
        return lifted
    }

    /// Drops an app that is being lifted out of its folder onto another app or
    /// folder: a folder is created, or the app joins the existing one.
    @discardableResult
    mutating func dropAppOutOfFolder(
        appID: String,
        onto targetID: String,
        newFolderName: String
    ) -> UUID? {
        guard var lifted = layoutLiftingAppOutOfFolder(appID),
              let target = lifted.locate(itemID: targetID) else { return nil }

        let folderID: UUID
        switch lifted.pages[target.page][target.index] {
        case .folder(var folder):
            guard !folder.appIDs.contains(appID) else { return nil }
            folder.appIDs.append(appID)
            lifted.pages[target.page][target.index] = .folder(folder)
            folderID = folder.id

        case .app(let targetApp):
            guard targetApp != appID else { return nil }
            let folder = AppFolder(name: newFolderName, appIDs: [targetApp, appID])
            lifted.pages[target.page][target.index] = .folder(folder)
            folderID = folder.id
        }

        pages = lifted.pages
        return folderID
    }

    // MARK: - Pages

    /// Adds an empty page at the end. The drag preview calls this when the
    /// pointer waits at the right edge of the last page; the page is only kept
    /// once something is dropped on it.
    @discardableResult
    mutating func appendEmptyPage() -> Bool {
        guard pages.last?.isEmpty != true else { return false }
        pages.append([])
        return true
    }

    /// Removes pages that a cancelled drag created and never filled.
    @discardableResult
    mutating func trimEmptyPages() -> Bool {
        var changed = false
        while pages.count > 1, pages.last?.isEmpty == true {
            pages.removeLast()
            changed = true
        }
        return changed
    }

    // MARK: - Private

    private func locate(itemID: String) -> (page: Int, index: Int)? {
        for (page, items) in pages.enumerated() {
            if let index = items.firstIndex(where: { $0.id == itemID }) {
                return (page, index)
            }
        }
        return nil
    }

    private func locateFolder(_ folderID: UUID) -> (page: Int, index: Int)? {
        for (page, items) in pages.enumerated() {
            if let index = items.firstIndex(where: { $0.folder?.id == folderID }) {
                return (page, index)
            }
        }
        return nil
    }

    private func locateFolder(containing appID: String) -> (page: Int, index: Int)? {
        for (page, items) in pages.enumerated() {
            if let index = items.firstIndex(where: { $0.folder?.appIDs.contains(appID) == true }) {
                return (page, index)
            }
        }
        return nil
    }

    private mutating func removeItem(at location: (page: Int, index: Int)) {
        pages[location.page].remove(at: location.index)
        removePageIfEmpty(location.page)
    }

    private mutating func removePageIfEmpty(_ page: Int) {
        guard pages.indices.contains(page), pages[page].isEmpty, pages.count > 1 else { return }
        pages.remove(at: page)
    }

    /// Moves the overflow of any page that briefly holds more than a page's
    /// worth of icons onto the next page, creating a page at the end if needed.
    private mutating func splitOverflowPages() {
        var page = 0
        while page < pages.count {
            guard pages[page].count > capacity else {
                page += 1
                continue
            }

            let overflow = Array(pages[page][capacity...])
            pages[page].removeSubrange(capacity...)
            if page + 1 < pages.count {
                pages[page + 1].insert(contentsOf: overflow, at: 0)
            } else {
                pages.append(overflow)
            }
            page += 1
        }
    }

    /// Repairs decoded layouts and empty pages: every page is full except for
    /// the last one, and the layout always has one page to draw.
    private mutating func normalize() {
        var split: [[LauncherItem]] = []
        for page in pages {
            guard !page.isEmpty else { continue }
            var rest = page
            while rest.count > capacity {
                split.append(Array(rest.prefix(capacity)))
                rest.removeFirst(capacity)
            }
            split.append(rest)
        }
        pages = split.isEmpty ? [[]] : split
    }

    private static func packing(_ items: [LauncherItem], capacity: Int) -> [[LauncherItem]] {
        guard !items.isEmpty else { return [[]] }
        let capacity = max(1, capacity)
        var pages: [[LauncherItem]] = []
        var start = 0
        while start < items.count {
            let end = min(start + capacity, items.count)
            pages.append(Array(items[start..<end]))
            start = end
        }
        return pages
    }

    private static func appendToLastPage(
        _ item: LauncherItem,
        in pages: inout [[LauncherItem]],
        capacity: Int
    ) {
        guard !pages.isEmpty else {
            pages = [[item]]
            return
        }
        if pages[pages.count - 1].count >= capacity {
            pages.append([item])
        } else {
            pages[pages.count - 1].append(item)
        }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case pages
        case items
        case capacity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let capacity = try container.decodeIfPresent(Int.self, forKey: .capacity)
            ?? Self.defaultPageCapacity
        if let pages = try container.decodeIfPresent([[LauncherItem]].self, forKey: .pages) {
            self.init(pages: pages, capacity: capacity)
        } else {
            // Layouts saved before pages were explicit stored one flat list.
            let items = try container.decodeIfPresent([LauncherItem].self, forKey: .items) ?? []
            self.init(items: items, capacity: capacity)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(capacity, forKey: .capacity)
        try container.encode(pages, forKey: .pages)
    }
}

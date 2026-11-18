import Foundation
import Observation

/// Shared, observable application state.
@MainActor
@Observable
final class AppModel {
    let catalog: AppCatalog

    private let store: LayoutStore

    /// Grid contents, reconciled against `catalog.apps`.
    private(set) var layout = LauncherLayout()

    /// Catalog lookup, rebuilt whenever the scan finishes.
    private(set) var appsByID: [String: AppItem] = [:]

    /// Incremented every time the panel is presented, so the UI can replay its
    /// entrance animation even though the hosting view is long-lived.
    private(set) var showCount = 0

    /// Zero-based index of the visible grid page.
    private(set) var currentPage = 0

    /// Number of grid pages for the current layout. Kept in sync by the model
    /// so the AppKit scroll handler can page without knowing the layout.
    var pageCount = 1

    // MARK: Editing

    private(set) var isEditing = false

    /// Identifier of the icon currently being dragged by the UI.
    var draggingID: String?

    // MARK: Folders

    private(set) var openFolderID: UUID?

    // MARK: Search

    var searchQuery = ""
    var searchSelection = 0

    /// Bumped when the search field should take focus.
    private(set) var searchFocusRequest = 0

    var pageCapacity: Int {
        LaunchpadMetrics.defaultColumns * LaunchpadMetrics.defaultRows
    }

    init(catalog: AppCatalog = AppCatalog(), store: LayoutStore = .shared) {
        self.catalog = catalog
        self.store = store
        layout = store.load() ?? LauncherLayout()
    }

    var items: [LauncherItem] { layout.items }

    var openFolder: AppFolder? {
        openFolderID.flatMap(layout.folder(withID:))
    }

    var columns: Int { LaunchpadMetrics.defaultColumns }
    var rows: Int { LaunchpadMetrics.defaultRows }

    // MARK: - Catalog

    /// Merges the stored layout with the installed apps. Called when the scan
    /// finishes and after an uninstall.
    func reconcile() {
        appsByID = Dictionary(uniqueKeysWithValues: catalog.apps.map { ($0.id, $0) })
        var next = layout
        next.reconcile(with: catalog.apps)
        if next != layout {
            layout = next
            store.save(layout)
        }
        refreshPageCount()
        if let openFolderID, layout.folder(withID: openFolderID) == nil {
            self.openFolderID = nil
        }
    }

    func app(_ appID: String) -> AppItem? {
        appsByID[appID]
    }

    func apps(in folder: AppFolder) -> [AppItem] {
        folder.appIDs.compactMap { appsByID[$0] }
    }

    func item(withID itemID: String) -> LauncherItem? {
        guard let index = layout.index(of: itemID) else { return nil }
        return layout.items[index]
    }

    func item(atSlot slot: Int) -> LauncherItem? {
        guard slot >= 0, slot < layout.items.count else { return nil }
        return layout.items[slot]
    }

    func items(onPage page: Int) -> [LauncherItem] {
        let start = page * pageCapacity
        guard start < layout.items.count else { return [] }
        let end = min(start + pageCapacity, layout.items.count)
        return Array(layout.items[start..<end])
    }

    func canRemove(appID: String) -> Bool {
        appsByID[appID]?.isRemovable == true
    }

    // MARK: - Paging

    func notePresented() {
        showCount += 1
        endEditing()
        closeFolder()
        clearSearch()
    }

    /// Moves by `delta` pages, clamped to the available range.
    func stepPage(by delta: Int) {
        goToPage(currentPage + delta)
    }

    func goToPage(_ page: Int) {
        let upperBound = max(pageCount - 1, 0)
        let clamped = min(max(page, 0), upperBound)
        guard clamped != currentPage else { return }
        currentPage = clamped
    }

    /// Keeps the visible page valid after the layout changes.
    func clampCurrentPage() {
        let upperBound = max(pageCount - 1, 0)
        if currentPage > upperBound {
            currentPage = upperBound
        }
    }

    private func refreshPageCount() {
        pageCount = max(1, Int(ceil(Double(items.count) / Double(pageCapacity))))
        clampCurrentPage()
    }

    private func commit() {
        refreshPageCount()
        if let openFolderID, layout.folder(withID: openFolderID) == nil {
            self.openFolderID = nil
        }
        store.save(layout)
    }

    // MARK: - Editing

    func beginEditing() {
        guard !isEditing else { return }
        isEditing = true
        clearSearch()
    }

    func endEditing() {
        isEditing = false
        draggingID = nil
    }

    /// Resolves a drop. Dropping one app on another creates a folder; dropping
    /// on a folder adds the app to it; anything else is a reorder.
    func performDrop(itemID: String, slot: Int, ontoIcon: Bool) {
        defer { draggingID = nil }
        guard let dragged = item(withID: itemID) else { return }

        if ontoIcon, case .app(let draggedApp) = dragged, let target = item(atSlot: slot) {
            if target.isFolder {
                if layout.drop(draggedID: itemID, onto: target.id, newFolderName: "Folder") != nil {
                    commit()
                }
                return
            }
            if case .app(let targetApp) = target, targetApp != draggedApp {
                let involved = [targetApp, draggedApp].compactMap { appsByID[$0] }
                let name = FolderNaming.suggestedName(for: involved)
                if layout.drop(draggedID: itemID, onto: target.id, newFolderName: name) != nil {
                    commit()
                }
                return
            }
        }

        if layout.move(itemID: itemID, toSlot: slot) {
            commit()
        }
    }

    /// Removes the app from the grid (without touching the filesystem). Used by
    /// tests and by the uninstall flow.
    func remove(appID: String) {
        layout.remove(appID: appID)
        commit()
    }

    func uninstall(appID: String) {
        guard let app = appsByID[appID], app.isRemovable else { return }
        guard AppUninstaller.confirmAndTrash(app) else { return }

        catalog.remove(id: appID)
        appsByID[appID] = nil
        layout.remove(appID: appID)
        commit()
    }

    func renameFolder(_ folderID: UUID, to name: String) {
        layout.renameFolder(folderID, to: name)
        commit()
    }

    /// Moves an app out of its folder onto the grid at `slot`. The folder
    /// collapses when only one app would remain, or disappears when empty.
    func moveAppOutOfFolder(appID: String, toSlot slot: Int?) {
        guard layout.moveAppOutOfFolder(appID: appID, toSlot: slot) else { return }
        commit()
    }

    // MARK: - Folders

    func openFolder(_ folderID: UUID) {
        guard layout.folder(withID: folderID) != nil else { return }
        openFolderID = folderID
        // Opening a folder does not end jiggle mode: the apps inside keep
        // wobbling with the grid, the way Launchpad does it. Opening from the
        // resting grid leaves edit mode off.
        draggingID = nil
    }

    func closeFolder() {
        openFolderID = nil
    }

    // MARK: - Search

    var isSearching: Bool { !searchQuery.isEmpty }

    var searchResults: [AppItem] {
        SearchRanking.rank(catalog.apps, query: searchQuery)
    }

    var selectedSearchResult: AppItem? {
        let results = searchResults
        guard !results.isEmpty else { return nil }
        return results[min(max(searchSelection, 0), results.count - 1)]
    }

    func beginSearch(with text: String) {
        endEditing()
        closeFolder()
        searchQuery = text
        searchSelection = 0
    }

    /// Adds characters typed while the search is active but the field itself
    /// does not own the keyboard.
    func appendToSearch(_ text: String) {
        guard isSearching else {
            beginSearch(with: text)
            return
        }
        searchQuery += text
        searchSelection = 0
    }

    func deleteLastSearchCharacter() {
        guard isSearching else { return }
        searchQuery.removeLast()
        searchSelection = 0
    }

    func requestSearchFocus() {
        if isEditing { endEditing() }
        searchFocusRequest += 1
    }

    func clearSearch() {
        searchQuery = ""
        searchSelection = 0
    }

    func moveSearchSelection(by delta: Int) {
        let count = searchResults.count
        guard count > 0 else { return }
        searchSelection = min(max(searchSelection + delta, 0), count - 1)
    }
}

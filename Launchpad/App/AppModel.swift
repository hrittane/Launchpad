import Foundation
import Observation
import SwiftUI

/// Shared, observable application state.
@MainActor
@Observable
final class AppModel {
    let catalog: AppCatalog

    private let store: LayoutStore

    /// Grid contents, reconciled against `catalog.apps`.
    private(set) var layout = LauncherLayout()

    /// Grid shape, kept in sync with `LaunchpadSettings`. Stored here (rather
    /// than read from the settings) so a bare `AppModel()` used by the tests
    /// always starts on the default 7 × 5 grid.
    private(set) var columns = LaunchpadMetrics.defaultColumns
    private(set) var rows = LaunchpadMetrics.defaultRows

    /// Catalog lookup, rebuilt whenever the scan finishes.
    private(set) var appsByID: [String: AppItem] = [:]

    /// Incremented every time the panel is presented, so the UI can replay its
    /// entrance animation even though the hosting view is long-lived.
    private(set) var showCount = 0

    /// True when gesture blocking is enabled but macOS has not granted
    /// Accessibility for this build — normally right after an update, because
    /// an ad-hoc signature is identified by the build's code hash. The panel
    /// shows a one-click repair banner instead of failing silently.
    private(set) var needsAccessibilityGrant = false

    /// Zero-based index of the visible grid page.
    private(set) var currentPage = 0

    /// Live horizontal translation of the page strip while a trackpad swipe is
    /// in flight, in points. Negative reveals the next page, positive the
    /// previous one. Zero at rest.
    private(set) var pageDragOffset: CGFloat = 0

    /// True between the first and the last scroll event of a paging swipe.
    private(set) var isPaging = false

    /// Number of grid pages for the current layout. Kept in sync by the model
    /// so the AppKit scroll handler can page without knowing the layout.
    var pageCount = 1

    // MARK: Editing

    private(set) var isEditing = false

    /// Identifier of the icon currently being dragged by the UI.
    var draggingID: String?

    // MARK: Folders

    private(set) var openFolderID: UUID?

    /// Folder whose name field should take focus, set for a folder that has
    /// just been created. Cleared once the field has it.
    private(set) var folderNamePromptID: UUID?

    var isPromptingFolderName: Bool { folderNamePromptID != nil }

    // MARK: Search

    var searchQuery = ""
    var searchSelection = 0

    /// Bumped when the search field should take focus.
    private(set) var searchFocusRequest = 0

    var pageCapacity: Int { columns * rows }

    init(catalog: AppCatalog = AppCatalog(), store: LayoutStore = .shared) {
        self.catalog = catalog
        self.store = store
        layout = store.load() ?? LauncherLayout()
    }

    var items: [LauncherItem] { layout.items }

    var openFolder: AppFolder? {
        openFolderID.flatMap(layout.folder(withID:))
    }

    /// Adopts the grid size from the settings and reflows the saved layout when
    /// it changed. Appearance-only changes are ignored.
    func apply(settings: LaunchpadSettings) {
        let newColumns = settings.columns
        let newRows = settings.rows
        let capacity = newColumns * newRows
        guard newColumns != columns || newRows != rows || layout.capacity != capacity else {
            return
        }

        columns = newColumns
        rows = newRows
        var next = layout
        next.setCapacity(capacity)
        if next != layout {
            layout = next
            store.save(layout)
        }
        refreshPageCount()
        clampCurrentPage()
    }

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

    func item(onPage page: Int, offset: Int) -> LauncherItem? {
        layout.item(onPage: page, offset: offset)
    }

    func items(onPage page: Int) -> [LauncherItem] {
        layout.items(onPage: page)
    }

    func canRemove(appID: String) -> Bool {
        appsByID[appID]?.isRemovable == true
    }

    // MARK: - Paging

    /// Drives the stale-permission banner. Only assigns when the value really
    /// changes, so the panel's 1.5 s trust poll does not invalidate the view.
    func setAccessibilityGrantNeeded(_ needed: Bool) {
        guard needsAccessibilityGrant != needed else { return }
        needsAccessibilityGrant = needed
    }

    func notePresented() {
        showCount += 1
        cancelPageGesture()
        endEditing()
        closeFolder()
        clearSearch()
    }

    /// Starts a finger-following page swipe. The strip moves with every scroll
    /// event and only snaps when the gesture ends.
    func beginPageGesture() {
        guard pageCount > 1, !isPaging else { return }
        isPaging = true
        pageDragOffset = 0
    }

    /// Adds the horizontal finger travel to the live offset, with a rubber band
    /// past the first and last pages instead of a hard stop.
    func updatePageGesture(deltaX: CGFloat, pageWidth: CGFloat) {
        guard isPaging, pageWidth > 0 else { return }
        let proposed = pageDragOffset + deltaX
        let isPullingPastFirst = currentPage == 0 && proposed > 0
        let isPullingPastLast = currentPage >= pageCount - 1 && proposed < 0
        if isPullingPastFirst || isPullingPastLast {
            let band = pageWidth * 0.32
            pageDragOffset = min(max(proposed * 0.32, -band), band)
        } else {
            pageDragOffset = min(max(proposed, -pageWidth), pageWidth)
        }
    }

    /// Settles the swipe: a turn past `pageTurnFraction` commits the adjacent
    /// page, anything shorter springs back. A fast flick is projected a short
    /// way with its release velocity, so a quick two-finger swipe turns the
    /// page even when the fingers only travelled a little. Both the page index
    /// and the live offset animate together, so the strip finishes the distance
    /// the fingers did not cover instead of jumping.
    func endPageGesture(pageWidth: CGFloat, velocityX: CGFloat = 0) {
        guard isPaging else { return }
        isPaging = false
        guard pageWidth > 0 else {
            pageDragOffset = 0
            return
        }
        // A flick that reverses direction at the last moment must not carry the
        // page the other way.
        let velocity = velocityX * pageDragOffset >= 0 ? velocityX : 0
        let projected = pageDragOffset + velocity * Self.pageVelocityProjection
        let fraction = projected / pageWidth
        let step = abs(fraction) > Self.pageTurnFraction ? (fraction < 0 ? 1 : -1) : 0
        let target = min(max(currentPage + step, 0), max(pageCount - 1, 0))
        withAnimation(.spring(duration: 0.34, bounce: 0.08)) {
            currentPage = target
            pageDragOffset = 0
        }
    }

    /// Drops a live swipe without animating, for dismissal or a layout change.
    func cancelPageGesture() {
        guard isPaging || pageDragOffset != 0 else { return }
        isPaging = false
        pageDragOffset = 0
    }

    /// Share of a page a swipe has to cover to turn it.
    private static let pageTurnFraction: CGFloat = 0.16

    /// How far a release velocity is projected, in seconds. Mirrors the drag
    /// gesture's predicted end: a quick flick carries further than the fingers.
    private static let pageVelocityProjection: CGFloat = 0.15

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

    /// Adds an empty page at the end so a drag that waits at the right edge of
    /// the last page can continue onto it. Nothing is saved until the drop
    /// actually lands there; `trimEmptyPages()` removes it otherwise.
    func addPageForDragging() {
        var next = layout
        guard next.appendEmptyPage() else { return }
        layout = next
        refreshPageCount()
        goToPage(pageCount - 1)
    }

    /// Removes a page a cancelled drag left empty and pulls the visible page
    /// back into range.
    func trimEmptyPages() {
        var next = layout
        guard next.trimEmptyPages() else {
            refreshPageCount()
            return
        }
        layout = next
        refreshPageCount()
    }

    private func refreshPageCount() {
        pageCount = max(1, layout.pageCount)
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
    func performDrop(itemID: String, page: Int, offset: Int, ontoIcon: Bool) {
        defer { draggingID = nil }
        guard let dragged = item(withID: itemID) else { return }

        if ontoIcon, case .app(let draggedApp) = dragged,
           let target = item(onPage: page, offset: offset) {
            if target.isFolder {
                if layout.drop(draggedID: itemID, onto: target.id, newFolderName: "Folder") != nil {
                    commit()
                }
                return
            }
            if case .app(let targetApp) = target, targetApp != draggedApp {
                let involved = [targetApp, draggedApp].compactMap { appsByID[$0] }
                let name = FolderNaming.suggestedName(for: involved)
                if let folderID = layout.drop(
                    draggedID: itemID,
                    onto: target.id,
                    newFolderName: name
                ) {
                    commit()
                    // A brand-new folder opens with its name ready to edit.
                    openFolder(folderID, promptingName: true)
                }
                return
            }
        }

        if layout.move(itemID: itemID, toPage: page, offset: offset) {
            commit()
        }
    }

    /// Flat-slot entry point kept for the tests and older call sites.
    func performDrop(itemID: String, slot: Int, ontoIcon: Bool) {
        performDrop(
            itemID: itemID,
            page: slot / pageCapacity,
            offset: slot % pageCapacity,
            ontoIcon: ontoIcon
        )
    }

    /// Removes the app from the grid (without touching the filesystem). Used by
    /// tests and by the uninstall flow.
    func remove(appID: String) {
        layout.remove(appID: appID)
        commit()
    }

    /// Rebuilds the grid from the installed apps in catalog order. Folders,
    /// custom order and page splits are discarded.
    func resetLayout() {
        var next = LauncherLayout(capacity: pageCapacity)
        next.reconcile(with: catalog.apps)
        layout = next
        refreshPageCount()
        clampCurrentPage()
        store.save(layout)
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
        guard let slot else {
            if layout.moveAppOutOfFolder(appID: appID, toSlot: nil) {
                commit()
            }
            return
        }
        moveAppOutOfFolder(
            appID: appID,
            page: slot / pageCapacity,
            offset: slot % pageCapacity
        )
    }

    /// Page-aware drop of an app that is leaving its folder. Page indices are
    /// unchanged by the lift, because a folder with two apps becomes the
    /// survivor in the same slot.
    func moveAppOutOfFolder(appID: String, page: Int, offset: Int) {
        if layout.moveAppOutOfFolder(appID: appID, toPage: page, offset: offset) {
            commit()
        }
    }

    /// The grid as it would look if `appID` stepped out of its folder. Used by
    /// the live drag preview; nothing is written.
    func liftedItems(appID: String) -> [LauncherItem]? {
        layout.liftingAppOutOfFolder(appID)
    }

    /// The page-aware grid with `appID` lifted out of its folder.
    func layoutLiftingAppOutOfFolder(_ appID: String) -> LauncherLayout? {
        layout.layoutLiftingAppOutOfFolder(appID)
    }

    /// Resolves a drop of an app dragged out of its folder: dropping it on
    /// another app creates a folder, dropping it on a folder adds it there and
    /// anything else is a plain reorder on the grid.
    /// - Returns: the identifier of a folder this drop created (and opened for
    ///   naming), or `nil` when the drop joined an existing folder or reordered.
    @discardableResult
    func dropAppFromFolder(
        appID: String,
        page: Int,
        offset: Int,
        onto target: LauncherItem?
    ) -> UUID? {
        defer { draggingID = nil }

        if let target {
            if target.isFolder {
                if layout.dropAppOutOfFolder(
                    appID: appID,
                    onto: target.id,
                    newFolderName: "Folder"
                ) != nil {
                    commit()
                }
                return nil
            }
            if case .app(let targetApp) = target, targetApp != appID {
                let involved = [targetApp, appID].compactMap { appsByID[$0] }
                let name = FolderNaming.suggestedName(for: involved)
                if let folderID = layout.dropAppOutOfFolder(
                    appID: appID,
                    onto: target.id,
                    newFolderName: name
                ) {
                    commit()
                    openFolder(folderID, promptingName: true)
                    return folderID
                }
                return nil
            }
        }

        if layout.moveAppOutOfFolder(appID: appID, toPage: page, offset: offset) {
            commit()
        }
        return nil
    }

    /// Flat-slot entry point kept for the tests.
    @discardableResult
    func dropAppFromFolder(appID: String, slot: Int, onto target: LauncherItem?) -> UUID? {
        dropAppFromFolder(
            appID: appID,
            page: slot / pageCapacity,
            offset: slot % pageCapacity,
            onto: target
        )
    }

    /// Reorders an app inside the open folder, dropping it on `index` in the
    /// folder's child list.
    func moveApp(inFolder folderID: UUID, appID: String, toIndex index: Int) {
        guard layout.moveApp(inFolder: folderID, appID: appID, toSlot: index) else { return }
        commit()
    }

    // MARK: - Folders

    func openFolder(_ folderID: UUID, promptingName: Bool = false) {
        guard layout.folder(withID: folderID) != nil else { return }
        openFolderID = folderID
        // A folder that was just created asks for its name right away; opening
        // an existing one never steals the keyboard.
        folderNamePromptID = promptingName ? folderID : nil
        // Opening a folder does not end jiggle mode: the apps inside keep
        // wobbling with the grid, the way Launchpad does it. Opening from the
        // resting grid leaves edit mode off.
        draggingID = nil
    }

    /// Called by the sheet once the name field has focus.
    func clearFolderNamePrompt() {
        folderNamePromptID = nil
    }

    func closeFolder() {
        openFolderID = nil
        folderNamePromptID = nil
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

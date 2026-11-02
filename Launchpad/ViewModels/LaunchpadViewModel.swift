import AppKit
import SwiftUI

/// A custom drag that is rendered above the grid. The icon follows the cursor
/// while the view model decides which slot or folder will receive it.
struct DragSession: Equatable {
    var entry: LaunchpadEntry
    var sourcePage: Int
    var sourceIndex: Int
    var targetInsertionSlot: Int?
    var hoveredEntryID: String?
    var armedMergeTargetID: String?
    var mergeCandidateID: String?
}

/// A drag that starts inside an opened folder. Keeping it separate from the
/// grid drag lets the folder close while the item is still following the
/// cursor, which is what makes drag-out feel continuous.
struct FolderDragSession: Equatable {
    var app: AppItem
    var folderID: UUID
    /// Absolute index inside the folder's app array.
    var sourceIndex: Int
    /// Page-local slot inside the folder grid, when the cursor is over it.
    var hoverSlot: Int?
    var isOutside: Bool = false
    var panelFrame: CGRect
}

/// A committed page turn whose slide is still on screen.
///
/// Base page positions stay fixed while the strip slides one full page; the
/// current index is swapped in afterwards. That keeps every icon's body out of
/// the animation, which is what makes the turn smooth.
private struct PendingPageSnap {
    let target: Int
    let wasSearching: Bool
}

/// MVVM state for the whole overlay. The view model owns layout, search,
/// folders, drag state, keyboard focus, and settings.
@MainActor
final class LaunchpadViewModel: ObservableObject {
    // MARK: Published state

    @Published private(set) var pages: [PageLayout] = [[]]
    @Published private(set) var currentPage = 0
    @Published var searchText = "" {
        didSet {
            guard oldValue != searchText else { return }
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                searchResults = []
                searchPage = 0
                focusedEntryID = nil
            } else {
                closeFolder(animated: false)
                isEditing = false
            }
            scheduleSearch()
        }
    }
    @Published private(set) var searchResults: [AppItem] = []
    @Published private(set) var searchPage = 0
    @Published private(set) var isSearchModeCache = false

    @Published private(set) var isVisible = false
    @Published private(set) var isEditing = false
    @Published var focusedEntryID: String?
    @Published var infoApp: AppItem?
    @Published var pendingDelete: AppItem?
    @Published private(set) var isScanning = false
    @Published private(set) var reduceMotion = false
    @Published private(set) var reduceTransparency = false
    @Published var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            settingsStore.save(settings)
            if settings.pageCapacity != oldValue.pageCapacity {
                repaginateForCapacityChange()
            }
            onSettingsChanged?(settings)
        }
    }

    // Folder presentation is split into identity and visibility so the close
    // animation can finish before the panel leaves the view tree.
    @Published private(set) var openFolderID: UUID?
    @Published private(set) var activeFolderCache: FolderItem?
    @Published private(set) var folderIsPresented = false
    @Published private(set) var folderAnchor: CGRect = .zero
    @Published private(set) var folderPage = 0
    @Published private(set) var folderTitleEditing = false
    @Published var folderTitleDraft = ""
    /// Incremented whenever the title field should take focus. The panel
    /// observes this instead of focusing inside the zoom animation, where the
    /// field editor may not exist yet.
    @Published private(set) var folderFocusToken = 0
    /// Set when a folder was just created: the panel starts renaming as soon as
    /// it finishes zooming open, so the name field is ready immediately.
    private var renameOnPresent = false
    /// Bumped on every open/close so a delayed presentation cannot reopen a
    /// folder that is already closing.
    private var folderPresentationGeneration = 0
    private var folderIsClosing = false
    /// Gesture offsets are observable on their own so a scroll event only
    /// invalidates the small offset modifier, not the whole grid.
    let folderDrag = PageDragState()
    let pageDrag = PageDragState()
    /// Cursor position for a grid drag, isolated so mouse-move events do not
    /// invalidate the grid. Only the floating drag preview observes it.
    let itemDrag = ItemDragState()
    /// Cursor position for a folder drag-out, isolated for the same reason.
    let folderItemDrag = FolderDragState()
    private var isDraggingPage = false
    @Published private(set) var dragSession: DragSession?
    /// The exact layout a drop would commit, rendered while dragging. Nil when
    /// no drag is active or when hovering a folder merge target (the drop will
    /// not reorder the grid in that case).
    @Published private(set) var reorderPreview: GridReorderPreview?
    @Published private(set) var folderDragSession: FolderDragSession?
    @Published private(set) var screenSize: CGSize = NSScreen.main?.frame.size ?? Metrics.referenceSize
    @Published private(set) var searchFocusToken = 0

    // MARK: Callbacks

    var onRequestClose: (() -> Void)?
    var onRequestPreferences: (() -> Void)?
    var onSettingsChanged: ((AppSettings) -> Void)?

    // MARK: Dependencies

    private let scanner: AppScanner
    private let layoutStore: LayoutStore
    private let settingsStore: SettingsStore
    private let directoryMonitor: AppDirectoryMonitor
    private let workspace = NSWorkspace.shared

    // MARK: Private state

    private var discoveredApps: [AppItem] = []
    private var searchTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var mergeArmTask: Task<Void, Never>?
    private var edgeFlipTask: Task<Void, Never>?
    private var scrollCommitTask: Task<Void, Never>?
    private var pageSnapTask: Task<Void, Never>?
    private var pendingPageSnap: PendingPageSnap?
    private var accessibilityObserver: NSObjectProtocol?
    private var started = false
    private var queuedScan = false
    private var scrollAccumulator: CGFloat = 0
    private var folderScrollAccumulator: CGFloat = 0
    private var lastWheelFlip = Date.distantPast
    private var scrollVelocity: CGFloat = 0
    private var lastScrollTimestamp: TimeInterval = 0
    private var folderScrollVelocity: CGFloat = 0
    private var folderLastScrollTimestamp: TimeInterval = 0

    /// Frames reported by the interactive page view, in the "launchpad"
    /// coordinate space. This is deliberately not @Published: updating frames
    /// must not invalidate the view hierarchy.
    private(set) var iconFrames: [String: CGRect] = [:]

    // MARK: Init

    init(
        scanner: AppScanner = AppScanner(),
        layoutStore: LayoutStore = LayoutStore(),
        settingsStore: SettingsStore = SettingsStore(),
        directoryMonitor: AppDirectoryMonitor? = nil
    ) {
        self.scanner = scanner
        self.layoutStore = layoutStore
        self.settingsStore = settingsStore
        self.directoryMonitor = directoryMonitor ?? AppDirectoryMonitor()
        self.settings = settingsStore.load()
        observeAccessibility()
        refreshAccessibilityState()
    }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        layoutStorePreloadAndScan()
        directoryMonitor.start(roots: AppScanner.defaultRoots()) { [weak self] in
            self?.refreshApps()
        }
    }

    private func layoutStorePreloadAndScan() {
        Task { [weak self] in
            guard let self else { return }
            let saved = await self.layoutStore.load()
            if !saved.isEmpty {
                self.pages = saved
                self.clampPages()
            }
            self.refreshApps()
        }
    }

    /// Scans the application folders off the main thread and merges the result
    /// into the current layout, preserving user arrangement.
    func refreshApps() {
        guard started else { return }
        if isScanning {
            queuedScan = true
            return
        }
        isScanning = true
        scanTask = Task { [weak self] in
            guard let self else { return }
            let discovered = await self.scanner.scan()
            self.applyScan(discovered)
        }
    }

    private func applyScan(_ discovered: [AppItem]) {
        isScanning = false
        discoveredApps = discovered
        let capacity = settings.pageCapacity
        let normalized = LayoutEngine.normalize(pages: pages, discovered: discovered, capacity: capacity)
        if normalized != pages {
            pages = normalized
            persist()
        }
        clampPages()
        if openFolderID != nil && activeFolder == nil {
            closeFolder(animated: false)
        }
        if queuedScan {
            queuedScan = false
            refreshApps()
        }
    }

    func shutdown() {
        directoryMonitor.stop()
        scanTask?.cancel()
        searchTask?.cancel()
        mergeArmTask?.cancel()
        edgeFlipTask?.cancel()
        scrollCommitTask?.cancel()
        pageSnapTask?.cancel()
        folderDragSession = nil
        if let accessibilityObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver)
        }
        persistNow()
    }

    // MARK: Windowing

    func prepareForShow() {
        finishPageSnap()
        refreshAccessibilityState()
        searchTask?.cancel()
        searchText = ""
        searchResults = []
        searchPage = 0
        focusedEntryID = nil
        isEditing = false
        cancelDrag()
        cancelFolderDrag()
        folderPresentationGeneration &+= 1
        folderIsClosing = false
        openFolderID = nil
        folderIsPresented = false
        folderTitleEditing = false
        renameOnPresent = false
        folderPage = 0
        pageDrag.offset = 0
        isDraggingPage = false
        clampPages()
        refreshApps()
    }

    func setVisible(_ visible: Bool) {
        isVisible = visible
        if visible {
            refreshAccessibilityState()
        } else {
            isEditing = false
            focusedEntryID = nil
            folderTitleEditing = false
            finishPageSnap()
            cancelDrag()
            cancelFolderDrag()
            persistNow()
        }
    }

    func setScreenSize(_ size: CGSize) {
        guard size.width > 1, size.height > 1, size != screenSize else { return }
        screenSize = size
    }

#if DEBUG
    /// Test-only hook that installs a deterministic layout without scanning the
    /// file system. Kept in DEBUG so release builds never expose it.
    func seedLayoutForTesting(_ layout: [PageLayout], page: Int = 0) {
        pages = layout
        currentPage = page
        clampPages()
    }
#endif

    func requestSearchFocus() {
        searchFocusToken &+= 1
    }

    // MARK: Layout accessors

    var isSearchMode: Bool { isSearchModeCache }

    /// Pages currently rendered: real pages in normal mode, paginated results
    /// while searching. Search overflow therefore uses the same grid metrics.
    var displayedPages: [PageLayout] {
        if isSearchMode {
            return LayoutEngine.paginate(
                searchResults.map(LaunchpadEntry.app),
                capacity: settings.pageCapacity
            )
        }
        return pages.isEmpty ? [[]] : pages
    }

    var currentDisplayedPage: Int {
        let page = isSearchMode ? searchPage : currentPage
        return min(max(page, 0), max(0, displayedPageCount - 1))
    }

    var displayedPageCount: Int {
        // A drag preview never adds pages, but it can collapse a transient
        // trailing page created by dragging past the last real page.
        if !isSearchMode, let reorderPreview {
            return max(1, reorderPreview.pages.count)
        }
        return max(1, displayedPages.count)
    }

    var activeFolder: FolderItem? {
        guard let openFolderID else { return nil }
        return folder(withID: openFolderID) ?? activeFolderCache
    }

    var folderPageCapacity: Int {
        FolderMetrics(screenSize: screenSize, settings: settings).capacity
    }

    var folderPages: [PageLayout] {
        guard let activeFolder else { return [[]] }
        var result: [PageLayout] = []
        var index = 0
        while index < activeFolder.apps.count {
            let end = min(index + folderPageCapacity, activeFolder.apps.count)
            result.append(activeFolder.apps[index..<end].map(LaunchpadEntry.app))
            index = end
        }
        return result.isEmpty ? [[]] : result
    }

    var folderPageCount: Int { max(1, folderPages.count) }

    var currentFolderPage: Int {
        min(max(folderPage, 0), folderPageCount - 1)
    }

    var currentFolderEntries: PageLayout {
        let pages = folderPages
        guard pages.indices.contains(currentFolderPage) else { return [] }
        return pages[currentFolderPage]
    }

    var activeFolderEntryCount: Int {
        openFolderID == nil ? 0 : currentFolderEntries.count
    }

    // MARK: Page navigation

    func goToPage(_ page: Int, animated: Bool = true) {
        finishPageSnap()
        let target = min(max(page, 0), displayedPageCount - 1)
        if isSearchMode {
            guard target != searchPage else { return }
            if animated { withAnimation(animation(.page)) { searchPage = target } } else { searchPage = target }
        } else {
            guard target != currentPage else { return }
            if animated { withAnimation(animation(.page)) { currentPage = target } } else { currentPage = target }
        }
        pageDrag.offset = 0
    }

    func nextPage() { goToPage(currentDisplayedPage + 1) }
    func previousPage() { goToPage(currentDisplayedPage - 1) }

    func jumpToPageShortcut(_ number: Int) {
        goToPage(number - 1)
    }

    private func setDisplayedPage(_ page: Int, animated: Bool) {
        finishPageSnap()
        if isSearchMode {
            searchPage = min(max(page, 0), displayedPageCount - 1)
        } else {
            let target = min(max(page, 0), displayedPageCount - 1)
            if animated {
                withAnimation(animation(.page)) { currentPage = target }
            } else {
                currentPage = target
            }
        }
    }

    // MARK: Search

    private func scheduleSearch() {
        finishPageSnap()
        searchTask?.cancel()
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isSearchModeCache = false
            searchResults = []
            searchPage = 0
            return
        }
        isSearchModeCache = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Metrics.Durations.searchDebounce * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            let results = SearchEngine.search(trimmed, in: LayoutEngine.allApps(in: self.pages))
            self.searchResults = results
            self.searchPage = 0
            self.focusedEntryID = nil
            self.clampSearchPage()
        }
    }

    func clearSearch(keepFocus: Bool = true) {
        searchTask?.cancel()
        searchText = ""
        searchResults = []
        searchPage = 0
        focusedEntryID = nil
        if keepFocus { requestSearchFocus() }
    }

    func appendSearchCharacters(_ characters: String) {
        guard !characters.isEmpty else { return }
        searchText.append(contentsOf: characters)
        requestSearchFocus()
    }

    private func clampSearchPage() {
        let count = max(1, LayoutEngine.pageCount(forItemCount: searchResults.count, capacity: settings.pageCapacity))
        searchPage = min(max(searchPage, 0), count - 1)
    }

    // MARK: Activation

    func activate(_ entry: LaunchpadEntry) {
        switch entry {
        case .app(let app):
            launch(app)
        case .folder(let folder):
            openFolder(folder, anchor: iconFrames[entry.id] ?? .zero)
        }
    }

    func activateFocused() {
        if let openFolderID, activeFolder != nil {
            if let focused = focusedEntryID,
               let app = activeFolder?.apps.first(where: { LaunchpadEntry.app($0).id == focused }) {
                launch(app)
            }
            _ = openFolderID
            return
        }

        let entries = LayoutEngine.flatten(displayedPages)
        if let focused = focusedEntryID,
           let entry = entries.first(where: { $0.id == focused }) {
            activate(entry)
            return
        }
        if isSearchMode, let first = searchResults.first {
            launch(first)
        }
    }

    func launch(_ app: AppItem) {
        NSLog("Launchpad: opening %@ at %@", app.name, app.url.path)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.openApplication(at: app.url, configuration: configuration) { _, error in
            if let error {
                NSLog("Launchpad: failed to open %@: %@", app.url.path, error.localizedDescription)
            }
        }
        onRequestClose?()
    }

    func showInFinder(_ app: AppItem) {
        onRequestClose?()
        workspace.activateFileViewerSelecting([app.url])
    }

    func showInfo(_ app: AppItem) {
        infoApp = app
    }

    // MARK: Edit mode

    func enterEditMode() {
        guard !isEditing, !isSearchMode else { return }
        isEditing = true
        focusedEntryID = nil
    }

    func exitEditMode() {
        guard isEditing else { return }
        isEditing = false
    }

    func toggleEditMode() {
        isEditing ? exitEditMode() : enterEditMode()
    }

    // MARK: Background / escape / return

    func handleBackgroundTap() {
        if folderTitleEditing {
            commitFolderRename()
            return
        }
        if openFolderID != nil {
            closeFolder()
            return
        }
        if isEditing {
            exitEditMode()
            return
        }
        onRequestClose?()
    }

    /// Esc precedence: cancel folder rename → edit mode → folder → search →
    /// close the overlay.
    func handleEscape() {
        if folderTitleEditing {
            cancelFolderRename()
            return
        }
        if isEditing {
            exitEditMode()
            return
        }
        if openFolderID != nil {
            closeFolder()
            return
        }
        if isSearchMode {
            clearSearch()
            return
        }
        onRequestClose?()
    }

    /// Return precedence: edit mode exits before anything can launch.
    func handleReturn() {
        if folderTitleEditing {
            commitFolderRename()
            return
        }
        if isEditing {
            exitEditMode()
            return
        }
        activateFocused()
    }

    func handleDeleteKey() {
        requestSearchFocus()
    }

    // MARK: Focus navigation

    enum FocusDirection {
        case left, right, up, down
    }

    func moveFocus(_ direction: FocusDirection) {
        if folderTitleEditing { return }
        if openFolderID != nil {
            moveFolderFocus(direction)
            return
        }
        moveGridFocus(direction)
    }

    private func moveGridFocus(_ direction: FocusDirection) {
        let pages = displayedPages
        guard !pages.isEmpty else { return }
        let pageIndex = min(currentDisplayedPage, pages.count - 1)
        let pageEntries = pages[pageIndex]
        guard !pageEntries.isEmpty else {
            if pages.contains(where: { !$0.isEmpty }) { setDisplayedPage(0, animated: false) }
            return
        }

        if let focused = focusedEntryID,
           let location = location(of: focused, in: pages, preferredPage: pageIndex) {
            var targetPage = location.page
            var targetIndex = location.index
            switch direction {
            case .left:
                if targetIndex > 0 {
                    targetIndex -= 1
                } else if targetPage > 0 {
                    targetPage -= 1
                    targetIndex = max(0, pages[targetPage].count - 1)
                }
            case .right:
                if targetIndex + 1 < pages[targetPage].count {
                    targetIndex += 1
                } else if targetPage + 1 < pages.count {
                    targetPage += 1
                    targetIndex = 0
                }
            case .up:
                if targetIndex >= settings.columns {
                    targetIndex -= settings.columns
                } else if targetPage > 0 {
                    targetPage -= 1
                    targetIndex = max(0, pages[targetPage].count - 1)
                }
            case .down:
                let target = targetIndex + settings.columns
                if target < pages[targetPage].count {
                    targetIndex = target
                } else if targetPage + 1 < pages.count {
                    targetPage += 1
                    targetIndex = 0
                }
            }
            if targetPage != pageIndex {
                setDisplayedPage(targetPage, animated: true)
            }
            if pages[targetPage].indices.contains(targetIndex) {
                focusedEntryID = pages[targetPage][targetIndex].id
            }
        } else {
            let index: Int
            switch direction {
            case .left, .up: index = max(0, pageEntries.count - 1)
            case .right, .down: index = 0
            }
            focusedEntryID = pageEntries[index].id
            setDisplayedPage(pageIndex, animated: false)
        }
    }

    private func moveFolderFocus(_ direction: FocusDirection) {
        let entries = currentFolderEntries
        guard !entries.isEmpty else { return }
        guard let focused = focusedEntryID,
              let index = entries.firstIndex(where: { $0.id == focused }) else {
            focusedEntryID = entries[0].id
            return
        }
        let columns = Metrics.folderColumns
        var target = index
        switch direction {
        case .left:
            if index > 0 { target = index - 1 }
        case .right:
            if index + 1 < entries.count { target = index + 1 }
        case .up:
            if index - columns >= 0 { target = index - columns }
        case .down:
            if index + columns < entries.count { target = index + columns }
        }
        focusedEntryID = entries[target].id
    }

    private func location(
        of entryID: String,
        in pages: [PageLayout],
        preferredPage: Int
    ) -> (page: Int, index: Int)? {
        if pages.indices.contains(preferredPage),
           let index = pages[preferredPage].firstIndex(where: { $0.id == entryID }) {
            return (preferredPage, index)
        }
        for (page, entries) in pages.enumerated() {
            if let index = entries.firstIndex(where: { $0.id == entryID }) {
                return (page, index)
            }
        }
        return nil
    }

    // MARK: Folder presentation

    func openFolder(_ folder: FolderItem, anchor: CGRect) {
        finishPageSnap()
        if openFolderID == folder.id && folderIsPresented {
            return
        }
        folderPresentationGeneration &+= 1
        folderIsClosing = false
        openFolderID = folder.id
        activeFolderCache = folder
        folderAnchor = anchor
        folderPage = 0
        folderTitleEditing = false
        renameOnPresent = false
        focusedEntryID = nil
        // Insert the panel collapsed. `FolderPanelView` asks for presentation
        // on the next run-loop turn, after this collapsed frame has been
        // committed, so the zoom always starts from the folder's tile.
        if folderIsPresented {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                folderIsPresented = false
            }
        } else {
            folderIsPresented = false
        }
    }

    /// Called by the panel once it has been inserted. Presenting from the view
    /// (instead of scheduling from `openFolder`) removes the race between the
    /// async present and the panel's first render.
    func presentFolder() {
        guard openFolderID != nil, !folderIsClosing else { return }
        guard !folderIsPresented else {
            consumeRenameOnPresent()
            return
        }
        let generation = folderPresentationGeneration
        withAnimation(animation(.folder)) {
            folderIsPresented = true
        } completion: {
            guard self.folderPresentationGeneration == generation,
                  self.folderIsPresented else { return }
            self.consumeRenameOnPresent()
        }
    }

    /// Opens a folder that was just created by a drop and begins renaming it.
    func openNewFolder(folderID: UUID, anchor: CGRect) {
        guard folder(withID: folderID) != nil else { return }
        openFolder(folderID: folderID, anchor: anchor)
        renameOnPresent = true
        // Show the title field during the zoom, but defer focus until the
        // animation settles so the field editor is not created inside a
        // transformed view.
        beginFolderRename(focus: false)
    }

    func openFolder(folderID: UUID, anchor: CGRect) {
        guard let folder = folder(withID: folderID) else { return }
        openFolder(folder, anchor: anchor)
    }

    func closeFolder(animated: Bool = true) {
        guard openFolderID != nil, !folderIsClosing else { return }
        folderPresentationGeneration &+= 1
        folderIsClosing = true
        folderTitleEditing = false
        renameOnPresent = false
        if animated && !reduceMotion {
            let generation = folderPresentationGeneration
            withAnimation(animation(.folderClose)) {
                folderIsPresented = false
            } completion: {
                guard self.folderPresentationGeneration == generation else { return }
                self.finishFolderClose()
            }
        } else {
            if folderIsPresented {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    folderIsPresented = false
                }
            } else {
                folderIsPresented = false
            }
            finishFolderClose()
        }
    }

    private func finishFolderClose() {
        openFolderID = nil
        activeFolderCache = nil
        folderAnchor = .zero
        folderPage = 0
        folderDrag.offset = 0
        folderTitleEditing = false
        renameOnPresent = false
        folderIsClosing = false
        focusedEntryID = nil
    }

    private func consumeRenameOnPresent() {
        guard renameOnPresent else { return }
        renameOnPresent = false
        requestFolderTitleFocus()
    }

    func beginFolderRename(focus: Bool = true) {
        guard let activeFolder else { return }
        folderTitleDraft = activeFolder.name
        folderTitleEditing = true
        if focus { requestFolderTitleFocus() }
    }

    func requestFolderTitleFocus() {
        folderFocusToken &+= 1
    }

    func commitFolderRename() {
        defer {
            folderTitleEditing = false
        }
        guard let id = openFolderID, let folder = activeFolder else { return }
        let trimmed = folderTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != folder.name else { return }
        updateFolder(id: id) { stored in
            var updated = stored
            updated.name = String(trimmed.prefix(80))
            return updated
        }
        persist()
    }

    func cancelFolderRename() {
        folderTitleEditing = false
        folderTitleDraft = ""
    }

    func goToFolderPage(_ page: Int) {
        let target = min(max(page, 0), folderPageCount - 1)
        guard target != folderPage else { return }
        folderPage = target
        folderDrag.offset = 0
        focusedEntryID = nil
    }

    // MARK: Folder operations

    private func folder(withID id: UUID) -> FolderItem? {
        for entry in LayoutEngine.flatten(pages) {
            if let folder = entry.folder, folder.id == id { return folder }
        }
        return nil
    }

    private func updateFolder(id: UUID, _ transform: (FolderItem) -> FolderItem) {
        for pageIndex in pages.indices {
            for index in pages[pageIndex].indices {
                if let folder = pages[pageIndex][index].folder, folder.id == id {
                    let updated = transform(folder)
                    if updated.isViable {
                        pages[pageIndex][index] = .folder(updated)
                    } else {
                        let apps = updated.apps
                        pages[pageIndex].remove(at: index)
                        for (offset, app) in apps.enumerated() {
                            LayoutEngine.insert(
                                .app(app),
                                at: pageIndex,
                                index: index + offset,
                                in: &pages,
                                capacity: settings.pageCapacity
                            )
                        }
                        if openFolderID == id { closeFolder() }
                    }
                    return
                }
            }
        }
    }

    func addApp(_ app: AppItem, toFolder folderID: UUID) {
        updateFolder(id: folderID) { folder in
            LayoutEngine.folder(folder, adding: app)
        }
        persist()
    }

    func removeFolder(folderID: UUID) {
        guard let location = entryLocation(id: "folder:\(folderID.uuidString)"),
              let folder = folder(withID: folderID) else { return }

        // If the folder being deleted is currently open, animate the panel closing first.
        let wasOpen = (openFolderID == folderID)
        if wasOpen {
            closeFolder(animated: true)
        }

        // Animate the folder dissolving on the grid and its apps unpacking.
        withAnimation(animation(.folder)) {
            pages[location.page].remove(at: location.index)
            for (offset, app) in folder.apps.enumerated() {
                LayoutEngine.insert(
                    .app(app),
                    at: location.page,
                    index: location.index + offset,
                    in: &pages,
                    capacity: settings.pageCapacity
                )
            }
            clampPagesAfterMutation()
            clampSearchPage()
            folderPage = min(max(folderPage, 0), folderPageCount - 1)
        }
        persist()
    }

    func renameFolder(folderID: UUID, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateFolder(id: folderID) { folder in
            var updated = folder
            updated.name = String(trimmed.prefix(80))
            return updated
        }
        persist()
    }

    // MARK: App removal

    func requestDelete(_ app: AppItem) {
        guard app.isDeletable else { return }
        pendingDelete = app
    }

    func cancelDelete() {
        pendingDelete = nil
    }

    func confirmDelete() {
        guard let app = pendingDelete else { return }
        pendingDelete = nil
        workspace.recycle([app.url]) { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    NSLog("Launchpad: failed to move app to Trash: %@", error.localizedDescription)
                    NSSound.beep()
                    return
                }
                self.removeAppFromLayout(appID: app.id)
            }
        }
    }

    private func removeAppFromLayout(appID: String) {
        let released = LayoutEngine.removeApp(appID: appID, from: &pages)
        for entry in released {
            switch entry {
            case .app(let app):
                LayoutEngine.appendApp(app, to: &pages, capacity: settings.pageCapacity)
            case .folder(let folder):
                for app in folder.apps {
                    LayoutEngine.appendApp(app, to: &pages, capacity: settings.pageCapacity)
                }
            }
        }
        cleanupAfterLayoutChange()
        persist()
    }

    // MARK: Reset

    func resetLayout() {
        let source = discoveredApps.isEmpty ? LayoutEngine.allApps(in: pages) : discoveredApps
        let sorted = source.sorted { lhs, rhs in
            let comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return lhs.id < rhs.id
        }
        withAnimation(animation(.reorder)) {
            pages = LayoutEngine.paginate(sorted.map(LaunchpadEntry.app), capacity: settings.pageCapacity)
            currentPage = 0
        }
        closeFolder(animated: false)
        isEditing = false
        focusedEntryID = nil
        // The icon size is persisted, so a fresh default alone would never
        // reach an existing install. Reset restores it explicitly.
        var resetSettings = settings
        resetSettings.iconSize = Double(Metrics.defaultIconSize)
        settings = resetSettings
        persist()
    }

    // MARK: Drag and drop

    func beginDrag(entry: LaunchpadEntry, page: Int, index: Int) {
        guard !isSearchMode, openFolderID == nil else { return }
        finishPageSnap()
        isEditing = true
        focusedEntryID = entry.id
        itemDrag.location = .zero
        dragSession = DragSession(
            entry: entry,
            sourcePage: page,
            sourceIndex: index,
            targetInsertionSlot: index
        )
        // The initial preview is the untouched layout; the first pointer update
        // replaces it with the projected reflow.
        reorderPreview = GridReorder.preview(
            moving: entry.id,
            toPage: page,
            slot: index,
            in: pages,
            capacity: settings.pageCapacity
        )
    }

    func updateDrag(location: CGPoint) {
        guard var session = dragSession else { return }
        // Cursor tracking is isolated from the grid: only the floating preview
        // observes this value, so moving inside one cell does not re-render any
        // tiles.
        itemDrag.location = location

        let metrics = LayoutMetrics(screenSize: screenSize, settings: settings)
        // Use the page the user actually sees. A transient trailing page is
        // already folded into the last real page by `currentDisplayedPage`.
        let page = min(max(currentDisplayedPage, 0), max(0, pages.count - 1))
        let currentEntries = pages.indices.contains(page) ? pages[page] : []

        // 1. Hit-test against the original entry positions, never the projected
        // preview. The preview pushes tiles aside to open a gap, so testing the
        // previewed centres would always leave the cursor over empty space and
        // make every merge target unreachable.
        let engageRadius = metrics.iconSize * 0.5
        let disengageRadius = metrics.iconSize * 0.62

        var hoveredTargetID: String?
        if session.entry.app != nil {
            // Hysteresis: keep the current target until the cursor clearly
            // leaves it, so a pointer wobbling at the edge does not flicker
            // between neighbouring tiles.
            if let currentID = session.hoveredEntryID,
               currentID != session.entry.id,
               let index = currentEntries.firstIndex(where: { $0.id == currentID }) {
                let center = metrics.iconCenter(at: index)
                if hypot(center.x - location.x, center.y - location.y) <= disengageRadius {
                    hoveredTargetID = currentID
                }
            }

            if hoveredTargetID == nil {
                for (index, item) in currentEntries.enumerated()
                where item.id != session.entry.id && isMergeableTarget(item) {
                    let center = metrics.iconCenter(at: index)
                    if hypot(center.x - location.x, center.y - location.y) <= engageRadius {
                        hoveredTargetID = item.id
                        break
                    }
                }
            }
        }

        session.hoveredEntryID = hoveredTargetID

        // 2. Merge arming is only the dwell-driven shrink affordance. The drop
        // itself targets whatever is under the cursor, so an app-on-app drop
        // creates a folder immediately instead of requiring a pause.
        if let targetID = hoveredTargetID {
            if session.armedMergeTargetID != targetID {
                // Leaving an armed target for another one drops the old arm so
                // the drop always uses the item currently under the cursor.
                session.armedMergeTargetID = nil
                if session.mergeCandidateID != targetID {
                    session.mergeCandidateID = targetID
                    mergeArmTask?.cancel()
                    mergeArmTask = Task { [weak self] in
                        try? await Task.sleep(nanoseconds: UInt64(Metrics.Durations.dragHoverFolder * 1_000_000_000))
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            guard let self,
                                  var sess = self.dragSession,
                                  sess.mergeCandidateID == targetID,
                                  sess.hoveredEntryID == targetID else { return }
                            sess.armedMergeTargetID = targetID
                            self.dragSession = sess
                        }
                    }
                }
            }
        } else {
            session.armedMergeTargetID = nil
            session.mergeCandidateID = nil
            cancelMergeArm()
        }

        // 3. Project the layout for the cell under the cursor. This preview is
        // also what `endDrag` commits, so the drop can never disagree with it.
        if session.armedMergeTargetID == nil {
            let targetSlot = metrics.nearestSlot(at: location)
            session.targetInsertionSlot = targetSlot

            var targetPage = page
            var preview = GridReorder.preview(
                moving: session.entry.id,
                toPage: targetPage,
                slot: targetSlot,
                in: pages,
                capacity: settings.pageCapacity
            )
            if let projected = preview, targetPage >= projected.pages.count {
                // The cursor was over a transient trailing page; the packed
                // layout folds that page back into the last real one.
                targetPage = max(0, projected.pages.count - 1)
                preview = GridReorder.preview(
                    moving: session.entry.id,
                    toPage: targetPage,
                    slot: targetSlot,
                    in: pages,
                    capacity: settings.pageCapacity
                )
            }
            // Hovering any item means the drop merges rather than reorders, so
            // the reflow preview is hidden and the original layout stays put
            // underneath the cursor.
            let projectedPreview: GridReorderPreview? = session.hoveredEntryID == nil ? preview : nil
            if reorderPreview != projectedPreview {
                reorderPreview = projectedPreview
            }
        } else if reorderPreview != nil {
            reorderPreview = nil
        }

        // Publish only when something visible actually changed. A drag used to
        // assign a new session on every mouse-moved event, re-rendering every
        // tile even while the cursor stayed inside one cell.
        if dragSession != session {
            dragSession = session
        }
        updateEdgeFlip(location: location)
    }

    func endDrag() {
        guard let session = dragSession else { return }
        cancelMergeArm()
        edgeFlipTask?.cancel()
        edgeFlipTask = nil
        mergeArmTask = nil

        let armedMergeID = session.armedMergeTargetID
        let hoveredID = session.hoveredEntryID
        let draggedEntry = session.entry

        // The drop always targets the item under the cursor. The dwell-driven
        // arm only supplies the shrink affordance; an immediate app-on-app drop
        // must still create a folder, just like macOS.
        let mergeTargetID = armedMergeID ?? hoveredID

        var targetLocationBefore: (page: Int, index: Int)?
        if let mergeTargetID {
            targetLocationBefore = entryLocation(id: mergeTargetID)
        }

        var didCreateFolder = false
        var createdFolderID: UUID?
        let preview = reorderPreview

        if let targetID = mergeTargetID,
           let draggedApp = draggedEntry.app,
           let targetLocationBefore,
           let targetEntry = entry(withID: targetID) {

            // Animate the merge as one transaction so the dragged tile folds
            // into the target while the surrounding tiles close up.
            withAnimation(animation(.folder)) {
                // Folder merges keep their own path: the dragged entry is removed
                // first so the target index can be adjusted for the shifted row.
                var releasedDuringRemoval: [LaunchpadEntry] = []
                if let app = draggedEntry.app {
                    releasedDuringRemoval = LayoutEngine.removeApp(appID: app.id, from: &pages)
                } else {
                    LayoutEngine.remove(entryID: draggedEntry.id, from: &pages)
                }

                var targetLocation = targetLocationBefore
                if session.sourcePage == targetLocation.page && session.sourceIndex < targetLocation.index {
                    targetLocation.index = max(0, targetLocation.index - 1)
                }

                if let folder = targetEntry.folder {
                    // Drop onto existing folder
                    updateFolder(id: folder.id) { existing in
                        LayoutEngine.folder(existing, adding: draggedApp)
                    }
                } else if let targetApp = targetEntry.app,
                          let newFolder = LayoutEngine.makeFolder(apps: [targetApp, draggedApp]) {
                    // Create new folder
                    if pages.indices.contains(targetLocation.page),
                       pages[targetLocation.page].indices.contains(targetLocation.index) {
                        pages[targetLocation.page].remove(at: targetLocation.index)
                    }
                    LayoutEngine.insert(
                        .folder(newFolder),
                        at: targetLocation.page,
                        index: targetLocation.index,
                        in: &pages,
                        capacity: settings.pageCapacity
                    )
                    didCreateFolder = true
                    createdFolderID = newFolder.id
                }

                for released in releasedDuringRemoval {
                    switch released {
                    case .app(let app):
                        LayoutEngine.appendApp(app, to: &pages, capacity: settings.pageCapacity)
                    case .folder(let folder):
                        for app in folder.apps {
                            LayoutEngine.appendApp(app, to: &pages, capacity: settings.pageCapacity)
                        }
                    }
                }
            }
        } else if let preview {
            // Commit exactly the layout the user saw. Using the preview pages
            // (not a remove/insert reconstruction) is what keeps the icon from
            // jumping to a neighbouring slot on drop.
            pages = preview.pages
        } else {
            // Defensive fallback for a drag that ends before any pointer update
            // produced a preview.
            var releasedDuringRemoval: [LaunchpadEntry] = []
            if let app = draggedEntry.app {
                releasedDuringRemoval = LayoutEngine.removeApp(appID: app.id, from: &pages)
            } else {
                LayoutEngine.remove(entryID: draggedEntry.id, from: &pages)
            }
            let fallbackPage = min(max(currentPage, 0), max(0, pages.count - 1))
            let insertionIndex = session.targetInsertionSlot
                ?? (pages.indices.contains(fallbackPage) ? pages[fallbackPage].count : 0)
            LayoutEngine.insert(
                draggedEntry,
                at: fallbackPage,
                index: insertionIndex,
                in: &pages,
                capacity: settings.pageCapacity
            )
            for released in releasedDuringRemoval {
                switch released {
                case .app(let app):
                    LayoutEngine.appendApp(app, to: &pages, capacity: settings.pageCapacity)
                case .folder(let folder):
                    for app in folder.apps {
                        LayoutEngine.appendApp(app, to: &pages, capacity: settings.pageCapacity)
                    }
                }
            }
        }

        dragSession = nil
        reorderPreview = nil
        itemDrag.location = .zero
        pageDrag.offset = 0
        isDraggingPage = false
        cleanupAfterLayoutChange()
        persist()

        if didCreateFolder, let createdFolderID {
            // Zoom the freshly created folder open from its *final* tile. The
            // layout may have been repaginated, so the pre-cleanup anchor can
            // point at a slot the folder no longer occupies.
            revealCreatedFolder(createdFolderID)
        }
    }

    func cancelDrag() {
        mergeArmTask?.cancel()
        mergeArmTask = nil
        edgeFlipTask?.cancel()
        edgeFlipTask = nil
        dragSession = nil
        reorderPreview = nil
        itemDrag.location = .zero
    }

    // MARK: Folder drag

    /// The panel frame in the root "launchpad" coordinate space. Kept in one
    /// place so the panel view and hit testing always agree.
    func folderPanelFrame() -> CGRect {
        let metrics = FolderMetrics(screenSize: screenSize, settings: settings)
        return CGRect(
            x: (screenSize.width - metrics.panelSize.width) / 2,
            y: (screenSize.height - metrics.panelSize.height) / 2,
            width: metrics.panelSize.width,
            height: metrics.panelSize.height
        )
    }

    func beginFolderDrag(app: AppItem, folderID: UUID, sourceIndex: Int) {
        guard openFolderID == folderID, dragSession == nil else { return }
        cancelFolderDrag()
        folderTitleEditing = false
        folderItemDrag.location = .zero
        folderDragSession = FolderDragSession(
            app: app,
            folderID: folderID,
            sourceIndex: sourceIndex,
            panelFrame: folderPanelFrame()
        )
    }

    func updateFolderDrag(location: CGPoint) {
        guard var session = folderDragSession else { return }
        // Cursor tracking is isolated from the overlay: only the floating
        // preview observes this value, so moving inside one slot does not
        // re-render the grid or the folder panel.
        folderItemDrag.location = location

        let panelFrame = folderPanelFrame()
        session.panelFrame = panelFrame
        let outside = folderDragIsOutside(location, panelFrame: panelFrame, wasOutside: session.isOutside)
        var stateChanged = false
        if outside != session.isOutside {
            session.isOutside = outside
            stateChanged = true
            // Hide the panel (without ending the folder session) so the icon
            // can be seen continuing over the main grid.
            setFolderPanelVisible(!outside, animated: !reduceMotion)
        }

        let hoverSlot: Int?
        if outside {
            hoverSlot = nil
        } else {
            let metrics = FolderMetrics(screenSize: screenSize, settings: settings)
            let local = CGPoint(
                x: location.x - panelFrame.minX,
                y: location.y - panelFrame.minY
            )
            hoverSlot = metrics.slot(at: local)
        }
        if hoverSlot != session.hoverSlot {
            session.hoverSlot = hoverSlot
            stateChanged = true
        }

        // Publish only when the discrete drop state changes. A drag used to
        // assign a new session on every pointer event, invalidating the whole
        // overlay at mouse-move frequency.
        if stateChanged, folderDragSession != session {
            folderDragSession = session
        }
    }

    /// A small hysteresis band around the panel edge. Once outside, the pointer
    /// must come back inside the panel proper before the panel reappears; once
    /// inside, it must leave a slightly expanded frame before it hides.
    private func folderDragIsOutside(
        _ location: CGPoint,
        panelFrame: CGRect,
        wasOutside: Bool
    ) -> Bool {
        let margin: CGFloat = 10
        let bounds = wasOutside
            ? panelFrame.insetBy(dx: margin, dy: margin)
            : panelFrame.insetBy(dx: -margin, dy: -margin)
        return !bounds.contains(location)
    }

    private func setFolderPanelVisible(_ visible: Bool, animated: Bool) {
        guard folderIsPresented != visible else { return }
        if animated {
            withAnimation(animation(visible ? .folder : .folderClose)) {
                folderIsPresented = visible
            }
        } else {
            folderIsPresented = visible
        }
    }

    func endFolderDrag() {
        guard let session = folderDragSession else { return }
        let location = folderItemDrag.location
        folderDragSession = nil
        folderItemDrag.location = .zero

        if session.isOutside {
            // The panel was already hidden while the pointer was over the grid.
            // Commit the drop and close the folder without replaying the zoom.
            dropAppFromFolder(session, at: location)
        } else {
            if let slot = session.hoverSlot {
                reorderFolderApp(folderID: session.folderID, from: session.sourceIndex, toSlot: slot)
            }
            setFolderPanelVisible(true, animated: !reduceMotion)
        }
    }

    func cancelFolderDrag() {
        guard folderDragSession != nil else { return }
        folderDragSession = nil
        folderItemDrag.location = .zero
        if openFolderID != nil {
            setFolderPanelVisible(true, animated: false)
        }
    }

    private func reorderFolderApp(folderID: UUID, from sourceIndex: Int, toSlot slot: Int) {
        guard let folder = folder(withID: folderID),
              folder.apps.indices.contains(sourceIndex) else { return }
        let capacity = folderPageCapacity
        var apps = folder.apps
        let app = apps.remove(at: sourceIndex)
        let base = currentFolderPage * capacity
        let target = min(max(base + slot, base), apps.count)
        apps.insert(app, at: target)
        updateFolder(id: folderID) { stored in
            var updated = stored
            updated.apps = apps
            return updated
        }
        persist()
    }

    /// Removes the dragged app from its folder and inserts it on the visible
    /// grid page. If the folder drops below two apps it dissolves: the survivor
    /// takes the folder's former slot and the dragged app lands at the cursor.
    private func dropAppFromFolder(_ session: FolderDragSession, at location: CGPoint) {
        guard let folderLocation = entryLocation(id: "folder:\(session.folderID.uuidString)"),
              let folder = folder(withID: session.folderID) else {
            // A rescan can remove the folder mid-drag; leave the overlay in a
            // consistent state instead of keeping a ghost scrim.
            closeFolder(animated: false)
            return
        }
        guard folder.apps.contains(where: { $0.id == session.app.id }) else {
            // The dragged app is no longer in the folder (for example after a
            // rescan). Close the panel rather than re-inserting a duplicate.
            closeFolder(animated: false)
            return
        }

        let metrics = LayoutMetrics(screenSize: screenSize, settings: settings)
        let page = min(max(currentPage, 0), max(0, pages.count - 1))
        // Snap to the nearest cell when the pointer is over the search field or
        // a margin, matching the grid's own drop behaviour.
        let dropSlot = metrics.nearestSlot(at: location)
        let capacity = settings.pageCapacity
        let survivingApps = folder.apps.filter { $0.id != session.app.id }

        withAnimation(animation(.reorder)) {
            if survivingApps.count >= 2 {
                var updated = folder
                updated.remove(appID: session.app.id)
                pages[folderLocation.page][folderLocation.index] = .folder(updated)
                LayoutEngine.insert(
                    .app(session.app),
                    at: page,
                    index: dropSlot,
                    in: &pages,
                    capacity: capacity
                )
            } else {
                // A one-app folder is not viable. Remove it, then place the
                // survivor where the folder was and the dragged app where the
                // pointer was released.
                pages[folderLocation.page].remove(at: folderLocation.index)
                if dropSlot <= folderLocation.index {
                    LayoutEngine.insert(
                        .app(session.app),
                        at: page,
                        index: dropSlot,
                        in: &pages,
                        capacity: capacity
                    )
                    LayoutEngine.insert(
                        .app(survivingApps[0]),
                        at: folderLocation.page,
                        index: folderLocation.index,
                        in: &pages,
                        capacity: capacity
                    )
                } else {
                    LayoutEngine.insert(
                        .app(survivingApps[0]),
                        at: folderLocation.page,
                        index: folderLocation.index,
                        in: &pages,
                        capacity: capacity
                    )
                    LayoutEngine.insert(
                        .app(session.app),
                        at: page,
                        index: dropSlot,
                        in: &pages,
                        capacity: capacity
                    )
                }
            }
        }

        // Remove empty pages only. Repaginating the whole layout here is what
        // made unrelated apps jump across page boundaries after a drop.
        removeEmptyPagesAfterMutation()
        persist()
        closeFolder(animated: false)
    }

    private func cancelMergeArm() {
        mergeArmTask?.cancel()
        mergeArmTask = nil
        if dragSession?.armedMergeTargetID != nil {
            withAnimation(.easeOut(duration: 0.15)) {
                dragSession?.armedMergeTargetID = nil
            }
        }
        if dragSession?.mergeCandidateID != nil {
            dragSession?.mergeCandidateID = nil
        }
    }

    private func updateEdgeFlip(location: CGPoint) {
        let width = screenSize.width
        let nearLeft = location.x <= Metrics.edgeFlipThreshold
        let nearRight = location.x >= width - Metrics.edgeFlipThreshold
        guard nearLeft || nearRight else {
            edgeFlipTask?.cancel()
            edgeFlipTask = nil
            return
        }
        guard edgeFlipTask == nil else { return }
        let right = nearRight
        edgeFlipTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Metrics.Durations.dragEdgeFlip * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.flipPageWhileDragging(right: right)
            self.edgeFlipTask = nil
            self.updateEdgeFlip(location: self.itemDrag.location)
        }
    }

    private func flipPageWhileDragging(right: Bool) {
        guard dragSession != nil, !isSearchMode else { return }
        if right {
            if currentPage + 1 < pages.count {
                withAnimation(animation(.page)) { currentPage += 1 }
            } else if pages.indices.contains(currentPage), !pages[currentPage].isEmpty {
                withAnimation(animation(.page)) {
                    pages.append([])
                    currentPage += 1
                }
            }
        } else if currentPage > 0 {
            withAnimation(animation(.page)) { currentPage -= 1 }
        }
        if dragSession != nil {
            updateDrag(location: itemDrag.location)
        }
    }

    func recordIconFrames(_ frames: [String: CGRect]) {
        iconFrames = frames
    }

    // MARK: Swipe / scroll

    func updatePageSwipe(translation: CGFloat) {
        guard dragSession == nil, openFolderID == nil else { return }
        finishPageSnap()
        isDraggingPage = true
        pageDrag.offset = boundedPageOffset(translation)
    }

    func endPageSwipe(translation: CGFloat, predictedTranslation: CGFloat) {
        guard isDraggingPage else { return }
        let velocity = (predictedTranslation - translation) * 4
        endPageDrag(translation: translation, velocity: velocity)
    }

    private func endPageDrag(translation: CGFloat, velocity: CGFloat) {
        defer {
            isDraggingPage = false
            scrollAccumulator = 0
        }
        let current = currentDisplayedPage
        let target = PageDragGeometry.targetPage(
            from: current,
            translation: translation,
            velocity: velocity,
            pageCount: displayedPageCount,
            width: screenSize.width
        )
        guard target != current else {
            // The turn was cancelled: slide back without touching the index.
            withAnimation(animation(.page)) { pageDrag.offset = 0 }
            return
        }

        // Slide the whole strip one full page while every page keeps its base
        // position. The index is committed once the slide has finished, so no
        // icon body re-evaluates on the animation's first frame.
        let width = max(1, screenSize.width)
        pendingPageSnap = PendingPageSnap(target: target, wasSearching: isSearchMode)
        withAnimation(animation(.page)) {
            pageDrag.offset = target > current ? -width : width
        }
        schedulePageSnapCompletion()
    }

    /// Commits a slide immediately. Any new gesture calls this first so input
    /// always starts from a settled page instead of fighting the animation.
    private func finishPageSnap() {
        pageSnapTask?.cancel()
        pageSnapTask = nil
        guard let pending = pendingPageSnap else { return }
        pendingPageSnap = nil
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            pageDrag.offset = 0
            guard pending.wasSearching == isSearchMode else { return }
            let target = min(max(pending.target, 0), displayedPageCount - 1)
            if isSearchMode {
                searchPage = target
            } else {
                currentPage = target
            }
        }
    }

    private func schedulePageSnapCompletion() {
        pageSnapTask?.cancel()
        let slide = reduceMotion
            ? Metrics.Durations.reducedMotion
            : Metrics.Durations.pageSlide
        let delay = slide + Metrics.Durations.pageSnapBuffer
        pageSnapTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.finishPageSnap()
        }
    }

    func updateFolderSwipe(translation: CGFloat) {
        guard folderPageCount > 1 else { return }
        folderDrag.offset = PageDragGeometry.boundedOffset(
            translation: translation,
            page: currentFolderPage,
            pageCount: folderPageCount,
            width: folderPageWidth
        )
    }

    func endFolderSwipe(translation: CGFloat, predictedTranslation: CGFloat) {
        let velocity = (predictedTranslation - translation) * 4
        let target = PageDragGeometry.targetPage(
            from: currentFolderPage,
            translation: translation,
            velocity: velocity,
            pageCount: folderPageCount,
            width: folderPageWidth
        )
        withAnimation(animation(.page)) {
            folderPage = target
            folderDrag.offset = 0
            focusedEntryID = nil
        }
    }

    /// Width of one folder page. The folder panel is much narrower than the
    /// screen, so commit distance and drag bounds must use the panel width.
    private var folderPageWidth: CGFloat {
        FolderMetrics(screenSize: screenSize, settings: settings).panelSize.width
    }

    /// Limits a page drag to one page width. Without this, a fast trackpad
    /// gesture can drag several page widths at once, exposing unrendered slots
    /// before the view snaps back.
    private func boundedPageOffset(_ translation: CGFloat) -> CGFloat {
        PageDragGeometry.boundedOffset(
            translation: translation,
            page: currentDisplayedPage,
            pageCount: displayedPageCount,
            width: screenSize.width
        )
    }

    func handleScroll(_ event: NSEvent) {
        guard isVisible, dragSession == nil else { return }
        if openFolderID != nil {
            handleFolderScroll(event)
            return
        }

        if event.hasPreciseScrollingDeltas {
            handlePrecisePageScroll(event)
        } else {
            let now = Date()
            guard now.timeIntervalSince(lastWheelFlip) >= Metrics.Durations.pageScrollCooldown else { return }
            let horizontal = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            let delta = horizontal ? event.scrollingDeltaX : event.scrollingDeltaY
            guard abs(delta) > 0.1 else { return }
            lastWheelFlip = now
            if delta < 0 { nextPage() } else { previousPage() }
        }
    }

    private func handlePrecisePageScroll(_ event: NSEvent) {
        // Trackpad momentum keeps sending events after the fingers lift. The
        // page is committed when the gesture ends; letting momentum drag the
        // grid would push it past the neighbouring page and feel continuous.
        guard event.momentumPhase.isEmpty else { return }

        // A new gesture interrupts an in-flight slide by settling the index
        // immediately, so the fresh drag starts from the page now on screen.
        finishPageSnap()

        let phase = event.phase
        let isStart = phase.contains(.began)
        let isEnd = phase.contains(.ended) || phase.contains(.cancelled)

        if isStart {
            scrollAccumulator = 0
            scrollVelocity = 0
            lastScrollTimestamp = 0
            scrollCommitTask?.cancel()
        }

        let deltaX = event.scrollingDeltaX
        let isHorizontal = abs(deltaX) > 0.5
            && abs(deltaX) >= abs(event.scrollingDeltaY) * 0.5
        if isHorizontal {
            registerScrollDelta(deltaX, timestamp: event.timestamp)
            isDraggingPage = true
            scrollAccumulator += deltaX
            pageDrag.offset = boundedPageOffset(scrollAccumulator)
        }

        if isEnd {
            commitScrollPage()
        } else if isHorizontal {
            // Fallback for devices that do not report gesture phases.
            scheduleScrollCommit()
        }
    }

    private func registerScrollDelta(_ delta: CGFloat, timestamp: TimeInterval) {
        if lastScrollTimestamp > 0 {
            let interval = max(timestamp - lastScrollTimestamp, 1.0 / 240.0)
            let instantaneous = delta / CGFloat(interval)
            scrollVelocity = scrollVelocity == 0
                ? instantaneous
                : scrollVelocity * 0.65 + instantaneous * 0.35
        }
        lastScrollTimestamp = timestamp
    }

    private func commitScrollPage() {
        guard isDraggingPage else { return }
        scrollCommitTask?.cancel()
        let velocity = scrollVelocity
        endPageDrag(translation: scrollAccumulator, velocity: velocity)
        scrollVelocity = 0
        lastScrollTimestamp = 0
    }

    private func handleFolderScroll(_ event: NSEvent) {
        guard folderPageCount > 1 else { return }
        if event.hasPreciseScrollingDeltas {
            handlePreciseFolderScroll(event)
        } else {
            let now = Date()
            guard now.timeIntervalSince(lastWheelFlip) >= Metrics.Durations.pageScrollCooldown else { return }
            let horizontal = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            let delta = horizontal ? event.scrollingDeltaX : event.scrollingDeltaY
            guard abs(delta) > 0.1 else { return }
            lastWheelFlip = now
            goToFolderPage(currentFolderPage + (delta < 0 ? 1 : -1))
        }
    }

    private func handlePreciseFolderScroll(_ event: NSEvent) {
        guard event.momentumPhase.isEmpty else { return }

        let phase = event.phase
        let isStart = phase.contains(.began)
        let isEnd = phase.contains(.ended) || phase.contains(.cancelled)

        if isStart {
            folderScrollAccumulator = 0
            folderScrollVelocity = 0
            folderLastScrollTimestamp = 0
            scrollCommitTask?.cancel()
        }

        let deltaX = event.scrollingDeltaX
        let isHorizontal = abs(deltaX) > 0.5
            && abs(deltaX) >= abs(event.scrollingDeltaY) * 0.5
        if isHorizontal {
            registerFolderScrollDelta(deltaX, timestamp: event.timestamp)
            folderScrollAccumulator += deltaX
            folderDrag.offset = PageDragGeometry.boundedOffset(
                translation: folderScrollAccumulator,
                page: currentFolderPage,
                pageCount: folderPageCount,
                width: folderPageWidth
            )
        }

        if isEnd {
            commitFolderScroll()
        } else if isHorizontal {
            scheduleFolderScrollCommit()
        }
    }

    private func registerFolderScrollDelta(_ delta: CGFloat, timestamp: TimeInterval) {
        if folderLastScrollTimestamp > 0 {
            let interval = max(timestamp - folderLastScrollTimestamp, 1.0 / 240.0)
            let instantaneous = delta / CGFloat(interval)
            folderScrollVelocity = folderScrollVelocity == 0
                ? instantaneous
                : folderScrollVelocity * 0.65 + instantaneous * 0.35
        }
        folderLastScrollTimestamp = timestamp
    }

    private func commitFolderScroll() {
        guard folderScrollAccumulator != 0 else { return }
        scrollCommitTask?.cancel()
        endFolderSwipe(
            translation: folderScrollAccumulator,
            predictedTranslation: folderScrollAccumulator + folderScrollVelocity / 4
        )
        folderScrollAccumulator = 0
        folderScrollVelocity = 0
        folderLastScrollTimestamp = 0
    }

    private func scheduleScrollCommit() {
        scrollCommitTask?.cancel()
        scrollCommitTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled, let self else { return }
            self.commitScrollPage()
        }
    }

    private func scheduleFolderScrollCommit() {
        scrollCommitTask?.cancel()
        scrollCommitTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled, let self else { return }
            self.commitFolderScroll()
        }
    }

    // MARK: Keyboard events

    func handleKeyDown(_ event: NSEvent, isTextEditing: Bool) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let characters = event.charactersIgnoringModifiers ?? ""

        if flags.contains(.command) {
            if characters.lowercased() == "q" {
                NSApp.terminate(nil)
                return true
            }
            if characters == "," {
                onRequestPreferences?()
                return true
            }
            if let number = Int(characters), (1...9).contains(number) {
                jumpToPageShortcut(number)
                return true
            }
            return false
        }

        let keyCode = event.keyCode
        switch keyCode {
        case 53: // Escape
            handleEscape()
            return true
        case 36, 76: // Return / keypad Enter
            handleReturn()
            return true
        case 48: // Tab
            if flags.contains(.shift) { previousPage() } else { nextPage() }
            return true
        case 123:
            if isTextEditing && folderTitleEditing { return false }
            moveFocus(.left)
            return true
        case 124:
            if isTextEditing && folderTitleEditing { return false }
            moveFocus(.right)
            return true
        case 125:
            if isTextEditing && folderTitleEditing { return false }
            moveFocus(.down)
            return true
        case 126:
            if isTextEditing && folderTitleEditing { return false }
            moveFocus(.up)
            return true
        case 51: // Delete / Backspace
            if isTextEditing || folderTitleEditing { return false }
            handleDeleteKey()
            return true
        default:
            break
        }

        if isTextEditing {
            // The search field owns printable input; arrows, Return, Esc, and
            // command shortcuts were handled above.
            return false
        }

        if folderTitleEditing {
            // The folder title field owns input even if the field editor has
            // not claimed focus yet (for example during the opening zoom).
            // Falling through to search would close the folder mid-rename.
            return false
        }

        guard let typed = event.characters, !typed.isEmpty else { return false }
        let scalars = typed.unicodeScalars
        let isPrintable = scalars.allSatisfy { scalar in
            scalar.value >= 0x20 && scalar.value != 0x7F
        }
        if isPrintable {
            appendSearchCharacters(typed)
            return true
        }
        return false
    }

    func handleModifierFlags(_ event: NSEvent) {
        if event.modifierFlags.contains(.option), isVisible {
            enterEditMode()
        }
    }

    // MARK: Settings helpers

    func clearIconCache() {
        IconProvider.shared.clear()
    }

    // MARK: Accessibility

    private func observeAccessibility() {
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshAccessibilityState() }
        }
    }

    private func refreshAccessibilityState() {
        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    private func animation(_ kind: AnimationKind) -> Animation? {
        guard !reduceMotion else { return Metrics.Motion.reduced }
        switch kind {
        case .page: return Metrics.Motion.page
        case .folder: return Metrics.Motion.folder
        case .folderClose: return Metrics.Motion.folderClose
        case .reorder: return Metrics.Motion.reorder
        }
    }

    private enum AnimationKind {
        case page, folder, folderClose, reorder
    }

    // MARK: Persistence

    func persist() {
        let snapshot = pages
        Task { [layoutStore] in
            await layoutStore.save(snapshot)
        }
    }

    func persistNow() {
        let snapshot = pages
        Task { [layoutStore] in
            try? await layoutStore.saveImmediately(snapshot)
        }
    }

    /// Captures the current layout on the main actor and starts an off-actor
    /// write that the termination path can await without needing the main
    /// actor, which AppKit blocks while waiting for `terminateLater`.
    func makeFlushTask() -> Task<Void, Never> {
        let snapshot = pages
        let store = layoutStore
        return Task.detached {
            try? await store.saveImmediately(snapshot)
        }
    }

    private func clampPages() {
        currentPage = min(max(currentPage, 0), max(0, pages.count - 1))
        clampSearchPage()
        folderPage = min(max(folderPage, 0), folderPageCount - 1)
        if openFolderID != nil && activeFolder == nil {
            closeFolder(animated: false)
        }
    }

    private func clampPagesAfterMutation() {
        pages.removeAll { $0.isEmpty }
        if pages.isEmpty { pages = [[]] }
        // Compact: move items up to fill gaps (no empty slots)
        var flat = LayoutEngine.flatten(pages)
        let capacity = max(1, settings.pageCapacity)
        pages = LayoutEngine.paginate(flat, capacity: capacity)
        currentPage = min(max(currentPage, 0), pages.count - 1)
    }

    private func cleanupAfterLayoutChange() {
        clampPagesAfterMutation()
        clampSearchPage()
        folderPage = min(max(folderPage, 0), folderPageCount - 1)
        if openFolderID != nil && activeFolder == nil && !folderIsClosing {
            closeFolder(animated: false)
        }
    }

    /// Removes empty pages without repaginating the remaining entries. Used
    /// after a folder drop so unrelated apps never jump across page breaks.
    private func removeEmptyPagesAfterMutation() {
        guard pages.contains(where: { $0.isEmpty }) else {
            currentPage = min(max(currentPage, 0), max(0, pages.count - 1))
            return
        }
        let anchorID = pages.indices.contains(currentPage) ? pages[currentPage].first?.id : nil
        pages.removeAll { $0.isEmpty }
        if pages.isEmpty { pages = [[]] }
        if let anchorID, let location = entryLocation(id: anchorID) {
            currentPage = location.page
        } else {
            currentPage = min(max(currentPage, 0), pages.count - 1)
        }
    }

    /// Presents a folder that was just created. The layout may have been
    /// repaginated after the merge, so use the folder's final page and slot and
    /// switch the visible page when it moved.
    private func revealCreatedFolder(_ folderID: UUID) {
        guard let location = entryLocation(id: "folder:\(folderID.uuidString)") else { return }
        if location.page != currentPage {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                currentPage = location.page
                pageDrag.offset = 0
            }
        }
        let metrics = LayoutMetrics(screenSize: screenSize, settings: settings)
        openNewFolder(folderID: folderID, anchor: metrics.iconFrame(at: location.index))
    }

    private func repaginateForCapacityChange() {
        let flat = LayoutEngine.flatten(pages)
        pages = LayoutEngine.paginate(flat, capacity: settings.pageCapacity)
        currentPage = min(max(currentPage, 0), pages.count - 1)
        if openFolderID != nil {
            folderPage = min(max(folderPage, 0), folderPageCount - 1)
        }
        persist()
    }

    // MARK: Helpers

    /// Whether a drop onto this entry is a valid merge. A full folder cannot
    /// accept another app, so it is treated like empty space instead of
    /// swallowing (and losing) the dragged app.
    private func isMergeableTarget(_ entry: LaunchpadEntry) -> Bool {
        if let folder = entry.folder {
            return folder.apps.count < FolderItem.maximumAppCount
        }
        return entry.app != nil
    }

    private func entry(withID id: String) -> LaunchpadEntry? {
        LayoutEngine.flatten(pages).first { $0.id == id }
    }

    private func entryLocation(id: String) -> (page: Int, index: Int)? {
        for (page, entries) in pages.enumerated() {
            if let index = entries.firstIndex(where: { $0.id == id }) {
                return (page, index)
            }
        }
        return nil
    }
}

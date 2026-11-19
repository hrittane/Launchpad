import SwiftUI

/// Flags that only exist for the development snapshot mode.
enum DebugSnapshot {
    #if DEBUG
    nonisolated static let isEnabled = CommandLine.arguments.contains("--snapshot")

    /// Set only when the window-server capture is unavailable; renders the
    /// interface without `GlassEffectContainer` so it survives `cacheDisplay`.
    @MainActor static var flattenGlass = false
    #else
    nonisolated static let isEnabled = false
    #endif
}

/// The full-screen Launchpad interface: paged grid, folders, search, editing.
struct LaunchpadView: View {
    @Bindable var model: AppModel
    let onDismiss: () -> Void
    let onLaunch: (AppItem) -> Void
    /// Called when the folder sheet starts or stops dimming the grid. The dim
    /// object animates the grid layer and the menu-bar cover together.
    let onFolderObscured: (Bool) -> Void

    /// Shared with the menu-bar cover so both dim layers fade on one clock.
    let folderDim: FolderDim

    @State private var appeared = false
    @State private var dragOffset: CGFloat = 0
    @State private var dragSession: DragSession?
    @State private var folderDrag: FolderDrag?
    @State private var folderPanelFrame: CGRect = .zero
    @State private var edgeDirection = 0
    /// Dwell timer for the drag-to-turn-page gesture. A task (instead of a
    /// timestamp checked on the next pointer event) flips the page even when
    /// the pointer rests motionless in the margin.
    @State private var edgeDwell: Task<Void, Never>?
    /// True while a drag is panning the pages instead of moving an icon.
    @State private var isPageDragging = false
    /// One new page per drag: waiting at the right edge adds it once, so a
    /// pointer parked in the margin cannot trail empty pages behind it.
    @State private var createdPageWhileDragging = false
    /// Debounces the canvas tap: one physical click must only ever take one
    /// step (leave jiggle mode *or* dismiss), never both.
    @State private var lastBackgroundTap: Date = .distantPast
    @FocusState private var isSearchFocused: Bool

    /// Fraction of the screen width a flick must cover before it turns a page.
    private let pageTurnThreshold: CGFloat = 0.16

    private struct DragSession: Equatable {
        var itemID: String
        var location: CGPoint
    }

    /// An app dragged out of the open folder, in canvas coordinates.
    private struct FolderDrag: Equatable {
        var app: AppItem
        var location: CGPoint
    }

    /// True once the pointer leaves the folder panel: the sheet fades and the
    /// grid becomes the drop target.
    private var isDraggingOutOfFolder: Bool {
        guard let folderDrag, folderPanelFrame != .zero else { return false }
        return !folderPanelFrame.contains(folderDrag.location)
    }

    /// The folder sheet dims/blurs the grid behind it, except while an app is
    /// being dragged out — then the grid is the visible drop surface.
    private var isFolderObscuringGrid: Bool {
        model.openFolder != nil && !isDraggingOutOfFolder
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = LaunchpadMetrics(size: proxy.size)
            let pageCount = model.pageCount
            let currentPage = min(model.currentPage, max(pageCount - 1, 0))

            ZStack(alignment: .topLeading) {
                content(metrics: metrics, currentPage: currentPage)
                    .blur(radius: isFolderObscuringGrid ? 26 : 0)
                    .opacity(isFolderObscuringGrid ? 0.82 : 1)
                    .animation(.easeOut(duration: 0.2), value: isFolderObscuringGrid)

                SearchPillView(
                    metrics: metrics,
                    text: $model.searchQuery,
                    isFocused: $isSearchFocused,
                    onSubmit: launchSearchSelection,
                    onTap: { model.requestSearchFocus() }
                )
                .position(
                    x: proxy.size.width / 2,
                    y: metrics.searchTop + metrics.searchHeight / 2
                )

                // Folder dim. It sits above the grid content (icons included)
                // and below the sheet, and is animated by `FolderDim` in the
                // same animation group as the menu-bar cover's share of it, so
                // the two windows cannot disagree about how dark the screen is.
                FolderDimView(dim: folderDim)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .zIndex(1)

                if model.openFolder == nil && !model.isSearching {
                    PageDotsView(
                        pageCount: pageCount,
                        currentPage: currentPage,
                        metrics: metrics,
                        onSelect: { page in
                            withAnimation(.spring(duration: 0.34, bounce: 0.08)) {
                                model.goToPage(page)
                            }
                        }
                    )
                    .position(x: proxy.size.width / 2, y: metrics.dotsCenterY)
                }

                if let folder = model.openFolder {
                    FolderView(
                        folder: folder,
                        apps: folderPreview(metrics: metrics)?.apps ?? model.apps(in: folder),
                        metrics: metrics,
                        isEditing: model.isEditing,
                        draggingAppID: folderDrag?.app.id,
                        isDraggingOut: isDraggingOutOfFolder,
                        promptsForName: model.isPromptingFolderName,
                        onLaunch: onLaunch,
                        onClose: { model.closeFolder() },
                        onRename: { model.renameFolder(folder.id, to: $0) },
                        onNamePromptShown: { model.clearFolderNamePrompt() },
                        onAppDragChanged: { app, location in
                            // Pulling an icon inside the folder switches to
                            // jiggle mode exactly like a grid drag does.
                            if !model.isEditing { model.beginEditing() }
                            // The grid previews the app in its future slot, so
                            // the real tile has to be suppressed there. Grid
                            // drags use the `LauncherItem` id ("app:…"), not the
                            // bundle id, and the preview matches on that.
                            model.draggingID = LauncherItem.app(app.id).id
                            folderDrag = FolderDrag(app: app, location: location)
                        },
                        onAppDragEnded: { app, location in
                            handleFolderDragEnded(
                                app: app,
                                at: location,
                                metrics: metrics
                            )
                        },
                        onPanelFrameChange: { frame in
                            if frame != folderPanelFrame { folderPanelFrame = frame }
                        }
                    )
                    .transition(.opacity)
                    .zIndex(2)
                    // New folder, new sheet state: the draft name and the
                    // entrance animation belong to this folder only.
                    .id(folder.id)
                }

                dragOverlay(metrics: metrics)
                    .zIndex(3)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .coordinateSpace(.named(LaunchpadCanvas.space))
            .scaleEffect(appeared ? 1 : 1.04)
            .opacity(appeared ? 1 : 0)
            .onAppear {
                if !model.catalog.apps.isEmpty { model.reconcile() }
            }
            .onChange(of: model.catalog.apps) { _, apps in
                if !apps.isEmpty { model.reconcile() }
            }
            .onChange(of: model.showCount) { _, _ in
                isSearchFocused = false
            }
            .onChange(of: model.searchFocusRequest) { _, _ in
                isSearchFocused = true
            }
            .onChange(of: model.searchQuery) { _, query in
                model.searchSelection = 0
                if query.isEmpty { isSearchFocused = false }
            }
            .onChange(of: model.isEditing) { _, editing in
                if !editing {
                    dragSession = nil
                    edgeDirection = 0
                    cancelEdgeDwell()
                    createdPageWhileDragging = false
                    model.trimEmptyPages()
                }
            }
            .onChange(of: isFolderObscuringGrid) { _, obscured in
                onFolderObscured(obscured)
            }
        }
        .ignoresSafeArea()
        .task(id: model.showCount) {
            appeared = false
            dragOffset = 0
            dragSession = nil
            folderDrag = nil
            isPageDragging = false
            createdPageWhileDragging = false
            edgeDirection = 0
            cancelEdgeDwell()
            model.trimEmptyPages()
            onFolderObscured(false)
            await Task.yield()
            withAnimation(.spring(duration: 0.42, bounce: 0.06)) {
                appeared = true
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(metrics: LaunchpadMetrics, currentPage: Int) -> some View {
        if model.isSearching {
            SearchResultsView(
                results: Array(model.searchResults.prefix(metrics.pageCapacity)),
                selection: model.searchSelection,
                metrics: metrics,
                onLaunch: onLaunch,
                onBackgroundTap: handleBackgroundTap
            )
        } else {
            pages(metrics: metrics, currentPage: currentPage)
        }
    }

    /// All pages laid out side by side and translated horizontally, so a drag
    /// moves content with the finger and the snap animates the remainder.
    ///
    /// The gesture lives on this container rather than on each tile: a tile that
    /// crosses a page boundary moves into another page's `ForEach`, which would
    /// tear down the gesture halfway through the drag.
    private func pages(metrics: LaunchpadMetrics, currentPage: Int) -> some View {
        let preview = dragPreview(metrics: metrics, page: currentPage)
        let pageItems = preview?.pages ?? model.layout.pages
        let folderTarget = folderTargetID(metrics: metrics, page: currentPage)

        return HStack(spacing: 0) {
            ForEach(pageItems.indices, id: \.self) { page in
                gridLayer(
                    items: pageItems[page],
                    folderTargetID: folderTarget,
                    metrics: metrics
                )
                .frame(width: metrics.size.width, height: metrics.size.height, alignment: .topLeading)
            }
        }
        .frame(width: metrics.size.width * CGFloat(pageItems.count), alignment: .leading)
        .offset(x: -CGFloat(currentPage) * metrics.size.width + dragOffset + model.pageDragOffset)
        .frame(width: metrics.size.width, height: metrics.size.height, alignment: .leading)
        .clipped()
        .contentShape(Rectangle())
        // Simultaneous with the tiles' taps and long press: the drag still has
        // to start here, because a tile-owned gesture dies when the preview
        // moves the tile to another page.
        .simultaneousGesture(canvasGesture(metrics: metrics))
        .animation(.spring(duration: 0.34, bounce: 0.08), value: currentPage)
        // Icons slide aside as the pointer crosses slots, so the grid always
        // shows the gap the drop will fill.
        .animation(.spring(response: 0.26, dampingFraction: 0.82), value: preview)
    }

    /// A reorder in progress: the pages as they look once the dragged item has
    /// landed. Nothing is committed until the drop.
    private struct DragPreview: Equatable {
        var pages: [[LauncherItem]]
    }

    private func dragPreview(metrics: LaunchpadMetrics, page: Int) -> DragPreview? {
        if let session = dragSession {
            return gridDragPreview(session: session, metrics: metrics, page: page)
        }
        return folderDragPreview(metrics: metrics, page: page)
    }

    private func gridDragPreview(
        session: DragSession,
        metrics: LaunchpadMetrics,
        page: Int
    ) -> DragPreview? {
        guard model.items.count > 1,
              let target = dropSlot(at: session.location, metrics: metrics, page: page)
        else { return nil }

        // Hovering another icon (or a folder) with an app means "put it in
        // there": keep the grid still so the target stays under the pointer.
        // Folders can only be reordered, so they always preview the gap.
        let draggedIsApp = model.item(withID: session.itemID).map { !$0.isFolder } ?? false
        if draggedIsApp,
           target.ontoIcon,
           let hovered = model.item(onPage: target.page, offset: target.offset),
           hovered.id != session.itemID {
            return nil
        }

        var preview = model.layout
        guard preview.move(itemID: session.itemID, toPage: target.page, offset: target.offset) else {
            return nil
        }
        return DragPreview(pages: preview.pages)
    }

    /// The grid as it looks while an app is being dragged out of the open
    /// folder: the app has already left the folder (which collapses exactly as
    /// it will on drop) and sits in the slot under the pointer, leaving the
    /// same live gap a grid reorder does.
    private func folderDragPreview(metrics: LaunchpadMetrics, page: Int) -> DragPreview? {
        guard let drag = folderDrag,
              isDraggingOutOfFolder,
              let target = dropSlot(at: drag.location, metrics: metrics, page: page),
              let lifted = model.layoutLiftingAppOutOfFolder(drag.app.id) else { return nil }

        // The lift is previewed from the moment the pointer leaves the panel and
        // never flips back: a two-app folder becomes its survivor (or vanishes)
        // right away, so the tile cannot pulse while the pointer crosses icon
        // centres.
        if target.ontoIcon,
           lifted.item(onPage: target.page, offset: target.offset) != nil {
            // Hovering a tile means "fold it in there": the app is not on the
            // grid at all, so only the lift is shown.
            return DragPreview(pages: lifted.pages)
        }

        var preview = lifted
        preview.insert(.app(drag.app.id), onPage: target.page, offset: target.offset)
        return DragPreview(pages: preview.pages)
    }

    /// The item a dragged app is hovering right now, when dropping there would
    /// create a folder or add to one. The grid stays still in that case, so a
    /// plain slot lookup matches the tile actually under the pointer.
    private func folderTargetID(metrics: LaunchpadMetrics, page: Int) -> String? {
        guard let location = dragSession?.location ?? folderDrag?.location,
              let target = dropSlot(at: location, metrics: metrics, page: page),
              target.ontoIcon,
              let hovered = model.item(onPage: target.page, offset: target.offset)
        else { return nil }

        if let session = dragSession {
            guard let dragged = model.item(withID: session.itemID), !dragged.isFolder,
                  hovered.id != session.itemID else { return nil }
            return hovered.id
        }

        if let drag = folderDrag, isDraggingOutOfFolder {
            // Dropping back on the folder it came from just returns the app.
            guard hovered.folder?.id != model.openFolder?.id,
                  !hovered.appIDs.contains(drag.app.id) else { return nil }
            return hovered.id
        }

        return nil
    }

    /// Icons live in their own glass container so hover plates and folder
    /// morphs can merge later; the pill and dots are independent surfaces, and
    /// positioned children do not lay out correctly inside the container.
    @ViewBuilder
    private func gridLayer(
        items: [LauncherItem],
        folderTargetID: String?,
        metrics: LaunchpadMetrics
    ) -> some View {
        if isFlattenedForSnapshot {
            // `GlassEffectContainer` renders nothing into an offscreen bitmap.
            gridContent(items: items, folderTargetID: folderTargetID, metrics: metrics)
        } else {
            GlassEffectContainer(spacing: 24) {
                gridContent(items: items, folderTargetID: folderTargetID, metrics: metrics)
            }
        }
    }

    private func gridContent(
        items: [LauncherItem],
        folderTargetID: String?,
        metrics: LaunchpadMetrics
    ) -> some View {
        GridPageView(
            items: items,
            metrics: metrics,
            appsByID: model.appsByID,
            isEditing: model.isEditing,
            draggingID: model.draggingID,
            folderTargetID: folderTargetID,
            onBackgroundTap: handleBackgroundTap,
            onLaunch: onLaunch,
            onRemove: { model.uninstall(appID: $0.id) },
            onOpenFolder: { model.openFolder($0) },
            onBeginEditing: { model.beginEditing() }
        )
    }

    private var isFlattenedForSnapshot: Bool {
        #if DEBUG
        return DebugSnapshot.isEnabled && DebugSnapshot.flattenGlass
        #else
        return false
        #endif
    }

    // MARK: - Interaction

    /// Clicking empty canvas steps out one layer at a time, like Launchpad:
    /// first it stops the jiggle, then it closes the panel.
    private func handleBackgroundTap() {
        let now = Date.now
        guard now.timeIntervalSince(lastBackgroundTap) > 0.08 else { return }
        lastBackgroundTap = now

        if model.isEditing {
            model.endEditing()
        } else {
            onDismiss()
        }
    }

    private func launchSearchSelection() {
        if let app = model.selectedSearchResult {
            onLaunch(app)
        }
    }

    // MARK: - Canvas gesture

    /// One drag gesture for the whole grid. It decides once, from where the
    /// press started, whether the drag moves an icon or turns the page.
    ///
    /// Owning the drag here keeps it alive when the dragged icon's preview
    /// crosses into another page: the tile itself leaves its old `ForEach` at
    /// that moment, so a gesture attached to the tile would be cancelled.
    private func canvasGesture(metrics: LaunchpadMetrics) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named(LaunchpadCanvas.space))
            .onChanged { value in
                if dragSession == nil, !isPageDragging {
                    if let itemID = draggableItemID(at: value.startLocation, metrics: metrics) {
                        beginGridDrag(itemID: itemID, at: value.location, metrics: metrics)
                    } else if !model.isEditing, model.openFolder == nil, !model.isSearching {
                        isPageDragging = true
                    } else {
                        return
                    }
                }

                if dragSession != nil {
                    updateGridDrag(at: value.location, metrics: metrics)
                } else if isPageDragging {
                    updatePageDrag(value)
                }
            }
            .onEnded { value in
                if dragSession != nil {
                    finishGridDrag(at: value.location, metrics: metrics)
                } else if isPageDragging {
                    finishPageDrag(value, metrics: metrics)
                }
                isPageDragging = false
            }
    }

    /// The item under a press, when the press is on an icon (not a gap).
    private func draggableItemID(at location: CGPoint, metrics: LaunchpadMetrics) -> String? {
        guard let target = dropSlot(at: location, metrics: metrics, page: model.currentPage),
              target.ontoIcon else { return nil }
        return model.item(onPage: target.page, offset: target.offset)?.id
    }

    private func updatePageDrag(_ value: DragGesture.Value) {
        guard abs(value.translation.width) >= abs(value.translation.height) else { return }
        var translation = value.translation.width
        let currentPage = model.currentPage
        let isPullingPastFirst = currentPage == 0 && translation > 0
        let isPullingPastLast = currentPage == model.pageCount - 1 && translation < 0
        if isPullingPastFirst || isPullingPastLast {
            // Rubber band at the ends instead of a hard stop.
            translation /= 3
        }
        dragOffset = translation
    }

    private func finishPageDrag(_ value: DragGesture.Value, metrics: LaunchpadMetrics) {
        guard !model.isEditing, model.openFolder == nil else {
            dragOffset = 0
            return
        }
        let projected = value.predictedEndTranslation.width
        let threshold = metrics.size.width * pageTurnThreshold
        var target = model.currentPage
        if projected <= -threshold {
            target += 1
        } else if projected >= threshold {
            target -= 1
        }
        target = min(max(target, 0), model.pageCount - 1)
        withAnimation(.spring(duration: 0.34, bounce: 0.08)) {
            dragOffset = 0
            model.goToPage(target)
        }
    }

    // MARK: - Dragging

    private func beginGridDrag(itemID: String, at location: CGPoint, metrics: LaunchpadMetrics) {
        // Pulling an icon out of the grid switches Launchpad into jiggle mode
        // immediately, so the rest of the page wiggles while the drag is in
        // flight. Reordering, folder creation and adding to a folder all keep
        // working in that state.
        if !model.isEditing { model.beginEditing() }
        createdPageWhileDragging = false
        edgeDirection = 0
        cancelEdgeDwell()
        dragSession = DragSession(itemID: itemID, location: location)
        model.draggingID = itemID
        handleEdgeDrag(at: location, metrics: metrics)
    }

    private func updateGridDrag(at location: CGPoint, metrics: LaunchpadMetrics) {
        guard var session = dragSession else { return }
        session.location = location
        dragSession = session
        model.draggingID = session.itemID
        handleEdgeDrag(at: location, metrics: metrics)
    }

    private func finishGridDrag(at location: CGPoint, metrics: LaunchpadMetrics) {
        defer {
            dragSession = nil
            model.draggingID = nil
            edgeDirection = 0
            cancelEdgeDwell()
            createdPageWhileDragging = false
        }
        guard let session = dragSession else { return }
        guard let target = dropSlot(at: location, metrics: metrics, page: model.currentPage) else {
            model.trimEmptyPages()
            return
        }
        model.performDrop(
            itemID: session.itemID,
            page: target.page,
            offset: target.offset,
            ontoIcon: target.ontoIcon
        )
        model.trimEmptyPages()
    }

    /// Ends a drag that started inside the open folder. Dropping back on the
    /// panel reorders the folder's apps; dropping outside it acts exactly like
    /// a grid drag: another app or folder folds the app into a folder, and any
    /// other slot simply reorders the grid.
    private func handleFolderDragEnded(
        app: AppItem,
        at location: CGPoint,
        metrics: LaunchpadMetrics
    ) {
        defer {
            folderDrag = nil
            model.draggingID = nil
        }
        guard folderPanelFrame != .zero else { return }

        if folderPanelFrame.contains(location) {
            guard let folder = model.openFolder,
                  let slot = folderSlot(at: location, metrics: metrics) else { return }
            model.moveApp(inFolder: folder.id, appID: app.id, toIndex: slot)
            return
        }

        guard let target = dropSlot(at: location, metrics: metrics, page: model.currentPage) else {
            return
        }
        // Only an icon is a folder target; a gap between icons is a plain
        // reorder even when the nearest slot happens to hold an app.
        let hovered = target.ontoIcon
            ? model.item(onPage: target.page, offset: target.offset)
            : nil

        // Dropping on the folder it came from just returns the app: the sheet
        // fades back in unchanged.
        if hovered?.folder?.id == model.openFolder?.id { return }

        // A drop that creates a folder leaves that folder open for naming; the
        // source sheet is only closed when nothing new was opened.
        if model.dropAppFromFolder(
            appID: app.id,
            page: target.page,
            offset: target.offset,
            onto: hovered
        ) == nil {
            model.closeFolder()
        }
    }

    /// The folder's app order as it would look if the app under the pointer
    /// landed in the slot it hovers. Icons slide aside and leave the live gap
    /// the drop will fill, with nothing written until the drag ends.
    private func folderPreview(metrics: LaunchpadMetrics) -> (apps: [AppItem], slot: Int)? {
        guard let drag = folderDrag,
              let folder = model.openFolder,
              let slot = folderSlot(at: drag.location, metrics: metrics) else { return nil }

        let apps = model.apps(in: folder)
        guard apps.count > 1,
              let from = apps.firstIndex(where: { $0.id == drag.app.id }) else { return nil }
        let target = min(max(slot, 0), apps.count - 1)
        guard target != from else { return nil }

        var reordered = apps
        let moved = reordered.remove(at: from)
        reordered.insert(moved, at: target)
        return (reordered, target)
    }

    /// Slot index inside the folder panel under `location`, or nil when the
    /// pointer is outside the panel's grid.
    private func folderSlot(at location: CGPoint, metrics: LaunchpadMetrics) -> Int? {
        guard folderPanelFrame != .zero, folderPanelFrame.contains(location) else { return nil }
        let local = CGPoint(
            x: location.x - folderPanelFrame.minX,
            y: location.y - folderPanelFrame.minY
        )
        let columnPitch = metrics.folderPanelWidth / CGFloat(metrics.folderColumns)
        let rowPitch = (metrics.folderPanelHeight - metrics.folderGridTop - metrics.folderGridBottom)
            / CGFloat(metrics.folderRows)
        guard columnPitch > 0, rowPitch > 0 else { return nil }

        let column = Int((local.x / columnPitch).rounded(.down))
        let row = Int(((local.y - metrics.folderGridTop) / rowPitch).rounded(.down))
        guard (0..<metrics.folderColumns).contains(column),
              (0..<metrics.folderRows).contains(row) else { return nil }
        return row * metrics.folderColumns + column
    }

    /// Switches pages when the dragged icon rests near the left or right edge.
    private func handleEdgeDrag(at location: CGPoint, metrics: LaunchpadMetrics) {
        let width = metrics.size.width
        let direction: Int
        if location.x < width * 0.05 {
            direction = -1
        } else if location.x > width * 0.95 {
            direction = 1
        } else {
            direction = 0
        }

        guard direction != 0 else {
            edgeDirection = 0
            cancelEdgeDwell()
            return
        }

        // Still in the same margin: the running dwell keeps counting, so a
        // pointer that arrives and stops flips the page without needing one
        // more movement event.
        guard direction != edgeDirection else { return }
        edgeDirection = direction
        armEdgeDwell(direction: direction)
    }

    /// Waits out the dwell time at an edge, then turns one page and waits
    /// again while the pointer stays there. Creating a page happens only once
    /// per drag.
    private func armEdgeDwell(direction: Int) {
        cancelEdgeDwell()
        edgeDwell = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(550))
                guard !Task.isCancelled,
                      dragSession != nil,
                      edgeDirection == direction else { return }
                guard flipPageForDrag(direction: direction) else { return }
            }
        }
    }

    /// @discardableResult: whether the drag actually moved to another page.
    @discardableResult
    private func flipPageForDrag(direction: Int) -> Bool {
        // Waiting at the right edge of the last page creates a page to drop
        // onto, even when it will end up holding a single icon.
        if direction > 0, model.currentPage == model.pageCount - 1 {
            guard !createdPageWhileDragging else { return false }
            model.addPageForDragging()
            createdPageWhileDragging = true
            return true
        }

        let before = model.currentPage
        model.stepPage(by: direction)
        return model.currentPage != before
    }

    private func cancelEdgeDwell() {
        edgeDwell?.cancel()
        edgeDwell = nil
    }

    /// Nearest grid slot to a point, and whether the point is on the icon
    /// itself (dropping there creates a folder instead of a reorder).
    private func dropSlot(
        at location: CGPoint,
        metrics: LaunchpadMetrics,
        page: Int
    ) -> (page: Int, offset: Int, ontoIcon: Bool)? {
        let column = Int(((location.x - metrics.columnX(0)) / metrics.columnPitch).rounded())
        let firstCenterY = metrics.gridTop + metrics.iconSize / 2
        let row = Int(((location.y - firstCenterY) / metrics.rowPitch).rounded())

        // Rows stay strict, but a pointer in the left/right margin snaps to the
        // nearest column: releasing there after a page flip still drops the
        // icon on the page that just slid in.
        guard (0..<metrics.rows).contains(row) else { return nil }
        let targetColumn = min(max(column, 0), metrics.columns - 1)

        let offset = row * metrics.columns + targetColumn
        let dx = location.x - metrics.columnX(targetColumn)
        let dy = location.y - (firstCenterY + CGFloat(row) * metrics.rowPitch)
        let ontoIcon = (dx * dx + dy * dy).squareRoot() < metrics.iconSize * 0.72
        return (page, offset, ontoIcon)
    }

    // MARK: - Drag overlay

    @ViewBuilder
    private func dragOverlay(metrics: LaunchpadMetrics) -> some View {
        // The dragged icon follows the pointer at full size for the whole
        // gesture, over folders too. It is not shrunk or faded into the
        // hover plate: the app only becomes a miniature when the mouse is
        // released and the drop is committed.
        ZStack(alignment: .topLeading) {
            if let session = dragSession, let item = model.item(withID: session.itemID) {
                draggedTile(item: item, metrics: metrics)
                    .shadow(color: .black.opacity(0.38), radius: 18, y: 9)
                    .position(session.location)
            } else if let drag = folderDrag {
                AppIconImage(
                    item: drag.app,
                    size: folderPanelFrame.contains(drag.location)
                        ? metrics.folderIconSize
                        : metrics.iconSize,
                    artworkScale: metrics.iconArtworkScale
                )
                .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
                .scaleEffect(1.12)
                .position(drag.location)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func draggedTile(item: LauncherItem, metrics: LaunchpadMetrics) -> some View {
        switch item {
        case .app(let appID):
            if let app = model.app(appID) {
                AppIconImage(item: app, size: metrics.iconSize, artworkScale: metrics.iconArtworkScale)
                    .scaleEffect(1.12)
            }
        case .folder(let folder):
            // A lifted folder is bigger than an app tile and, unlike an app
            // icon, is glass: it is drawn at its final size instead of being
            // scaled, because the hoisted glass ignores `scaleEffect` and would
            // otherwise stay at 1× under a shrunken set of miniatures.
            FolderPlate(
                apps: folder.appIDs.compactMap { model.appsByID[$0] },
                size: metrics.iconSize * FolderPlate.liftScale,
                artworkScale: metrics.iconArtworkScale
            )
        }
    }
}

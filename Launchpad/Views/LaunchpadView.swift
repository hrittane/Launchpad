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

    @State private var appeared = false
    @State private var dragOffset: CGFloat = 0
    @State private var dragSession: DragSession?
    @State private var folderDrag: FolderDrag?
    @State private var folderPanelFrame: CGRect = .zero
    @State private var edgeDirection = 0
    @State private var edgeStartedAt: Date?
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
                        onLaunch: onLaunch,
                        onClose: { model.closeFolder() },
                        onRename: { model.renameFolder(folder.id, to: $0) },
                        onAppDragChanged: { app, location in
                            // Pulling an icon inside the folder switches to
                            // jiggle mode exactly like a grid drag does.
                            if !model.isEditing { model.beginEditing() }
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
                }

                dragOverlay(metrics: metrics, currentPage: currentPage)
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
                    edgeStartedAt = nil
                }
            }
        }
        .ignoresSafeArea()
        .task(id: model.showCount) {
            appeared = false
            dragOffset = 0
            dragSession = nil
            folderDrag = nil
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
    private func pages(metrics: LaunchpadMetrics, currentPage: Int) -> some View {
        let pageCount = model.pageCount
        let preview = dragPreview(metrics: metrics, page: currentPage)
        let items = preview?.items ?? model.items
        let folderTarget = folderTargetID(metrics: metrics, page: currentPage)

        return HStack(spacing: 0) {
            ForEach(0..<pageCount, id: \.self) { page in
                gridLayer(
                    items: pageSlice(items, page: page, metrics: metrics),
                    folderTargetID: folderTarget,
                    metrics: metrics
                )
                .frame(width: metrics.size.width, height: metrics.size.height, alignment: .topLeading)
            }
        }
        .frame(width: metrics.size.width * CGFloat(pageCount), alignment: .leading)
        .offset(x: -CGFloat(currentPage) * metrics.size.width + dragOffset)
        .frame(width: metrics.size.width, height: metrics.size.height, alignment: .leading)
        .clipped()
        .contentShape(Rectangle())
        .gesture(swipeGesture(metrics: metrics, currentPage: currentPage))
        .animation(.spring(duration: 0.34, bounce: 0.08), value: currentPage)
        // Icons slide aside as the pointer crosses slots, so the grid always
        // shows the gap the drop will fill.
        .animation(.spring(response: 0.26, dampingFraction: 0.82), value: preview?.slot)
    }

    /// A reorder in progress: the whole grid re-ordered as if the dragged item
    /// had already landed in `slot`. Nothing is committed until the drop.
    private struct DragPreview: Equatable {
        var slot: Int
        var items: [LauncherItem]
    }

    private func dragPreview(metrics: LaunchpadMetrics, page: Int) -> DragPreview? {
        guard let session = dragSession,
              model.items.count > 1,
              let target = dropSlot(at: session.location, metrics: metrics, page: page)
        else { return nil }

        // Hovering another icon (or a folder) with an app means "put it in
        // there": keep the grid still so the target stays under the pointer.
        // Folders can only be reordered, so they always preview the gap.
        let draggedIsApp = model.item(withID: session.itemID).map { !$0.isFolder } ?? false
        if draggedIsApp,
           target.ontoIcon,
           let hovered = model.item(atSlot: target.index),
           hovered.id != session.itemID {
            return nil
        }

        let slot = min(max(target.index, 0), model.items.count - 1)
        guard let from = model.items.firstIndex(where: { $0.id == session.itemID }),
              slot != from else { return nil }

        var items = model.items
        let moved = items.remove(at: from)
        items.insert(moved, at: slot)
        return DragPreview(slot: slot, items: items)
    }

    /// The item a dragged app is hovering right now, when dropping there would
    /// create a folder or add to one. The grid stays still in that case, so a
    /// plain index lookup matches the tile actually under the pointer.
    private func folderTargetID(metrics: LaunchpadMetrics, page: Int) -> String? {
        guard let session = dragSession,
              let dragged = model.item(withID: session.itemID),
              !dragged.isFolder,
              let target = dropSlot(at: session.location, metrics: metrics, page: page),
              target.ontoIcon,
              let hovered = model.item(atSlot: target.index),
              hovered.id != session.itemID
        else { return nil }
        return hovered.id
    }

    private func pageSlice(
        _ items: [LauncherItem],
        page: Int,
        metrics: LaunchpadMetrics
    ) -> [LauncherItem] {
        let start = page * metrics.pageCapacity
        guard start < items.count else { return [] }
        let end = min(start + metrics.pageCapacity, items.count)
        return Array(items[start..<end])
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
            onBeginEditing: { model.beginEditing() },
            onDragChanged: { itemID, location in
                handleDragChanged(itemID: itemID, at: location, metrics: metrics)
            },
            onDragEnded: { itemID, location in
                handleDragEnded(itemID: itemID, at: location, metrics: metrics)
            }
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

    private func swipeGesture(metrics: LaunchpadMetrics, currentPage: Int) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard !model.isEditing, model.openFolder == nil else { return }
                guard abs(value.translation.width) >= abs(value.translation.height) else { return }
                var translation = value.translation.width
                let isPullingPastFirst = currentPage == 0 && translation > 0
                let isPullingPastLast = currentPage == model.pageCount - 1 && translation < 0
                if isPullingPastFirst || isPullingPastLast {
                    // Rubber band at the ends instead of a hard stop.
                    translation /= 3
                }
                dragOffset = translation
            }
            .onEnded { value in
                guard !model.isEditing, model.openFolder == nil else {
                    dragOffset = 0
                    return
                }
                let projected = value.predictedEndTranslation.width
                let threshold = metrics.size.width * pageTurnThreshold
                var target = currentPage
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
    }

    // MARK: - Dragging

    private func handleDragChanged(itemID: String, at location: CGPoint, metrics: LaunchpadMetrics) {
        // Pulling an icon out of the grid switches Launchpad into jiggle mode
        // immediately, so the rest of the page wiggles while the drag is in
        // flight. Reordering, folder creation and adding to a folder all keep
        // working in that state.
        if !model.isEditing { model.beginEditing() }
        dragSession = DragSession(itemID: itemID, location: location)
        model.draggingID = itemID
        handleEdgeDrag(at: location, metrics: metrics)
    }

    private func handleDragEnded(itemID: String, at location: CGPoint, metrics: LaunchpadMetrics) {
        defer {
            dragSession = nil
            model.draggingID = nil
            edgeDirection = 0
            edgeStartedAt = nil
        }
        guard model.items.count > 0 else { return }
        guard let target = dropSlot(at: location, metrics: metrics, page: model.currentPage) else {
            return
        }
        let slot = min(max(target.index, 0), model.items.count - 1)
        model.performDrop(itemID: itemID, slot: slot, ontoIcon: target.ontoIcon)
    }

    /// Ends a drag that started inside the open folder. Dropping back on the
    /// panel reorders the folder's apps; dropping outside it moves the app onto
    /// the grid at the nearest slot and closes the folder.
    private func handleFolderDragEnded(
        app: AppItem,
        at location: CGPoint,
        metrics: LaunchpadMetrics
    ) {
        defer { folderDrag = nil }
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
        let slot = min(max(target.index, 0), max(model.items.count - 1, 0))
        model.moveAppOutOfFolder(appID: app.id, toSlot: slot)
        model.closeFolder()
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
            edgeStartedAt = nil
            return
        }

        guard direction == edgeDirection else {
            edgeDirection = direction
            edgeStartedAt = .now
            return
        }
        guard let started = edgeStartedAt, Date.now.timeIntervalSince(started) > 0.55 else { return }

        let before = model.currentPage
        model.stepPage(by: direction)
        edgeStartedAt = model.currentPage == before ? nil : .now
    }

    /// Nearest grid slot to a point, and whether the point is on the icon
    /// itself (dropping there creates a folder instead of a reorder).
    private func dropSlot(
        at location: CGPoint,
        metrics: LaunchpadMetrics,
        page: Int
    ) -> (index: Int, ontoIcon: Bool)? {
        let column = Int(((location.x - metrics.columnX(0)) / metrics.columnPitch).rounded())
        let firstCenterY = metrics.gridTop + metrics.iconSize / 2
        let row = Int(((location.y - firstCenterY) / metrics.rowPitch).rounded())

        guard (0..<metrics.columns).contains(column),
              (0..<metrics.rows).contains(row) else { return nil }

        let index = page * metrics.pageCapacity + row * metrics.columns + column
        let dx = location.x - metrics.columnX(column)
        let dy = location.y - (firstCenterY + CGFloat(row) * metrics.rowPitch)
        let ontoIcon = (dx * dx + dy * dy).squareRoot() < metrics.iconSize * 0.72
        return (index, ontoIcon)
    }

    // MARK: - Drag overlay

    @ViewBuilder
    private func dragOverlay(metrics: LaunchpadMetrics, currentPage: Int) -> some View {
        ZStack(alignment: .topLeading) {
            if let target = dropIndicator(metrics: metrics, currentPage: currentPage) {
                RoundedRectangle(cornerRadius: metrics.iconSize * 0.26, style: .continuous)
                    .strokeBorder(
                        .white.opacity(0.5),
                        style: StrokeStyle(lineWidth: 2, dash: [6, 5])
                    )
                    .frame(width: metrics.iconSize + 18, height: metrics.iconSize + 18)
                    .position(
                        x: metrics.columnX(target % metrics.columns),
                        y: metrics.rowTop(target / metrics.columns) + metrics.iconSize / 2
                    )
            }

            if let session = dragSession, let item = model.item(withID: session.itemID) {
                draggedTile(item: item, metrics: metrics)
                    .scaleEffect(1.12)
                    .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
                    .position(session.location)
            } else if let drag = folderDrag {
                AppIconImage(
                    item: drag.app,
                    size: folderPanelFrame.contains(drag.location)
                        ? metrics.folderIconSize
                        : metrics.iconSize,
                    artworkScale: metrics.iconArtworkScale
                )
                .scaleEffect(1.12)
                .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
                .position(drag.location)
            }
        }
        .allowsHitTesting(false)
    }

    /// Grid-local slot of the folder drag-out drop target, or nil.
    ///
    /// Plain reorders draw no marker at all: the live preview already opens a
    /// gap under the pointer, so a highlight would just sit on top of an icon.
    private func dropIndicator(metrics: LaunchpadMetrics, currentPage: Int) -> Int? {
        guard let drag = folderDrag, isDraggingOutOfFolder,
              let target = dropSlot(at: drag.location, metrics: metrics, page: currentPage)
        else { return nil }
        let clamped = min(target.index, max(model.items.count - 1, 0))
        return localSlot(clamped, metrics: metrics, currentPage: currentPage)
    }

    private func localSlot(
        _ index: Int,
        metrics: LaunchpadMetrics,
        currentPage: Int
    ) -> Int? {
        let local = index - currentPage * metrics.pageCapacity
        guard local >= 0, local < metrics.pageCapacity else { return nil }
        return local
    }

    @ViewBuilder
    private func draggedTile(item: LauncherItem, metrics: LaunchpadMetrics) -> some View {
        switch item {
        case .app(let appID):
            if let app = model.app(appID) {
                AppIconImage(item: app, size: metrics.iconSize, artworkScale: metrics.iconArtworkScale)
            }
        case .folder(let folder):
            ZStack {
                RoundedRectangle(cornerRadius: metrics.iconSize * 0.225, style: .continuous)
                    .fill(.white.opacity(0.16))
                    .glassEffect(
                        .regular,
                        in: RoundedRectangle(
                            cornerRadius: metrics.iconSize * 0.225,
                            style: .continuous
                        )
                    )
                    .frame(width: metrics.iconSize, height: metrics.iconSize)

                FolderMiniGrid(
                    apps: folder.appIDs.compactMap { model.appsByID[$0] },
                    tileSize: metrics.iconSize,
                    artworkScale: metrics.iconArtworkScale
                )
            }
        }
    }
}

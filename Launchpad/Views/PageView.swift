import SwiftUI

/// One page of the main grid. Only the current page and its immediate
/// neighbors are instantiated by `LaunchpadRootView`, which keeps large
/// libraries cheap to render.
struct PageView: View {
    @ObservedObject var viewModel: LaunchpadViewModel
    let pageIndex: Int
    let entries: PageLayout
    let metrics: LayoutMetrics
    let isInteractive: Bool
    let recordsFrames: Bool

    /// Shared half-cycle for the edit-mode wiggle. A single clock for the page
    /// keeps tiles in sync no matter when their views were inserted.
    @State private var jigglePhase = false

    /// The wiggle only runs on the page the user is looking at.
    private var jiggleActive: Bool {
        viewModel.isEditing
            && !viewModel.reduceMotion
            && pageIndex == viewModel.currentDisplayedPage
            && isInteractive
    }

    /// Pause the clock during a drag. The pose stays where it is, but the grid
    /// no longer re-renders under the pointer while a gesture is in flight.
    private var jiggleClockActive: Bool {
        jiggleActive && viewModel.dragSession == nil && viewModel.folderDragSession == nil
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                // Position from the projected reorder layout, but keep this
                // view in its source page so the in-flight drag gesture keeps
                // its identity. When an entry is projected onto another page,
                // shift it by whole page widths instead of moving the view.
                //
                // The drag source is deliberately pinned to its original slot.
                // Moving the view that owns an active DragGesture can make
                // SwiftUI stop delivering pointer updates (the classic "drag
                // freezes mid-move"), and the source is invisible during the
                // drag anyway. When the folder preview appears the reorder
                // preview is dropped, which used to yank the source view back
                // under the cursor at the worst possible moment.
                let isDragSource = viewModel.dragSession?.entry.id == entry.id
                let projected = isDragSource ? nil : viewModel.reorderPreview?.locations[entry.id]
                let slot = projected?.index ?? index
                let cell = metrics.cellRect(at: slot)
                let pageDelta = (projected?.page ?? pageIndex) - pageIndex
                let x = cell.midX + CGFloat(pageDelta) * metrics.screenSize.width

                ItemIconView(
                    entry: entry,
                    iconSize: metrics.iconSize,
                    labelFontSize: metrics.labelFontSize,
                    labelMaxWidth: max(1, metrics.cellWidth - 8 * metrics.scale),
                    scale: metrics.scale,
                    isEditing: viewModel.isEditing,
                    isFocused: viewModel.focusedEntryID == entry.id,
                    isMergeTarget: viewModel.dragSession?.mergeHighlightID == entry.id,
                    isMergeArmed: viewModel.dragSession?.armedMergeTargetID == entry.id,
                    mergePreviewApps: viewModel.mergePreviewApps(for: entry),
                    jiggleActive: jiggleActive,
                    jigglePhase: jigglePhase,
                    isDragSource: isDragSource,
                    reduceMotion: viewModel.reduceMotion,
                    showDeleteBadge: entry.app?.isDeletable == true,
                    showIconShadow: viewModel.settings.showIconShadow,
                    recordsFrame: recordsFrames,
                    onTap: {
                        if let folder = entry.folder {
                            let frame = metrics.iconFrame(at: slot)
                            viewModel.openFolder(folder, anchor: frame)
                        } else {
                            viewModel.activate(entry)
                        }
                    },
                    onDelete: {
                        if let app = entry.app { viewModel.requestDelete(app) }
                    },
                    onLongPress: {
                        viewModel.enterEditMode()
                    },
                    onDragBegan: {
                        viewModel.beginDrag(entry: entry, page: pageIndex, index: index)
                    },
                    onDragChanged: { location in
                        viewModel.updateDrag(location: location)
                    },
                    onDragEnded: {
                        viewModel.endDrag()
                    },
                    onContextAction: { action in
                        handle(action, for: entry)
                    },
                    onDoubleTap: entry.isFolder
                        ? {
                            let frame = metrics.iconFrame(at: slot)
                            viewModel.openFolder(folderID: entry.folder!.id, anchor: frame)
                            viewModel.beginFolderRename()
                        }
                        : nil
                )
                .frame(width: metrics.cellWidth, height: metrics.cellHeight)
                .position(x: x, y: cell.midY)
                .opacity(isDragSource ? 0 : 1)
                // Keep hit testing enabled on the drag source. Disabling it
                // after the gesture has started can cancel the in-flight
                // drag on the next grid update, which froze the floating icon
                // mid-move. The source is invisible and the preview layer is
                // non-interactive, so it only keeps feeding pointer updates.
                .transition(.scale(scale: 0.88).combined(with: .opacity))
                // The view model already wraps every preview change in
                // `withAnimation`; this is a second net for slot changes so a
                // displaced tile always interpolates, never snaps.
                .animation(reorderAnimation, value: slot)
            }
        }
        .task(id: jiggleClockActive) {
            // Flip a shared phase instead of using a per-tile repeating
            // animation. A tile that comes back into the hierarchy (for example
            // an app dropped out of a folder) keeps its old `@State` and loses
            // the running animation, so it used to land frozen at one angle.
            // A value owned by the page reaches every tile on the next tick.
            guard jiggleActive else {
                jigglePhase = false
                return
            }
            guard jiggleClockActive else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Metrics.Durations.jiggle))
                guard !Task.isCancelled, jiggleClockActive else { return }
                jigglePhase.toggle()
            }
        }
    }

    private var reorderAnimation: Animation? {
        if viewModel.reduceMotion { return Metrics.Motion.reduced }
        if viewModel.dragSession != nil { return Metrics.Motion.dragReorder }
        return Metrics.Motion.reorder
    }

    private func handle(_ action: ItemContextAction, for entry: LaunchpadEntry) {
        switch action {
        case .open:
            viewModel.activate(entry)
        case .showInFinder:
            if let app = entry.app { viewModel.showInFinder(app) }
        case .getInfo:
            if let app = entry.app { viewModel.showInfo(app) }
        case .removeFolder(let id):
            viewModel.removeFolder(folderID: id)
        case .renameFolder(let id):
            let projected = viewModel.reorderPreview?.locations[entry.id]
            let slot = projected?.index ?? (entries.firstIndex(where: { $0.id == entry.id }) ?? 0)
            let frame = metrics.iconFrame(at: slot)
            viewModel.openFolder(folderID: id, anchor: frame)
            viewModel.beginFolderRename()
        }
    }
}

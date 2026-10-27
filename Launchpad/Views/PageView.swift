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

    private struct DragPreviewLayout {
        var slots: [String: Int]
        var insertionSlot: Int?
    }

    @State private var hasShownOnce = false
    /// Trigger the first appearance transition when the app shows and the view
    /// is first laid out. Without this, the first show can skip the zoom if the
    /// view appeared before `isVisible` changed.
    @State private var readyForShow = false

    private var tileScale: CGFloat {
        if viewModel.reduceMotion { return 1 }
        if viewModel.isVisible {
            return 1
        }
        return hasShownOnce ? 1.06 : 1.14
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                let preview = dragPreview
                let slot = preview?.slots[entry.id] ?? index
                let cell = metrics.cellRect(at: slot)
                let isDragSource = viewModel.dragSession?.entry.id == entry.id

                ItemIconView(
                    entry: entry,
                    iconSize: metrics.iconSize,
                    labelFontSize: metrics.labelFontSize,
                    labelMaxWidth: max(1, metrics.cellWidth - 8 * metrics.scale),
                    scale: metrics.scale,
                    isEditing: viewModel.isEditing,
                    isFocused: viewModel.focusedEntryID == entry.id,
                    isMergeTarget: viewModel.dragSession?.armedMergeTargetID == entry.id,
                    reduceMotion: viewModel.reduceMotion,
                    showDeleteBadge: entry.app?.isDeletable == true,
                    recordsFrame: recordsFrames,
                    onTap: {
                        viewModel.activate(entry)
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
                            viewModel.activate(entry)
                            viewModel.beginFolderRename()
                        }
                        : nil
                )
                .frame(width: metrics.cellWidth, height: metrics.cellHeight)
                .position(x: cell.midX, y: cell.midY)
                .opacity(1.0)
                .scaleEffect(isDragSource ? 1.12 : (viewModel.dragSession?.armedMergeTargetID == entry.id ? 1.15 : tileScale))
                .shadow(color: .black.opacity(isDragSource ? 0.4 : 0), radius: isDragSource ? 14 : 0)
                .animation(.easeOut(duration: 0.12), value: isDragSource)
                .animation(.easeOut(duration: 0.18), value: viewModel.dragSession?.armedMergeTargetID)
                .animation(visibilityAnimation(row: slot / max(1, metrics.columns)), value: viewModel.isVisible)
                .animation(reorderAnimation, value: slot)
                .animation(Metrics.Motion.hover, value: isDragSource)
                .animation(.easeInOut(duration: 0.15), value: viewModel.dragSession?.hoveredEntryID)
            }

            if let preview = dragPreview, let insertion = preview.insertionSlot {
                // Removed drag placeholder highlight per user request
            }
        }
        .onAppear {
            if viewModel.isVisible {
                hasShownOnce = true
                readyForShow = true
            }
        }
        .onChange(of: viewModel.isVisible) { visible in
            if visible {
                hasShownOnce = true
                readyForShow = true
            }
        }
    }

    private func opacity(for isDragSource: Bool) -> Double {
        guard viewModel.isVisible else { return 0 }
        return 1 // keep others visible for tight packing
    }

    private var tileOpacity: Double {
        if viewModel.reduceMotion { return 1 }
        guard !viewModel.isVisible else { return 1 }
        return hasShownOnce ? 0.7 : 0.4
    }

    private var reorderAnimation: Animation? {
        guard let session = viewModel.dragSession else { return viewModel.reduceMotion ? Metrics.Motion.reduced : .spring(response: 0.22, dampingFraction: 0.9) }
        if session.armedMergeTargetID != nil { return nil }
        if session.mergeCandidateID != nil { return nil }
        // Keep layout tight with no gaps
        return viewModel.reduceMotion ? Metrics.Motion.reduced : .spring(response: 0.22, dampingFraction: 0.92)
    }

    private func visibilityAnimation(row: Int) -> Animation? {
        if viewModel.reduceMotion { return Metrics.Motion.reduced }
        if viewModel.isVisible {
            let delay = min(Double(row) * Metrics.Durations.showStagger, Metrics.Durations.showStaggerMax)
            return Metrics.Motion.showIcons.delay(delay)
        }
        return .easeIn(duration: Metrics.Durations.hideIcons)
    }

    /// Slots used for the live reorder preview. A folder target or an armed
    /// folder-merge intentionally shows no reflow because the drop will not
    /// insert on the grid.
    private var dragPreview: DragPreviewLayout? {
        guard isInteractive,
              let session = viewModel.dragSession,
              pageIndex == viewModel.currentDisplayedPage,
              session.isOverFolder == false,
              session.armedMergeTargetID == nil,
              session.mergeCandidateID == nil else { return nil }

        let remaining = entries.filter { $0.id != session.entry.id }
        let capacity = max(1, metrics.columns * metrics.rows)
        guard remaining.count < capacity else { return nil }

        var insertion: Int = remaining.count
        if let hoveredID = session.hoveredEntryID,
           let hoveredIndex = remaining.firstIndex(where: { $0.id == hoveredID }) {
            insertion = hoveredIndex
        } else if let slot = metrics.slot(at: session.location) {
            insertion = min(max(slot, 0), remaining.count)
        }

        var slots: [String: Int] = [:]
        for (index, entry) in remaining.enumerated() {
            slots[entry.id] = index < insertion ? index : index
        }
        return DragPreviewLayout(slots: slots, insertionSlot: nil)
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
            viewModel.openFolder(folderID: id, anchor: viewModel.iconFrames[entry.id] ?? .zero)
            viewModel.beginFolderRename()
        }
    }
}

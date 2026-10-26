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

    private var tileScale: CGFloat {
        guard !viewModel.isVisible else { return 1 }
        // Launchpad's show animation starts slightly larger (1.12) than the
        // hide animation ends (1.08), so track whether this page has been
        // shown once to pick the right resting scale.
        return hasShownOnce ? 1.08 : 1.12
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
                .opacity(opacity(for: isDragSource))
                .scaleEffect(tileScale)
                .animation(visibilityAnimation(row: slot / max(1, metrics.columns)), value: viewModel.isVisible)
                .animation(reorderAnimation, value: slot)
                .animation(Metrics.Motion.hover, value: isDragSource)
            }

            if let preview = dragPreview, let insertion = preview.insertionSlot {
                let frame = metrics.iconFrame(at: insertion)
                RoundedRectangle(cornerRadius: Metrics.iconCornerRadius * metrics.scale, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                    .overlay {
                        RoundedRectangle(cornerRadius: Metrics.iconCornerRadius * metrics.scale, style: .continuous)
                            .stroke(
                                Color.white.opacity(0.45),
                                style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                            )
                    }
                    .frame(width: metrics.iconSize, height: metrics.iconSize)
                    .position(x: frame.midX, y: frame.midY)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .onAppear {
            if viewModel.isVisible { hasShownOnce = true }
        }
        .onChange(of: viewModel.isVisible) { visible in
            if visible { hasShownOnce = true }
        }
    }

    private func opacity(for isDragSource: Bool) -> Double {
        guard viewModel.isVisible else { return 0 }
        return isDragSource ? 0 : 1
    }

    private var reorderAnimation: Animation? {
        viewModel.reduceMotion ? Metrics.Motion.reduced : Metrics.Motion.reorder
    }

    private func visibilityAnimation(row: Int) -> Animation? {
        if viewModel.reduceMotion { return Metrics.Motion.reduced }
        if viewModel.isVisible {
            let delay = min(Double(row) * Metrics.Durations.showStagger, Metrics.Durations.showStaggerMax)
            return .easeOut(duration: Metrics.Durations.showIcons).delay(delay)
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
              session.armedMergeTargetID == nil else { return nil }

        let remaining = entries.filter { $0.id != session.entry.id }
        let capacity = max(1, metrics.columns * metrics.rows)
        guard remaining.count < capacity else { return nil }

        let insertion: Int
        if let hoveredID = session.hoveredEntryID,
           let hoveredIndex = remaining.firstIndex(where: { $0.id == hoveredID }) {
            insertion = hoveredIndex
        } else if let slot = metrics.slot(at: session.location) {
            insertion = min(max(slot, 0), remaining.count)
        } else {
            return nil
        }

        var slots: [String: Int] = [:]
        for (index, entry) in remaining.enumerated() {
            slots[entry.id] = index < insertion ? index : index + 1
        }
        return DragPreviewLayout(slots: slots, insertionSlot: insertion)
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

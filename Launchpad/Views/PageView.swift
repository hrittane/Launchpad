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
                // Position from the projected reorder layout, but keep this
                // view in its source page so the in-flight drag gesture keeps
                // its identity. When an entry is projected onto another page,
                // shift it by whole page widths instead of moving the view.
                let projected = viewModel.reorderPreview?.locations[entry.id]
                let slot = projected?.index ?? index
                let cell = metrics.cellRect(at: slot)
                let pageDelta = (projected?.page ?? pageIndex) - pageIndex
                let x = cell.midX + CGFloat(pageDelta) * metrics.screenSize.width
                let isDragSource = viewModel.dragSession?.entry.id == entry.id

                ItemIconView(
                    entry: entry,
                    iconSize: metrics.iconSize,
                    labelFontSize: metrics.labelFontSize,
                    labelMaxWidth: max(1, metrics.cellWidth - 8 * metrics.scale),
                    scale: metrics.scale,
                    isEditing: viewModel.isEditing,
                    isFocused: viewModel.focusedEntryID == entry.id,
                    isMergeTarget: viewModel.dragSession?.hoveredEntryID == entry.id,
                    isMergeArmed: viewModel.dragSession?.armedMergeTargetID == entry.id,
                    reduceMotion: viewModel.reduceMotion,
                    showDeleteBadge: entry.app?.isDeletable == true,
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
                .allowsHitTesting(!isDragSource)
                .animation(reorderAnimation, value: CGPoint(x: x, y: cell.midY))
                .animation(visibilityAnimation(row: slot / max(1, metrics.columns)), value: viewModel.isVisible)
            }
        }
        .onAppear {
            if viewModel.isVisible {
                hasShownOnce = true
                readyForShow = true
            }
        }
        .onChange(of: viewModel.isVisible) { _, visible in
            if visible {
                hasShownOnce = true
                readyForShow = true
            }
        }
    }

    private func opacity(for isDragSource: Bool) -> Double {
        guard viewModel.isVisible else { return 0 }
        return 1
    }

    private var tileOpacity: Double {
        if viewModel.reduceMotion { return 1 }
        guard !viewModel.isVisible else { return 1 }
        return hasShownOnce ? 0.7 : 0.4
    }

    private var reorderAnimation: Animation? {
        viewModel.reduceMotion ? Metrics.Motion.reduced : Metrics.Motion.reorder
    }

    private func visibilityAnimation(row: Int) -> Animation? {
        if viewModel.reduceMotion { return Metrics.Motion.reduced }
        if viewModel.isVisible {
            let delay = min(Double(row) * Metrics.Durations.showStagger, Metrics.Durations.showStaggerMax)
            return Metrics.Motion.showIcons.delay(delay)
        }
        return .easeIn(duration: Metrics.Durations.hideIcons)
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

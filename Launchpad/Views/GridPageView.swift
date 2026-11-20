import SwiftUI

/// One page of the icon grid: applications and folders laid out with the
/// proportions measured from the reference frames (7 × 5 by default).
struct GridPageView: View {
    let items: [LauncherItem]
    let metrics: LaunchpadMetrics
    let appsByID: [String: AppItem]
    let isEditing: Bool
    let draggingID: String?
    /// Item under the pointer that a dragged app would fold into a folder, if
    /// any. Only that tile shows the folder chip.
    let folderTargetID: String?
    let onBackgroundTap: () -> Void
    let onLaunch: (AppItem) -> Void
    let onRemove: (AppItem) -> Void
    let onOpenFolder: (UUID) -> Void
    let onBeginEditing: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Sits behind the tiles: a click that misses an icon lands here and
            // is handled by the owner (exit editing or dismiss).
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: onBackgroundTap)
                .frame(width: metrics.size.width, height: metrics.size.height)
                .accessibilityHidden(true)

            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let column = index % metrics.columns
                let row = index / metrics.columns

                tile(for: item, index: index)
                    .frame(width: metrics.columnPitch, height: metrics.cellHeight)
                    .position(
                        x: metrics.columnX(column),
                        y: metrics.rowTop(row) + metrics.cellHeight / 2
                    )
            }
        }
        .frame(width: metrics.size.width, height: metrics.size.height, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Applications"))
    }

    @ViewBuilder
    private func tile(for item: LauncherItem, index: Int) -> some View {
        switch item {
        case .app(let appID):
            if let app = appsByID[appID] {
                AppIconView(
                    item: app,
                    metrics: metrics,
                    isEditing: isEditing,
                    isDragging: draggingID == item.id,
                    showsRemoveBadge: app.isRemovable,
                    dropsIntoFolder: folderTargetID == item.id,
                    wiggleSeed: Double(index),
                    onLaunch: { onLaunch(app) },
                    onRemove: { onRemove(app) },
                    onBeginEditing: onBeginEditing
                )
            }

        case .folder(let folder):
            FolderIconView(
                folder: folder,
                apps: folder.appIDs.compactMap { appsByID[$0] },
                metrics: metrics,
                isEditing: isEditing,
                isDragging: draggingID == item.id,
                dropsIntoFolder: folderTargetID == item.id,
                wiggleSeed: Double(index),
                onOpen: { onOpenFolder(folder.id) },
                onBeginEditing: onBeginEditing
            )
        }
    }
}

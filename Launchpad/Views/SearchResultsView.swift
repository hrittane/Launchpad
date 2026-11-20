import SwiftUI

/// Replaces the grid while a search is active. The selected result is drawn
/// with a glass ring so the arrow keys have something to move.
struct SearchResultsView: View {
    let results: [AppItem]
    let selection: Int
    let metrics: LaunchpadMetrics
    let onLaunch: (AppItem) -> Void
    let onBackgroundTap: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: onBackgroundTap)
                .frame(width: metrics.size.width, height: metrics.size.height)
                .accessibilityHidden(true)

            ForEach(Array(results.enumerated()), id: \.element.id) { index, app in
                let column = index % metrics.columns
                let row = index / metrics.columns

                if row < metrics.rows {
                    if index == selection {
                        RoundedRectangle(cornerRadius: metrics.iconSize * 0.26, style: .continuous)
                            .fill(.white.opacity(0.12))
                            .overlay {
                                RoundedRectangle(
                                    cornerRadius: metrics.iconSize * 0.26,
                                    style: .continuous
                                )
                                .strokeBorder(.white.opacity(0.7), lineWidth: 2)
                            }
                            .frame(width: metrics.iconSize + 18, height: metrics.iconSize + 18)
                            .position(
                                x: metrics.columnX(column),
                                y: metrics.rowTop(row) + metrics.iconSize / 2
                            )
                            .accessibilityHidden(true)
                    }

                    AppIconView(
                        item: app,
                        metrics: metrics,
                        isEditing: false,
                        isDragging: false,
                        showsRemoveBadge: false,
                        dropsIntoFolder: false,
                        wiggleSeed: 0,
                        onLaunch: { onLaunch(app) },
                        onRemove: {},
                        onBeginEditing: {}
                    )
                    .frame(width: metrics.columnPitch, height: metrics.cellHeight)
                    .position(
                        x: metrics.columnX(column),
                        y: metrics.rowTop(row) + metrics.cellHeight / 2
                    )
                }
            }
        }
        .frame(width: metrics.size.width, height: metrics.size.height, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Search results"))
    }
}

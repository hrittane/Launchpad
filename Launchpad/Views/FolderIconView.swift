import AppKit
import SwiftUI

/// The 3 × 3 thumbnail of applications shown inside a folder tile.
struct FolderMiniGrid: View {
    let apps: [AppItem]
    let tileSize: CGFloat
    let artworkScale: CGFloat

    var body: some View {
        let mini = tileSize * 0.235
        let pitch = tileSize * 0.285

        ZStack {
            ForEach(Array(apps.prefix(9).enumerated()), id: \.offset) { index, app in
                AppIconImage(item: app, size: mini, artworkScale: artworkScale)
                    .position(
                        x: tileSize / 2 + CGFloat(index % 3 - 1) * pitch,
                        y: tileSize / 2 + CGFloat(index / 3 - 1) * pitch
                    )
            }
        }
        .frame(width: tileSize, height: tileSize)
    }
}

/// A folder on the grid: a frosted tile with miniatures and the folder name.
struct FolderIconView: View {
    let folder: AppFolder
    let apps: [AppItem]
    let metrics: LaunchpadMetrics
    let isEditing: Bool
    let isDragging: Bool
    let wigglePhase: Double

    let onOpen: () -> Void
    let onBeginEditing: () -> Void
    let onDragChanged: (CGPoint) -> Void
    let onDragEnded: (CGPoint) -> Void

    @State private var wiggle = false

    private var iconSize: CGFloat { metrics.iconSize }

    private var labelWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: metrics.labelFontSize, weight: .medium)
        let measured = (folder.name as NSString).size(withAttributes: [.font: font]).width
        return min(ceil(measured) + 2, metrics.columnPitch - 8)
    }

    var body: some View {
        VStack(spacing: metrics.labelGap) {
            tile
            Text(folder.name)
                .font(.system(size: metrics.labelFontSize, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.tail)
                .shadow(color: .black.opacity(0.55), radius: 2.5, y: 1)
                .frame(width: labelWidth, height: metrics.labelHeight)
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpen)
                .accessibilityHidden(true)
        }
        .frame(width: metrics.columnPitch, height: metrics.cellHeight, alignment: .top)
        .opacity(isDragging ? 0.28 : 1)
        .onChange(of: isEditing) { _, editing in
            updateWiggle(editing)
        }
        .onAppear {
            if isEditing { updateWiggle(true) }
        }
    }

    private var tile: some View {
        ZStack {
            // The glass is attached to the tile that *contains* the
            // miniatures. A glass element that is only a sibling would be
            // composited above them by `GlassEffectContainer`, leaving the
            // icons as blurred smudges underneath.
            folderTile
        }
        .frame(width: iconSize, height: iconSize)
        .rotationEffect(.degrees(isEditing ? (wiggle ? 1.2 : -1.2) : 0), anchor: .center)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.65, maximumDistance: 14)
                .onEnded { _ in onBeginEditing() }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 5, coordinateSpace: .named(LaunchpadCanvas.space))
                .onChanged { value in
                    onDragChanged(value.location)
                }
                .onEnded { value in
                    onDragEnded(value.location)
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(folder.name) folder, \(apps.count) apps"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onOpen() }
    }

    private var folderTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: iconSize * 0.225, style: .continuous)
                .fill(.white.opacity(0.13))

            FolderMiniGrid(apps: apps, tileSize: iconSize, artworkScale: metrics.iconArtworkScale)
        }
        .frame(width: iconSize, height: iconSize)
        // Liquid Glass is hoisted into the surrounding `GlassEffectContainer`
        // and ignores this tile's rotation, so while wiggling the tile uses a
        // plain translucent fill instead: the whole square then rotates as one
        // piece instead of its miniatures sliding inside a static plate.
        .modifier(FolderTileGlass(enabled: !isEditing, cornerRadius: iconSize * 0.225))
        .overlay {
            RoundedRectangle(cornerRadius: iconSize * 0.225, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        }
    }

    private func updateWiggle(_ editing: Bool) {
        guard editing else {
            withAnimation(.easeOut(duration: 0.15)) { wiggle = false }
            return
        }
        wiggle = false
        withAnimation(
            .easeInOut(duration: 0.13 + wigglePhase * 0.035).repeatForever(autoreverses: true)
        ) {
            wiggle = true
        }
    }
}

/// Applies the folder's Liquid Glass plate except in edit mode, where the tile
/// must be a normal view so the wiggle rotation moves it as a unit.
private struct FolderTileGlass: ViewModifier {
    let enabled: Bool
    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            content
        }
    }
}

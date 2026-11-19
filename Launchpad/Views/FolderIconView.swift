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
    let dropsIntoFolder: Bool
    let wigglePhase: Double

    let onOpen: () -> Void
    let onBeginEditing: () -> Void

    /// Brief enlargement played when an app lands inside the folder.
    @State private var addMagnification: CGFloat = 1

    private var iconSize: CGFloat { metrics.iconSize }

    /// Timeline-driven wobble; 0° whenever edit mode is off.
    private func jiggleAngle(_ date: Date) -> Double {
        guard isEditing else { return 0 }
        let period = 0.3 + wigglePhase * 0.06
        let phase = date.timeIntervalSinceReferenceDate * 2 * .pi / period
        return sin(phase) * 1.2
    }

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
        .opacity(isDragging ? 0 : 1)
        // A folder that takes in a new app pops once, so the addition is
        // visible even though the tile is only a miniature of its contents.
        .onChange(of: apps.count) { oldCount, newCount in
            guard newCount > oldCount else { return }
            magnifyForAddition()
        }
    }

    private func magnifyForAddition() {
        withAnimation(.spring(response: 0.16, dampingFraction: 0.5)) {
            addMagnification = 1.16
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.spring(response: 0.32, dampingFraction: 0.62)) {
                addMagnification = 1
            }
        }
    }

    private var tile: some View {
        ZStack {
            // Purely visual: the plate swaps between Liquid Glass and a plain
            // fill when edit mode starts, so nothing that must survive that
            // swap lives in here.
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isEditing)) { context in
                ZStack {
                    // The folder plate that appears when a dragged app hovers
                    // this folder: the same lifted glass squircle as the
                    // floating folder, larger than the tile, carrying the
                    // folder's own miniatures at the plate's scale. The hover
                    // therefore reads as the folder swelling open to take the
                    // app in. The app itself lands in the next empty cell; it is
                    // drawn by the drag overlay at that cell's size and
                    // position.
                    FolderDropPlate(
                        iconSize: iconSize,
                        isVisible: dropsIntoFolder,
                        apps: apps,
                        artworkScale: metrics.iconArtworkScale,
                        glass: .clear
                    )

                    // The glass is attached to the tile that *contains* the
                    // miniatures. A glass element that is only a sibling would
                    // be composited above them by `GlassEffectContainer`,
                    // leaving the icons as blurred smudges underneath.
                    //
                    // While the plate is showing, the tile itself is hidden:
                    // otherwise the target folder is a second squircle inside
                    // the plate.
                    folderTile
                        .opacity(dropsIntoFolder ? 0 : 1)
                }
                .rotationEffect(.degrees(jiggleAngle(context.date)), anchor: .center)
            }
            .frame(width: iconSize, height: iconSize)
            .scaleEffect(addMagnification)

            // Gestures live on a transparent layer above the artwork, outside
            // the subtree that changes when edit mode toggles: swapping the
            // plate mid-gesture would otherwise tear down a drag that had just
            // started.
            Color.clear
                .frame(width: iconSize, height: iconSize)
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpen)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.65, maximumDistance: 14)
                        .onEnded { _ in onBeginEditing() }
                )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(folder.name) folder, \(apps.count) apps"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onOpen() }
    }

    private var folderTile: some View {
        // The resting tile is the same lifted plate as the floating folder: a
        // clear glass squircle with the folder's miniatures and the full
        // specular rim, so the look does not change when the folder is picked
        // up. Liquid Glass is hoisted into the surrounding `GlassEffectContainer`
        // and ignores this tile's rotation and opacity, so while wiggling — and
        // while a drag hides the slot — the tile drops to a plain translucent
        // fill instead: the whole square then rotates as one piece, and a hidden
        // tile cannot leave a glass plate behind at its old slot.
        FolderPlate(
            apps: apps,
            size: iconSize,
            artworkScale: metrics.iconArtworkScale,
            glass: isEditing || dropsIntoFolder ? nil : .clear
        )
        .frame(width: iconSize, height: iconSize)
    }
}

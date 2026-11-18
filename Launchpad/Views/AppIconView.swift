import AppKit
import SwiftUI

/// A single app icon with its label, plus the editing affordances: jiggle,
/// the delete badge and dragging.
struct AppIconView: View {
    let item: AppItem
    let metrics: LaunchpadMetrics
    let isEditing: Bool
    let isDragging: Bool
    let showsRemoveBadge: Bool
    let dropsIntoFolder: Bool
    let wigglePhase: Double

    let onLaunch: () -> Void
    let onRemove: () -> Void
    let onBeginEditing: () -> Void
    let onDragChanged: (CGPoint) -> Void
    let onDragEnded: (CGPoint) -> Void

    private var iconSize: CGFloat { metrics.iconSize }

    /// Angle for the wobble at a given instant. While edit mode is off this is
    /// always 0°, so the tile settles as soon as jiggle ends. Driving it from
    /// the timeline (instead of a `repeatForever` animation) means there is no
    /// infinite animation left running to keep the icon rocking afterwards.
    private func jiggleAngle(_ date: Date) -> Double {
        guard isEditing else { return 0 }
        let period = 0.3 + wigglePhase * 0.06
        let phase = date.timeIntervalSinceReferenceDate * 2 * .pi / period
        return sin(phase) * 1.2
    }

    /// Width of the name itself, so the clickable strip under the icon never
    /// becomes a wide invisible band reaching into the gaps between columns.
    /// Long names still truncate at the column width.
    private var labelWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: metrics.labelFontSize, weight: .medium)
        let measured = (item.name as NSString).size(withAttributes: [.font: font]).width
        return min(ceil(measured) + 2, metrics.columnPitch - 8)
    }

    var body: some View {
        VStack(spacing: metrics.labelGap) {
            iconSquare
            label
        }
        .frame(width: metrics.columnPitch, height: metrics.cellHeight, alignment: .top)
        // The tile is represented by the floating drag preview; keeping it
        // invisible leaves a clean gap at the landing slot.
        .opacity(isDragging ? 0 : 1)
    }

    private var iconSquare: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isEditing)) { context in
            ZStack {
                // Always in the tree (visibility is animated) so hovering a
                // target never rebuilds the icon subtree during a drag.
                FolderDropPlate(iconSize: iconSize, isVisible: dropsIntoFolder)

                AppIconImage(item: item, size: iconSize, artworkScale: metrics.iconArtworkScale)
            }
            .rotationEffect(.degrees(jiggleAngle(context.date)), anchor: .center)
        }
        .frame(width: iconSize, height: iconSize)
        // The icon square and its name are the only targets: the grid cell
        // around them stays inert, so a click in a gap does nothing at all.
        .contentShape(Rectangle())
        .onTapGesture(perform: onLaunch)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.65, maximumDistance: 14)
                .onEnded { _ in onBeginEditing() }
        )
        .simultaneousGesture(dragGesture)
        .overlay(alignment: .topLeading) { removeBadge }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.name)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onLaunch() }
    }

    private var label: some View {
        Text(item.name)
            .font(.system(size: metrics.labelFontSize, weight: .medium))
            .foregroundStyle(.white.opacity(0.92))
            .lineLimit(1)
            .truncationMode(.tail)
            .shadow(color: .black.opacity(0.55), radius: 2.5, y: 1)
            .frame(width: labelWidth, height: metrics.labelHeight)
            .contentShape(Rectangle())
            .onTapGesture(perform: onLaunch)
            .accessibilityHidden(true)
    }

    private var removeBadge: some View {
        // Always part of the overlay, even when hidden: swapping EmptyView for
        // a Button rebuilds this subtree, which cancelled an in-flight drag
        // when jiggle mode switched on mid-gesture.
        let visible = isEditing && showsRemoveBadge

        return Button(action: onRemove) {
            Image(systemName: "xmark")
                .font(.system(size: max(8, iconSize * 0.145), weight: .bold))
                .foregroundStyle(.white)
                .frame(width: iconSize * 0.3, height: iconSize * 0.3)
                .background(Circle().fill(.black.opacity(0.62)))
                .overlay {
                    Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .offset(x: -iconSize * 0.1, y: -iconSize * 0.1)
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
        .help(visible ? "Delete \(item.name)" : "")
        .accessibilityHidden(!visible)
        .accessibilityLabel(Text("Delete \(item.name)"))
    }

    /// Dragging works straight from the resting grid, the way Launchpad does:
    /// press an icon, move, and it reorders (or folds into a folder) without
    /// waiting for edit mode first. `LaunchpadView` turns edit mode on when the
    /// drag begins, so the rest of the grid starts jiggling under the pointer.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named(LaunchpadCanvas.space))
            .onChanged { value in
                onDragChanged(value.location)
            }
            .onEnded { value in
                onDragEnded(value.location)
            }
    }
}

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
    let wigglePhase: Double

    let onLaunch: () -> Void
    let onRemove: () -> Void
    let onBeginEditing: () -> Void
    let onDragChanged: (CGPoint) -> Void
    let onDragEnded: (CGPoint) -> Void

    @State private var wiggle = false

    private var iconSize: CGFloat { metrics.iconSize }

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
        .onChange(of: isEditing) { _, editing in
            updateWiggle(editing)
        }
        .onAppear {
            if isEditing { updateWiggle(true) }
        }
    }

    private var iconSquare: some View {
        ZStack {
            AppIconImage(item: item, size: iconSize, artworkScale: metrics.iconArtworkScale)
        }
        .frame(width: iconSize, height: iconSize)
        .rotationEffect(.degrees(wiggleAngle), anchor: .center)
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

    private var wiggleAngle: Double {
        guard isEditing else { return 0 }
        return wiggle ? 1.2 : -1.2
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

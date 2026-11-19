import SwiftUI

/// The folder plate shown behind an icon that a dragged app is hovering:
/// dropping there folds both into a folder. It is the lifted glass squircle the
/// floating folder uses, sized a little larger than the icon and centred on it,
/// so the icon sits inside the new folder. It replaces the edit-mode drop ring
/// and is decorative only — never hit-tested.
struct FolderDropPlate: View {
    /// How much larger than the icon the plate is. A folder tile showing the
    /// plate draws its miniatures at this scale so they fill it.
    static let contentScale = FolderPlate.liftScale

    let iconSize: CGFloat
    let isVisible: Bool
    /// The folder's miniatures, drawn inside the plate. Empty when the plate
    /// opens under a bare app icon: that icon is drawn above it instead.
    var apps: [AppItem] = []
    var artworkScale: CGFloat = 1
    /// Glass is opt-in: a plate behind a bare app icon must stay a plain fill,
    /// because a hoisted glass surface would be composited above that icon.
    var glass: Glass?

    /// The plate springs in when a drag reaches the tile but disappears without
    /// animating. A fade-out would still be on screen when the drop lands, and
    /// the folder's add-pop starts immediately: the fading plate reads as a
    /// second, static folder behind the one that is magnifying.
    @State private var shown = false
    /// Grows from 92 % to 100 % once inserted. The *frame* animates, not
    /// `scaleEffect`: Liquid Glass is hoisted by the enclosing
    /// `GlassEffectContainer` and ignores render transforms, so only a layout
    /// change carries the plate with it.
    @State private var growth: CGFloat = 0.92

    private var plateSize: CGFloat { iconSize * Self.contentScale }

    var body: some View {
        ZStack {
            if shown {
                FolderPlate(
                    apps: apps,
                    size: plateSize * growth,
                    artworkScale: artworkScale,
                    glass: glass
                )
                .onAppear {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.74)) {
                        growth = 1
                    }
                }
            }
        }
        .frame(width: plateSize, height: plateSize)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            if isVisible { show() }
        }
        .onChange(of: isVisible) { _, visible in
            if visible {
                show()
            } else {
                hide()
            }
        }
    }

    private func show() {
        growth = 0.92
        shown = true
    }

    private func hide() {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            shown = false
            growth = 0.92
        }
    }
}

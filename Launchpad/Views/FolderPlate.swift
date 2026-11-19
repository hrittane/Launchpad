import SwiftUI

/// The lifted folder plate: a clear Liquid Glass squircle carrying the folder's
/// 3 × 3 miniature grid.
///
/// It is used for the floating folder during a drag and for the plate that opens
/// under a dragged app, and it is the reference for the resting tile's rim. The
/// look follows the system Launchpad folder: the wallpaper and any icon passing
/// underneath stay visible through the glass (with the system's edge lensing),
/// while a bright specular rim and a soft drop shadow make the plate read as a
/// separate, lifted surface.
struct FolderPlate: View {
    /// How much larger than a grid icon the lifted plate is.
    static let liftScale: CGFloat = 1.28

    let apps: [AppItem]
    let size: CGFloat
    let artworkScale: CGFloat
    /// `.clear` for a lifted plate; `.regular` for a resting surface that needs
    /// more frost for legibility; `nil` for a plate that must sit *behind*
    /// sibling content, because a hoisted glass surface would draw over it.
    var glass: Glass? = .clear
    /// 0…1: a lifted plate carries a full rim, a resting tile a faint one.
    var rimIntensity: Double = 1

    private var cornerRadius: CGFloat { size * 0.225 }
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        ZStack {
            // A little milkiness over the clear glass: the reference plate lifts
            // the wallpaper toward white without hiding what is behind it.
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.white.opacity(0.11))

            if !apps.isEmpty {
                FolderMiniGrid(apps: apps, tileSize: size, artworkScale: artworkScale)
            }
        }
        .frame(width: size, height: size)
        // The miniatures are the glass view's content, so they stay crisp above
        // the material instead of being sampled as its backdrop.
        .modifier(PlateGlass(glass: glass, shape: shape))
        .overlay {
            GlassRim(cornerRadius: cornerRadius, intensity: rimIntensity)
        }
    }
}

/// Applies the plate's material when one is requested. Kept as a modifier so the
/// two branches keep identical layout and the rim overlay stays outside the
/// hoisted glass either way.
private struct PlateGlass: ViewModifier {
    let glass: Glass?
    let shape: RoundedRectangle

    @ViewBuilder
    func body(content: Content) -> some View {
        if let glass {
            content.glassEffect(glass, in: shape)
        } else {
            content
        }
    }
}

/// A specular rim for Liquid Glass surfaces: bright on the light side, fading
/// across, with a thin inner bevel and a faint reflected edge opposite.
///
/// The system draws its own rim, but it is subtle. This overlay is what makes a
/// plate read as a lifted lens, matching the folder in the reference captures.
struct GlassRim: View {
    let cornerRadius: CGFloat
    var intensity: Double = 1

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            shape.strokeBorder(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.90 * intensity), location: 0),
                        .init(color: .white.opacity(0.40 * intensity), location: 0.42),
                        .init(color: .white.opacity(0.12 * intensity), location: 0.76),
                        .init(color: .white.opacity(0.28 * intensity), location: 1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.2
            )

            // Inner bevel: a soft highlight just inside the top edge.
            shape
                .inset(by: 1.2)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.55 * intensity), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
                .blur(radius: 0.5)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

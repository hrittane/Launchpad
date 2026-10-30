import AppKit
import SwiftUI

/// Public AppKit blur material, used only when the wallpaper cannot be loaded
/// as a bitmap (dynamic or aerial wallpapers). The normal path blurs the
/// desktop's image so color stays saturated.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .fullScreenUI
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active
    var isEmphasized: Bool = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = isEmphasized
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
        nsView.isEmphasized = isEmphasized
    }
}

struct LaunchpadBackgroundView: View {
    @ObservedObject var viewModel: LaunchpadViewModel
    var screen: NSScreen? = nil
    /// The part of the screen this window covers, in top-left screen
    /// coordinates. The Dock strip and menu-bar patch render the same
    /// full-screen wallpaper offset by this region, so the pieces line up.
    var viewport: CGRect? = nil

    var body: some View {
        LaunchpadBackgroundSurface(viewModel: viewModel, screen: screen, viewport: viewport)
    }
}

/// One continuous blurred-wallpaper surface for a single screen.
///
/// The wallpaper is sharpened back up with a small saturation boost and dimmed
/// with a flat black layer. There is no wash, sheen, or gradient over it, so the
/// desktop's own colors carry the backdrop. When the wallpaper cannot be loaded
/// the view falls back to the system material, still dimmed the same way.
struct LaunchpadBackgroundSurface: View {
    @ObservedObject var viewModel: LaunchpadViewModel
    /// The window's own screen, so mirrored displays blur their own wallpaper.
    var screen: NSScreen? = nil
    /// The region of the screen the hosting window covers, in top-left screen
    /// coordinates. `nil` renders the wallpaper to the view's own bounds.
    var viewport: CGRect? = nil
    /// Test seams: override the live accessibility setting and image source.
    var reduceTransparencyOverride: Bool? = nil
    var wallpaperImage: CGImage? = nil

    @Environment(\.colorScheme) private var colorScheme

    private var isTransparencyReduced: Bool {
        reduceTransparencyOverride ?? viewModel.reduceTransparency
    }

    private var wallpaper: CGImage? {
        if let wallpaperImage { return wallpaperImage }
        guard let screen = screen ?? NSScreen.main ?? NSScreen.screens.first else { return nil }
        return WallpaperBackdrop.blurredImage(for: screen)
    }

    private var dim: Color {
        Color.black.opacity(
            colorScheme == .dark ? Metrics.darkTintOpacity : Metrics.lightTintOpacity
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let screenSize = screen?.frame.size ?? proxy.size
            let region = viewport ?? CGRect(origin: .zero, size: screenSize)

            ZStack(alignment: .topLeading) {
                if isTransparencyReduced {
                    Color(white: 0.12)
                        .opacity(Metrics.reduceTransparencyBackground)
                } else if let wallpaper {
                    fullScreenWallpaper(wallpaper, size: screenSize)
                        .offset(x: -region.minX, y: -region.minY)
                } else {
                    // Fallback for wallpapers that cannot be loaded as an image
                    // (dynamic or aerial wallpapers).
                    VisualEffectBackground(isEmphasized: true)
                    dim
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipped()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    /// One full-screen wallpaper layer. Each window clips a different region of
    /// it, so the main overlay, Dock strip, and corner patch reconstruct the
    /// same continuous backdrop.
    private func fullScreenWallpaper(_ image: CGImage, size: CGSize) -> some View {
        ZStack {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
            dim
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

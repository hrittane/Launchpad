import AppKit
import SwiftUI

/// Public AppKit blur material. A continuous 40–60 pt Gaussian radius is not
/// exposed by AppKit, so the overlay combines a full-screen material with a
/// light wash and specular highlights to achieve a glassy, legible backdrop.
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

/// Which part of the desktop the backdrop is covering. The main overlay can
/// carry a specular sheen; the strip behind the Dock must stay flat so the two
/// separate windows meet without a visible seam.
enum BackdropRole {
    case overlay
    case dockStrip
    case patch
}

struct LaunchpadBackgroundView: View {
    @ObservedObject var viewModel: LaunchpadViewModel
    var role: BackdropRole = .overlay

    var body: some View {
        LaunchpadBackgroundSurface(viewModel: viewModel, role: role)
            .opacity(viewModel.isVisible ? 1 : 0)
            .animation(backgroundAnimation, value: viewModel.isVisible)
    }

    private var backgroundAnimation: Animation {
        if viewModel.reduceMotion { return Metrics.Motion.reduced }
        if viewModel.isVisible {
            return .easeOut(duration: Metrics.Durations.showBackground)
        }
        return .easeIn(duration: Metrics.Durations.hideBackground)
            .delay(Metrics.Durations.hideIcons)
    }
}

/// The blur and light layers shared by the main overlay, the Dock background,
/// and the side-Dock menu-bar patch. Keeping them in one view guarantees every
/// window renders the same backdrop.
///
/// The app background intentionally uses a standard material rather than
/// Liquid Glass: Apple's HIG reserves Liquid Glass for the floating control and
/// navigation layer. The glass look comes from a vibrant, low-opacity material
/// plus a cool ambient wash and a soft specular highlight, instead of the flat
/// gray tint that previously read as frost.
struct LaunchpadBackgroundSurface: View {
    @ObservedObject var viewModel: LaunchpadViewModel
    var role: BackdropRole = .overlay
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if viewModel.reduceTransparency {
                    Color(white: 0.12)
                        .opacity(Metrics.reduceTransparencyBackground)
                } else {
                    VisualEffectBackground(
                        material: .fullScreenUI,
                        blendingMode: .behindWindow,
                        state: .active,
                        isEmphasized: true
                    )
                    liquidGlassWash(size: proxy.size)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    /// A light wash over the blurred desktop. The flat layers are identical in
    /// every window, so the main overlay and the Dock strip join seamlessly;
    /// the directional highlights fade to clear before the Dock edge.
    private func liquidGlassWash(size: CGSize) -> some View {
        let intensity = min(max(viewModel.settings.blurIntensity, 0), 1)
        let base = colorScheme == .dark ? Metrics.darkTintOpacity : Metrics.lightTintOpacity
        // The material itself has a fixed blur radius, so intensity has to read
        // through tint, ambient color, and sheen. Keep the swing wide enough
        // that the two ends of the slider are clearly different.
        let extra = (intensity - 0.5) * 0.30
        let tint = min(0.85, max(0.02, base + extra))
        let ambient = (colorScheme == .dark ? 0.14 : 0.08) + 0.10 * intensity
        let sheen = role == .dockStrip ? 0 : 0.08 + 0.10 * intensity

        return ZStack {
            // Cool ambient cast: keeps the blurred desktop from reading as
            // neutral gray frost and gives the glass a subtle tint.
            Color(red: 0.10, green: 0.17, blue: 0.32)
                .opacity(ambient)
            Color.black.opacity(tint)

            // Specular light catching the top of the glass. It fades out well
            // above the Dock so the separate backdrop window is seamless.
            if sheen > 0 {
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [Color.white.opacity(sheen), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: min(180, size.height * 0.22))
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }

            // A diagonal reflection across the main overlay. It is clear by
            // the middle of the screen, so it never reaches the Dock seam.
            if role == .overlay {
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(0.03 + 0.02 * intensity), location: 0),
                        .init(color: .clear, location: 0.55)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }
}

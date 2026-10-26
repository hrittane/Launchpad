import AppKit
import SwiftUI

/// Public AppKit blur material. A continuous 40–60 pt Gaussian radius is not
/// exposed by AppKit, so the overlay combines a full-screen material with a
/// tint to achieve a heavily blurred, legible backdrop.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .fullScreenUI
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

struct LaunchpadBackgroundView: View {
    @ObservedObject var viewModel: LaunchpadViewModel

    var body: some View {
        LaunchpadBackgroundSurface(viewModel: viewModel)
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

/// The blur and tint layers shared by the main overlay, the Dock background,
/// and the side-Dock menu-bar patch. Keeping them in one view guarantees every
/// window renders the same backdrop.
struct LaunchpadBackgroundSurface: View {
    @ObservedObject var viewModel: LaunchpadViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if viewModel.reduceTransparency {
                Color(white: 0.12)
                    .opacity(Metrics.reduceTransparencyBackground)
            } else {
                VisualEffectBackground(material: .fullScreenUI, blendingMode: .behindWindow, state: .active)
                tint
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var tint: Color {
        let base = colorScheme == .dark ? Metrics.darkTintOpacity : Metrics.lightTintOpacity
        let extra = (viewModel.settings.blurIntensity - 0.5) * 0.10
        return Color.black.opacity(min(0.9, max(0.02, base + extra)))
    }
}

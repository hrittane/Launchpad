import SwiftUI

/// The two system Liquid Glass variants.
///
/// `regular` is the legible, adaptive material used for panels and controls
/// with text. `clear` is the highly translucent variant for visually rich
/// backgrounds. Apple recommends the regular variant for anything containing
/// labels or icons.
enum LiquidGlassVariant {
    case regular
    case clear
}

extension View {
    /// Applies the system Liquid Glass material on macOS 26 and later.
    ///
    /// Liquid Glass is a system material, not a hand-drawn gradient: the
    /// compositor blurs and refracts the content behind the shape, adds
    /// specular edge light, and (with `interactive`) reacts to the pointer.
    /// Older systems fall back to a layered ultra-thin material with the same
    /// silhouette, so layout and hit testing are unchanged.
    @ViewBuilder
    func liquidGlass<S: Shape>(
        _ variant: LiquidGlassVariant = .regular,
        tint: Color? = nil,
        interactive: Bool = false,
        in shape: S
    ) -> some View {
        if #available(macOS 26.0, *) {
            let base: Glass = variant == .regular ? .regular : .clear
            let tinted = tint.map { base.tint($0) } ?? base
            let glass = interactive ? tinted.interactive() : tinted
            self.glassEffect(glass, in: shape)
        } else {
            self.background {
                LiquidGlassFallback(shape: shape, tint: tint)
            }
            .clipShape(shape)
        }
    }
}

/// Groups Liquid Glass effects so the system can render them in one pass and
/// morph them together. A single effect works without a container, but Apple
/// recommends hosting custom glass in one for correct batching.
struct LiquidGlassHost<Content: View>: View {
    var spacing: CGFloat = 0
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing, content: content)
        } else {
            content()
        }
    }
}

/// Pre-macOS 26 stand-in for the system material. It deliberately layers a
/// thin material, a diagonal light wash, and a bright edge instead of a flat
/// white fill, which is what made the old surfaces look frosted.
private struct LiquidGlassFallback<S: Shape>: View {
    let shape: S
    let tint: Color?

    var body: some View {
        ZStack {
            shape.fill(.ultraThinMaterial)

            if let tint {
                shape.fill(tint)
            }

            shape.fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.20),
                        Color.white.opacity(0.05),
                        Color.black.opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

            shape.stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.55),
                        Color.white.opacity(0.08),
                        Color.white.opacity(0.22)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.8
            )
        }
    }
}

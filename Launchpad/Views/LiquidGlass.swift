import SwiftUI

/// Liquid Glass helpers for the overlay's floating controls.
///
/// The app deploys to macOS 26, so there is no material fallback to maintain:
/// `glassEffect` is always the real system material. The compositor blurs and
/// refracts the desktop behind the shape, adds specular edge light, and reacts
/// to the pointer when the glass is marked interactive.
extension View {
    /// Applies the system glass material to `shape`.
    ///
    /// Call sites pass the fully configured `Glass` value, for example
    /// `.regular.tint(tint).interactive()`, so the tint and interactivity stay
    /// visible where they are used.
    func liquidGlass<S: Shape>(_ glass: Glass = .regular, in shape: S) -> some View {
        glassEffect(glass, in: shape)
            .overlay {
                LiquidGlassEdge(shape: shape)
            }
    }
}

/// Restores the specular edge that the system highlight loses on bright
/// backgrounds. It is hidden in dark mode, where the glass already separates
/// itself from the content; only light mode needs the extra definition.
private struct LiquidGlassEdge<S: Shape>: View {
    let shape: S
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    var body: some View {
        if colorScheme == .light {
            shape.stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.50),
                        Color.white.opacity(0.06),
                        Color.white.opacity(0.18)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.7
            )
            .allowsHitTesting(false)
        }
    }
}

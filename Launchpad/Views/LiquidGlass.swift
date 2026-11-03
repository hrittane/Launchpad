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

    /// A static stand-in for the system glass while a tile is being transformed
    /// continuously, as in the edit-mode wiggle.
    ///
    /// `glassEffect` re-captures its backdrop for every transformed frame. On a
    /// folder tile that reads as a pulsing highlight instead of a rotation and
    /// costs a full glass pass per frame. A material with the same tint and rim
    /// rotates as one ordinary layer.
    func stillGlass<S: Shape>(tint: Color, in shape: S) -> some View {
        background {
            shape
                .fill(.regularMaterial)
                .overlay {
                    shape.fill(tint)
                }
                .overlay {
                    LiquidGlassEdge(shape: shape)
                }
        }
    }

    /// A completely AppKit-free folder surface for the merge preview.
    ///
    /// Inserting a material-backed view into the grid *while a drag gesture is
    /// in flight* makes AppKit rebuild its tracking hierarchy and cancels the
    /// gesture: the floating icon stops following the cursor and `onEnded`
    /// never runs. The preview only needs to read as a folder for a moment, so
    /// it is drawn with plain shapes that do not create a visual-effect view.
    func plainGlass<S: Shape>(tint: Color, in shape: S) -> some View {
        background {
            shape
                .fill(Color.black.opacity(0.16))
                .overlay {
                    shape.fill(tint)
                }
                .overlay {
                    LiquidGlassEdge(shape: shape)
                }
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

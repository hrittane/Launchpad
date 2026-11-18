import SwiftUI

/// The folder plate shown behind an icon that a dragged app is hovering:
/// dropping there folds both into a folder. It is the same frosted squircle the
/// folder tiles use, sized a little larger than the icon and centred on it, so
/// the icon sits inside the new folder. It replaces the edit-mode drop ring and
/// is decorative only — never hit-tested.
struct FolderDropPlate: View {
    /// How much larger than the icon the plate is. A folder tile showing the
    /// plate draws its miniatures at this scale so they fill it.
    static let contentScale: CGFloat = 1.28

    let iconSize: CGFloat
    let isVisible: Bool

    /// The plate springs in when a drag reaches the tile but disappears without
    /// animating. A fade-out would still be on screen when the drop lands, and
    /// the folder's add-pop starts immediately: the fading plate reads as a
    /// second, static folder behind the one that is magnifying.
    @State private var shown = false

    private var plateSize: CGFloat { iconSize * Self.contentScale }
    private var cornerRadius: CGFloat { plateSize * 0.225 }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.white.opacity(shown ? 0.17 : 0))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(shown ? 0.3 : 0), lineWidth: 1)
            }
            .frame(width: plateSize, height: plateSize)
            .shadow(color: .black.opacity(shown ? 0.3 : 0), radius: 6, y: 3)
            .scaleEffect(shown ? 1 : 0.9)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear { shown = isVisible }
            .onChange(of: isVisible) { _, visible in
                if visible {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.74)) {
                        shown = true
                    }
                } else {
                    var transaction = Transaction()
                    transaction.animation = nil
                    withTransaction(transaction) {
                        shown = false
                    }
                }
            }
    }
}

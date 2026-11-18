import SwiftUI

/// The folder plate shown behind an icon that a dragged app is hovering:
/// dropping there folds both into a folder. It is the same frosted squircle the
/// folder tiles use, sized a little larger than the icon and centred on it, so
/// the icon sits inside the new folder. It replaces the edit-mode drop ring and
/// is decorative only — never hit-tested.
struct FolderDropPlate: View {
    let iconSize: CGFloat
    let isVisible: Bool

    private var plateSize: CGFloat { iconSize * 1.28 }
    private var cornerRadius: CGFloat { plateSize * 0.225 }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.white.opacity(isVisible ? 0.17 : 0))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(isVisible ? 0.3 : 0), lineWidth: 1)
            }
            .frame(width: plateSize, height: plateSize)
            .shadow(color: .black.opacity(isVisible ? 0.3 : 0), radius: 6, y: 3)
            .scaleEffect(isVisible ? 1 : 0.9)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .animation(.spring(response: 0.26, dampingFraction: 0.74), value: isVisible)
    }
}

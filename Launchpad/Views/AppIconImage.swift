import AppKit
import SwiftUI

/// Loads and draws one application icon at a given footprint.
///
/// `NSWorkspace` icons are full 1024 px canvases whose artwork occupies ~824 px,
/// so the image is drawn larger than the visible squircle (`artworkScale`).
struct AppIconImage: View {
    let item: AppItem
    let size: CGFloat
    let artworkScale: CGFloat

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size * artworkScale, height: size * artworkScale)
                    .shadow(
                        color: .black.opacity(0.14),
                        radius: max(1.5, size * 0.05),
                        y: max(0.5, size * 0.02)
                    )
            } else {
                RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.16), .white.opacity(0.08)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                            .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                    }
                    .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
        .task(id: item.id) {
            if let cached = IconProvider.shared.cachedIcon(for: item) {
                image = cached
            } else {
                image = await IconProvider.shared.icon(for: item)
            }
        }
    }
}

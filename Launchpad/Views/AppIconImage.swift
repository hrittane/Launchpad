import AppKit
import SwiftUI

/// Lazily loaded application icon. Loading and 2× rendering happen on
/// `IconProvider`'s background queue; this view only owns the final image.
struct AppIconImage: View {
    let path: String
    let size: CGFloat
    var fallbackName: String = ""

    @State private var image: NSImage?
    /// Tracks the identity that produced the current image so a recycled view
    /// does not flash a stale icon before the new `.task` fires.
    @State private var loadedIdentity: String = ""

    private var targetPointSize: CGFloat { max(16, size.rounded()) }
    private var identity: String { "\(path)|\(Int(targetPointSize))" }

    private var currentImage: NSImage? {
        if let cached = IconProvider.shared.cachedIcon(for: path, pointSize: targetPointSize) {
            return cached
        }
        if loadedIdentity == identity {
            return image
        }
        return nil
    }

    var body: some View {
        Group {
            if let img = currentImage {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .onChange(of: identity) { _, newValue in
            if loadedIdentity != newValue {
                image = nil
            }
        }
        .task(id: identity) {
            if IconProvider.shared.cachedIcon(for: path, pointSize: targetPointSize) == nil {
                let loaded = await IconProvider.shared.icon(for: path, pointSize: targetPointSize)
                guard !Task.isCancelled else { return }
                image = loaded
            }
            loadedIdentity = identity
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(Color.white.opacity(0.14))
            .overlay {
                if let first = fallbackName.first {
                    Text(String(first).uppercased())
                        .font(.system(size: max(10, size * 0.32), weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                } else {
                    Image(systemName: "app.dashed")
                        .font(.system(size: max(10, size * 0.28)))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
    }
}

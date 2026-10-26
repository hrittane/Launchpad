import AppKit
import SwiftUI

/// Lazily loaded application icon. Loading and 2× rendering happen on
/// `IconProvider`'s background queue; this view only owns the final image.
struct AppIconImage: View {
    let path: String
    let size: CGFloat
    var fallbackName: String = ""

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .task(id: "\(path)|\(Int(size.rounded()))") {
            await load()
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

    private func load() async {
        let pointSize = max(16, size.rounded())
        if let cached = IconProvider.shared.cachedIcon(for: path, pointSize: pointSize) {
            image = cached
            return
        }
        let loaded = await IconProvider.shared.icon(for: path, pointSize: pointSize)
        guard !Task.isCancelled else { return }
        image = loaded
    }
}

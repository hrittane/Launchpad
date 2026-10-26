import AppKit
import Foundation

/// Loads application icons off the main thread and caches them at the exact
/// point size requested by the UI. Rendering into a 2× bitmap keeps icons crisp
/// on Retina displays regardless of the screen that requested them first.
final class IconProvider {
    static let shared = IconProvider()

    private let cache = NSCache<NSString, NSImage>()
    private let queue = DispatchQueue(
        label: "com.soufiane.launchpad.icons",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private let workspace = NSWorkspace.shared

    init() {
        cache.countLimit = 600
        cache.totalCostLimit = 96 * 1024 * 1024
    }

    func cachedIcon(for path: String, pointSize: CGFloat) -> NSImage? {
        cache.object(forKey: cacheKey(path: path, size: pointSize))
    }

    func icon(for path: String, pointSize: CGFloat) async -> NSImage? {
        let key = cacheKey(path: path, size: pointSize)
        if let cached = cache.object(forKey: key) {
            return cached
        }

        return await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }
                let image = self.renderIcon(path: path, pointSize: pointSize)
                if let image {
                    self.cache.setObject(
                        image,
                        forKey: key,
                        cost: Int(pointSize * pointSize * 8)
                    )
                }
                continuation.resume(returning: image)
            }
        }
    }

    func icon(for app: AppItem, pointSize: CGFloat) async -> NSImage? {
        await icon(for: app.filePath, pointSize: pointSize)
    }

    func clear() {
        cache.removeAllObjects()
    }

    private func cacheKey(path: String, size: CGFloat) -> NSString {
        "\(path)|\(Int(size.rounded()))" as NSString
    }

    private func renderIcon(path: String, pointSize: CGFloat) -> NSImage? {
        let source = workspace.icon(forFile: path)
        let size = max(16, pointSize.rounded())
        let pixelSize = Int(size * 2)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            source.size = NSSize(width: size, height: size)
            return source
        }
        rep.size = NSSize(width: size, height: size)

        guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
            source.size = NSSize(width: size, height: size)
            return source
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        source.draw(
            in: NSRect(x: 0, y: 0, width: size, height: size),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: size, height: size))
        image.addRepresentation(rep)
        return image
    }
}

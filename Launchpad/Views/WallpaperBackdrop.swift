import AppKit
import CoreImage

/// Renders the desktop wallpaper as a heavily blurred, saturated backdrop.
///
/// `NSVisualEffectView` materials desaturate the desktop and expose no control
/// over their blur radius, so the overlay blurs the wallpaper itself. The
/// source comes from `SystemWallpaper`, which resolves provider-backed macOS 26
/// wallpapers that `NSWorkspace.desktopImageURL(for:)` reports as the generic
/// default.
///
/// Rendering is split into two paths so SwiftUI body evaluation stays cheap:
///
/// - `prepare(for:)` runs from the window controller before a show. It checks a
///   cheap wallpaper signature, resolves and decodes the wallpaper only when
///   that signature changed, blurs it at a small working size, and caches the
///   result per display, size, and radius.
/// - `blurredImage(for:)` is a cache-only lookup. It never reads the wallpaper
///   store or decodes an image, so re-rendering the grid (including every frame
///   of a page drag) cannot trigger the ~1 s HEIC decode.
@MainActor
enum WallpaperBackdrop {
    private struct CacheKey: Hashable {
        let display: String
        let width: Int
        let height: Int
        let radius: Int
    }

    private struct CacheEntry {
        let signature: String
        let image: CGImage
    }

    private static var cache: [CacheKey: CacheEntry] = [:]
    private static let context = CIContext()

    static func invalidate() {
        cache.removeAll()
    }

    /// Validates the cached blur and rebuilds it only when the wallpaper,
    /// appearance, display, or size changed. This is the only path that touches
    /// the wallpaper resolver or Core Image.
    static func prepare(for screen: NSScreen, radius: CGFloat = 50) {
        let key = cacheKey(for: screen, radius: radius)
        let signature = SystemWallpaper.signature(for: screen)
        if cache[key]?.signature == signature { return }

        cache[key] = nil
        guard let image = render(for: screen, radius: radius) else { return }
        cache[key] = CacheEntry(signature: signature, image: image)
    }

    /// Cache-only accessor for SwiftUI body evaluation.
    ///
    /// The expensive work belongs to `prepare(for:)`; a missing entry means the
    /// window has not been prepared yet and the caller should show the material
    /// fallback rather than block the main thread.
    static func blurredImage(for screen: NSScreen, radius: CGFloat = 50) -> CGImage? {
        cache[cacheKey(for: screen, radius: radius)]?.image
    }

    private static func cacheKey(for screen: NSScreen, radius: CGFloat) -> CacheKey {
        let size = screen.frame.size
        let number = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber
        return CacheKey(
            display: number?.stringValue ?? screen.localizedName,
            width: Int(size.width),
            height: Int(size.height),
            radius: Int(radius)
        )
    }

    private static func render(for screen: NSScreen, radius: CGFloat) -> CGImage? {
        guard let source = SystemWallpaper.resolve(for: screen) else { return nil }

        let size = screen.frame.size
        var image = CIImage(cgImage: source.image)

        // Aspect-fill to the screen at a small working size, then blur.
        let workWidth: CGFloat = 640
        let work = CGSize(width: workWidth, height: workWidth * size.height / size.width)
        let fill = max(work.width / image.extent.width, work.height / image.extent.height)
        image = image.transformed(by: CGAffineTransform(scaleX: fill, y: fill))
        let crop = CGRect(
            x: image.extent.midX - work.width / 2,
            y: image.extent.midY - work.height / 2,
            width: work.width,
            height: work.height
        )
        image = image.cropped(to: crop)

        let sigma = Double(radius * workWidth / size.width)
        let blurred = image.clampedToExtent() // avoids faded edges
            .applyingGaussianBlur(sigma: sigma)
            .cropped(to: crop)
            // Bake the saturation boost into the bitmap. A SwiftUI `.saturation`
            // filter on a full-screen image forces an extra offscreen pass every
            // time the window fades, which is expensive on integrated GPUs.
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.1])
        return context.createCGImage(blurred, from: crop)
    }
}

import AppKit
import CoreImage

/// Full-screen wallpaper backdrop that sits behind the icon grid.
///
/// The backdrop is rendered from the desktop *picture* instead of sampling the
/// window server, so other applications' windows never show through the panel:
/// Launchpad replaces the desktop, it does not look through it. The picture is
/// softened offscreen once per presentation (the blur the window-server
/// material used to provide) and the tint and vignette are layered on top
/// unchanged, so only the background differs from the previous rendering.
final class BackdropView: NSView {
    private let wallpaper = WallpaperView()
    private let fallback = GradientBackdropView()
    private let tint = NSView()
    private let vignette = VignetteView()

    /// True once a desktop picture was rendered for the current screen.
    private var hasWallpaper = false

    /// Set by the snapshot mode, which needs a deterministic opaque backdrop.
    private var usesFallbackOnly = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true

        tint.wantsLayer = true
        vignette.wantsLayer = true

        for view in [wallpaper, fallback, tint, vignette] {
            view.autoresizingMask = [.width, .height]
            view.frame = bounds
            addSubview(view)
        }

        updateTint()
        updateVisibility()

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("BackdropView is created programmatically")
    }

    override func layout() {
        super.layout()
        let frame = bounds
        wallpaper.frame = frame
        fallback.frame = frame
        tint.frame = frame
        vignette.frame = frame
    }

    /// Renders the desktop picture of `screen` behind the panel. Both the panel
    /// and the menu-bar cover call this with the same screen, so the two draw
    /// the same picture at the same scale and join without a seam.
    func present(on screen: NSScreen) {
        guard !usesFallbackOnly else { return }
        hasWallpaper = wallpaper.render(screen: screen)
        updateVisibility()
    }

    /// Warms the rendering pipeline at launch, so the first presentation does
    /// not pay Core Image's one-off shader compilation on the main thread.
    static func preheat() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        _ = WallpaperImage.blurred(for: screen)
    }

    @objc private func accessibilityDisplayOptionsChanged() {
        updateTint()
        updateVisibility()
    }

    #if DEBUG
    /// Replaces the wallpaper with the opaque gradient so offscreen bitmap
    /// rendering has something deterministic to composite the grid over.
    func forceFallbackForSnapshot() {
        usesFallbackOnly = true
        tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.22).cgColor
        vignette.layer?.opacity = 1.0
        updateVisibility()
    }
    #endif

    private func updateVisibility() {
        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let showsWallpaper = !reduceTransparency && hasWallpaper && !usesFallbackOnly
        wallpaper.isHidden = !showsWallpaper
        fallback.isHidden = showsWallpaper
    }

    private func updateTint() {
        let workspace = NSWorkspace.shared
        let reduceTransparency = workspace.accessibilityDisplayShouldReduceTransparency

        let alpha: CGFloat = reduceTransparency
            ? (workspace.accessibilityDisplayShouldIncreaseContrast ? 0.14 : 0.10)
            : (workspace.accessibilityDisplayShouldIncreaseContrast ? 0.30 : 0.22)
        tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(alpha).cgColor
        vignette.layer?.opacity = reduceTransparency ? 0.6 : 1.0
    }
}

/// Draws the blurred desktop picture, stretched to the view's bounds.
private final class WallpaperView: NSView {
    override func makeBackingLayer() -> CALayer {
        let layer = CALayer()
        layer.contentsGravity = .resize
        layer.magnificationFilter = .linear
        layer.minificationFilter = .linear
        layer.isOpaque = true
        return layer
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("WallpaperView is created programmatically")
    }

    /// - Returns: `false` when no desktop picture could be rendered, in which
    ///   case the caller falls back to the opaque gradient.
    func render(screen: NSScreen) -> Bool {
        guard let image = WallpaperImage.blurred(for: screen) else { return false }
        layer?.contents = image
        return true
    }
}

/// Loads, composes and blurs the desktop picture.
///
/// Composition honours the desktop's own picture options (scaling, fill
/// colour), so the backdrop matches what the Finder would draw on that screen.
@MainActor
private enum WallpaperImage {
    private struct Key: Hashable {
        var path: String
        var width: Int
        var height: Int
    }

    /// Blurring a 4K picture costs tens of milliseconds; the panel asks for the
    /// same screen from two windows, so the result is reused until the picture
    /// or the screen size changes.
    private static var cache: [Key: CGImage] = [:]
    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// The typed-enum members AppKit exposes for these keys are incomplete;
    /// the raw keys are the same strings the workspace puts in the dictionary.
    private static let scalingKey = NSWorkspace.DesktopImageOptionKey(
        rawValue: "NSWorkspaceDesktopImageScalingKey"
    )
    private static let allowClippingKey = NSWorkspace.DesktopImageOptionKey(
        rawValue: "NSWorkspaceDesktopImageAllowClippingKey"
    )
    private static let fillColorKey = NSWorkspace.DesktopImageOptionKey(
        rawValue: "NSWorkspaceDesktopImageFillColorKey"
    )

    static func blurred(for screen: NSScreen) -> CGImage? {
        let workspace = NSWorkspace.shared
        guard let url = workspace.desktopImageURL(for: screen),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let picture = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }

        // The result is blurred and then stretched over the screen, so it is
        // composed at a fraction of the pixel size: a quarter is invisible
        // after the blur yet renders in a few milliseconds instead of a third
        // of a second on an integrated GPU.
        let scale = screen.backingScaleFactor * Self.renderScale
        let width = Int((screen.frame.width * scale).rounded())
        let height = Int((screen.frame.height * scale).rounded())
        guard width > 0, height > 0 else { return nil }

        let key = Key(path: url.path, width: width, height: height)
        if let cached = cache[key] { return cached }

        let options = workspace.desktopImageOptions(for: screen) ?? [:]
        guard let composed = compose(picture, width: width, height: height, options: options)
        else { return nil }

        let radius = max(4, CGFloat(width) * 0.022)
        let blurred = blur(composed, radius: radius) ?? composed
        cache[key] = blurred
        return blurred
    }

    /// Fraction of the screen's pixel size the backdrop is rendered at.
    private static let renderScale: CGFloat = 0.25

    private static func compose(
        _ picture: CGImage,
        width: Int,
        height: Int,
        options: [NSWorkspace.DesktopImageOptionKey: Any]
    ) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else { return nil }

        let canvas = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        let fill = (options[fillColorKey] as? NSColor) ?? .black
        context.setFillColor(fill.cgColor)
        context.fill(canvas)

        let scaling: NSImageScaling
        if let raw = (options[scalingKey] as? NSNumber)?.uintValue,
           let parsed = NSImageScaling(rawValue: raw) {
            scaling = parsed
        } else {
            scaling = .scaleProportionallyUpOrDown
        }
        let clips = (options[allowClippingKey] as? NSNumber)?.boolValue ?? false
        let size = CGSize(width: CGFloat(picture.width), height: CGFloat(picture.height))
        let destination = destinationRect(
            for: size,
            in: canvas.size,
            scaling: scaling,
            clips: clips
        )

        context.interpolationQuality = .medium
        context.draw(picture, in: destination)
        return context.makeImage()
    }

    private static func destinationRect(
        for size: CGSize,
        in canvas: CGSize,
        scaling: NSImageScaling,
        clips: Bool
    ) -> CGRect {
        guard size.width > 0, size.height > 0 else { return CGRect(origin: .zero, size: canvas) }

        switch scaling {
        case .scaleNone:
            // Natural pixel size, centred on the screen.
            return CGRect(
                x: (canvas.width - size.width) / 2,
                y: (canvas.height - size.height) / 2,
                width: size.width,
                height: size.height
            )

        case .scaleAxesIndependently:
            // "Stretch to fill screen".
            return CGRect(origin: .zero, size: canvas)

        default:
            // Proportional: clipping is the Finder's "Fill Screen", otherwise
            // the picture is fully visible and padded with the fill colour.
            let ratio: CGFloat
            if clips {
                ratio = max(canvas.width / size.width, canvas.height / size.height)
            } else {
                ratio = min(canvas.width / size.width, canvas.height / size.height)
            }
            var scaled = CGSize(width: size.width * ratio, height: size.height * ratio)
            if scaling == .scaleProportionallyDown {
                let scale = min(1, ratio)
                scaled = CGSize(width: size.width * scale, height: size.height * scale)
            }
            return CGRect(
                x: (canvas.width - scaled.width) / 2,
                y: (canvas.height - scaled.height) / 2,
                width: scaled.width,
                height: scaled.height
            )
        }
    }

    private static func blur(_ image: CGImage, radius: CGFloat) -> CGImage? {
        let input = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage?.cropped(to: input.extent) else { return nil }
        return context.createCGImage(output, from: input.extent)
    }
}

/// Opaque replacement used when Reduce Transparency is on or the desktop
/// picture cannot be read.
private final class GradientBackdropView: NSView {
    override func makeBackingLayer() -> CALayer {
        let gradient = CAGradientLayer()
        gradient.colors = [
            NSColor(calibratedRed: 0.09, green: 0.08, blue: 0.24, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.16, green: 0.15, blue: 0.36, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.08, green: 0.12, blue: 0.28, alpha: 1).cgColor
        ]
        gradient.locations = [0, 0.55, 1]
        gradient.startPoint = CGPoint(x: 0.15, y: 0)
        gradient.endPoint = CGPoint(x: 0.85, y: 1)
        return gradient
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("GradientBackdropView is created programmatically")
    }
}

/// Soft radial darkening towards the screen corners.
private final class VignetteView: NSView {
    override func makeBackingLayer() -> CALayer {
        let gradient = CAGradientLayer()
        gradient.type = .radial
        gradient.colors = [
            NSColor.clear.cgColor,
            NSColor.black.withAlphaComponent(0.06).cgColor,
            NSColor.black.withAlphaComponent(0.34).cgColor
        ]
        gradient.locations = [0.0, 0.55, 1.0]
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 1.25, y: 1.25)
        return gradient
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("VignetteView is created programmatically")
    }
}

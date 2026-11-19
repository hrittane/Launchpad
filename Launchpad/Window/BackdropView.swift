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

    /// The screen last presented, so a settings change can re-render in place.
    private var screen: NSScreen?

    /// Set by the snapshot mode, which needs a deterministic opaque backdrop.
    private var usesFallbackOnly = false

    /// User settings. The dim is a plain black tint; the blur is part of the
    /// wallpaper composition and therefore re-renders the picture.
    private var blursWallpaper = true
    private var dimAlpha: CGFloat = 0.22

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
        self.screen = screen
        hasWallpaper = wallpaper.render(screen: screen, blurred: blursWallpaper)
        updateVisibility()
    }

    /// Applies the look-and-feel settings, re-rendering the wallpaper when the
    /// blur toggle changes.
    func apply(blurWallpaper: Bool, dim: CGFloat) {
        let blurChanged = blursWallpaper != blurWallpaper
        blursWallpaper = blurWallpaper
        dimAlpha = min(max(dim, 0), 0.85)
        updateTint()
        guard blurChanged, !usesFallbackOnly, let screen else { return }
        hasWallpaper = wallpaper.render(screen: screen, blurred: blursWallpaper)
        updateVisibility()
    }

    /// Warms the rendering pipeline at launch, so the first presentation does
    /// not pay Core Image's one-off shader compilation on the main thread.
    static func preheat() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        _ = WallpaperImage.blurred(for: screen, blurred: true)
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
        let increaseContrast = workspace.accessibilityDisplayShouldIncreaseContrast

        let alpha: CGFloat
        if reduceTransparency {
            alpha = increaseContrast ? 0.14 : 0.10
        } else {
            alpha = min(0.85, dimAlpha + (increaseContrast ? 0.08 : 0))
        }
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
    func render(screen: NSScreen, blurred: Bool) -> Bool {
        guard let image = WallpaperImage.blurred(for: screen, blurred: blurred) else {
            return false
        }
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
        var blurred: Bool
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

    static func blurred(for screen: NSScreen, blurred: Bool) -> CGImage? {
        let workspace = NSWorkspace.shared
        guard let url = pictureURL(for: screen),
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

        let key = Key(path: url.path, width: width, height: height, blurred: blurred)
        if let cached = cache[key] { return cached }

        let options = workspace.desktopImageOptions(for: screen)
        guard let composed = compose(picture, width: width, height: height, options: options)
        else { return nil }

        let result: CGImage
        if blurred {
            let radius = max(4, CGFloat(width) * 0.022)
            result = blur(composed, radius: radius) ?? composed
        } else {
            result = composed
        }
        cache[key] = result
        return result
    }

    /// Fraction of the screen's pixel size the backdrop is rendered at.
    private static let renderScale: CGFloat = 0.25

    /// The file the desktop is currently showing.
    ///
    /// `desktopImageURL` normally points straight at the picture, but it is
    /// only authoritative when the picture is a file the user picked. For a
    /// wallpaper supplied by a wallpaper extension — every system wallpaper
    /// since macOS 14, including the default — it reports
    /// `/System/Library/CoreServices/DefaultDesktop.heic` instead, which is the
    /// old Tahoe Lake aerial, not what is on screen. `SystemWallpaper` resolves
    /// the active extension and its rendered picture for that case.
    ///
    /// The reported URL also goes stale when the file is deleted or moved: the
    /// Finder keeps drawing the picture anyway, because the Wallpaper settings
    /// extension keeps its own copy for exactly that case. Without that
    /// fallback the panel would drop to the opaque gradient while the desktop
    /// still shows the picture.
    private static func pictureURL(for screen: NSScreen) -> URL? {
        let reported = NSWorkspace.shared.desktopImageURL(for: screen)

        if let reported, FileManager.default.isReadableFile(atPath: reported.path) {
            guard SystemWallpaper.isPlaceholder(reported) else { return reported }
            return SystemWallpaper.picture(for: screen) ?? reported
        }
        if let reported, let copy = WallpaperStore.cachedCopy(of: reported) { return copy }
        return SystemWallpaper.picture(for: screen)
    }

    private static func compose(
        _ picture: CGImage,
        width: Int,
        height: Int,
        options: [NSWorkspace.DesktopImageOptionKey: Any]?
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
        let fill = (options?[fillColorKey] as? NSColor) ?? .black
        context.setFillColor(fill.cgColor)
        context.fill(canvas)

        let scaling: NSImageScaling
        if let raw = (options?[scalingKey] as? NSNumber)?.uintValue,
           let parsed = NSImageScaling(rawValue: raw) {
            scaling = parsed
        } else {
            scaling = .scaleProportionallyUpOrDown
        }
        // Extension wallpapers report no picture options at all, and all of
        // them are meant to fill the screen ("Fill Screen" is the modern
        // default). Fitting them instead would letterbox a square still with
        // bars of the fill colour.
        let clips = (options?[allowClippingKey] as? NSNumber)?.boolValue ?? true
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

/// Resolves the picture of a wallpaper supplied by a wallpaper extension.
///
/// `NSWorkspace.desktopImageURL(for:)` does not know about extension
/// wallpapers: for every system wallpaper it reports the built-in
/// `DefaultDesktop.heic` placeholder. The real picture lives in two places:
///
/// - The provider's app extension bundles the wallpaper still itself
///   (`TahoeLight.heic`, `TahoeDark.heic`, …), which is exactly what the
///   window server draws when the wallpaper is not animated.
/// - The wallpaper agent renders what it draws for the screen at the screen's
///   pixel size under
///   `~/Library/Containers/com.apple.wallpaper.agent/…/extension-<provider>/`.
///   The newest render of the active provider is the current wallpaper,
///   already cropped and already the right light/dark variant. This covers
///   extensions that only bundle thumbnails and wallpapers whose still has
///   not been downloaded.
///
/// Which provider is active is written by the system in
/// `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`.
@MainActor
private enum SystemWallpaper {
    private static let placeholderPaths: Set<String> = [
        "/System/Library/CoreServices/DefaultDesktop.heic",
        "/System/Library/Wallpapers/.default/DefaultAerial.heic",
        "/System/Library/Wallpapers/.default/DefaultAerial.jpg"
    ]

    /// True when `url` is the built-in picture `desktopImageURL` substitutes
    /// for a wallpaper it cannot name, rather than the picture on screen.
    static func isPlaceholder(_ url: URL) -> Bool {
        placeholderPaths.contains(url.standardizedFileURL.resolvingSymlinksInPath().path)
    }

    static func picture(for screen: NSScreen) -> URL? {
        // The bundled still is the wallpaper itself; prefer it. It is only
        // skipped when the extension bundles thumbnails rather than the
        // picture (Sequoia), in which case the agent's render is exact.
        bundledPicture(for: screen) ?? renderedPicture(for: screen)
    }

    /// The last frame the wallpaper agent rendered for the active provider.
    private static func renderedPicture(for screen: NSScreen) -> URL? {
        guard let provider = activeProvider(for: screen) else { return nil }
        let directory = cachesURL.appending(
            path: "extension-\(provider)",
            directoryHint: .isDirectory
        )
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let renders = entries.compactMap { url -> (url: URL, date: Date)? in
            // Temporary writes end in `.bmp.sb-…`; only completed renders end
            // in `.bmp`.
            guard url.pathExtension.lowercased() == "bmp" else { return nil }
            guard let values = try? url.resourceValues(
                forKeys: [.contentModificationDateKey, .fileSizeKey]
            ),
            let date = values.contentModificationDate,
            (values.fileSize ?? 0) > 0 else { return nil }
            return (url, date)
        }
        guard !renders.isEmpty else { return nil }

        // A provider can have renders for more than one display; prefer the
        // one made for this screen's pixel size.
        let width = Int((screen.frame.width * screen.backingScaleFactor).rounded())
        let height = Int((screen.frame.height * screen.backingScaleFactor).rounded())
        let sizeTag = "-\(width)-\(height)-"
        let matching = renders.filter { $0.url.lastPathComponent.contains(sizeTag) }
        return (matching.isEmpty ? renders : matching)
            .max { $0.date < $1.date }?
            .url
    }

    /// The provider's bundled still, chosen for the current appearance.
    private static func bundledPicture(for screen: NSScreen) -> URL? {
        guard let provider = activeProvider(for: screen) else { return nil }
        let extensions = URL(
            fileURLWithPath: "/System/Library/ExtensionKit/Extensions",
            isDirectory: true
        )
        guard let bundles = try? FileManager.default.contentsOfDirectory(
            at: extensions,
            includingPropertiesForKeys: nil
        ),
        let bundle = bundles.first(where: { Bundle(url: $0)?.bundleIdentifier == provider })
        else { return nil }

        let resources = bundle.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: resources,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let pictures = files.filter {
            ["heic", "png", "jpg", "jpeg"].contains($0.pathExtension.lowercased())
                && !name($0).contains("thumbnail")
        }
        guard !pictures.isEmpty else { return nil }

        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let wanted = isDark ? "dark" : "light"
        let unwanted = isDark ? "light" : "dark"
        let preferred = pictures.filter { name($0).contains(wanted) }
        let neutral = pictures.filter { !name($0).contains(unwanted) }
        let candidates = preferred.isEmpty ? neutral : preferred
        return candidates.max { size(of: $0) < size(of: $1) }
    }

    private static func name(_ url: URL) -> String {
        url.deletingPathExtension().lastPathComponent.lowercased()
    }

    private static func size(of url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
    }

    /// The provider of the wallpaper choice that applies to `screen`.
    private static func activeProvider(for screen: NSScreen) -> String? {
        guard let data = try? Data(contentsOf: indexURL),
              let index = try? PropertyListSerialization.propertyList(
                  from: data,
                  format: nil
              ) as? [String: Any] else { return nil }

        // The agent resolves a per-display choice first, then per-space, then
        // the shared one, then the system default.
        if let display = displayUUID(for: screen),
           let displays = index["Displays"] as? [String: Any],
           let provider = provider(in: displays[display]) {
            return provider
        }
        for key in ["Spaces", "AllSpacesAndDisplays", "SystemDefault"] {
            if let provider = provider(in: index[key]) { return provider }
        }
        if let provider = provider(in: index["Displays"]) { return provider }
        return nil
    }

    /// Follows a store section (`linked` references and `choices` arrays) to
    /// the first wallpaper choice.
    private static func provider(in section: Any?) -> String? {
        guard let section else { return nil }
        if let dictionary = section as? [String: Any] {
            if let linked = dictionary["Linked"], let provider = provider(in: linked) {
                return provider
            }
            if let choices = dictionary["Choices"] as? [[String: Any]] {
                for choice in choices {
                    if let provider = choice["Provider"] as? String, !provider.isEmpty {
                        return provider
                    }
                }
            }
            for key in dictionary.keys.sorted() where key != "Choices" {
                if let provider = provider(in: dictionary[key]) { return provider }
            }
        }
        if let array = section as? [Any] {
            for entry in array {
                if let provider = provider(in: entry) { return provider }
            }
        }
        return nil
    }

    /// The store keys displays by the UUID the window server assigns them.
    private static func displayUUID(for screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber else { return nil }
        let display = CGDirectDisplayID(number.uint32Value)
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    private static var indexURL: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appending(path: "Library/Application Support/com.apple.wallpaper/Store/Index.plist")
    }

    private static var cachesURL: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appending(
                path: "Library/Containers/com.apple.wallpaper.agent/Data/Library/Caches"
                    + "/com.apple.wallpaper.caches",
                directoryHint: .isDirectory
            )
    }
}

/// Recovers the picture the desktop is showing when its file is gone.
///
/// Picking a picture copies it into the Wallpaper settings extension's
/// container, and the list of those copies survives the original file. Each
/// entry remembers the URL it was made from, which is the same URL
/// `NSWorkspace` keeps reporting after a deletion, so the current picture can
/// be matched exactly instead of guessing.
private enum WallpaperStore {
    private struct Choice {
        var original: URL
        var copy: URL
        var dateAdded: Date
    }

    private static var preferencesURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appending(path: "Library/Containers/com.apple.wallpaper.extension.image")
            .appending(path: "Data/Library/Preferences")
            .appending(path: "com.apple.wallpaper.extension.image.plist")
    }

    /// The extension's copy of the picture that `original` used to point at.
    ///
    /// - Returns: `nil` when the extension never cached that picture (or its
    ///   copy has been cleaned up as well), in which case the caller keeps the
    ///   opaque fallback.
    static func cachedCopy(of original: URL) -> URL? {
        let fileManager = FileManager.default
        let choices = loadChoices().filter {
            fileManager.isReadableFile(atPath: $0.copy.path)
        }

        let exact = choices
            .filter { $0.original.path == original.path }
            .max { $0.dateAdded < $1.dateAdded }
        if let exact { return exact.copy }

        // A moved file keeps its name but loses its directory in the entry, so
        // a matching name is the best remaining clue.
        let sameName = choices
            .filter { $0.original.lastPathComponent == original.lastPathComponent }
            .max { $0.dateAdded < $1.dateAdded }
        return sameName?.copy
    }

    private static func loadChoices() -> [Choice] {
        guard let data = try? Data(contentsOf: preferencesURL),
              let preferences = try? PropertyListSerialization.propertyList(
                  from: data,
                  format: nil
              ) as? [String: Any],
              let entries = preferences["ChoiceRequests.ImageFiles"] as? [Data] else {
            return []
        }

        return entries.compactMap { entry in
            guard let archive = try? PropertyListSerialization.propertyList(
                    from: entry,
                    format: nil
                  ) as? [String: Any],
                  let original = url(from: archive["originalURL"]),
                  let copy = url(from: archive["copyURL"]) else { return nil }
            return Choice(
                original: original,
                copy: copy,
                dateAdded: archive["dateAdded"] as? Date ?? .distantPast
            )
        }
    }

    private static func url(from value: Any?) -> URL? {
        guard let entry = value as? [String: Any],
              let string = entry["relative"] as? String else { return nil }
        return URL(string: string)
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

import AppKit
import AVFoundation
import CoreGraphics
import ImageIO

/// Resolves the wallpaper the system is actually displaying.
///
/// `NSWorkspace.desktopImageURL(for:)` is the public API, but on macOS 26 it
/// returns the generic `DefaultDesktop.heic` fallback for provider-backed
/// wallpapers (the Tahoe default and dynamic aerials). Those wallpapers live in
/// the system wallpaper store and in provider bundles, so this resolver reads
/// the store, maps the provider to its real still or video frame, and only uses
/// the public URL when it is not the generic desktop.
@MainActor
enum SystemWallpaper {
    struct Source {
        /// Stable identity for the blur cache.
        let identity: String
        /// Source image, already downscaled for a blurred backdrop.
        let image: CGImage
    }

    enum Appearance {
        case light
        case dark
    }

    private static let storeURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
    private static let aerialVideoDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials/videos")
    private static let neptuneResourceDirectory = URL(
        fileURLWithPath: "/System/Library/ExtensionKit/Extensions/NeptuneOneWallpaper.appex/Contents/Resources",
        isDirectory: true
    )

    static func resolve(for screen: NSScreen) -> Source? {
        let publicURL = NSWorkspace.shared.desktopImageURL(for: screen)

        // A user-picked static image is already the real wallpaper.
        if let publicURL, !isGenericFallback(publicURL),
           let image = loadImage(publicURL) {
            return Source(
                identity: "file:\(publicURL.resolvingSymlinksInPath().path)",
                image: image
            )
        }

        if let store = loadStore(),
           let source = resolveFromStore(
               store,
               appearance: currentAppearance,
               screen: screen
           ) {
            return source
        }

        // Nothing better than the system's generic fallback.
        if let publicURL, let image = loadImage(publicURL) {
            let path = publicURL.resolvingSymlinksInPath().path
            return Source(identity: "fallback:\(path)", image: image)
        }
        return nil
    }

    /// A cheap token that changes when the wallpaper or appearance changes.
    ///
    /// The backdrop uses this to decide whether its cached blur is still valid
    /// before a show. It stats the wallpaper store and provider resources but
    /// never decodes an image, so calling it on the show path is cheap.
    static func signature(for screen: NSScreen) -> String {
        let appearance = currentAppearance == .dark ? "dark" : "light"
        let publicPath = NSWorkspace.shared.desktopImageURL(for: screen)?
            .resolvingSymlinksInPath().path ?? "none"
        return [
            appearance,
            publicPath,
            fileSignature(storeURL),
            fileSignature(aerialVideoDirectory)
        ].joined(separator: "|")
    }

    /// The public API points at this generic aerial when the real wallpaper is
    /// provider-backed and cannot be represented by a single user file.
    static func isGenericFallback(_ url: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().path
        return path.hasSuffix("/DefaultDesktop.heic")
            || path.hasSuffix("/DefaultAerial.heic")
            || path.hasSuffix("/DefaultAerial.jpg")
    }

    /// Pulls the aerial id out of the store's nested `EncodedOptionValues`
    /// plist. Returns `nil` for the "automatic" appearance picker.
    static func aerialIdentifier(fromEncodedOptions data: Data) -> String? {
        guard
            let plist = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ),
            let root = plist as? [String: Any],
            let values = root["values"] as? [String: Any],
            let appearance = values["appearance"] as? [String: Any],
            let picker = appearance["picker"] as? [String: Any],
            let first = picker["_0"] as? [String: Any],
            let identifier = first["id"] as? String,
            identifier != "automatic"
        else { return nil }
        return identifier
    }

    static func resolveFromStore(
        _ store: [String: Any],
        appearance: Appearance,
        screen: NSScreen? = nil
    ) -> Source? {
        guard
            let content = wallpaperContent(in: store, for: screen),
            let choices = content["Choices"] as? [[String: Any]],
            let choice = choices.first
        else { return nil }

        // A linked file is the most direct description of the wallpaper.
        if let files = choice["Files"] as? [String], let path = files.first {
            let url = URL(fileURLWithPath: path)
            if let image = loadImage(url) {
                return Source(identity: "file:\(url.path)", image: image)
            }
        }

        let provider = choice["Provider"] as? String
        let encoded = content["EncodedOptionValues"] as? Data
        let aerialID = encoded.flatMap { aerialIdentifier(fromEncodedOptions: $0) }

        if let aerialID {
            guard let image = loadVideoFrame(id: aerialID) else {
                // A chosen aerial that is not downloaded. Substituting a
                // different wallpaper would be worse than the material fallback.
                return nil
            }
            return Source(identity: "aerial:\(aerialID)", image: image)
        }

        if provider == "com.apple.NeptuneOneExtension" {
            return neptuneSource(appearance: appearance)
        }

        return nil
    }

    private static func wallpaperContent(
        in store: [String: Any],
        for screen: NSScreen?
    ) -> [String: Any]? {
        // Per-display choices take precedence over the all-displays default.
        if let screen,
           let displays = store["Displays"] as? [String: Any],
           let uuid = displayUUID(for: screen) {
            for (key, value) in displays where key.caseInsensitiveCompare(uuid) == .orderedSame {
                if let content = linkedContent(value) {
                    return content
                }
            }
        }

        guard let all = store["AllSpacesAndDisplays"] else { return nil }
        return linkedContent(all)
    }

    private static func linkedContent(_ value: Any) -> [String: Any]? {
        guard
            let entry = value as? [String: Any],
            let linked = entry["Linked"] as? [String: Any],
            let content = linked["Content"] as? [String: Any]
        else { return nil }
        return content
    }

    private static var currentAppearance: Appearance {
        let match = NSApplication.shared.effectiveAppearance
            .bestMatch(from: [.darkAqua, .aqua])
        return match == .darkAqua ? .dark : .light
    }

    private static func neptuneSource(appearance: Appearance) -> Source? {
        let name = appearance == .dark ? "TahoeDark" : "TahoeLight"
        let url = neptuneResourceDirectory.appendingPathComponent("\(name).heic")
        guard let image = loadImage(url) else { return nil }
        return Source(identity: "neptune:\(name)", image: image)
    }

    private static func loadImage(_ url: URL, maxPixelSize: Int = 1280) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func loadVideoFrame(id: String) -> CGImage? {
        let url = aerialVideoDirectory.appendingPathComponent("\(id).mov")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)
        // Aerial videos are long ambient loops; one second in is past any
        // fade-in and represents the scene the desktop is showing.
        let time = CMTime(seconds: 1, preferredTimescale: 600)

        let box = ImageBox()
        let semaphore = DispatchSemaphore(value: 0)
        generator.generateCGImageAsynchronously(for: time) { image, _, _ in
            box.store(image)
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 5) == .success else { return nil }
        return box.load()
    }

    /// Thread-safe hand-off between AVFoundation's callback queue and the
    /// synchronous wallpaper pipeline.
    private final class ImageBox: @unchecked Sendable {
        private let lock = NSLock()
        private var image: CGImage?

        func store(_ image: CGImage?) {
            lock.lock()
            self.image = image
            lock.unlock()
        }

        func load() -> CGImage? {
            lock.lock()
            defer { lock.unlock() }
            return image
        }
    }

    private static func displayUUID(for screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber else { return nil }

        let displayID = CGDirectDisplayID(truncating: number)
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?
            .takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    private static func fileSignature(_ url: URL) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(
            atPath: url.path
        ) else { return "missing" }
        let modified = (attributes[.modificationDate] as? Date)?
            .timeIntervalSince1970 ?? 0
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        return "\(Int64(modified)):\(size)"
    }

    private static func loadStore() -> [String: Any]? {
        guard let data = try? Data(contentsOf: storeURL) else { return nil }
        guard let plist = try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) else { return nil }
        return plist as? [String: Any]
    }
}

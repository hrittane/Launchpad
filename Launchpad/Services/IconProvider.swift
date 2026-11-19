import AppKit
import Observation

/// Wrapper that lets us move an `NSImage` created off the main actor back to it.
/// `NSImage` is immutable once created and safe to read from multiple threads.
struct SendableImage: @unchecked Sendable {
    let image: NSImage
}

/// Loads and caches application icons off the main thread.
///
/// `NSWorkspace` renders the icon in the icon style macOS is currently set to
/// (Normal, Clear, Dark or Tinted) and in the current light/dark appearance.
/// The cache therefore belongs to one appearance only: when that appearance
/// changes the cached images are dropped and every visible icon reloads.
@MainActor
@Observable
final class IconProvider {
    static let shared = IconProvider()

    @ObservationIgnored private let cache = NSCache<NSString, NSImage>()
    @ObservationIgnored private var tasks: [String: LoadTask] = [:]
    @ObservationIgnored private var appearanceKey: String
    @ObservationIgnored private var appearanceTask: Task<Void, Never>?

    /// Incremented whenever the system icon appearance changes, so views that
    /// already loaded an icon know to load it again.
    private(set) var revision = 0

    private struct LoadTask {
        let token: UUID
        let task: Task<SendableImage?, Never>
    }

    private init() {
        cache.countLimit = 800
        appearanceKey = Self.appearanceKey(defaults: .standard)
        appearanceTask = Task { @MainActor [weak self] in
            // The system does not post a notification for this preference that
            // a third-party app can observe, so poll the two defaults it
            // depends on. Two dictionary lookups a second are free.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.refreshForCurrentAppearance()
            }
        }
    }

    func cachedIcon(for item: AppItem) -> NSImage? {
        cache.object(forKey: item.id as NSString)
    }

    func icon(for item: AppItem) async -> NSImage? {
        if let cached = cachedIcon(for: item) { return cached }
        if let running = tasks[item.id] { return await running.task.value?.image }

        let url = item.url
        let generation = revision
        let token = UUID()
        let task = Task.detached(priority: .utility) { () -> SendableImage? in
            let image = NSWorkspace.shared.icon(forFile: url.path)
            image.size = NSSize(width: 256, height: 256)
            return SendableImage(image: image)
        }
        tasks[item.id] = LoadTask(token: token, task: task)

        let result = await task.value
        if tasks[item.id]?.token == token {
            tasks[item.id] = nil
        }
        guard let image = result?.image else { return nil }
        // The style may have changed while this icon was loading. Caching it
        // would put the previous appearance back after the cache was cleared.
        if generation == revision {
            cache.setObject(image, forKey: item.id as NSString)
        }
        return image
    }

    func prefetch(_ items: [AppItem]) {
        for item in items where cachedIcon(for: item) == nil && tasks[item.id] == nil {
            Task { _ = await icon(for: item) }
        }
    }

    /// Drops every cached icon when macOS switched to another icon style or
    /// light/dark appearance, then bumps `revision` so visible icons reload.
    func refreshForCurrentAppearance() {
        let key = Self.appearanceKey(defaults: .standard)
        guard key != appearanceKey else { return }
        appearanceKey = key
        cache.removeAllObjects()
        tasks.removeAll()
        revision &+= 1
    }

    /// The preferences `NSWorkspace` uses to choose the icon variant. The tint
    /// keys only exist in the Tinted style, so they are appended when present.
    nonisolated static func appearanceKey(defaults: UserDefaults) -> String {
        let base = appearanceKey(
            theme: defaults.string(forKey: "AppleIconAppearanceTheme")
                ?? defaults.string(forKey: "SLSIconAppearanceTheme"),
            style: defaults.string(forKey: "AppleInterfaceStyle")
        )
        var parts = [base]
        for key in ["SLSIconAppearanceTintColorName", "CustomTintColor", "AppleAccentColor"] {
            if let value = stringValue(defaults, key) {
                parts.append(value)
            }
        }
        return parts.joined(separator: "|")
    }

    nonisolated static func appearanceKey(theme: String?, style: String?) -> String {
        let theme = theme ?? "Default"
        let style = style ?? "Light"
        return "\(theme)|\(style)"
    }

    private nonisolated static func stringValue(_ defaults: UserDefaults, _ key: String) -> String? {
        guard let value = defaults.object(forKey: key) else { return nil }
        // A custom tint is archived colour data; its description is only its
        // length, so encode the bytes to keep different colours distinct.
        if let data = value as? Data {
            return data.base64EncodedString()
        }
        return String(describing: value)
    }
}

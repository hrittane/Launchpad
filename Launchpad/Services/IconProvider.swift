import AppKit

/// Wrapper that lets us move an `NSImage` created off the main actor back to it.
/// `NSImage` is immutable once created and safe to read from multiple threads.
struct SendableImage: @unchecked Sendable {
    let image: NSImage
}

/// Loads and caches application icons off the main thread.
@MainActor
final class IconProvider {
    static let shared = IconProvider()

    private let cache = NSCache<NSString, NSImage>()
    private var tasks: [String: Task<SendableImage?, Never>] = [:]

    private init() {
        cache.countLimit = 800
    }

    func cachedIcon(for item: AppItem) -> NSImage? {
        cache.object(forKey: item.id as NSString)
    }

    func icon(for item: AppItem) async -> NSImage? {
        if let cached = cachedIcon(for: item) { return cached }
        if let running = tasks[item.id] { return await running.value?.image }

        let url = item.url
        let task = Task.detached(priority: .utility) { () -> SendableImage? in
            let image = NSWorkspace.shared.icon(forFile: url.path)
            image.size = NSSize(width: 256, height: 256)
            return SendableImage(image: image)
        }
        tasks[item.id] = task

        let result = await task.value
        tasks[item.id] = nil
        guard let image = result?.image else { return nil }
        cache.setObject(image, forKey: item.id as NSString)
        return image
    }

    func prefetch(_ items: [AppItem]) {
        for item in items where cachedIcon(for: item) == nil && tasks[item.id] == nil {
            Task { _ = await icon(for: item) }
        }
    }
}

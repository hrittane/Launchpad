import Foundation

/// Persists the custom grid arrangement as JSON.
///
/// Writes are debounced by 0.5 s. The actor is the only owner of the file URL
/// and pending document, so concurrent loads and saves cannot interleave.
actor LayoutStore {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var pendingPages: [PageLayout]?
    private var saveTask: Task<Void, Never>?

    init(fileURL: URL = LayoutStore.defaultFileURL(), fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    static func applicationSupportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Launchpad", isDirectory: true)
    }

    static func defaultFileURL() -> URL {
        applicationSupportDirectory().appendingPathComponent("layout.json", isDirectory: false)
    }

    /// Reads and validates the persisted document. Corrupt files are ignored
    /// rather than crashing or blocking startup.
    func load() -> [PageLayout] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        guard let document = try? decoder.decode(LayoutDocument.self, from: data) else { return [] }
        guard document.version <= LayoutDocument.currentVersion else { return [] }
        return document.pages
    }

    /// Queues a debounced write. Repeated calls reset the timer.
    func save(_ pages: [PageLayout]) {
        pendingPages = pages
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Metrics.Durations.layoutSaveDebounce * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.flushIfNeeded()
        }
    }

    /// Writes any pending document immediately. Safe to call repeatedly.
    func flushIfNeeded() {
        saveTask?.cancel()
        saveTask = nil
        guard let pages = pendingPages else { return }
        pendingPages = nil
        try? write(pages)
    }

    /// Synchronous write used by tests and by the "save on close" path.
    func saveImmediately(_ pages: [PageLayout]) throws {
        saveTask?.cancel()
        saveTask = nil
        pendingPages = nil
        try write(pages)
    }

    private func write(_ pages: [PageLayout]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let document = LayoutDocument(pages: pages)
        let data = try encoder.encode(document)
        try data.write(to: fileURL, options: [.atomic])
    }

    /// The URL is exposed for diagnostics shown in Preferences.
    nonisolated var url: URL { fileURL }
}

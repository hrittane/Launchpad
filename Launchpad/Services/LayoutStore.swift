import Foundation

/// Reads and writes the layout JSON in Application Support.
struct LayoutStore {
    static let shared = LayoutStore()

    private let url: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Launchpad", isDirectory: true)
        url = base.appendingPathComponent("layout.json")
    }

    var fileURL: URL { url }

    func load() -> LauncherLayout? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(LauncherLayout.self, from: data)
    }

    func save(_ layout: LauncherLayout) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(layout)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("Launchpad: could not save the layout: \(error.localizedDescription)")
        }
    }
}

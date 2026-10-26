import Foundation

/// Persists user preferences in `UserDefaults` as JSON, keeping AppSettings a
/// single source of truth shared by the UI, the layout, and input services.
final class SettingsStore {
    static let defaultKey = "com.soufiane.launchpad.settings"

    private let defaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard, key: String = SettingsStore.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    func load() -> AppSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? decoder.decode(AppSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    func save(_ settings: AppSettings) {
        guard let data = try? encoder.encode(settings) else { return }
        defaults.set(data, forKey: key)
    }

    func reset() {
        defaults.removeObject(forKey: key)
    }
}

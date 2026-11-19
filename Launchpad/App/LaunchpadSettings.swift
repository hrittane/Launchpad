import Foundation
import Observation

extension Notification.Name {
    /// Posted after any setting changes, so the AppKit side (hot key, hot
    /// corner, pinch monitor, panel) can react without polling.
    static let launchpadSettingsDidChange = Notification.Name("LaunchpadSettingsDidChange")
}

/// User-facing preferences, persisted in `UserDefaults`.
///
/// The grid columns/rows decide how many icons a page holds, so changing them
/// also reflows the saved layout. Everything else is purely visual.
@MainActor
@Observable
final class LaunchpadSettings {
    static let shared = LaunchpadSettings(defaults: .standard)

    enum HotCorner: String, CaseIterable, Identifiable {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight

        var id: Self { self }

        var title: String {
            switch self {
            case .topLeft: return "Top Left"
            case .topRight: return "Top Right"
            case .bottomLeft: return "Bottom Left"
            case .bottomRight: return "Bottom Right"
            }
        }
    }

    static let columnChoices = [7, 8, 9]
    static let rowChoices = [4, 5, 6]

    private enum Key {
        static let columns = "Launchpad.columns"
        static let rows = "Launchpad.rows"
        static let iconScale = "Launchpad.iconScale"
        static let labelScale = "Launchpad.labelScale"
        static let showLabels = "Launchpad.showLabels"
        static let blurWallpaper = "Launchpad.blurWallpaper"
        static let backgroundDim = "Launchpad.backgroundDim"
        static let hotKeyEnabled = "Launchpad.hotKeyEnabled"
        static let hotCornerEnabled = "Launchpad.hotCornerEnabled"
        static let hotCorner = "Launchpad.hotCorner"
        static let pinchEnabled = "Launchpad.pinchEnabled"
        static let suppressDesktopSwipe = "Launchpad.suppressDesktopSwipe"
        static let showMenuBarIcon = "Launchpad.showMenuBarIcon"
    }

    @ObservationIgnored private let defaults: UserDefaults

    // MARK: Grid

    var columns: Int {
        didSet { persist(columns, Key.columns) }
    }

    var rows: Int {
        didSet { persist(rows, Key.rows) }
    }

    /// Multiplier applied to the icon size derived from the grid.
    var iconScale: Double {
        didSet { persist(iconScale, Key.iconScale) }
    }

    /// Multiplier applied to the label font size.
    var labelScale: Double {
        didSet { persist(labelScale, Key.labelScale) }
    }

    var showLabels: Bool {
        didSet { persist(showLabels, Key.showLabels) }
    }

    // MARK: Background

    var blurWallpaper: Bool {
        didSet { persist(blurWallpaper, Key.blurWallpaper) }
    }

    /// Black tint over the wallpaper, 0…0.6.
    var backgroundDim: Double {
        didSet { persist(backgroundDim, Key.backgroundDim) }
    }

    // MARK: Activation

    var hotKeyEnabled: Bool {
        didSet { persist(hotKeyEnabled, Key.hotKeyEnabled) }
    }

    var hotCornerEnabled: Bool {
        didSet { persist(hotCornerEnabled, Key.hotCornerEnabled) }
    }

    var hotCorner: HotCorner {
        didSet { persist(hotCorner.rawValue, Key.hotCorner) }
    }

    /// Four-finger pinch opens Launchpad. Enabling it also disables the system
    /// Launchpad/Spotlight Apps pinch so the two cannot race.
    var pinchEnabled: Bool {
        didSet { persist(pinchEnabled, Key.pinchEnabled) }
    }

    // MARK: System

    /// Blocks the Dock's trackpad gestures (desktop swipe, Mission Control,
    /// Show Desktop) while the panel is on screen. Needs Accessibility.
    var suppressDesktopSwipe: Bool {
        didSet { persist(suppressDesktopSwipe, Key.suppressDesktopSwipe) }
    }

    var showMenuBarIcon: Bool {
        didSet { persist(showMenuBarIcon, Key.showMenuBarIcon) }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        columns = Self.valid(
            defaults.object(forKey: Key.columns) as? Int ?? 7,
            choices: Self.columnChoices,
            fallback: 7
        )
        rows = Self.valid(
            defaults.object(forKey: Key.rows) as? Int ?? 5,
            choices: Self.rowChoices,
            fallback: 5
        )
        iconScale = Self.clamp(
            defaults.object(forKey: Key.iconScale) as? Double ?? 1,
            lower: 0.75,
            upper: 1.3
        )
        labelScale = Self.clamp(
            defaults.object(forKey: Key.labelScale) as? Double ?? 1,
            lower: 0.75,
            upper: 1.4
        )
        showLabels = defaults.object(forKey: Key.showLabels) as? Bool ?? true
        blurWallpaper = defaults.object(forKey: Key.blurWallpaper) as? Bool ?? true
        backgroundDim = Self.clamp(
            defaults.object(forKey: Key.backgroundDim) as? Double ?? 0.22,
            lower: 0,
            upper: 0.6
        )
        hotKeyEnabled = defaults.object(forKey: Key.hotKeyEnabled) as? Bool ?? true
        hotCornerEnabled = defaults.object(forKey: Key.hotCornerEnabled) as? Bool ?? false
        hotCorner = HotCorner(
            rawValue: defaults.string(forKey: Key.hotCorner) ?? ""
        ) ?? .topLeft
        pinchEnabled = defaults.object(forKey: Key.pinchEnabled) as? Bool ?? false
        suppressDesktopSwipe = defaults.object(forKey: Key.suppressDesktopSwipe) as? Bool ?? true
        showMenuBarIcon = defaults.object(forKey: Key.showMenuBarIcon) as? Bool ?? true
    }

    /// Restores every value to its first-run default.
    func resetToDefaults() {
        columns = 7
        rows = 5
        iconScale = 1
        labelScale = 1
        showLabels = true
        blurWallpaper = true
        backgroundDim = 0.22
        hotKeyEnabled = true
        hotCornerEnabled = false
        hotCorner = .topLeft
        pinchEnabled = false
        suppressDesktopSwipe = true
        showMenuBarIcon = true
    }

    private func persist(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: .launchpadSettingsDidChange, object: self)
    }

    private static func valid(_ value: Int, choices: [Int], fallback: Int) -> Int {
        choices.contains(value) ? value : fallback
    }

    private static func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}

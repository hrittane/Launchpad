import AppKit
import Foundation

/// A recordable global keyboard shortcut.
///
/// Carbon hot keys work from a menu-bar agent without the Accessibility
/// permission required by event taps. We persist both the virtual key code and
/// a human-readable character so the recorder can render its value without
/// reverse-engineering keyboard layouts at display time.
struct KeyShortcut: Codable, Equatable, Hashable, Sendable {
    var keyCode: UInt16
    /// Raw `NSEvent.ModifierFlags` value, restricted to device-independent flags.
    var modifierFlags: UInt
    /// Display label captured at recording time ("F4", "A", "Space", …).
    var displayKey: String

    static let launchpadDefault = KeyShortcut(
        keyCode: 118, // kVK_F4
        modifierFlags: 0,
        displayKey: "F4"
    )

    var modifierFlagsValue: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlags)
    }

    var isValid: Bool {
        !displayKey.isEmpty && !Self.reservedModifierOnlyKeyCodes.contains(keyCode)
    }

    var displayString: String {
        Self.modifierSymbols(for: modifierFlagsValue) + displayKey
    }

    static func modifiers(from flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection([.command, .option, .control, .shift])
    }

    static func modifierSymbols(for flags: NSEvent.ModifierFlags) -> String {
        var result = ""
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.shift) { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }
        return result
    }

    /// Key codes that only represent modifiers and therefore cannot be recorded.
    private static let reservedModifierOnlyKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
}

enum HotCorner: String, Codable, CaseIterable, Identifiable, Sendable {
    case disabled
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .disabled:
            return String(localized: "Off", comment: "Hot corner disabled")
        case .topLeft:
            return String(localized: "Top Left", comment: "Hot corner position")
        case .topRight:
            return String(localized: "Top Right", comment: "Hot corner position")
        case .bottomLeft:
            return String(localized: "Bottom Left", comment: "Hot corner position")
        case .bottomRight:
            return String(localized: "Bottom Right", comment: "Hot corner position")
        }
    }
}

/// User-visible configuration. Every property is persisted as JSON in
/// `UserDefaults` by `SettingsStore`.
struct AppSettings: Codable, Equatable, Sendable {
    var columns: Int
    var rows: Int
    /// Requested icon size in points at the reference screen scale.
    var iconSize: Double
    var labelFontSize: Double
    var showOnAllDisplays: Bool
    /// Draws the soft drop shadow under every app and folder icon.
    var showIconShadow: Bool
    var hotCorner: HotCorner
    var shortcut: KeyShortcut
    var launchAtLogin: Bool

    static let `default` = AppSettings(
        columns: 7,
        rows: 5,
        iconSize: Double(Metrics.defaultIconSize),
        labelFontSize: 13,
        showOnAllDisplays: false,
        showIconShadow: true,
        hotCorner: .bottomRight,
        shortcut: .launchpadDefault,
        launchAtLogin: false
    )

    init(
        columns: Int,
        rows: Int,
        iconSize: Double,
        labelFontSize: Double,
        showOnAllDisplays: Bool,
        showIconShadow: Bool = true,
        hotCorner: HotCorner,
        shortcut: KeyShortcut,
        launchAtLogin: Bool
    ) {
        self.columns = Self.clamp(columns, 5...9)
        self.rows = Self.clamp(rows, 4...6)
        self.iconSize = Self.clampDouble(iconSize, 64...128)
        self.labelFontSize = Self.clampDouble(labelFontSize, 6...15)
        self.showOnAllDisplays = showOnAllDisplays
        self.showIconShadow = showIconShadow
        self.hotCorner = hotCorner
        self.shortcut = shortcut
        self.launchAtLogin = launchAtLogin
    }

    private static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private static func clampDouble(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    // Decoding is defensive: older or hand-edited JSON must never produce an
    // unusable grid.
    init(from decoder: Decoder) throws {
        let defaults = Self.default
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let columns = try container.decodeIfPresent(Int.self, forKey: .columns) ?? defaults.columns
        let rows = try container.decodeIfPresent(Int.self, forKey: .rows) ?? defaults.rows
        let iconSize = try container.decodeIfPresent(Double.self, forKey: .iconSize) ?? defaults.iconSize
        let labelFontSize = try container.decodeIfPresent(Double.self, forKey: .labelFontSize) ?? defaults.labelFontSize
        let showOnAllDisplays = try container.decodeIfPresent(Bool.self, forKey: .showOnAllDisplays) ?? defaults.showOnAllDisplays
        let showIconShadow = try container.decodeIfPresent(Bool.self, forKey: .showIconShadow) ?? defaults.showIconShadow
        let hotCorner = try container.decodeIfPresent(HotCorner.self, forKey: .hotCorner) ?? defaults.hotCorner
        let shortcut = try container.decodeIfPresent(KeyShortcut.self, forKey: .shortcut) ?? defaults.shortcut
        let launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin

        self.init(
            columns: columns,
            rows: rows,
            iconSize: iconSize,
            labelFontSize: labelFontSize,
            showOnAllDisplays: showOnAllDisplays,
            showIconShadow: showIconShadow,
            hotCorner: hotCorner,
            shortcut: shortcut,
            launchAtLogin: launchAtLogin
        )
    }

    var pageCapacity: Int { columns * rows }
}

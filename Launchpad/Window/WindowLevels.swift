import AppKit
import CoreGraphics

/// Shared window levels.
///
/// The Dock and the menu bar live on different system levels: the Dock is at
/// level 20 and the menu bar at 24 (status items at 25). The overlay therefore
/// cannot be both above the menu bar and below the Dock. Launchpad uses two
/// windows: the main overlay above the status bar, and a background-only strip
/// below the Dock.
enum WindowLevels {
    /// Above the menu bar and status items, so neither can show through.
    static let aboveStatusBar = NSWindow.Level(
        rawValue: NSWindow.Level.statusBar.rawValue + 1
    )

    /// One level below the Dock, so the Dock stays visible and clickable.
    static let belowDock: NSWindow.Level = {
        // `kCGDockWindowLevelKey` has no Swift case name in the current SDK.
        let dockKey = CGWindowLevelKey(rawValue: 7)
        let dockLevel = dockKey.map { Int(CGWindowLevelForKey($0)) } ?? 20
        return NSWindow.Level(rawValue: dockLevel - 1)
    }()
}

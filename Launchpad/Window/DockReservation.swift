import AppKit

/// Describes the screen area occupied by the Dock.
///
/// The main overlay has to stay above the menu bar, which also puts it above
/// the Dock. To keep the Dock visible, the overlay stops at the Dock's edge and
/// a background-only window fills the reserved strip one level below the Dock.
struct DockReservation {
    enum Edge {
        case bottom
        case left
        case right
    }

    let edge: Edge?
    let thickness: CGFloat

    var isEmpty: Bool {
        edge == nil || thickness < 0.5
    }

    /// Reserves the Dock area reported by the screen, or a conservative strip
    /// for an auto-hidden Dock (where `visibleFrame` no longer reserves it).
    static func current(for screen: NSScreen) -> DockReservation {
        let frame = screen.frame
        let visible = screen.visibleFrame

        let bottom = max(0, visible.minY - frame.minY)
        let left = max(0, visible.minX - frame.minX)
        let right = max(0, frame.maxX - visible.maxX)
        let candidates: [(Edge, CGFloat)] = [
            (.bottom, bottom),
            (.left, left),
            (.right, right)
        ]

        if let dock = candidates.max(by: { $0.1 < $1.1 }), dock.1 > 0.5 {
            return DockReservation(edge: dock.0, thickness: dock.1)
        }

        // An auto-hidden Dock is not part of `visibleFrame`. Reserve a strip on
        // the display that owns the Dock so an auto-revealed Dock is not covered
        // by the overlay above it.
        guard screen === NSScreen.screens.first else {
            return DockReservation(edge: nil, thickness: 0)
        }
        return DockReservation.preferencesFallback()
    }

    /// Frame of the main interactive window: the full screen minus the Dock.
    func interactiveFrame(for screen: NSScreen) -> NSRect {
        let frame = screen.frame
        guard let edge, !isEmpty else { return frame }

        switch edge {
        case .bottom:
            return NSRect(
                x: frame.minX,
                y: frame.minY + thickness,
                width: frame.width,
                height: frame.height - thickness
            )
        case .left:
            return NSRect(
                x: frame.minX + thickness,
                y: frame.minY,
                width: frame.width - thickness,
                height: frame.height
            )
        case .right:
            return NSRect(
                x: frame.minX,
                y: frame.minY,
                width: frame.width - thickness,
                height: frame.height
            )
        }
    }

    /// Frame of the background-only window behind the Dock. It overlaps the
    /// interactive window by one point to avoid a hairline seam.
    func backgroundFrame(for screen: NSScreen) -> NSRect? {
        let frame = screen.frame
        guard let edge, !isEmpty else { return nil }

        switch edge {
        case .bottom:
            return NSRect(
                x: frame.minX,
                y: frame.minY,
                width: frame.width,
                height: thickness + 1
            )
        case .left:
            return NSRect(
                x: frame.minX,
                y: frame.minY,
                width: thickness + 1,
                height: frame.height
            )
        case .right:
            return NSRect(
                x: frame.maxX - thickness - 1,
                y: frame.minY,
                width: thickness + 1,
                height: frame.height
            )
        }
    }

    /// A side Dock leaves the menu-bar strip above it uncovered by the main
    /// window. This returns the small top-corner patch that covers it.
    func menuBarPatchFrame(for screen: NSScreen) -> NSRect? {
        guard let edge, edge != .bottom, !isEmpty else { return nil }

        let visibleMenuBar = screen.frame.maxY - screen.visibleFrame.maxY
        let height = max(24, visibleMenuBar) + 1
        let y = screen.frame.maxY - height

        switch edge {
        case .left:
            return NSRect(
                x: screen.frame.minX,
                y: y,
                width: thickness + 1,
                height: height
            )
        case .right:
            return NSRect(
                x: screen.frame.maxX - thickness - 1,
                y: y,
                width: thickness + 1,
                height: height
            )
        case .bottom:
            return nil
        }
    }

    /// Converts a window frame in screen coordinates into the region of the
    /// screen the window covers, using a top-left origin for SwiftUI.
    ///
    /// The wallpaper backdrop renders one full-screen image per display and
    /// offsets it by this region, so the main window, Dock strip, and corner
    /// patch line up into a single continuous surface.
    func viewport(for frame: NSRect, on screen: NSScreen) -> CGRect {
        let screenFrame = screen.frame
        return CGRect(
            x: frame.minX - screenFrame.minX,
            y: screenFrame.maxY - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    private static func preferencesFallback() -> DockReservation {
        let defaults = UserDefaults(suiteName: "com.apple.dock")
        let edge: Edge
        switch defaults?.string(forKey: "orientation") ?? "bottom" {
        case "left":
            edge = .left
        case "right":
            edge = .right
        default:
            edge = .bottom
        }

        let tileSize = (defaults?.object(forKey: "tilesize") as? NSNumber)?.doubleValue ?? 57
        let magnified = defaults?.bool(forKey: "magnification") ?? false
        let largeSize = (defaults?.object(forKey: "largesize") as? NSNumber)?.doubleValue ?? 128
        let iconSize = magnified ? max(tileSize, largeSize) : tileSize
        return DockReservation(edge: edge, thickness: CGFloat(iconSize) + 30)
    }
}

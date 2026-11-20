import AppKit
import ApplicationServices
import Foundation
import os

/// Where a drag released over the Dock should land.
enum DockDropTarget: Equatable, Sendable {
    case addToDock
    case trash
}

/// Pure geometry for the Dock bar and its trailing Trash tile.
///
/// `barRect` is the Dock's own window (not the reserved screen strip); the
/// Trash sits at the trailing edge of that bar. Accessibility supplies the
/// exact Trash frame when it is trusted; this fallback keeps the gesture
/// working for users who have not granted it.
struct DockGeometry {
    let screenFrame: CGRect
    let visibleFrame: CGRect
    let barRect: CGRect?
    let trashRect: CGRect?
    let tileSize: CGFloat

    /// The screen area reserved for a visible Dock.
    var strip: CGRect? {
        let epsilon: CGFloat = 0.5
        if visibleFrame.minY > screenFrame.minY + epsilon {
            return CGRect(
                x: screenFrame.minX,
                y: screenFrame.minY,
                width: screenFrame.width,
                height: visibleFrame.minY - screenFrame.minY
            )
        }
        if visibleFrame.minX > screenFrame.minX + epsilon {
            return CGRect(
                x: screenFrame.minX,
                y: screenFrame.minY,
                width: visibleFrame.minX - screenFrame.minX,
                height: screenFrame.height
            )
        }
        if visibleFrame.maxX < screenFrame.maxX - epsilon {
            return CGRect(
                x: visibleFrame.maxX,
                y: screenFrame.minY,
                width: screenFrame.maxX - visibleFrame.maxX,
                height: screenFrame.height
            )
        }
        return nil
    }

    func target(at point: CGPoint) -> DockDropTarget? {
        if let trashRect, trashRect.insetBy(dx: -3, dy: -3).contains(point) {
            return .trash
        }

        guard let bar = barRect ?? strip,
              bar.insetBy(dx: -3, dy: -3).contains(point) else {
            return nil
        }

        if let barRect, let fallback = fallbackTrash(in: barRect), fallback.contains(point) {
            return .trash
        }
        return .addToDock
    }

    private func fallbackTrash(in bar: CGRect) -> CGRect? {
        let extent = tileSize + 20
        if bar.width >= bar.height {
            return CGRect(
                x: bar.maxX - extent,
                y: bar.minY,
                width: extent,
                height: bar.height
            )
        }
        return CGRect(
            x: bar.minX,
            y: bar.minY,
            width: bar.width,
            height: extent
        )
    }
}

/// Resolves the live Dock geometry and decides whether a screen point is over
/// the Dock or its Trash tile.
@MainActor
enum DockDrop {
    static let trashSubrole = "AXTrashDockItem"

    static func target(at point: CGPoint) -> DockDropTarget? {
        guard let screen = screen(containing: point) else { return nil }
        let mainHeight = mainScreenHeight
        return DockGeometry(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            barRect: dockBarRect(containing: point, mainScreenHeight: mainHeight),
            trashRect: DockAccessibility.trashFrame(mainScreenHeight: mainHeight),
            tileSize: tileSize
        )
        .target(at: point)
    }

    /// Cheap pre-check used to avoid walking the Dock's accessibility tree on
    /// every pointer event. Returns true near the reserved strip or a screen
    /// edge, where an auto-hidden Dock appears.
    static func isNearDock(_ point: CGPoint) -> Bool {
        guard let screen = screen(containing: point) else { return false }
        if let strip = DockGeometry(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            barRect: nil,
            trashRect: nil,
            tileSize: 64
        ).strip,
           strip.insetBy(dx: -24, dy: -24).contains(point) {
            return true
        }

        let edgeBand: CGFloat = 30
        return point.y <= screen.frame.minY + edgeBand
            || point.x <= screen.frame.minX + edgeBand
            || point.x >= screen.frame.maxX - edgeBand
    }

    static func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
            ?? NSScreen.main
    }

    static var mainScreenHeight: CGFloat {
        NSScreen.screens.first { $0.frame.origin == .zero }?.frame.height
            ?? NSScreen.main?.frame.height
            ?? 0
    }

    static var tileSize: CGFloat {
        let value = UserDefaults(suiteName: "com.apple.dock")?.double(forKey: "tilesize") ?? 64
        return CGFloat(min(max(value, 32), 128))
    }

    /// Finds the visible Dock bar containing `point`. CGWindow bounds use the
    /// top-left origin of the main display, so they are flipped into AppKit's
    /// bottom-left screen coordinates.
    static func dockBarRect(containing point: CGPoint, mainScreenHeight: CGFloat) -> CGRect? {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        let dockPIDs = Set(
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
                .map(\.processIdentifier)
        )
        var rects: [CGRect] = []
        for info in windows {
            guard let pid = info[kCGWindowOwnerPID as String] as? Int,
                  dockPIDs.contains(pid_t(pid)),
                  (info[kCGWindowLayer as String] as? Int) == 20,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let x = number(bounds["X"]),
                  let y = number(bounds["Y"]),
                  let width = number(bounds["Width"]),
                  let height = number(bounds["Height"]),
                  width > 1, height > 1 else {
                continue
            }
            rects.append(
                CGRect(
                    x: x,
                    y: mainScreenHeight - (y + height),
                    width: width,
                    height: height
                )
            )
        }

        return rects.first {
            $0.insetBy(dx: -4, dy: -4).contains(point)
        }
    }

    private static func number(_ value: Any?) -> CGFloat? {
        (value as? NSNumber).map { CGFloat(truncating: $0) }
    }
}

/// The Dock's own accessibility tree names its Trash tile with the
/// `AXTrashDockItem` subrole. Reading it is optional: without Accessibility the
/// trailing-edge fallback in `DockGeometry` takes over.
@MainActor
private enum DockAccessibility {
    static func trashFrame(mainScreenHeight: CGFloat) -> CGRect? {
        guard AXIsProcessTrusted(),
              let dock = NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.apple.dock"
              ).first else {
            return nil
        }
        let application = AXUIElementCreateApplication(dock.processIdentifier)
        guard let frame = findTrash(in: application, depth: 0) else { return nil }
        return CGRect(
            x: frame.minX,
            y: mainScreenHeight - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    private static func findTrash(in element: AXUIElement, depth: Int) -> CGRect? {
        guard depth < 8 else { return nil }

        var subrole: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            element,
            kAXSubroleAttribute as CFString,
            &subrole
        ) == .success,
           let subrole,
           (subrole as? String) == DockDrop.trashSubrole {
            return frame(of: element)
        }

        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &children
        ) == .success,
              let children,
              let list = children as? [AXUIElement] else {
            return nil
        }
        for child in list {
            if let frame = findTrash(in: child, depth: depth + 1) {
                return frame
            }
        }
        return nil
    }

    /// AX positions use the top-left origin; the caller flips them.
    private static func frame(of element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            &positionRef
        ) == .success,
              AXUIElementCopyAttributeValue(
                element,
                kAXSizeAttribute as CFString,
                &sizeRef
              ) == .success,
              let positionRef,
              let sizeRef,
              CFGetTypeID(positionRef) == AXValueGetTypeID(),
              CFGetTypeID(sizeRef) == AXValueGetTypeID() else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        let positionValue = unsafeDowncast(positionRef, to: AXValue.self)
        let sizeValue = unsafeDowncast(sizeRef, to: AXValue.self)
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }
}

/// Pins an app by appending it to the Dock's `persistent-apps`.
///
/// There is no public “add to Dock” API. The Dock reads this preference at
/// launch, so it is restarted once after the write. Duplicate entries are
/// ignored and nothing is restarted when the app is already pinned.
enum DockPinning {
    private static let domain = "com.apple.dock"
    private static let logger = Logger(
        subsystem: "com.example.Launchpad",
        category: "dock"
    )

    static func entry(for app: AppItem) -> [String: Any] {
        let url = URL(fileURLWithPath: app.url.path, isDirectory: true)
        var tileData: [String: Any] = [
            "file-data": [
                "_CFURLString": url.absoluteString,
                "_CFURLStringType": 15
            ],
            "file-label": app.name,
            "file-type": 41,
            "dock-extra": 0,
            "is-beta": 0
        ]
        if let bundleIdentifier = app.bundleIdentifier {
            tileData["bundle-identifier"] = bundleIdentifier
        }
        return [
            "GUID": Int.random(in: 1_000_000_000...9_999_999_999),
            "tile-data": tileData,
            "tile-type": "file-tile"
        ]
    }

    static func isPinned(_ app: AppItem, among apps: [[String: Any]]) -> Bool {
        let wanted = app.url.standardizedFileURL.path
        return apps.contains { entry in
            guard let tile = entry["tile-data"] as? [String: Any] else {
                return false
            }
            if let bundleIdentifier = app.bundleIdentifier,
               tile["bundle-identifier"] as? String == bundleIdentifier {
                return true
            }
            guard let fileData = tile["file-data"] as? [String: Any],
                  let string = fileData["_CFURLString"] as? String,
                  let url = URL(string: string),
                  url.isFileURL else {
                return false
            }
            return URL(fileURLWithPath: url.path).standardizedFileURL.path == wanted
        }
    }

    static func adding(
        _ app: AppItem,
        to apps: [[String: Any]]
    ) -> [[String: Any]]? {
        guard !isPinned(app, among: apps) else { return nil }
        return apps + [entry(for: app)]
    }

    @discardableResult
    static func addToDock(_ app: AppItem) -> Bool {
        // Read the raw array so an unexpected value can never wipe the
        // existing Dock entries: unknown objects are carried over untouched.
        let current = (CFPreferencesCopyAppValue(
            "persistent-apps" as CFString,
            domain as CFString
        ) as? [Any]) ?? []
        let pinned = current.compactMap { $0 as? [String: Any] }
        guard !isPinned(app, among: pinned) else { return false }

        let updated = current + [entry(for: app)]
        CFPreferencesSetAppValue(
            "persistent-apps" as CFString,
            updated as NSArray,
            domain as CFString
        )
        CFPreferencesAppSynchronize(domain as CFString)
        restartDock()
        return true
    }

    private static func restartDock() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Dock"]
        do {
            try process.run()
        } catch {
            logger.error("Could not restart the Dock: \(error.localizedDescription)")
        }
    }
}

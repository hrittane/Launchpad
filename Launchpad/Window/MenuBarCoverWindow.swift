import AppKit

/// Paints over the menu bar while the panel is on screen.
///
/// AppKit has no way to hide *only* the menu bar: `NSMenu.setMenuBarVisible(false)`
/// always takes the Dock with it, and the `.hideMenuBar` presentation options both
/// hide the Dock and block the main thread in an accessory app. The Dock has to
/// stay visible, so the menu bar is covered instead — by a window above the menu
/// bar and its control-centre extras, while the panel itself stays below the Dock.
///
/// The cover draws the top of a screen-sized `BackdropView` and the panel leaves
/// that strip transparent, so both windows blur the wallpaper rather than each
/// other. Two windows never render a vibrancy material *exactly* alike, so the
/// strip's last few points fade out instead of ending in a hard edge.
final class MenuBarCoverWindow: NSWindow {
    private let clip = NSView()
    private let fade = CAGradientLayer()
    private let backdrop = BackdropView()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isMovable = false
        animationBehavior = .none
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        clip.wantsLayer = true
        clip.layer?.masksToBounds = true
        clip.layer?.mask = fade
        clip.addSubview(backdrop)
        contentView = clip
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Moves the cover over the menu bar of `screen` and shows it.
    ///
    /// - Returns: The height the panel must keep clear at the top. The cover
    ///   reaches a little further down and fades out over the panel's backdrop,
    ///   so the two renderings meet in a soft gradient instead of a hard edge.
    @discardableResult
    func present(over screen: NSScreen) -> CGFloat? {
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        guard menuBarHeight > 0 else { return nil }

        let strip = NSRect(
            x: screen.frame.minX,
            y: screen.frame.maxY - menuBarHeight - Self.fadeLength,
            width: screen.frame.width,
            height: menuBarHeight + Self.fadeLength
        )
        setFrame(strip, display: false)

        clip.frame = NSRect(origin: .zero, size: strip.size)
        backdrop.present(on: screen)
        backdrop.frame = NSRect(
            x: 0,
            y: strip.height - screen.frame.height,
            width: screen.frame.width,
            height: screen.frame.height
        )

        // Opaque over the menu bar, then fading out over the panel.
        fade.frame = clip.bounds
        fade.colors = [NSColor.white.cgColor, NSColor.white.cgColor, NSColor.clear.cgColor]
        fade.locations = [0, NSNumber(value: menuBarHeight / strip.height), 1]
        fade.startPoint = CGPoint(x: 0.5, y: 1)
        fade.endPoint = CGPoint(x: 0.5, y: 0)

        orderFrontRegardless()
        return menuBarHeight
    }

    /// How far the strip fades into the panel below it.
    private static let fadeLength: CGFloat = 10
}

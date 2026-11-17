import AppKit

/// Full-screen wallpaper blur + tint that sits behind the icon grid.
///
/// Uses `NSVisualEffectView` with `.behindWindow` blending so the actual desktop
/// wallpaper is blurred by the window server. A tint and a vignette match the
/// reference frames (measured ≈ 25–30 % darkening, stronger at the edges).
final class BackdropView: NSView {
    private let blur = NSVisualEffectView()
    private let fallback = GradientBackdropView()
    private let tint = NSView()
    private let vignette = VignetteView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true

        blur.blendingMode = .behindWindow
        blur.material = .fullScreenUI
        blur.state = .active

        tint.wantsLayer = true
        vignette.wantsLayer = true

        for view in [blur, fallback, tint, vignette] {
            view.autoresizingMask = [.width, .height]
            view.frame = bounds
            addSubview(view)
        }

        fallback.isHidden = true
        updateTint()

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("BackdropView is created programmatically")
    }

    override func layout() {
        super.layout()
        let frame = bounds
        blur.frame = frame
        fallback.frame = frame
        tint.frame = frame
        vignette.frame = frame
    }

    @objc private func accessibilityDisplayOptionsChanged() {
        updateTint()
    }

    #if DEBUG
    /// Replaces the behind-window blur with the opaque gradient so offscreen
    /// bitmap rendering has something to composite the grid over.
    func forceFallbackForSnapshot() {
        blur.isHidden = true
        fallback.isHidden = false
        tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.22).cgColor
        vignette.layer?.opacity = 1.0
    }
    #endif

    private func updateTint() {
        let workspace = NSWorkspace.shared
        let reduceTransparency = workspace.accessibilityDisplayShouldReduceTransparency
        blur.isHidden = reduceTransparency
        fallback.isHidden = !reduceTransparency

        let alpha: CGFloat = reduceTransparency
            ? (workspace.accessibilityDisplayShouldIncreaseContrast ? 0.14 : 0.10)
            : (workspace.accessibilityDisplayShouldIncreaseContrast ? 0.30 : 0.22)
        tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(alpha).cgColor
        vignette.layer?.opacity = reduceTransparency ? 0.6 : 1.0
    }
}

/// Opaque replacement used when Reduce Transparency is on.
private final class GradientBackdropView: NSView {
    override func makeBackingLayer() -> CALayer {
        let gradient = CAGradientLayer()
        gradient.colors = [
            NSColor(calibratedRed: 0.09, green: 0.08, blue: 0.24, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.16, green: 0.15, blue: 0.36, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.08, green: 0.12, blue: 0.28, alpha: 1).cgColor
        ]
        gradient.locations = [0, 0.55, 1]
        gradient.startPoint = CGPoint(x: 0.15, y: 0)
        gradient.endPoint = CGPoint(x: 0.85, y: 1)
        return gradient
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("GradientBackdropView is created programmatically")
    }
}

/// Soft radial darkening towards the screen corners.
private final class VignetteView: NSView {
    override func makeBackingLayer() -> CALayer {
        let gradient = CAGradientLayer()
        gradient.type = .radial
        gradient.colors = [
            NSColor.clear.cgColor,
            NSColor.black.withAlphaComponent(0.06).cgColor,
            NSColor.black.withAlphaComponent(0.34).cgColor
        ]
        gradient.locations = [0.0, 0.55, 1.0]
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 1.25, y: 1.25)
        return gradient
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("VignetteView is created programmatically")
    }
}

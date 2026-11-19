import AppKit
import SwiftUI

/// The folder dim, shared by the grid and the menu-bar cover.
///
/// The cover is a separate window above the panel because AppKit cannot cover
/// just the menu bar in the panel's window level. Two windows cannot share one
/// animation, so whichever window starts its fade first leaves a strip at the
/// top that is brighter than the grid for as long as the two clocks disagree —
/// that strip is the bar across the menu bar. Both layers are therefore owned
/// by this one object and always animated in the same animation group.
@MainActor
final class FolderDim {
    private weak var gridLayer: CALayer?
    private weak var coverLayer: CALayer?

    /// The black overlay strength, matching the folder sheet's dim.
    private static let strength: Float = 0.18
    private static let duration: TimeInterval = 0.2

    func attach(grid layer: CALayer) {
        gridLayer = layer
        layer.opacity = 0
    }

    func attach(cover layer: CALayer) {
        coverLayer = layer
        layer.opacity = 0
    }

    func setDimmed(_ dimmed: Bool, animated: Bool = true) {
        let target: Float = dimmed ? Self.strength : 0
        guard gridLayer?.opacity != target || coverLayer?.opacity != target else { return }

        let apply = {
            self.gridLayer?.opacity = target
            self.coverLayer?.opacity = target
        }

        guard animated else {
            apply()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            apply()
        }
    }
}

/// Layer-backed view that places the grid's share of the folder dim above the
/// grid content (so the icons dim like the wallpaper) and below the sheet.
struct FolderDimView: NSViewRepresentable {
    let dim: FolderDim

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        if let layer = view.layer {
            dim.attach(grid: layer)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

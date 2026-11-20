import AppKit

/// The three Dock icon treatments offered in Settings.
enum DockIconStyle: String, CaseIterable, Identifiable, Sendable {
    case classic
    case midnight
    case aurora

    var id: Self { self }

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .midnight: return "Midnight"
        case .aurora: return "Aurora"
        }
    }
}

/// Draws the Dock icon choices without shipping extra image assets.
///
/// The shapes mirror the app icon: a rounded square holding nine coloured
/// tiles. `classic` is the familiar white face, `midnight` puts the same tiles
/// on a dark face, and `aurora` uses a violet-to-teal glass face.
@MainActor
enum DockIconArt {
    private static var cache: [DockIconStyle: NSImage] = [:]

    static func image(for style: DockIconStyle) -> NSImage {
        if let cached = cache[style] { return cached }

        let image = NSImage(size: NSSize(width: 512, height: 512), flipped: false) { _ in
            draw(style)
            return true
        }
        image.isTemplate = false
        cache[style] = image
        return image
    }

    private static let tileColors: [NSColor] = [
        NSColor(calibratedRed: 0.98, green: 0.67, blue: 0.18, alpha: 1),
        NSColor(calibratedRed: 0.97, green: 0.40, blue: 0.59, alpha: 1),
        NSColor(calibratedRed: 0.95, green: 0.34, blue: 0.30, alpha: 1),
        NSColor(calibratedRed: 0.25, green: 0.84, blue: 0.50, alpha: 1),
        NSColor(calibratedWhite: 0.64, alpha: 1),
        NSColor(calibratedRed: 0.97, green: 0.40, blue: 0.59, alpha: 1),
        NSColor(calibratedRed: 0.73, green: 0.43, blue: 0.94, alpha: 1),
        NSColor(calibratedRed: 0.30, green: 0.72, blue: 0.96, alpha: 1),
        NSColor(calibratedRed: 0.22, green: 0.81, blue: 0.66, alpha: 1)
    ]

    private static func draw(_ style: DockIconStyle) {
        let outer = NSRect(x: 32, y: 32, width: 448, height: 448)
        let face = NSBezierPath(roundedRect: outer, xRadius: 104, yRadius: 104)

        switch style {
        case .classic:
            NSColor(calibratedWhite: 0.985, alpha: 1).setFill()
            face.fill()
            NSColor(calibratedWhite: 0, alpha: 0.07).setStroke()
            face.lineWidth = 2
            face.stroke()

        case .midnight:
            if let gradient = NSGradient(colors: [
                NSColor(calibratedWhite: 0.16, alpha: 1),
                NSColor(calibratedWhite: 0.035, alpha: 1)
            ]) {
                gradient.draw(in: face, angle: -90)
            }
            NSColor.white.withAlphaComponent(0.12).setStroke()
            face.lineWidth = 2
            face.stroke()

        case .aurora:
            if let gradient = NSGradient(colors: [
                NSColor(calibratedRed: 0.48, green: 0.34, blue: 0.96, alpha: 1),
                NSColor(calibratedRed: 0.20, green: 0.55, blue: 0.98, alpha: 1),
                NSColor(calibratedRed: 0.16, green: 0.82, blue: 0.74, alpha: 1)
            ]) {
                gradient.draw(in: face, angle: -55)
            }
            NSColor.white.withAlphaComponent(0.28).setStroke()
            face.lineWidth = 2
            face.stroke()
        }

        drawTiles(for: style, in: outer)
    }

    private static func drawTiles(for style: DockIconStyle, in outer: NSRect) {
        let grid: CGFloat = 258
        let tile: CGFloat = 66
        let gap = (grid - tile * 3) / 2
        let origin = NSPoint(x: outer.midX - grid / 2, y: outer.midY - grid / 2)

        for row in 0..<3 {
            for column in 0..<3 {
                let rect = NSRect(
                    x: origin.x + CGFloat(column) * (tile + gap),
                    y: origin.y + CGFloat(2 - row) * (tile + gap),
                    width: tile,
                    height: tile
                )
                let tilePath = NSBezierPath(roundedRect: rect, xRadius: 15, yRadius: 15)
                let fill = style == .aurora
                    ? NSColor.white.withAlphaComponent(0.84)
                    : tileColors[row * 3 + column]
                fill.setFill()
                tilePath.fill()

                if style == .midnight {
                    NSColor.white.withAlphaComponent(0.10).setStroke()
                    tilePath.lineWidth = 1.5
                    tilePath.stroke()
                }
            }
        }
    }
}

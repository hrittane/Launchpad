import AppKit
import Foundation

// Renders the Launchpad app icon (white squircle, 3x3 coloured tiles) at 1024 px.
let size: CGFloat = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
rep.size = NSSize(width: size, height: size)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))

let inset: CGFloat = 100
let body = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let radius = body.width * 0.2245
let bodyPath = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

// Drop shadow underneath the squircle.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: NSColor.black.withAlphaComponent(0.38).cgColor)
ctx.addPath(bodyPath)
ctx.setFillColor(NSColor.white.cgColor)
ctx.fillPath()
ctx.restoreGState()

// Subtle vertical sheen.
ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()
let colors = [
    NSColor(calibratedWhite: 1.0, alpha: 1).cgColor,
    NSColor(calibratedRed: 0.94, green: 0.94, blue: 0.97, alpha: 1).cgColor
] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
ctx.restoreGState()

let tileColors: [NSColor] = [
    NSColor(calibratedRed: 1.00, green: 0.58, blue: 0.10, alpha: 1),
    NSColor(calibratedRed: 0.98, green: 0.30, blue: 0.55, alpha: 1),
    NSColor(calibratedRed: 0.95, green: 0.27, blue: 0.25, alpha: 1),
    NSColor(calibratedRed: 0.22, green: 0.82, blue: 0.39, alpha: 1),
    NSColor(calibratedRed: 0.62, green: 0.62, blue: 0.65, alpha: 1),
    NSColor(calibratedRed: 1.00, green: 0.35, blue: 0.60, alpha: 1),
    NSColor(calibratedRed: 0.75, green: 0.37, blue: 0.93, alpha: 1),
    NSColor(calibratedRed: 0.28, green: 0.78, blue: 0.96, alpha: 1),
    NSColor(calibratedRed: 0.18, green: 0.83, blue: 0.66, alpha: 1)
]

let tile: CGFloat = 150
let gap: CGFloat = 42
let gridWidth = tile * 3 + gap * 2
let originX = (size - gridWidth) / 2
let originY = (size - gridWidth) / 2

for index in 0..<9 {
    let column = CGFloat(index % 3)
    let row = CGFloat(index / 3)
    let rect = CGRect(
        x: originX + column * (tile + gap),
        y: originY + (2 - row) * (tile + gap),
        width: tile, height: tile
    )
    let path = CGPath(roundedRect: rect, cornerWidth: 38, cornerHeight: 38, transform: nil)
    ctx.addPath(path)
    ctx.setFillColor(tileColors[index].cgColor)
    ctx.fillPath()
}

NSGraphicsContext.restoreGraphicsState()

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")

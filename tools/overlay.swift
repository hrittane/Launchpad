import AppKit
import Foundation

// usage: overlay <in> <out> <x> <y> <w> <h> <scale> [step]
let a = CommandLine.arguments
guard a.count >= 8, let img = NSImage(contentsOfFile: a[1]),
      let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { print("bad"); exit(1) }
let ox = Int(a[3])!, oy = Int(a[4])!, w = Int(a[5])!, h = Int(a[6])!
let scale = Double(a[7])!
let step = a.count > 8 ? Int(a[8])! : 20
let crop = cg.cropping(to: CGRect(x: ox, y: oy, width: w, height: h))!
let outW = Int(Double(w) * scale), outH = Int(Double(h) * scale)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: outW, pixelsHigh: outH,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: outW, height: outH)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
ctx.interpolationQuality = .none
ctx.draw(crop, in: CGRect(x: 0, y: 0, width: outW, height: outH))
ctx.setLineWidth(1)
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold),
    .foregroundColor: NSColor.systemYellow,
    .backgroundColor: NSColor.black.withAlphaComponent(0.55)
]
var x = 0
while x <= w {
    let px = Double(x) * scale
    ctx.setStrokeColor(NSColor.systemYellow.withAlphaComponent(x % (step*5) == 0 ? 0.85 : 0.3).cgColor)
    ctx.move(to: CGPoint(x: px, y: 0)); ctx.addLine(to: CGPoint(x: px, y: Double(outH))); ctx.strokePath()
    if x % step == 0 {
        NSString(string: "\(x + ox)").draw(at: NSPoint(x: px + 1, y: Double(outH) - 14), withAttributes: attrs)
    }
    x += step
}
var y = 0
while y <= h {
    let py = Double(outH) - Double(y) * scale
    ctx.setStrokeColor(NSColor.systemYellow.withAlphaComponent(y % (step*5) == 0 ? 0.85 : 0.3).cgColor)
    ctx.move(to: CGPoint(x: 0, y: py)); ctx.addLine(to: CGPoint(x: Double(outW), y: py)); ctx.strokePath()
    if y % step == 0 {
        NSString(string: "\(y + oy)").draw(at: NSPoint(x: 1, y: py + 1), withAttributes: attrs)
    }
    y += step
}
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2]))
print("wrote \(a[2])")

import AppKit
import Foundation

// Usage: contactsheet <outdir> <cols> <cellWidth> <inputs...>
let args = CommandLine.arguments
guard args.count > 4 else { print("usage: contactsheet outdir cols cellWidth inputs..."); exit(1) }
let outDir = args[1]
let cols = Int(args[2]) ?? 4
let cellW = CGFloat(Double(args[3]) ?? 480)
let inputs = Array(args.dropFirst(4))
let rows = 2
let perSheet = cols * rows

try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

var sheetIndex = 0
var i = 0
while i < inputs.count {
    let batch = Array(inputs[i..<min(i + perSheet, inputs.count)])
    var images: [NSImage] = []
    for p in batch {
        if let img = NSImage(contentsOfFile: p) { images.append(img) }
    }
    guard let first = images.first else { i += perSheet; continue }
    let aspect = first.size.height / first.size.width
    let cellH = cellW * aspect
    let labelH: CGFloat = 26
    let totalW = cellW * CGFloat(cols)
    let totalRows = Int(ceil(Double(batch.count) / Double(cols)))
    let totalH = (cellH + labelH) * CGFloat(totalRows)

    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(totalW), pixelsHigh: Int(totalH),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    guard let rep else { exit(1) }
    rep.size = NSSize(width: totalW, height: totalH)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.black.setFill()
    NSRect(x: 0, y: 0, width: totalW, height: totalH).fill()

    for (idx, img) in images.enumerated() {
        let c = idx % cols
        let r = idx / cols
        let x = CGFloat(c) * cellW
        let yTop = CGFloat(r) * (cellH + labelH)
        // AppKit origin bottom-left; draw from top
        let y = totalH - yTop - cellH - labelH
        img.draw(in: NSRect(x: x, y: y + labelH, width: cellW, height: cellH))
        let name = (batch[idx] as NSString).lastPathComponent
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        NSString(string: name).draw(at: NSPoint(x: x + 4, y: y + 4), withAttributes: attrs)
    }
    NSGraphicsContext.restoreGraphicsState()
    let outPath = String(format: "%@/sheet-%02d.png", outDir, sheetIndex)
    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: outPath))
        print(outPath)
    }
    sheetIndex += 1
    i += perSheet
}

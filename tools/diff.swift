import AppKit
import Foundation

// usage: diff <a> <b> [threshold]
let a = CommandLine.arguments
guard a.count >= 3, let i1 = NSImage(contentsOfFile: a[1]), let i2 = NSImage(contentsOfFile: a[2]),
      let r1 = NSBitmapImageRep(data: i1.tiffRepresentation!), let r2 = NSBitmapImageRep(data: i2.tiffRepresentation!) else { exit(1) }
let th = a.count > 3 ? Double(a[3])! : 0.02
let w = min(r1.pixelsWide, r2.pixelsWide), h = min(r1.pixelsHigh, r2.pixelsHigh)
var count = 0, sum = 0.0
var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
for y in 0..<h { for x in 0..<w {
    guard let c1 = r1.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
          let c2 = r2.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
    let d = (abs(c1.redComponent - c2.redComponent) + abs(c1.greenComponent - c2.greenComponent) + abs(c1.blueComponent - c2.blueComponent)) / 3
    sum += d
    if d > th {
        count += 1
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    }
}}
print(String(format: "changed %d px (%.2f%%), mean %.4f", count, 100.0*Double(count)/Double(w*h), sum/Double(w*h)))
if maxX >= 0 { print("bbox \(minX)...\(maxX) x \(minY)...\(maxY)") }

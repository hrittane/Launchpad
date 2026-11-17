import AppKit
import Foundation

// usage: measure <image> row <y> [threshold]
//        measure <image> col <x> [threshold]
//        measure <image> bbox <x> <y> <w> <h> [threshold]
//        measure <image> sample <x> <y>
let a = CommandLine.arguments
guard a.count >= 3, let img = NSImage(contentsOfFile: a[1]),
      let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else {
    print("bad image"); exit(1)
}
let w = rep.pixelsWide, h = rep.pixelsHigh
func rgb(_ x: Int, _ y: Int) -> (Double, Double, Double) {
    guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return (0,0,0) }
    return (c.redComponent, c.greenComponent, c.blueComponent)
}
func lum(_ x: Int, _ y: Int) -> Double {
    let (r,g,b) = rgb(x,y); return 0.2126*r + 0.7152*g + 0.0722*b
}
let mode = a[2]
if mode == "row" || mode == "col" {
    let n = Int(a[3]) ?? 0
    let th = a.count > 4 ? Double(a[4]) ?? 0.12 : 0.12
    var runs: [(Int, Int)] = []
    var start: Int? = nil
    let count = mode == "row" ? w : h
    for i in 0..<count {
        let l = mode == "row" ? lum(i, n) : lum(n, i)
        let on = l > th
        if on && start == nil { start = i }
        if !on, let s = start { runs.append((s, i-1)); start = nil }
    }
    if let s = start { runs.append((s, count-1)) }
    print("size \(w)x\(h)")
    for r in runs where r.1 - r.0 >= 1 { print("run \(r.0)...\(r.1) len \(r.1-r.0+1)") }
} else if mode == "bbox" {
    let x0 = Int(a[3]) ?? 0, y0 = Int(a[4]) ?? 0, ww = Int(a[5]) ?? 10, hh = Int(a[6]) ?? 10
    let th = a.count > 7 ? Double(a[7]) ?? 0.2 : 0.2
    var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
    for y in y0..<min(y0+hh, h) { for x in x0..<min(x0+ww, w) {
        if lum(x,y) > th { minX = min(minX,x); maxX = max(maxX,x); minY = min(minY,y); maxY = max(maxY,y) }
    }}
    print("size \(w)x\(h) bbox x \(minX)...\(maxX) (\(maxX-minX+1)) y \(minY)...\(maxY) (\(maxY-minY+1))")
} else if mode == "sample" {
    let x = Int(a[3]) ?? 0, y = Int(a[4]) ?? 0
    let (r,g,b) = rgb(x,y)
    print(String(format: "rgb %.3f %.3f %.3f  hex %02X%02X%02X", r,g,b, Int(r*255), Int(g*255), Int(b*255)))
}

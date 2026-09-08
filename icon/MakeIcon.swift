// Draws the app icon at every size macOS needs, straight from vectors, so the
// small sizes stay crisp instead of being downscaled from one big bitmap.
//
// Semantics: a clockwise retry loop (the app presses Retry for you) around an
// amber bolt (automatic recovery from a capacity stall).

import AppKit
import Foundation

func rad(_ degrees: CGFloat) -> CGFloat { degrees * .pi / 180 }

func makeIcon(size: CGFloat) -> Data? {
    let pixels = Int(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let graphics = NSGraphicsContext(bitmapImageRep: rep)
    else { return nil }

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = graphics
    let ctx = graphics.cgContext

    let u = size / 1024                     // everything is designed on a 1024 grid
    let space = CGColorSpaceCreateDeviceRGB()
    let white = CGColor(colorSpace: space, components: [1, 1, 1, 1])!
    let amber = CGColor(colorSpace: space, components: [1.0, 0.74, 0.24, 1])!

    // ---- rounded-square plate with a top-down gradient
    let plate = CGRect(x: 100 * u, y: 100 * u, width: 824 * u, height: 824 * u)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: plate, cornerWidth: 185 * u, cornerHeight: 185 * u, transform: nil))
    ctx.clip()
    if let gradient = CGGradient(
        colorsSpace: space,
        colors: [CGColor(colorSpace: space, components: [0.22, 0.34, 0.57, 1])!,
                 CGColor(colorSpace: space, components: [0.07, 0.12, 0.21, 1])!] as CFArray,
        locations: [0, 1]) {
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: plate.midX, y: plate.maxY),
                               end: CGPoint(x: plate.midX, y: plate.minY),
                               options: [])
    }
    ctx.restoreGState()

    // ---- retry loop: an almost-closed ring with a gap at the upper right
    let center = CGPoint(x: size / 2, y: size / 2)
    let ringRadius = 250 * u
    // Thicker stroke and no bolt at 16pt, where fine detail turns to mush.
    let tiny = size <= 32
    let lineWidth = (tiny ? 108 : 78) * u
    let gapStart: CGFloat = 26
    let gapEnd: CGFloat = 74

    ctx.setStrokeColor(white)
    ctx.setLineWidth(lineWidth)
    ctx.setLineCap(.butt)
    ctx.beginPath()
    ctx.addArc(center: center, radius: ringRadius,
               startAngle: rad(gapStart), endAngle: rad(gapEnd), clockwise: true)
    ctx.strokePath()

    // ---- arrowhead at the ring's leading end, pointing clockwise
    let angle = rad(gapStart)
    let onRing = CGPoint(x: center.x + ringRadius * cos(angle),
                         y: center.y + ringRadius * sin(angle))
    let tangent = CGPoint(x: sin(angle), y: -cos(angle))     // clockwise direction
    let radial = CGPoint(x: cos(angle), y: sin(angle))       // outward
    // Base overlaps the flat stroke end (no seam) and spans the radius; the tip
    // runs along the tangent, so the head reads as "keep going clockwise".
    let length = lineWidth * 2.05
    let half = lineWidth * 0.95
    let base = CGPoint(x: onRing.x - tangent.x * lineWidth * 0.35,
                       y: onRing.y - tangent.y * lineWidth * 0.35)
    ctx.setFillColor(white)
    ctx.beginPath()
    ctx.move(to: CGPoint(x: base.x + tangent.x * length, y: base.y + tangent.y * length))
    ctx.addLine(to: CGPoint(x: base.x + radial.x * half, y: base.y + radial.y * half))
    ctx.addLine(to: CGPoint(x: base.x - radial.x * half, y: base.y - radial.y * half))
    ctx.closePath()
    ctx.fillPath()

    // ---- bolt inside the ring
    if !tiny {
        let scale = 144 * u
        let boltShift = 4 * u
        let bolt: [CGPoint] = [
            CGPoint(x:  0.20, y:  1.00),
            CGPoint(x: -0.54, y:  0.04),
            CGPoint(x: -0.07, y:  0.04),
            CGPoint(x: -0.20, y: -1.00),
            CGPoint(x:  0.54, y: -0.04),
            CGPoint(x:  0.07, y: -0.04),
        ].map { CGPoint(x: center.x + boltShift + $0.x * scale, y: center.y + $0.y * scale) }

        ctx.setFillColor(amber)
        ctx.beginPath()
        ctx.move(to: bolt[0])
        for point in bolt.dropFirst() { ctx.addLine(to: point) }
        ctx.closePath()
        ctx.fillPath()
    }

    return rep.representation(using: .png, properties: [:])
}

let iconset = URL(fileURLWithPath: "AppIcon.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let sizes: [(String, CGFloat)] = [
    ("icon_16x16", 16),     ("icon_16x16@2x", 32),
    ("icon_32x32", 32),     ("icon_32x32@2x", 64),
    ("icon_128x128", 128),  ("icon_128x128@2x", 256),
    ("icon_256x256", 256),  ("icon_256x256@2x", 512),
    ("icon_512x512", 512),  ("icon_512x512@2x", 1024),
]

for (name, size) in sizes {
    guard let data = makeIcon(size: size) else {
        FileHandle.standardError.write("render failed: \(name)\n".data(using: .utf8)!)
        exit(1)
    }
    do {
        try data.write(to: iconset.appendingPathComponent("\(name).png"))
    } catch {
        FileHandle.standardError.write("write failed: \(name): \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}
print("rendered \(sizes.count) sizes into \(iconset.path)")

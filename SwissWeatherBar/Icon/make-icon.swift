// Draws the app icon (sun behind a cloud on a blue sky) and writes AppIcon.icns.
// Original artwork drawn in code: no SF Symbols, emoji or third-party graphics.
//
//   swift Icon/make-icon.swift Icon/AppIcon.icns
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Draws the icon on a 1024 × 1024 canvas (macOS icon grid: 824 pt body, 100 pt margin).
func draw() {
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    // body with a soft drop shadow
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x000000, 0.28)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    color(0x2F74E8).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    // sky: deep blue at the top to light blue at the bottom
    NSGradient(starting: color(0x1F5FD6), ending: color(0x8FD0FF))!.draw(in: body, angle: -90)

    // sun with a glow, upper right
    let sun = NSPoint(x: 615, y: 625)
    NSGradient(colors: [color(0xFFE27A, 0.55), color(0xFFE27A, 0.18), color(0xFFE27A, 0)],
               atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
        .draw(fromCenter: sun, radius: 150, toCenter: sun, radius: 330, options: [])
    let disc = NSBezierPath(ovalIn: NSRect(x: sun.x - 165, y: sun.y - 165, width: 330, height: 330))
    NSGraphicsContext.saveGraphicsState()
    disc.addClip()
    NSGradient(starting: color(0xFFE45C), ending: color(0xFFA824))!.draw(in: disc.bounds, angle: -60)
    NSGraphicsContext.restoreGraphicsState()

    // cloud in front: three bumps on a pill-shaped base. Each outer bump fully
    // contains the pill's rounded end (and touches its bottom), so the outline
    // has no notches where they meet.
    let cloud = NSBezierPath()
    cloud.windingRule = .nonZero
    cloud.append(NSBezierPath(roundedRect: NSRect(x: 245, y: 290, width: 540, height: 180), xRadius: 90, yRadius: 90))
    for (x, y, r) in [(335.0, 390.0, 100.0), (505.0, 500.0, 165.0), (695.0, 395.0, 105.0)] {
        cloud.append(NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)))
    }

    let ctx = NSGraphicsContext.current!.cgContext
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: color(0x0B3A8C, 0.35).cgColor)
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    NSColor.white.setFill()
    cloud.fill()
    NSGraphicsContext.saveGraphicsState()
    cloud.addClip()
    NSGradient(starting: color(0xFFFFFF), ending: color(0xDCE8F7))!.draw(in: cloud.bounds, angle: -90)
    NSGraphicsContext.restoreGraphicsState()
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
}

func png(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current!.cgContext.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let set = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(getpid()).iconset")
try? FileManager.default.removeItem(at: set)
try! FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for pt in [16, 32, 128, 256, 512] {
    try! png(pt).write(to: set.appendingPathComponent("icon_\(pt)x\(pt).png"))
    try! png(pt * 2).write(to: set.appendingPathComponent("icon_\(pt)x\(pt)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", out.path]
try! p.run(); p.waitUntilExit()
try? FileManager.default.removeItem(at: set)
if let preview = CommandLine.arguments.dropFirst(2).first {   // optional: write a 1024 px PNG preview
    try! png(1024).write(to: URL(fileURLWithPath: preview))
}
print(p.terminationStatus == 0 ? "Wrote \(out.path)" : "iconutil failed")

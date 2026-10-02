import AppKit

// Generates Resources/AppIcon.icns — a branch glyph with a "+" badge on a teal → indigo
// rounded square. Run: swift tools/make-icon.swift   (from the project root)

let iconset = "build/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(atPath: "Resources", withIntermediateDirectories: true)

func renderPNG(_ px: Int) -> Data {
    let s = CGFloat(px)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    // Rounded background with a small margin like a real app icon, lit diagonally.
    let rect = NSRect(x: 0, y: 0, width: s, height: s).insetBy(dx: s * 0.045, dy: s * 0.045)
    let bg = NSBezierPath(roundedRect: rect, xRadius: s * 0.225, yRadius: s * 0.225)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.16, green: 0.78, blue: 0.72, alpha: 1),
        NSColor(calibratedRed: 0.20, green: 0.24, blue: 0.70, alpha: 1),
    ])!.draw(in: bg, angle: -60)

    // Soft glass highlight across the top half.
    NSGraphicsContext.current?.saveGraphicsState()
    bg.setClip()
    let shine = NSBezierPath(ovalIn: NSRect(x: rect.minX - s * 0.2, y: s * 0.52, width: s * 1.4, height: s * 0.8))
    NSColor.white.withAlphaComponent(0.12).setFill()
    shine.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    // White branch glyph, slightly left of center.
    let cfg = NSImage.SymbolConfiguration(pointSize: s * 0.46, weight: .bold)
        .applying(NSImage.SymbolConfiguration(hierarchicalColor: .white))
    if let glyph = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) {
        let g = glyph.size
        glyph.draw(in: NSRect(x: (s - g.width) / 2 - s * 0.05, y: (s - g.height) / 2, width: g.width, height: g.height))
    }

    // "+" badge, bottom right.
    let d = s * 0.30
    let badge = NSRect(x: rect.maxX - d - s * 0.06, y: rect.minY + s * 0.06, width: d, height: d)
    NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.20, alpha: 1).setFill()
    NSBezierPath(ovalIn: badge).fill()
    let plus = NSBezierPath()
    plus.lineWidth = d * 0.16
    plus.lineCapStyle = .round
    plus.move(to: NSPoint(x: badge.midX - d * 0.24, y: badge.midY))
    plus.line(to: NSPoint(x: badge.midX + d * 0.24, y: badge.midY))
    plus.move(to: NSPoint(x: badge.midX, y: badge.midY - d * 0.24))
    plus.line(to: NSPoint(x: badge.midX, y: badge.midY + d * 0.24))
    NSColor.white.setStroke()
    plus.stroke()

    image.unlockFocus()
    let tiff = image.tiffRepresentation!
    return NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
}

// iconset entries → pixel size
let entries: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
var cache: [Int: Data] = [:]
for (name, px) in entries {
    let data = cache[px] ?? renderPNG(px)
    cache[px] = data
    try! data.write(to: URL(fileURLWithPath: "\(iconset)/\(name).png"))
}

// Build the .icns
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset, "-o", "Resources/AppIcon.icns"]
try! p.run()
p.waitUntilExit()
print(p.terminationStatus == 0 ? "✓ Resources/AppIcon.icns" : "✗ iconutil failed (\(p.terminationStatus))")

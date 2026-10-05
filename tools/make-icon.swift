import AppKit

// Builds Resources/AppIcon.icns from the artwork in Resources/AppIcon-source.png.
// The source may come with a baked-in "transparency" checkerboard: every light pixel connected to the
// image border is treated as background and dropped, the remaining artwork is fitted into the macOS
// icon grid (824 pt squircle centered in 1024) and clipped to a continuous-corner squircle.
// Run: swift tools/make-icon.swift [preview.png]   (from the project root)

let sourcePath = "Resources/AppIcon-source.png"
let iconset = "build/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

guard let source = NSImage(contentsOfFile: sourcePath)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("✗ cannot read \(sourcePath)")
}

/// RGBA8 copy of an image, row 0 = top.
func pixels(of image: CGImage) -> (data: [UInt8], width: Int, height: Int) {
    let w = image.width, h = image.height
    var data = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (data, w, h)
}

/// Clears light pixels reachable from the border (the fake checkerboard), returns the artwork's bounds.
func removeBackground(_ data: inout [UInt8], _ w: Int, _ h: Int) -> CGRect {
    func light(_ i: Int) -> Bool {
        let r = Int(data[i * 4]), g = Int(data[i * 4 + 1]), b = Int(data[i * 4 + 2])
        return (r + g + b) / 3 > 150 && max(r, g, b) - min(r, g, b) < 40   // light and unsaturated
    }
    var seen = [Bool](repeating: false, count: w * h)
    var stack: [Int] = []
    for x in 0..<w { stack += [x, (h - 1) * w + x] }
    for y in 0..<h { stack += [y * w, y * w + w - 1] }
    while let i = stack.popLast() {
        guard !seen[i], light(i) else { continue }
        seen[i] = true
        data.replaceSubrange(i * 4..<i * 4 + 4, with: [0, 0, 0, 0])
        let x = i % w, y = i / w
        if x > 0 { stack.append(i - 1) }
        if x < w - 1 { stack.append(i + 1) }
        if y > 0 { stack.append(i - w) }
        if y < h - 1 { stack.append(i + w) }
    }
    var minX = w, minY = h, maxX = 0, maxY = 0
    for y in 0..<h { for x in 0..<w where data[(y * w + x) * 4 + 3] > 0 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    } }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

var (data, w, h) = pixels(of: source)
let bounds = removeBackground(&data, w, h)
let cleaned = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
// Inset 1 px so the anti-aliased fringe of the old background falls outside the clip.
let artwork = cleaned.cropping(to: bounds.insetBy(dx: 1, dy: 1))!

/// Superellipse (n = 5) — the continuous-corner "squircle" used by macOS app icons.
func squircle(_ r: CGRect) -> CGPath {
    let path = CGMutablePath(), n = 5.0, steps = 360
    for i in 0...steps {
        let t = Double(i) / Double(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = pow(abs(c), 2 / n) * (c < 0 ? -1 : 1), y = pow(abs(s), 2 / n) * (s < 0 ? -1 : 1)
        let p = CGPoint(x: r.midX + x * r.width / 2, y: r.midY + y * r.height / 2)
        i == 0 ? path.move(to: p) : path.addLine(to: p)
    }
    path.closeSubpath()
    return path
}

func render(_ px: Int) -> Data {
    let s = CGFloat(px) / 1024
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    let tile = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    // Soft drop shadow under the tile, like system icons.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 24 * s, color: CGColor(gray: 0, alpha: 0.3))
    ctx.addPath(squircle(tile))
    ctx.setFillColor(CGColor(srgbRed: 0.1, green: 0.1, blue: 0.13, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(squircle(tile))
    ctx.clip()
    ctx.draw(artwork, in: tile)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

if CommandLine.arguments.count > 1 {
    try! render(1024).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}

let entries: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
var cache: [Int: Data] = [:]
for (name, px) in entries {
    let data = cache[px] ?? render(px)
    cache[px] = data
    try! data.write(to: URL(fileURLWithPath: "\(iconset)/\(name).png"))
}

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset, "-o", "Resources/AppIcon.icns"]
try! p.run()
p.waitUntilExit()
print(p.terminationStatus == 0 ? "✓ Resources/AppIcon.icns (artwork \(Int(bounds.width))×\(Int(bounds.height)) px)" : "✗ iconutil failed (\(p.terminationStatus))")

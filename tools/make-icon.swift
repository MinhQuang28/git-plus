import AppKit

// Generates Resources/AppIcon.icns — a macOS 26–style squircle: deep indigo glass with a soft glow,
// a hand-drawn branch graph whose branch ends in a bright "+" node.
// Run: swift tools/make-icon.swift [preview.png]   (from the project root)

let iconset = "build/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(atPath: "Resources", withIntermediateDirectories: true)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
}

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

/// Fills the stroke of `path` with a linear gradient.
func strokeGradient(_ ctx: CGContext, _ path: CGPath, width: CGFloat, _ g: CGGradient, from: CGPoint, to: CGPoint) {
    ctx.saveGState()
    ctx.addPath(path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10))
    ctx.clip()
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }   // unit → pixels (origin bottom-left)

    // Icon body: 824/1024 grid like Apple's template, with a soft drop shadow.
    let body = CGRect(x: s * 0.0977, y: s * 0.0977, width: s * 0.8046, height: s * 0.8046)
    let shape = squircle(body)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: rgb(0x000000, 0.35))
    ctx.addPath(shape); ctx.setFillColor(rgb(0x14123a)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    // Deep indigo → near-black, lit from the top.
    ctx.drawLinearGradient(gradient([rgb(0x3b2f8f), rgb(0x1a1650), rgb(0x0b0b24)], [0, 0.55, 1]),
                           start: P(0.5, 0.9), end: P(0.5, 0.1), options: [])
    // Coloured glows behind the glyph.
    ctx.drawRadialGradient(gradient([rgb(0x22d3ee, 0.45), rgb(0x22d3ee, 0)]), startCenter: P(0.66, 0.66), startRadius: 0,
                           endCenter: P(0.66, 0.66), endRadius: s * 0.36, options: [])
    ctx.drawRadialGradient(gradient([rgb(0xa855f7, 0.40), rgb(0xa855f7, 0)]), startCenter: P(0.34, 0.30), startRadius: 0,
                           endCenter: P(0.34, 0.30), endRadius: s * 0.38, options: [])

    // Branch graph: trunk on the left, a curve branching off to the right ending in the "+" node.
    let lw = s * 0.062
    let trunkX: CGFloat = 0.395, bottomY: CGFloat = 0.27, topY: CGFloat = 0.73
    let plusC = P(0.645, 0.615), plusR = s * 0.118

    let branch = CGMutablePath()
    branch.move(to: P(trunkX, 0.36))
    branch.addCurve(to: CGPoint(x: plusC.x, y: plusC.y - plusR), control1: P(trunkX, 0.47), control2: P(0.645, 0.40))
    strokeGradient(ctx, branch, width: lw, gradient([rgb(0xc084fc), rgb(0x67e8f9)]), from: P(trunkX, 0.36), to: plusC)

    let trunk = CGMutablePath()
    trunk.move(to: P(trunkX, bottomY)); trunk.addLine(to: P(trunkX, topY))
    strokeGradient(ctx, trunk, width: lw, gradient([rgb(0xffffff), rgb(0xd9d6ff)]), from: P(0, topY), to: P(0, bottomY))

    // Commit nodes: white rings with a dark core.
    for c in [P(trunkX, bottomY), P(trunkX, topY)] {
        let r = s * 0.072
        ctx.setFillColor(rgb(0xffffff)); ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        let inner = r * 0.48
        ctx.setFillColor(rgb(0x1e1a55)); ctx.fillEllipse(in: CGRect(x: c.x - inner, y: c.y - inner, width: inner * 2, height: inner * 2))
    }

    // "+" node: glowing cyan → violet disc.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s * 0.05, color: rgb(0x67e8f9, 0.7))
    ctx.setFillColor(rgb(0x67e8f9))
    ctx.fillEllipse(in: CGRect(x: plusC.x - plusR, y: plusC.y - plusR, width: plusR * 2, height: plusR * 2))
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: plusC.x - plusR, y: plusC.y - plusR, width: plusR * 2, height: plusR * 2)); ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(0x67e8f9), rgb(0x818cf8), rgb(0xc084fc)], [0, 0.5, 1]),
                           start: CGPoint(x: plusC.x - plusR, y: plusC.y + plusR), end: CGPoint(x: plusC.x + plusR, y: plusC.y - plusR), options: [])
    ctx.restoreGState()
    let arm = plusR * 0.48
    let plus = CGMutablePath()
    plus.move(to: CGPoint(x: plusC.x - arm, y: plusC.y)); plus.addLine(to: CGPoint(x: plusC.x + arm, y: plusC.y))
    plus.move(to: CGPoint(x: plusC.x, y: plusC.y - arm)); plus.addLine(to: CGPoint(x: plusC.x, y: plusC.y + arm))
    ctx.addPath(plus); ctx.setStrokeColor(rgb(0xffffff)); ctx.setLineWidth(plusR * 0.24); ctx.setLineCap(.round); ctx.strokePath()

    // Glass: top sheen + hairline rim.
    let sheen = CGMutablePath()
    sheen.addEllipse(in: CGRect(x: body.minX - s * 0.25, y: s * 0.50, width: body.width + s * 0.5, height: s * 0.85))
    ctx.addPath(sheen); ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(0xffffff, 0.13), rgb(0xffffff, 0)]), start: P(0.5, 0.92), end: P(0.5, 0.62), options: [])
    ctx.restoreGState()
    ctx.addPath(shape)
    ctx.setStrokeColor(rgb(0xffffff, 0.14)); ctx.setLineWidth(max(1, s * 0.004)); ctx.strokePath()

    return rep.representation(using: .png, properties: [:])!
}

// Optional preview: swift tools/make-icon.swift out.png
if CommandLine.arguments.count > 1 {
    try! render(1024).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    print("✓ preview \(CommandLine.arguments[1])")
    exit(0)
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
print(p.terminationStatus == 0 ? "✓ Resources/AppIcon.icns" : "✗ iconutil failed (\(p.terminationStatus))")

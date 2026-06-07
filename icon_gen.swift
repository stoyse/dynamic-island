import AppKit

// Renders the app icon (Dynamic Island motif) at any pixel size and writes PNGs.

func drawIcon(size S: CGFloat, into ctx: CGContext) {
    let rect = CGRect(x: 0, y: 0, width: S, height: S)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // --- Background squircle ---
    let margin = S * 0.085
    let content = rect.insetBy(dx: margin, dy: margin)
    let corner = content.width * 0.2237
    let squircle = CGPath(roundedRect: content, cornerWidth: corner, cornerHeight: corner, transform: nil)

    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    // Diagonal indigo → near-black gradient
    let cs = CGColorSpaceCreateDeviceRGB()
    let bg = CGGradient(colorsSpace: cs, colors: [
        CGColor(red: 0.21, green: 0.18, blue: 0.42, alpha: 1),
        CGColor(red: 0.04, green: 0.04, blue: 0.07, alpha: 1)
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: content.minX, y: content.maxY),
                           end: CGPoint(x: content.maxX, y: content.minY), options: [])

    // Soft teal glow behind the pill
    let glow = CGGradient(colorsSpace: cs, colors: [
        CGColor(red: 0.12, green: 0.72, blue: 0.66, alpha: 0.40),
        CGColor(red: 0.12, green: 0.72, blue: 0.66, alpha: 0.0)
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow,
        startCenter: CGPoint(x: S * 0.5, y: S * 0.52), startRadius: 0,
        endCenter: CGPoint(x: S * 0.5, y: S * 0.52), endRadius: S * 0.42, options: [])
    ctx.restoreGState()

    // Subtle top highlight on the squircle edge
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.setLineWidth(S * 0.004)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.12))
    ctx.strokePath()
    ctx.restoreGState()

    // --- Dynamic Island pill ---
    let pw = content.width * 0.66
    let ph = content.height * 0.255
    let pill = CGRect(x: (S - pw) / 2, y: (S - ph) / 2, width: pw, height: ph)
    let pillPath = CGPath(roundedRect: pill, cornerWidth: ph / 2, cornerHeight: ph / 2, transform: nil)

    // Green glow under the pill
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: S * 0.05,
                  color: CGColor(red: 0.20, green: 0.80, blue: 0.35, alpha: 0.55))
    ctx.addPath(pillPath)
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // Top inner highlight stroke on the pill
    ctx.saveGState()
    ctx.addPath(pillPath)
    ctx.setLineWidth(S * 0.0035)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.10))
    ctx.strokePath()
    ctx.restoreGState()

    let cy = pill.midY

    // --- Album art square (left) ---
    let side = ph * 0.60
    let albumCenter = CGPoint(x: pill.minX + pw * 0.245, y: cy)
    let album = CGRect(x: albumCenter.x - side/2, y: albumCenter.y - side/2, width: side, height: side)
    let albumPath = CGPath(roundedRect: album, cornerWidth: side * 0.26, cornerHeight: side * 0.26, transform: nil)
    ctx.saveGState()
    ctx.addPath(albumPath)
    ctx.clip()
    let albumGrad = CGGradient(colorsSpace: cs, colors: [
        CGColor(red: 1.0, green: 0.37, blue: 0.55, alpha: 1),
        CGColor(red: 1.0, green: 0.62, blue: 0.26, alpha: 1)
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(albumGrad, start: CGPoint(x: album.minX, y: album.maxY),
                           end: CGPoint(x: album.maxX, y: album.minY), options: [])
    ctx.restoreGState()

    // Music note glyph (SF Symbol, tinted white)
    let noteCfg = NSImage.SymbolConfiguration(pointSize: side * 0.52, weight: .bold)
    if let base = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)?
        .withSymbolConfiguration(noteCfg) {
        let tinted = NSImage(size: base.size)
        tinted.lockFocus()
        base.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        NSColor.white.set()
        CGRect(origin: .zero, size: base.size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        if let cg = tinted.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let w = base.size.width, h = base.size.height
            ctx.draw(cg, in: CGRect(x: albumCenter.x - w/2, y: albumCenter.y - h/2, width: w, height: h))
        }
    }

    // --- Usage ring (right) ---
    let ringD = ph * 0.62
    let ringCenter = CGPoint(x: pill.maxX - pw * 0.245, y: cy)
    let lw = ringD * 0.13
    // track
    ctx.saveGState()
    ctx.setLineWidth(lw)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.16))
    ctx.addEllipse(in: CGRect(x: ringCenter.x - ringD/2, y: ringCenter.y - ringD/2, width: ringD, height: ringD))
    ctx.strokePath()
    // progress arc (~72%), green, rounded caps, starting at top
    ctx.setLineCap(.round)
    ctx.setStrokeColor(CGColor(red: 0.20, green: 0.82, blue: 0.37, alpha: 1))
    let start = CGFloat.pi / 2                  // top
    let end = start - 2 * .pi * 0.72            // clockwise
    ctx.addArc(center: ringCenter, radius: ringD/2, startAngle: start, endAngle: end, clockwise: true)
    ctx.strokePath()
    ctx.restoreGState()
}

func renderPNG(size: Int, to path: String) {
    let S = CGFloat(size)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
    rep.size = NSSize(width: S, height: S)
    NSGraphicsContext.saveGraphicsState()
    let gctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gctx
    drawIcon(size: S, into: gctx.cgContext)
    gctx.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: path))
        print("wrote \(path) (\(size)px)")
    }
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let fm = FileManager.default
let iconset = "\(outDir)/AppIcon.iconset"
try? fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)

// Unique pixel sizes → iconset filenames
let map: [(Int, [String])] = [
    (16,  ["icon_16x16.png"]),
    (32,  ["icon_16x16@2x.png", "icon_32x32.png"]),
    (64,  ["icon_32x32@2x.png"]),
    (128, ["icon_128x128.png"]),
    (256, ["icon_128x128@2x.png", "icon_256x256.png"]),
    (512, ["icon_256x256@2x.png", "icon_512x512.png"]),
    (1024,["icon_512x512@2x.png"]),
]
for (px, names) in map {
    let tmp = "\(iconset)/_tmp_\(px).png"
    renderPNG(size: px, to: tmp)
    for n in names { try? fm.removeItem(atPath: "\(iconset)/\(n)"); try? fm.copyItem(atPath: tmp, toPath: "\(iconset)/\(n)") }
    try? fm.removeItem(atPath: tmp)
}
// App Store master
renderPNG(size: 1024, to: "\(outDir)/AppIcon_1024.png")
print("done")

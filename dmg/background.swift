import AppKit

// Renders the DMG installer background at 2x (1320x840 px → 660x420 pt) to dmg/background.png.
// Dark gradient + green glows + an "island" hero + an arrow toward the Applications folder,
// matching the in-app setup wizard.

let W: CGFloat = 660, H: CGFloat = 420
let accent = NSColor(calibratedRed: 0.20, green: 0.82, blue: 0.42, alpha: 1)
let white = NSColor.white

// 1x: pixel size == point size, so Finder positions the design correctly
// regardless of whether it honours the PNG DPI.
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)

NSGraphicsContext.saveGraphicsState()
let gctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = gctx
let cg = gctx.cgContext

// Helper: top-left Y → bottom-left Y
func by(_ topY: CGFloat) -> CGFloat { H - topY }

// 1) Vertical gradient backdrop
let bg = NSGradient(colors: [NSColor(white: 0.10, alpha: 1), NSColor(white: 0.025, alpha: 1)])!
bg.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)

// 2) Green radial glows
func glow(center: CGPoint, radius: CGFloat, alpha: CGFloat) {
    let g = NSGradient(colors: [accent.withAlphaComponent(alpha), accent.withAlphaComponent(0)])!
    g.draw(fromCenter: center, radius: 0, toCenter: center, radius: radius, options: [])
}
glow(center: CGPoint(x: W * 0.5, y: by(-20)), radius: 360, alpha: 0.20)
glow(center: CGPoint(x: W * 0.92, y: by(360)), radius: 300, alpha: 0.12)

// 3) Island hero pill
let pill = NSRect(x: (W - 320) / 2, y: by(88), width: 320, height: 62)
let pillPath = NSBezierPath(roundedRect: pill, xRadius: 26, yRadius: 26)
NSColor.black.setFill(); pillPath.fill()
white.withAlphaComponent(0.10).setStroke(); pillPath.lineWidth = 1; pillPath.stroke()

// 3a) artwork square
let artRect = NSRect(x: pill.minX + 16, y: pill.midY - 20, width: 40, height: 40)
let artPath = NSBezierPath(roundedRect: artRect, xRadius: 10, yRadius: 10)
let artGrad = NSGradient(colors: [accent, accent.withAlphaComponent(0.55)])!
artGrad.draw(in: artPath, angle: -45)
let note = NSAttributedString(string: "\u{266A}", attributes: [
    .font: NSFont.systemFont(ofSize: 20, weight: .semibold), .foregroundColor: white])
note.draw(at: CGPoint(x: artRect.midX - note.size().width / 2, y: artRect.midY - note.size().height / 2))

// 3b) title placeholder bar
let bar = NSBezierPath(roundedRect: NSRect(x: artRect.maxX + 14, y: pill.midY + 6, width: 96, height: 7), xRadius: 3, yRadius: 3)
white.withAlphaComponent(0.85).setFill(); bar.fill()

// 3c) dotted waveform row
func amp(_ i: Int) -> CGFloat {
    let x = Double(i)
    let s = sin(x * 0.5) * 0.5 + sin(x * 1.27 + 1.0) * 0.3 + sin(x * 0.21 + 2.3) * 0.2
    return CGFloat(min(1, max(0.2, (s * 0.5 + 0.5) * 0.8)))
}
let waveX = artRect.maxX + 14, waveY = pill.midY - 12.0
let cols = 30
for i in 0..<cols {
    let dots = max(1, Int((amp(i) * 4).rounded()))
    let played = Double(i) / Double(cols) < 0.4
    for d in 0..<dots {
        let r = NSRect(x: waveX + CGFloat(i) * 3.0, y: waveY - CGFloat(d) * 2.4, width: 1.6, height: 1.6)
        (played ? white.withAlphaComponent(0.9) : white.withAlphaComponent(0.28)).setFill()
        NSBezierPath(ovalIn: r).fill()
    }
}

// 3d) usage ring
let ringC = CGPoint(x: pill.maxX - 36, y: pill.midY), ringR: CGFloat = 19
white.withAlphaComponent(0.15).setStroke()
let bgRing = NSBezierPath(); bgRing.appendArc(withCenter: ringC, radius: ringR, startAngle: 0, endAngle: 360)
bgRing.lineWidth = 4; bgRing.stroke()
accent.setStroke()
let fg = NSBezierPath()
fg.appendArc(withCenter: ringC, radius: ringR, startAngle: 90, endAngle: 90 - 0.78 * 360, clockwise: true)
fg.lineWidth = 4; fg.lineCapStyle = .round; fg.stroke()
let pct = NSAttributedString(string: "78", attributes: [
    .font: NSFont.systemFont(ofSize: 13, weight: .bold), .foregroundColor: white])
pct.draw(at: CGPoint(x: ringC.x - pct.size().width / 2, y: ringC.y - pct.size().height / 2))

// 4) Title + subtitle
func drawCentered(_ s: String, font: NSFont, color: NSColor, topY: CGFloat) {
    let a = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
    let sz = a.size()
    a.draw(at: CGPoint(x: (W - sz.width) / 2, y: by(topY) - sz.height))
}
drawCentered("Dynamic Island", font: .systemFont(ofSize: 32, weight: .bold), color: white, topY: 104)
drawCentered("Drag the app into your Applications folder",
             font: .systemFont(ofSize: 13, weight: .medium), color: white.withAlphaComponent(0.55), topY: 150)

// 5) Arrow between the two icon slots (icon centers at x=175 and x=485, y=250 top-left)
let ay = by(250)
let arrow = NSBezierPath()
arrow.move(to: CGPoint(x: 258, y: ay))
arrow.line(to: CGPoint(x: 402, y: ay))
accent.withAlphaComponent(0.9).setStroke()
arrow.lineWidth = 3; arrow.lineCapStyle = .round
arrow.setLineDash([2, 7], count: 2, phase: 0)
arrow.stroke()
// arrowhead
let head = NSBezierPath()
head.move(to: CGPoint(x: 396, y: ay + 8))
head.line(to: CGPoint(x: 410, y: ay))
head.line(to: CGPoint(x: 396, y: ay - 8))
accent.setStroke(); head.lineWidth = 3; head.lineCapStyle = .round; head.lineJoinStyle = .round
head.setLineDash([], count: 0, phase: 0); head.stroke()

NSGraphicsContext.restoreGraphicsState()

let outURL = URL(fileURLWithPath: "dmg/background.png")
try! rep.representation(using: .png, properties: [:])!.write(to: outURL)
print("wrote \(outURL.path) (\(rep.pixelsWide)x\(rep.pixelsHigh) px)")

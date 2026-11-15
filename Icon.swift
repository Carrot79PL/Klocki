import Cocoa
// Generuje AppIcon.iconset: błyszczące klocki 3D na tle mgławicy z promieniami
let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
func c(_ h: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat((h >> 16) & 255) / 255, CGFloat((h >> 8) & 255) / 255, CGFloat(h & 255) / 255, a])!
}
func grad(_ cols: [CGColor], _ l: [CGFloat]) -> CGGradient { CGGradient(colorsSpace: cs, colors: cols as CFArray, locations: l)! }
func mix(_ h: UInt32, _ t: CGFloat, white: Bool) -> CGColor { NSColor(cgColor: c(h))!.blended(withFraction: t, of: white ? .white : .black)!.cgColor }

// siatka 6×6: stos (L, J, S, I) i spadający T
let stack: [(Int, Int, UInt32)] = [
    (0, 0, 0xFF8A1E), (1, 0, 0xFF8A1E), (0, 1, 0xFF8A1E), (0, 2, 0xFF8A1E),
    (2, 0, 0x3A6CFF), (3, 0, 0x3A6CFF), (4, 0, 0x3A6CFF), (4, 1, 0x3A6CFF),
    (1, 1, 0x37DE58), (2, 1, 0x37DE58), (2, 2, 0x37DE58), (3, 2, 0x37DE58),
    (5, 0, 0x20DDF0), (5, 1, 0x20DDF0), (5, 2, 0x20DDF0), (5, 3, 0x20DDF0)]
let falling: [(Int, Int, UInt32)] = [(2, 5, 0xB24CFF), (3, 5, 0xB24CFF), (4, 5, 0xB24CFF), (3, 4, 0xB24CFF)]

func block(_ ctx: CGContext, _ r: CGRect, _ h: UInt32) {
    let rad = r.width * 0.16
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -r.width * 0.07), blur: r.width * 0.18, color: CGColor(gray: 0, alpha: 0.55))
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil))
    ctx.setFillColor(c(h)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil)); ctx.clip()
    ctx.drawLinearGradient(grad([mix(h, 0.55, white: true), mix(h, 0.45, white: false)], [0, 1]),
                           start: CGPoint(x: r.minX, y: r.maxY), end: CGPoint(x: r.maxX, y: r.minY), options: [])
    let inner = r.insetBy(dx: r.width * 0.14, dy: r.width * 0.14)
    ctx.addPath(CGPath(roundedRect: inner, cornerWidth: rad * 0.6, cornerHeight: rad * 0.6, transform: nil)); ctx.clip()
    ctx.drawLinearGradient(grad([mix(h, 0.25, white: true), c(h), mix(h, 0.18, white: false)], [0, 0.55, 1]),
                           start: CGPoint(x: 0, y: inner.maxY), end: CGPoint(x: 0, y: inner.minY), options: [])
    ctx.setFillColor(CGColor(gray: 1, alpha: 0.3))
    ctx.fillEllipse(in: CGRect(x: inner.minX + inner.width * 0.08, y: inner.maxY - inner.height * 0.32, width: inner.width * 0.5, height: inner.height * 0.2))
    ctx.restoreGState()
}

func draw(_ s: Int) -> Data {
    let ctx = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let f = CGFloat(s), m = f * 0.098, r = CGRect(x: m, y: m, width: f - 2 * m, height: f - 2 * m)
    let corner = r.width * 0.225
    // cień całej ikony
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -f * 0.012), blur: f * 0.03, color: CGColor(gray: 0, alpha: 0.45))
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: corner, cornerHeight: corner, transform: nil))
    ctx.setFillColor(c(0x0A0C22)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: corner, cornerHeight: corner, transform: nil)); ctx.clip()
    // mgławica
    ctx.drawLinearGradient(grad([c(0x2A1F6E), c(0x111640), c(0x05060F)], [0, 0.55, 1]), start: CGPoint(x: 0, y: r.maxY), end: CGPoint(x: 0, y: r.minY), options: [])
    let center = CGPoint(x: r.midX, y: r.minY + r.height * 0.62)
    for (dx, dy, rr, h) in [(-0.25, 0.2, 0.55, 0xB03CFF as UInt32), (0.3, 0.05, 0.5, 0x2FA8FF), (0, -0.25, 0.45, 0xFF3FA8)] as [(CGFloat, CGFloat, CGFloat, UInt32)] {
        let p = CGPoint(x: r.midX + dx * r.width, y: r.midY + dy * r.height)
        ctx.drawRadialGradient(grad([c(h, 0.35), c(h, 0)], [0, 1]), startCenter: p, startRadius: 0, endCenter: p, endRadius: rr * r.width, options: [])
    }
    // promienie
    ctx.saveGState()
    for i in 0..<18 {
        let a0 = CGFloat(i) / 18 * 2 * .pi, a1 = a0 + .pi / 36
        ctx.move(to: center)
        ctx.addArc(center: center, radius: r.width, startAngle: a0, endAngle: a1, clockwise: false)
        ctx.closePath()
    }
    ctx.clip()
    ctx.drawRadialGradient(grad([CGColor(gray: 1, alpha: 0.22), CGColor(gray: 1, alpha: 0)], [0, 1]), startCenter: center, startRadius: 0, endCenter: center, endRadius: r.width * 0.75, options: [])
    ctx.restoreGState()
    // gwiazdy
    var seed: UInt64 = 7
    func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1) }
    for _ in 0..<40 {
        let x = r.minX + rnd() * r.width, y = r.minY + rnd() * r.height, d = (0.002 + rnd() * 0.004) * f
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.3 + rnd() * 0.6)); ctx.fillEllipse(in: CGRect(x: x, y: y, width: d, height: d))
    }
    // klocki
    let cell = r.width * 0.128, ox = r.midX - cell * 3, oy = r.minY + r.height * 0.1
    func rect(_ x: Int, _ y: Int) -> CGRect { CGRect(x: ox + CGFloat(x) * cell, y: oy + CGFloat(y) * cell, width: cell, height: cell).insetBy(dx: cell * 0.035, dy: cell * 0.035) }
    // poświata i smugi za spadającym klockiem
    let tc = CGPoint(x: rect(3, 5).midX, y: rect(3, 5).midY)
    ctx.drawRadialGradient(grad([c(0xB24CFF, 0.6), c(0xB24CFF, 0)], [0, 1]), startCenter: tc, startRadius: 0, endCenter: tc, endRadius: cell * 2.4, options: [])
    ctx.saveGState()
    for x in [2, 3, 4] {
        let b = rect(x, 6)
        ctx.addRect(CGRect(x: b.midX - cell * 0.09, y: b.minY - cell * 0.1, width: cell * 0.18, height: cell * 1.0))
    }
    ctx.clip()
    ctx.drawLinearGradient(grad([c(0xE6C8FF, 0.0), c(0xE6C8FF, 0.7)], [0, 1]), start: CGPoint(x: 0, y: rect(0, 7).maxY), end: CGPoint(x: 0, y: rect(0, 6).minY), options: [])
    ctx.restoreGState()
    for (x, y, h) in stack + falling { block(ctx, rect(x, y), h) }
    // subtelna obwódka
    ctx.restoreGState()
    ctx.addPath(CGPath(roundedRect: r.insetBy(dx: f * 0.002, dy: f * 0.002), cornerWidth: corner, cornerHeight: corner, transform: nil))
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.14)); ctx.setLineWidth(max(1, f * 0.004)); ctx.strokePath()
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

for n in [16, 32, 128, 256, 512] { for k in [1, 2] {
    let name = k == 1 ? "icon_\(n)x\(n).png" : "icon_\(n)x\(n)@2x.png"
    try! draw(n * k).write(to: URL(fileURLWithPath: out + "/" + name))
} }

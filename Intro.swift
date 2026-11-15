import Cocoa
import SpriteKit

// MARK: - Intro studia BLUEROOT
// Odwzorowanie LogoAnimacje/pixel_do_wektora.html: pixel art 192×108 („Klocki”: rzędy spadają od czubka,
// mruganie, pomarańcz → niebieski), potem płynne wyostrzenie do wektora z poświatą i połyskiem.

enum BluerootIntro {
    static let W = 192, H = 108
    static let CX: CGFloat = 96, K: CGFloat = 45.0 / 310, OY: CGFloat = 8 + 90 * 45.0 / 310
    static let HCY = OY + 70 * K
    static let tUp = 4.9, tEnd = 7.1, hold = 9.0
    static let bg: UInt32 = 0x111418

    // MARK: Paleta
    static let pO: [String: UInt32] = ["b0": 0xFF9433, "b1": 0xFF7A22, "b2": 0xF05A14, "hl": 0xFFC27E, "out": 0x3A1606,
                                       "leaf": 0x34C26B, "lo": 0x0D3A1D, "halo": 0x4A1E08, "st": 0xFF8A2A]
    static let pB: [String: UInt32] = ["b0": 0x5AAEFF, "b1": 0x3A8DF5, "b2": 0x1F66DB, "hl": 0xB4DCFF, "out": 0x081A40,
                                       "leaf": 0x34C26B, "lo": 0x0D3A1D, "halo": 0x0F2A5C, "st": 0x4DA3FF]
    static let fixed: [String: UInt32] = ["w": 0xFFFFFF, "ws": 0x1C3A78]
    static func white(_ t: String) -> UInt32 { t == "leaf" || t == "lo" ? pO[t]! : t == "out" ? 0x3A3A3A : 0xFFFFFF }

    struct Px { let x: Int, y: Int, type: String, ch: Int }

    // MARK: Sprite marchewki (rasteryzacja znaku do siatki pikseli)
    static let bands: [[CGPoint]] = [[(-60, 0), (60, 0), (42.29, 62), (-42.29, 62)],
                                     [(-39.71, 71), (39.71, 71), (24, 126), (-24, 126)],
                                     [(-21.43, 135), (21.43, 135), (0, 210)]].map { $0.map { CGPoint(x: $0.0, y: $0.1) } }
    static let leaves: [(CGFloat, CGFloat, CGFloat)] = [(-28, -60, 50), (0, -72, 62), (28, -60, 50)]

    static func inPoly(_ x: CGFloat, _ y: CGFloat, _ p: [CGPoint]) -> Bool {
        var c = false, j = p.count - 1
        for i in 0..<p.count {
            if (p[i].y > y) != (p[j].y > y) && x < (p[j].x - p[i].x) * (y - p[i].y) / (p[j].y - p[i].y) + p[i].x { c.toggle() }
            j = i
        }
        return c
    }
    static func inLeaf(_ x: CGFloat, _ y: CGFloat) -> Bool {
        leaves.contains { d, y0, h in
            let r = -d * .pi / 180, rx = x * cos(r) - y * sin(r), ry = x * sin(r) + y * cos(r)
            return abs(rx) <= 6.5 && ry >= y0 && ry <= y0 + h
        }
    }

    static var sprite: [Px] { spriteData.0 }
    static var occupied: Set<Int> { spriteData.1 }
    static let spriteData: ([Px], Set<Int>) = {
        let key = { (x: Int, y: Int) in y * 1000 + x }
        var g: [Int: String] = [:]
        for y in 0..<60 { for x in (Int(CX) - 16)..<(Int(CX) + 16) {
            let mx = (CGFloat(x) + 0.5 - CX) / K, my = (CGFloat(y) + 0.5 - OY) / K
            var t: String?
            for (i, p) in bands.enumerated() where inPoly(mx, my, p) { t = "b\(i)" }
            if t == nil && inLeaf(mx, my) { t = "leaf" }
            if let t { g[key(x, y)] = t }
        } }
        for k in g.keys.sorted() where g[k]!.hasPrefix("b") && g[k - 1] == nil { g[k] = "hl" }     // połysk z lewej
        let filled = g
        for k in filled.keys.sorted() {                                                           // ciemny obrys
            for n in [k + 1, k - 1, k + 1000, k - 1000] where filled[n] == nil && g[n] == nil { g[n] = filled[k] == "leaf" ? "lo" : "out" }
        }
        return (g.keys.sorted().map { Px(x: $0 % 1000, y: $0 / 1000, type: g[$0]!, ch: 0) }, Set(g.keys))
    }()
    static let rows: [Int] = Array(Set(sprite.map(\.y))).sorted(by: >)              // od dołu

    // MARK: Pikselowy font
    static let font: [Character: [String]] = [
        "B": ["1111.", "1...1", "1...1", "1111.", "1...1", "1...1", "1111."], "L": ["1....", "1....", "1....", "1....", "1....", "1....", "11111"],
        "U": ["1...1", "1...1", "1...1", "1...1", "1...1", "1...1", ".111."], "E": ["11111", "1....", "1....", "1111.", "1....", "1....", "11111"],
        "R": ["1111.", "1...1", "1...1", "1111.", "1.1..", "1..1.", "1...1"], "O": [".111.", "1...1", "1...1", "1...1", "1...1", "1...1", ".111."],
        "T": ["11111", "..1..", "..1..", "..1..", "..1..", "..1..", "..1.."]]
    static let fontS: [Character: [String]] = [
        "S": ["111", "1..", "111", "..1", "111"], "T": ["111", ".1.", ".1.", ".1.", ".1."], "U": ["1.1", "1.1", "1.1", "1.1", "111"],
        "D": ["11.", "1.1", "1.1", "1.1", "11."], "I": ["111", ".1.", ".1.", ".1.", "111"], "O": ["111", "1.1", "1.1", "1.1", "111"]]
    static func text(_ s: String, _ x0: Int, _ y0: Int, _ track: Int, _ type: String, _ f: [Character: [String]]) -> [Px] {
        var out: [Px] = [], x = x0
        for (ci, ch) in s.enumerated() {
            let g = f[ch]!
            for (ry, row) in g.enumerated() { for (rx, v) in row.enumerated() where v == "1" { out.append(Px(x: x + rx, y: y0 + ry, type: type, ch: ci)) } }
            x += g[0].count + track
        }
        return out
    }
    static let wordBig = text("BLUEROOT", Int(CX) - 27, 61, 2, "w", font)
    static let word = wordBig.map { Px(x: $0.x + 1, y: $0.y + 1, type: "ws", ch: $0.ch) } + wordBig
    static let studio = text("STUDIO", Int(CX) - 11, 71, 1, "st", fontS)

    // MARK: Poświata z ditheringiem Bayera
    static let halo: [(Int, Int, Double)] = {
        let bayer = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
        var rng = SeededRNG(s: 7), out: [(Int, Int, Double)] = []
        for y in 0..<62 { for x in (Int(CX) - 40)..<(Int(CX) + 40) {
            let d = hypot(CGFloat(x) + 0.5 - CX, (CGFloat(y) + 0.5 - HCY) / 1.1) / 38
            if d < 1 && !occupied.contains(y * 1000 + x) && CGFloat(bayer[y % 4][x % 4]) / 16 < 0.4 * pow(1 - d, 1.5) {
                out.append((x, y, Double.random(in: 0..<1, using: &rng)))
            }
        } }
        return out
    }()

    static func clamp(_ v: Double) -> Double { min(1, max(0, v)) }
    static func easeIO(_ p: Double) -> Double { 0.5 - 0.5 * cos(.pi * clamp(p)) }

    // MARK: Klatka pikselowa (wariant „Klocki”)
    static func pixelFrame(_ t: Double) -> CGImage {
        makeImage(W, H) { ctx in
            ctx.translateBy(x: 0, y: CGFloat(H)); ctx.scaleBy(x: 1, y: -1)
            var cache: [UInt32: CGColor] = [:]
            func dot(_ x: Int, _ y: Int, _ c: UInt32) {
                let col = cache[c] ?? { let v = rgb(c); cache[c] = v; return v }()
                ctx.setFillColor(col); ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
            dot(0, 0, bg); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
            let flash = t > 2.2 && t < 2.9
            let pal: (String) -> UInt32 = t >= 2.9 ? { pB[$0]! } : flash && Int((t - 2.2) / 0.1) % 2 == 0 ? white : { pO[$0]! }
            if t > 2.9 { let a = clamp((t - 2.9) / 0.5); for h in halo where h.2 < a { dot(h.0, h.1, pB["halo"]!) } }
            for (i, row) in rows.enumerated() {
                let p = clamp((t - 0.2 - Double(i) * 0.03) / 0.25)
                guard p > 0 else { continue }
                let dy = Int((Double(row + 12) * -(1 - p * p)).rounded())
                for s in sprite where s.y == row { dot(s.x, s.y + dy, pal(s.type)) }
            }
            for p in word {
                let q = clamp((t - 3.0 - Double(p.ch) * 0.08) / 0.2)
                if q > 0 { dot(p.x, p.y - Int(((1 - q) * 12).rounded()), fixed[p.type]!) }
            }
            if t > 3.9 && !(t < 4.3 && Int(t / 0.1) % 2 == 1) { for p in studio { dot(p.x, p.y, pB["st"]!) } }
        }
    }

    // MARK: Wektor
    static func svgPath(_ d: String) -> CGMutablePath {
        let p = CGMutablePath()
        let re = try! NSRegularExpression(pattern: "[MLHVQCZ]|-?\\d*\\.?\\d+(?:[eE][-+]?\\d+)?")
        let toks = re.matches(in: d, range: NSRange(d.startIndex..., in: d)).map { String(d[Range($0.range, in: d)!]) }
        var i = 0, cmd = "M", cur = CGPoint.zero
        func n() -> CGFloat { defer { i += 1 }; return CGFloat(Double(toks[i]) ?? 0) }
        while i < toks.count {
            if let c = toks[i].first, c.isLetter { cmd = String(c); i += 1; if cmd == "Z" { p.closeSubpath(); continue } }
            switch cmd {
            case "M": cur = CGPoint(x: n(), y: n()); p.move(to: cur); cmd = "L"
            case "L": cur = CGPoint(x: n(), y: n()); p.addLine(to: cur)
            case "H": cur.x = n(); p.addLine(to: cur)
            case "V": cur.y = n(); p.addLine(to: cur)
            case "Q": let c1 = CGPoint(x: n(), y: n()); cur = CGPoint(x: n(), y: n()); p.addQuadCurve(to: cur, control: c1)
            case "C": let c1 = CGPoint(x: n(), y: n()), c2 = CGPoint(x: n(), y: n()); cur = CGPoint(x: n(), y: n()); p.addCurve(to: cur, control1: c1, control2: c2)
            default: i += 1
            }
        }
        return p
    }
    static let wordPaths: (CGPath, CGPath)? = {
        guard let url = Bundle.main.url(forResource: "blueroot", withExtension: "svg"),
              let s = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let ds = try! NSRegularExpression(pattern: "\\sd=\"([^\"]+)\"").matches(in: s, range: NSRange(s.startIndex..., in: s))
            .map { String(s[Range($0.range(at: 1), in: s)!]) }
        guard ds.count == 2 else { return nil }
        var tr = CGAffineTransform(translationX: CX + (160 - 500) * K, y: OY + (372 - 110) * K).scaledBy(x: 0.68 * K, y: 0.68 * K)
        return (svgPath(ds[0]).copy(using: &tr)!, svgPath(ds[1]).copy(using: &tr)!)
    }()
    static let markPaths: (bands: [CGPath], leaves: [CGPath]) = {
        let m = CGAffineTransform(translationX: CX, y: OY).scaledBy(x: K, y: K)
        let b = bands.map { pts -> CGPath in let p = CGMutablePath(); p.addLines(between: pts, transform: m); p.closeSubpath(); return p }
        let l = leaves.map { d, y, h -> CGPath in
            var tr = CGAffineTransform(rotationAngle: d * .pi / 180).concatenating(m)
            return CGPath(roundedRect: CGRect(x: -6, y: y, width: 12, height: h), cornerWidth: 6, cornerHeight: 6, transform: &tr)
        }
        return (b, l)
    }()
    /// Rysuje wektorowe logo w układzie 192×108 (oś y w dół) przeskalowanym o `s`.
    static func drawVector(_ ctx: CGContext, _ s: CGFloat) {
        ctx.saveGState(); ctx.scaleBy(x: s, y: s)
        ctx.setFillColor(rgb(0x34C26B)); markPaths.leaves.forEach { ctx.addPath($0) }; ctx.fillPath()
        for (i, p) in markPaths.bands.enumerated() { ctx.setFillColor(rgb(pB["b\(i)"]!)); ctx.addPath(p); ctx.fillPath() }
        if let (w, st) = wordPaths {
            ctx.setFillColor(rgb(0xFFFFFF)); ctx.addPath(w); ctx.fillPath()
            ctx.setFillColor(rgb(0x4DA3FF)); ctx.addPath(st); ctx.fillPath()
        }
        ctx.restoreGState()
    }
    static func vectorImage(_ w: Int, _ h: Int) -> CGImage {
        makeImage(w, h) { ctx in ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1); drawVector(ctx, CGFloat(w) / CGFloat(W)) }
    }

    // MARK: Węzeł SpriteKit
    static func node(size: CGSize, scale px: CGFloat) -> SKNode {
        let o = SKNode()
        let w = size.width, h = size.height
        let sw = min(w, h * 16 / 9), sh = sw * 9 / 16
        let rect = CGRect(x: (w - sw) / 2, y: (h - sh) / 2, width: sw, height: sh), mid = CGPoint(x: rect.midX, y: rect.midY)
        func scene(_ gx: CGFloat, _ gy: CGFloat) -> CGPoint { CGPoint(x: rect.minX + gx / CGFloat(W) * sw, y: rect.maxY - gy / CGFloat(H) * sh) }
        func tex(_ img: CGImage, _ sharp: Bool) -> SKTexture { let t = SKTexture(cgImage: img); t.filteringMode = sharp ? .nearest : .linear; return t }

        let back = SKSpriteNode(color: nsc(bg), size: CGSize(width: w * 4, height: h * 4))
        back.position = CGPoint(x: w / 2, y: h / 2); back.zPosition = -1
        let gr = 190 / 1536 * sw
        let glow = SKSpriteNode(texture: SKTexture(cgImage: makeImage(256, 256) { ctx in
            ctx.drawRadialGradient(gradient([rgb(0x2E86FF, 0.22), rgb(0x2E86FF, 0)], [0, 1]), startCenter: CGPoint(x: 128, y: 128), startRadius: 0,
                                   endCenter: CGPoint(x: 128, y: 128), endRadius: 128, options: [])
        }), size: CGSize(width: gr * 2, height: gr * 2))
        glow.position = scene(CX, HCY); glow.alpha = 0; glow.zPosition = 0
        let lay = SKSpriteNode(color: .clear, size: rect.size); lay.position = mid; lay.zPosition = 1; lay.alpha = 0
        let vtex = tex(vectorImage(Int(sw * px), Int(sh * px)), false)
        let vec = SKSpriteNode(texture: vtex, size: rect.size); vec.position = mid; vec.zPosition = 2; vec.alpha = 0
        // połysk: jasny pas przesuwany po logo, przycięty do jego kształtu
        let crop = SKCropNode(); crop.zPosition = 3
        let mask = SKSpriteNode(texture: vtex, size: rect.size); mask.position = mid; crop.maskNode = mask
        let bandW = 320 / 1536 * sw
        let band = SKSpriteNode(texture: SKTexture(cgImage: makeImage(64, 4) { ctx in
            ctx.drawLinearGradient(gradient([rgb(0xFFFFFF, 0), rgb(0xFFFFFF, 0.55), rgb(0xFFFFFF, 0)], [0, 0.5, 1]),
                                   start: .zero, end: CGPoint(x: 64, y: 0), options: [])
        }), size: CGSize(width: bandW, height: sh * 1.6))
        band.zRotation = -0.33; band.position = CGPoint(x: rect.minX - bandW, y: mid.y); band.isHidden = true
        crop.addChild(band)
        let pix = SKSpriteNode(color: .clear, size: rect.size); pix.position = mid; pix.zPosition = 4
        let scan = SKSpriteNode(texture: tex(makeImage(4, H * 8) { ctx in
            ctx.setFillColor(rgb(0x000000, 0.3))
            for y in stride(from: 0, to: H * 8, by: 8) { ctx.fill(CGRect(x: 0, y: y, width: 4, height: 2)) }
        }, true), size: rect.size)
        scan.position = mid; scan.zPosition = 5
        [back, glow, lay, vec, crop, pix, scan].forEach { o.addChild($0) }

        var lastQ = -1.0, frozen = false
        o.run(.customAction(withDuration: hold) { _, e in
            let t = Double(e)
            if t < tUp {
                let q = (t * 20).rounded(.down) / 20
                if q != lastQ { lastQ = q; pix.texture = tex(pixelFrame(q), true) }
            } else if t < tEnd {
                let p = (t - tUp) / (tEnd - tUp), r = pow(8, easeIO(p))
                if !frozen { frozen = true; pix.texture = tex(pixelFrame(tUp), true) }
                pix.alpha = CGFloat(1 - easeIO(p / 0.35))
                lay.texture = tex(vectorImage(Int((Double(W) * r).rounded()), Int((Double(H) * r).rounded())), p <= 0.85)
                lay.alpha = 1
                glow.alpha = CGFloat(easeIO((p - 0.45) / 0.55))
                scan.alpha = CGFloat(1 - easeIO(p / 0.75))
                vec.alpha = CGFloat(clamp((p - 0.9) / 0.1))
            } else {
                pix.alpha = 0; scan.alpha = 0; lay.alpha = 0; vec.alpha = 1; glow.alpha = 1
                let sp = (t - tEnd - 0.3) / 1.1
                band.isHidden = sp <= 0 || sp >= 1
                band.position.x = rect.minX - bandW + CGFloat(easeIO(sp)) * (sw + 2 * bandW)
            }
        })
        return o
    }

    /// Test bez okna: KLOCKI_INTRO=<katalog> zapisuje kilka klatek do PNG.
    static func dumpFrames(_ dir: String) {
        func save(_ img: CGImage, _ name: String) {
            try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir + "/" + name))
        }
        for t in [1.0, 2.4, 3.4, 4.8] { save(pixelFrame(t), "pix_\(t).png") }
        save(vectorImage(384, 216), "vec_low.png")
        save(makeImage(1536, 864) { ctx in ctx.setFillColor(rgb(bg)); ctx.fill(CGRect(x: 0, y: 0, width: 1536, height: 864)); ctx.draw(vectorImage(1536, 864), in: CGRect(x: 0, y: 0, width: 1536, height: 864)) }, "vec_full.png")
    }
}

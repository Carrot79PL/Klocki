import Cocoa
import SceneKit
import SpriteKit
import GameController

// MARK: - Pomocnicze

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ h: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: srgb, components: [CGFloat((h >> 16) & 255) / 255, CGFloat((h >> 8) & 255) / 255, CGFloat(h & 255) / 255, a])!
}
func nsc(_ h: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((h >> 16) & 255) / 255, green: CGFloat((h >> 8) & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: a)
}
func makeImage(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: max(1, w), height: max(1, h), bitsPerComponent: 8, bytesPerRow: 0,
                        space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    draw(ctx)
    return ctx.makeImage()!
}
func gradient(_ c: [CGColor], _ l: [CGFloat]) -> CGGradient { CGGradient(colorsSpace: srgb, colors: c as CFArray, locations: l)! }
let thousands: NumberFormatter = { let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = " "; return f }()
func fmt(_ n: Int) -> String { thousands.string(from: NSNumber(value: n)) ?? "\(n)" }

// MARK: - Losowanie z ziarnem (powtarzalny układ tła)

struct SeededRNG: RandomNumberGenerator {
    var s: UInt64
    mutating func next() -> UInt64 {
        s &+= 0x9E3779B97F4A7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

// MARK: - Klocki (klasyczne 7 kształtów, rotacja SRS)

enum Kind: Int, CaseIterable { case I, O, T, S, Z, J, L }
let baseCells: [[(Int, Int)]] = [
    [(0, 2), (1, 2), (2, 2), (3, 2)],
    [(1, 2), (2, 2), (1, 1), (2, 1)],
    [(1, 2), (0, 1), (1, 1), (2, 1)],
    [(1, 2), (2, 2), (0, 1), (1, 1)],
    [(0, 2), (1, 2), (1, 1), (2, 1)],
    [(0, 2), (0, 1), (1, 1), (2, 1)],
    [(2, 2), (0, 1), (1, 1), (2, 1)],
]
let kindHex: [UInt32] = [0x20DDF0, 0xFFD21F, 0xB24CFF, 0x37DE58, 0xFF3B4C, 0x3A6CFF, 0xFF8A1E]
let shapes: [[[(Int, Int)]]] = Kind.allCases.map { k in
    (0..<4).map { r in
        var c = baseCells[k.rawValue]
        if k != .O { let n = k == .I ? 4 : 3; for _ in 0..<r { c = c.map { ($0.1, n - 1 - $0.0) } } }
        return c
    }
}
// przesunięcia dla obrotu w prawo z danego stanu (0, R, 2, L)
let kicksJ: [[(Int, Int)]] = [
    [(0, 0), (-1, 0), (-1, 1), (0, -2), (-1, -2)],
    [(0, 0), (1, 0), (1, -1), (0, 2), (1, 2)],
    [(0, 0), (1, 0), (1, 1), (0, -2), (1, -2)],
    [(0, 0), (-1, 0), (-1, -1), (0, 2), (-1, 2)]]
let kicksI: [[(Int, Int)]] = [
    [(0, 0), (-2, 0), (1, 0), (-2, -1), (1, 2)],
    [(0, 0), (-1, 0), (2, 0), (-1, 2), (2, -1)],
    [(0, 0), (2, 0), (-1, 0), (2, 1), (-1, -2)],
    [(0, 0), (1, 0), (-2, 0), (1, -2), (-2, 1)]]

// MARK: - Rekordy

struct Record: Codable { var name: String; var score: Int; var lines: Int; var level: Int; var date: Date; var diff: Int? = nil }   // diff: brak w starych zapisach
enum Records {
    static let key = "rekordy"
    static func load() -> [Record] {
        guard let d = UserDefaults.standard.data(forKey: key), let r = try? JSONDecoder().decode([Record].self, from: d) else { return [] }
        return r
    }
    static func qualifies(_ s: Int) -> Bool { let r = load(); return s > 0 && (r.count < 10 || s > (r.last?.score ?? 0)) }
    static func insert(_ rec: Record) -> Int {
        var r = load(); r.append(rec)
        r.sort { $0.score > $1.score }
        r = Array(r.prefix(10))
        if let d = try? JSONEncoder().encode(r) { UserDefaults.standard.set(d, forKey: key) }
        return r.firstIndex { $0.date == rec.date } ?? -1
    }
}

// MARK: - Logo studia (Orange Carrot) — jak w Samotniku

func markPart(_ part: Int, height: CGFloat) -> CGImage {
    let s = height / 310
    return makeImage(Int(160 * s), Int(height)) { ctx in
        ctx.translateBy(x: 0, y: height)
        ctx.scaleBy(x: s, y: -s)
        ctx.translateBy(x: 80, y: 90)
        func poly(_ pts: [(CGFloat, CGFloat)], _ hex: UInt32) {
            ctx.move(to: CGPoint(x: pts[0].0, y: pts[0].1))
            pts.dropFirst().forEach { ctx.addLine(to: CGPoint(x: $0.0, y: $0.1)) }
            ctx.closePath()
            ctx.setFillColor(rgb(hex))
            ctx.fillPath()
        }
        switch part {
        case 0: poly([(-60, 0), (60, 0), (42.29, 62), (-42.29, 62)], 0xFF9433)
        case 1: poly([(-39.71, 71), (39.71, 71), (24, 126), (-24, 126)], 0xFF7A22)
        case 2: poly([(-21.43, 135), (21.43, 135), (0, 210)], 0xF05A14)
        default:
            for (deg, y, h) in [(-28.0, -60.0, 50.0), (0, -72, 62), (28, -60, 50)] {
                ctx.saveGState()
                ctx.rotate(by: deg * .pi / 180)
                ctx.addPath(CGPath(roundedRect: CGRect(x: -6, y: y, width: 12, height: h), cornerWidth: 6, cornerHeight: 6, transform: nil))
                ctx.setFillColor(rgb(0x34C26B))
                ctx.fillPath()
                ctx.restoreGState()
            }
        }
    }
}

func wordmarkTexture(widthPx: CGFloat) -> SKTexture? {
    guard let url = Bundle.main.url(forResource: "wordmark", withExtension: "svg"),
          let img = NSImage(contentsOf: url) else { return nil }
    var r = CGRect(x: 0, y: 0, width: widthPx, height: widthPx * 0.15)
    guard let cg = img.cgImage(forProposedRect: &r, context: nil, hints: nil) else { return nil }
    let t = SKTexture(cgImage: cg)
    t.filteringMode = .linear
    return t
}

// MARK: - HUD (nakładka 2D)

final class HUD: SKScene {
    var px: CGFloat = 2
    let stats = SKNode(), panel = SKNode(), fx = SKNode()
    let shade = SKSpriteNode(color: .black, size: CGSize(width: 10, height: 10))
    let flashSprite = SKSpriteNode(color: .white, size: CGSize(width: 10, height: 10))
    let danger = SKSpriteNode(texture: SKTexture(cgImage: makeImage(256, 256) { ctx in
        ctx.drawRadialGradient(gradient([rgb(0xFF1030, 0), rgb(0xFF1030, 0), rgb(0xFF1030, 0.55)], [0, 0.55, 1]),
                               startCenter: CGPoint(x: 128, y: 128), startRadius: 0, endCenter: CGPoint(x: 128, y: 128), endRadius: 182, options: [.drawsAfterEndLocation])
    }))

    func flash(_ a: CGFloat, color: NSColor) {
        guard a > 0 else { return }
        flashSprite.removeAllActions()
        flashSprite.color = color
        flashSprite.alpha = a
        flashSprite.run(.fadeOut(withDuration: 0.45))
    }
    var intro: SKNode?
    var introDone: (() -> Void)?
    let sign = SKSpriteNode()          // podpis studia w prawym dolnym rogu (jak w Bilardzie)

    override init(size: CGSize) {
        super.init(size: size)
        if let u = Bundle.main.url(forResource: "podpis_logo", withExtension: "png"),
           let img = NSImage(contentsOf: u)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            sign.texture = SKTexture(cgImage: img); sign.anchorPoint = CGPoint(x: 1, y: 0); sign.alpha = 0; sign.zPosition = 20
            addChild(sign)
        }
        scaleMode = .resizeFill
        backgroundColor = .clear
        shade.anchorPoint = .zero
        shade.alpha = 1                       // kurtyna: zasłania planszę aż do startu intro
        shade.color = nsc(0x07080F)
        shade.size = CGSize(width: 20000, height: 20000)
        shade.zPosition = 50
        panel.zPosition = 60
        fx.zPosition = 40
        flashSprite.anchorPoint = .zero; flashSprite.alpha = 0; flashSprite.zPosition = 45; flashSprite.blendMode = .add
        danger.anchorPoint = .zero; danger.alpha = 0; danger.zPosition = 30; danger.blendMode = .add
        [stats, fx, shade, panel, flashSprite, danger].forEach { addChild($0) }
    }
    required init?(coder: NSCoder) { fatalError() }
    override func didChangeSize(_ oldSize: CGSize) {
        let s = CGSize(width: size.width + 4, height: size.height + 4)
        shade.size = s; flashSprite.size = s; danger.size = s
        let w = max(120, size.height * 0.17)
        sign.size = CGSize(width: w, height: w * 292 / 800)
        sign.position = CGPoint(x: size.width - 20, y: 14)
    }

    func text(_ t: String, _ size: CGFloat, _ color: NSColor = .white, font: String = "AvenirNext-DemiBold",
              align: SKLabelHorizontalAlignmentMode = .center) -> SKLabelNode {
        let l = SKLabelNode(fontNamed: font)
        l.text = t; l.fontSize = size; l.fontColor = color
        l.horizontalAlignmentMode = align; l.verticalAlignmentMode = .center
        return l
    }
    /// Napis z miękkim cieniem.
    @discardableResult
    func put(_ t: String, _ size: CGFloat, _ x: CGFloat, _ y: CGFloat, _ color: NSColor = .white, font: String = "AvenirNext-DemiBold",
             align: SKLabelHorizontalAlignmentMode = .center, in parent: SKNode) -> SKLabelNode {
        let sh = text(t, size, NSColor(white: 0, alpha: 0.55), font: font, align: align)
        sh.position = CGPoint(x: x + size * 0.03, y: y - size * 0.06)
        parent.addChild(sh)
        let l = text(t, size, color, font: font, align: align)
        l.position = CGPoint(x: x, y: y)
        parent.addChild(l)
        return l
    }

    private var graveyard: [[SKNode]] = []
    private var labels: [String: (SKLabelNode, SKLabelNode)] = [:]
    private var touched = Set<String>()

    func beginLabels() { touched = [] }
    func endLabels() { for (k, v) in labels where !touched.contains(k) { v.0.isHidden = true; v.1.isHidden = true } }

    /// Napis panelu: tworzony raz, potem zmieniana tylko treść/położenie — bez mrugania.
    var labelColor: [String: NSColor] = [:], labelFont: [String: String] = [:]
    func label(_ key: String, _ t: String, _ size: CGFloat, _ x: CGFloat, _ y: CGFloat, _ color: NSColor,
               font: String = "AvenirNext-DemiBold", align: SKLabelHorizontalAlignmentMode = .center) {
        touched.insert(key)
        let pair: (SKLabelNode, SKLabelNode)
        if let p = labels[key] { pair = p } else {
            pair = (text(t, size, NSColor(white: 0, alpha: 0.55), font: font, align: align), text(t, size, color, font: font, align: align))
            stats.addChild(pair.0); stats.addChild(pair.1)
            labels[key] = pair
        }
        let (sh, l) = pair
        if l.text != t { l.text = t; sh.text = t }
        if l.fontSize != size { l.fontSize = size; sh.fontSize = size }
        if labelFont[key] != font { labelFont[key] = font; l.fontName = font; sh.fontName = font }
        if !key.hasPrefix("sc") && labelColor[key] != color { labelColor[key] = color; l.fontColor = color }   // tylko przy zmianie: każde ustawienie
        if l.horizontalAlignmentMode != align { l.horizontalAlignmentMode = align; sh.horizontalAlignmentMode = align }   // od nowa rysuje napis
        let np = CGPoint(x: x, y: y)
        if l.position != np { l.position = np; sh.position = CGPoint(x: x + size * 0.03, y: y - size * 0.06) }
        if l.isHidden { l.isHidden = false; sh.isHidden = false }
    }

    func tweak(_ key: String, text t: String? = nil, scale: CGFloat? = nil, color: NSColor? = nil) {
        guard let (sh, l) = labels[key] else { return }
        if let t, l.text != t { l.text = t; sh.text = t }
        if let scale { l.setScale(scale); sh.setScale(scale) }
        if let color { l.fontColor = color }
    }
    /// Zdejmuje dzieci węzła, ale trzyma je jeszcze chwilę — SceneKit może je właśnie rysować w swoim wątku.
    func retireChildren(_ n: SKNode) {
        SCNTransaction.lock(); defer { SCNTransaction.unlock() }
        let kids = n.children
        guard !kids.isEmpty else { return }
        kids.forEach { $0.removeAllActions() }
        n.removeAllChildren()
        graveyard.append(kids)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, !self.graveyard.isEmpty else { return }
            SCNTransaction.lock(); self.graveyard.removeFirst(); SCNTransaction.unlock()
        }
    }

    func clearPanel() {
        panel.removeAllActions()
        retireChildren(panel)
        shade.removeAllActions()
        shade.run(.fadeAlpha(to: 0, duration: 0.3))
    }
    func openPanel(dim: CGFloat) {
        panel.removeAllActions()
        retireChildren(panel)
        panel.alpha = 0
        panel.setScale(0.97)
        panel.position = .zero
        let a = SKAction.group([.fadeIn(withDuration: 0.3), .scale(to: 1, duration: 0.3)]); a.timingMode = .easeOut
        panel.run(a)
        shade.removeAllActions()
        shade.run(.fadeAlpha(to: dim, duration: 0.3))
    }
    /// Prostokąt-tło pod panelem (współrzędne środka i wymiary).
    func card(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat) {
        let r = SKShapeNode(rect: CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h), cornerRadius: min(w, h) * 0.06)
        r.fillColor = nsc(0x0B1030, 0.82)
        r.strokeColor = nsc(0x5A6CFF, 0.45)
        r.lineWidth = 1.5
        r.glowWidth = 6
        panel.addChild(r)
    }
    /// Kolorowy tytuł — każda litera w barwie innego klocka.
    func title(_ t: String, _ size: CGFloat, _ cx: CGFloat, _ cy: CGFloat) {
        let letters = t.map { text(String($0), size, .white, font: "AvenirNext-Heavy") }
        let gap = size * 0.06
        let total = letters.reduce(0) { $0 + $1.frame.width } + gap * CGFloat(letters.count - 1)
        var x = cx - total / 2
        for (i, l) in letters.enumerated() {
            let w = l.frame.width
            let c = Int(i) % kindHex.count
            put(String(t[t.index(t.startIndex, offsetBy: i)]), size, x + w / 2, cy, nsc(kindHex[[0, 6, 1, 3, 5, 2, 4][c]]), font: "AvenirNext-Heavy", in: panel)
            x += w + gap
        }
    }
    func popup(_ t: String, _ color: NSColor, at p: CGPoint, size: CGFloat, delay: Double = 0) {
        let n = SKNode()
        n.position = p
        put(t, size, 0, 0, color, font: "AvenirNext-Heavy", in: n)
        n.alpha = 0
        n.setScale(0.6)
        let inA = SKAction.group([.fadeIn(withDuration: 0.12), .scale(to: 1.08, duration: 0.18)]); inA.timingMode = .easeOut
        let out = SKAction.group([.fadeOut(withDuration: 0.5), .moveBy(x: 0, y: size * 1.2, duration: 0.5), .scale(to: 1.0, duration: 0.5)])
        n.run(.sequence([.wait(forDuration: delay), inA, .wait(forDuration: 0.65), out, .removeFromParent()]))
        fx.addChild(n)
    }

    // MARK: Intro z logo studia

    var intro3d: Intro3DView?
    var tmIntroView: NSView?
    func playIntro(_ done: @escaping () -> Void) {
        introDone = done
        intro = SKNode()          // znacznik: intro trwa
        let host = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) })?.contentView
        if let host = host {
            tmIntroView = TMIntro.play(in: host) { [weak self] in self?.finishIntro() }
        } else {
            DispatchQueue.main.async { [weak self] in self?.finishIntro() }
        }
        shade.removeAllActions()
        shade.alpha = 0
        shade.color = .black
        shade.size = CGSize(width: size.width + 4, height: size.height + 4)
    }
    func skipIntro() {
        intro3d?.finish()
    }
    private func finishIntro() {
        guard intro != nil else { return }
        intro = nil; intro3d = nil; tmIntroView = nil
        sign.run(.fadeAlpha(to: 0.6, duration: 1.2))
        introDone?()
        introDone = nil
    }
}

// MARK: - Widok

final class GameView: SCNView {
    weak var game: Game?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with e: NSEvent) { game?.key(e, down: true) }
    override func keyUp(with e: NSEvent) { game?.key(e, down: false) }
    override func flagsChanged(with e: NSEvent) {
        game?.modifier(e)
    }
    override func setFrameSize(_ s: NSSize) { super.setFrameSize(s); game?.layoutHUD() }
}

// MARK: - Gra

final class Game: NSObject {
    enum State { case intro, menu, playing, paused, clearing, over, scores, options, controls, countdown }
    static let W = 10, H = 22

    let view: GameView
    let scene = SCNScene()
    let hud: HUD
    let music = Music()
    var debrisGeo: [SCNGeometry] = []          // odłamki: mało wielokątów, bez cieni
    var geo: [SCNGeometry] = [], ghostGeo: [SCNGeometry] = [], beamGeo: [SCNGeometry] = []
    var camNode = SCNNode()
    var bgNodes: [SCNNode] = [], bgFront = 0, theme = -1
    var floaters: [(node: SCNNode, speed: CGFloat, spin: CGFloat)] = [], floaterGeo: [SCNGeometry] = []
    var danger: CGFloat = 0, clock = 0.0
    var statsDirty = false, lastStats = 0.0
    let neonMat = SCNMaterial(), wallMat = SCNMaterial(), raysMat = SCNMaterial()
    let rays = SCNNode(), rays2 = SCNNode()
    var debris: [(n: SCNNode, v: SCNVector3, w: SCNVector3, life: Double)] = []
    var nextStar = 2.0
    var musicMode = UserDefaults.standard.integer(forKey: "muzyka")
    var flashGeo: SCNGeometry!, grayGeo: SCNGeometry!, fadeGeo: SCNGeometry!
    let glassMat = SCNMaterial()
    var rimCur = [SIMD3<Float>(0.2, 0.8, 1), SIMD3<Float>(1, 0.25, 0.8)], rimBase = [SIMD3<Float>(0.2, 0.8, 1), SIMD3<Float>(1, 0.25, 0.8)]
    var emberT = 0.0, fpsN = 0, fpsT = 0.0, worstDt = 0.0
    var rimA = SCNNode(), rimB = SCNNode(), flashLight = SCNNode()
    var spark: NSImage!

    // gracze: `cp` to gracz, którego dotyczy bieżąca operacja
    let p1 = Player(id: 0), p2 = Player(id: 1)
    lazy var cp: Player = p1
    var twoP = false, gen = 0, winner = 1, menuSel = 0
    var active: [Player] { twoP ? [p1, p2] : [p1] }
    var maxLevel: Int { active.map { $0.level }.max() ?? 1 }
    var best = 0
    var board: SCNNode { cp.board }
    var pieceNodes: [SCNNode] { get { cp.pieceNodes } set { cp.pieceNodes = newValue } }
    var ghostNodes: [SCNNode] { get { cp.ghostNodes } set { cp.ghostNodes = newValue } }
    var beamNodes: [SCNNode] { get { cp.beamNodes } set { cp.beamNodes = newValue } }
    var pieceLight: SCNNode { get { cp.pieceLight } set { cp.pieceLight = newValue } }
    var holdNode: SCNNode { get { cp.holdNode } set { cp.holdNode = newValue } }
    var nextNodes: [SCNNode] { get { cp.nextNodes } set { cp.nextNodes = newValue } }
    var grid: [[Int]] { get { cp.grid } set { cp.grid = newValue } }
    var cells: [[SCNNode?]] { get { cp.cells } set { cp.cells = newValue } }
    var cur: Kind { get { cp.cur } set { cp.cur = newValue } }
    var rot: Int { get { cp.rot } set { cp.rot = newValue } }
    var px: Int { get { cp.px } set { cp.px = newValue } }
    var py: Int { get { cp.py } set { cp.py = newValue } }
    var bag: [Kind] { get { cp.bag } set { cp.bag = newValue } }
    var queue: [Kind] { get { cp.queue } set { cp.queue = newValue } }
    var hold: Kind? { get { cp.hold } set { cp.hold = newValue } }
    var holdUsed: Bool { get { cp.holdUsed } set { cp.holdUsed = newValue } }
    var score: Int { get { cp.score } set { cp.score = newValue } }
    var lines: Int { get { cp.lines } set { cp.lines = newValue } }
    var level: Int { get { cp.level } set { cp.level = newValue } }
    var combo: Int { get { cp.combo } set { cp.combo = newValue } }
    var b2b: Bool { get { cp.b2b } set { cp.b2b = newValue } }
    var fallT: Double { get { cp.fallT } set { cp.fallT = newValue } }
    var lockT: Double { get { cp.lockT } set { cp.lockT = newValue } }
    var lockResets: Int { get { cp.lockResets } set { cp.lockResets = newValue } }
    var lowest: Int { get { cp.lowest } set { cp.lowest = newValue } }
    var leftHeld: Bool { get { cp.leftHeld } set { cp.leftHeld = newValue } }
    var rightHeld: Bool { get { cp.rightHeld } set { cp.rightHeld = newValue } }
    var softDrop: Bool { get { cp.softDrop } set { cp.softDrop = newValue } }
    var lastDir: Int { get { cp.lastDir } set { cp.lastDir = newValue } }
    var dasT: Double { get { cp.dasT } set { cp.dasT = newValue } }
    var arrT: Double { get { cp.arrT } set { cp.arrT = newValue } }
    var state: State = .intro
    var entering = false, name = ""
    var lastTime = CACurrentMediaTime()
    var timer: Timer?

    init(view: GameView) {
        self.view = view
        hud = HUD(size: view.bounds.size)
        super.init()
        view.game = self
        buildScene()
        setupSecondPlayer()
        layout()
        view.scene = scene
        view.overlaySKScene = hud
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 120
        view.isPlaying = true
        view.backgroundColor = .black
        best = Records.load().first?.score ?? 0
        music.mode = musicMode
        music.duck = 0                     // cisza pod logo
        applyAudio()
        applyQuality()
        setupPads()
        hud.stats.alpha = 0
        let t = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in self?.update() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: Scena 3D

    /// albedo polerowanego tworzywa: czysty kolor z bardzo drobnym szumem (bez malowanych odblasków)
    static func plasticImage(_ hex: UInt32) -> NSImage {
        let cg = makeImage(64, 64) { ctx in
            ctx.setFillColor(rgb(hex)); ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
            var r = SeededRNG(s: UInt64(hex))
            for _ in 0..<300 {
                ctx.setFillColor(CGColor(gray: CGFloat.random(in: 0...1, using: &r) > 0.5 ? 1 : 0, alpha: 0.025))
                ctx.fill(CGRect(x: Int.random(in: 0..<64, using: &r), y: Int.random(in: 0..<64, using: &r), width: 1, height: 1))
            }
        }
        return NSImage(cgImage: cg, size: NSSize(width: 64, height: 64))
    }

    func faceImage(_ hex: UInt32) -> NSImage {
        let s = 256
        let cg = makeImage(s, s) { ctx in
            let f = CGFloat(s)
            ctx.setFillColor(rgb(hex)); ctx.fill(CGRect(x: 0, y: 0, width: f, height: f))
            let c = NSColor(cgColor: rgb(hex))!
            let light = c.blended(withFraction: 0.45, of: .white)!.cgColor
            let dark = c.blended(withFraction: 0.35, of: .black)!.cgColor
            // obwódka-skos
            ctx.drawLinearGradient(gradient([light, dark], [0, 1]), start: CGPoint(x: 0, y: f), end: CGPoint(x: f, y: 0), options: [])
            let inner = CGRect(x: f * 0.13, y: f * 0.13, width: f * 0.74, height: f * 0.74)
            ctx.addPath(CGPath(roundedRect: inner, cornerWidth: f * 0.08, cornerHeight: f * 0.08, transform: nil))
            ctx.clip()
            ctx.drawLinearGradient(gradient([c.blended(withFraction: 0.18, of: .white)!.cgColor, rgb(hex), c.blended(withFraction: 0.15, of: .black)!.cgColor], [0, 0.5, 1]),
                                   start: CGPoint(x: 0, y: f), end: CGPoint(x: 0, y: 0), options: [])
            ctx.setFillColor(CGColor(gray: 1, alpha: 0.22))
            ctx.fillEllipse(in: CGRect(x: f * 0.2, y: f * 0.62, width: f * 0.3, height: f * 0.14))
        }
        return NSImage(cgImage: cg, size: NSSize(width: s, height: s))
    }

    func ghostImage(_ hex: UInt32) -> NSImage {
        let s = 128, f = CGFloat(s)
        let cg = makeImage(s, s) { ctx in
            ctx.setFillColor(rgb(hex, 0.24)); ctx.fill(CGRect(x: 0, y: 0, width: f, height: f))
            let r = CGRect(x: 7, y: 7, width: f - 14, height: f - 14)
            ctx.setStrokeColor(rgb(hex, 0.6)); ctx.setLineWidth(18)
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: 12, cornerHeight: 12, transform: nil)); ctx.strokePath()
            ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.9)); ctx.setLineWidth(5)
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: 12, cornerHeight: 12, transform: nil)); ctx.strokePath()
        }
        return NSImage(cgImage: cg, size: NSSize(width: s, height: s))
    }
    func beamImage(_ hex: UInt32) -> NSImage {
        let cg = makeImage(64, 256) { ctx in
            ctx.drawLinearGradient(gradient([rgb(hex, 0.04), rgb(hex, 0.16), rgb(hex, 0.42)], [0, 0.6, 1]),
                                   start: .zero, end: CGPoint(x: 0, y: 256), options: [])
            ctx.setBlendMode(.destinationIn)
            ctx.drawLinearGradient(gradient([CGColor(gray: 1, alpha: 0), CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0)], [0, 0.5, 1]),
                                   start: .zero, end: CGPoint(x: 64, y: 0), options: [])
        }
        return NSImage(cgImage: cg, size: NSSize(width: 64, height: 256))
    }

    // MARK: Tła (mgławice zmieniane co poziom)

    static let themes: [(top: UInt32, bottom: UInt32, c: [UInt32])] = [
        (0x0B1238, 0x020308, [0x2E4BFF, 0x7A3CFF, 0x1FB5FF]),
        (0x1C0A36, 0x05020A, [0xB03CFF, 0xFF3FA8, 0x4A2CFF]),
        (0x06232A, 0x020607, [0x1FFFC0, 0x2FA8FF, 0x7CFF5A]),
        (0x2C0812, 0x070205, [0xFF3B4C, 0xFF8A1E, 0x9A1CFF]),
        (0x07240F, 0x020604, [0x37DE58, 0x20DDF0, 0xD4FF3A]),
        (0x2C1C06, 0x080502, [0xFFD21F, 0xFF8A1E, 0xFF4FA0])]

    /// Przesunięcie barwy koloru po kole kolorów.
    static func hueShift(_ hex: UInt32, _ d: CGFloat) -> UInt32 {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsc(hex).usingColorSpace(.sRGB)!.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let c = NSColor(hue: (h + d).truncatingRemainder(dividingBy: 1), saturation: s, brightness: b, alpha: 1).usingColorSpace(.sRGB)!
        return UInt32(c.redComponent * 255) << 16 | UInt32(c.greenComponent * 255) << 8 | UInt32(c.blueComponent * 255)
    }
    /// Kolory motywu dla poziomu: bazowy granat/fiolet, z każdym poziomem barwa delikatnie się przesuwa.
    static func themeColors(_ t: Int) -> (top: UInt32, bottom: UInt32, c: [UInt32]) {
        let b = themes[0], d = CGFloat(t) * 0.045
        return (hueShift(b.top, d), hueShift(b.bottom, d), b.c.map { hueShift($0, d) })
    }

    static func nebula(_ t: Int) -> CGImage {
        let th = themeColors(t)
        let w = 2048, h = 1152, W = CGFloat(w), H = CGFloat(h)
        var g = SeededRNG(s: 2024)          // zawsze ten sam układ mgławicy i gwiazd
        return makeImage(w, h) { ctx in
            ctx.drawLinearGradient(gradient([rgb(th.top), rgb(th.bottom)], [0, 1]), start: CGPoint(x: 0, y: H), end: .zero, options: [])
            ctx.setBlendMode(.screen)
            for i in 0..<46 {
                let c = th.c[i % th.c.count]
                let x = CGFloat.random(in: 0...W, using: &g), y = CGFloat.random(in: H * 0.1...H, using: &g)
                let r = CGFloat.random(in: 120...560, using: &g)
                ctx.drawRadialGradient(gradient([rgb(c, .random(in: 0.05...0.16, using: &g)), rgb(c, 0)], [0, 1]),
                                       startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x + r * 0.2, y: y), endRadius: r, options: [])
            }
            ctx.setBlendMode(.normal)
            for _ in 0..<900 {
                let x = CGFloat.random(in: 0...W, using: &g), y = CGFloat.random(in: 0...H, using: &g)
                let s = CGFloat.random(in: 0.6...2.4, using: &g)
                ctx.setFillColor(CGColor(gray: 1, alpha: .random(in: 0.15...0.85, using: &g)))
                ctx.fillEllipse(in: CGRect(x: x, y: y, width: s, height: s))
            }
            for _ in 0..<14 {
                let x = CGFloat.random(in: 0...W, using: &g), y = CGFloat.random(in: H * 0.3...H, using: &g)
                ctx.drawRadialGradient(gradient([CGColor(gray: 1, alpha: 0.9), CGColor(gray: 1, alpha: 0)], [0, 1]),
                                       startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y), endRadius: 9, options: [])
                ctx.setFillColor(CGColor(gray: 1, alpha: 0.35))
                ctx.fill(CGRect(x: x - 22, y: y - 0.6, width: 44, height: 1.2))
                ctx.fill(CGRect(x: x - 0.6, y: y - 22, width: 1.2, height: 44))
            }
        }
    }

    /// Płynne przejście do tła danego motywu.
    func setTheme(_ t: Int) {
        if ProcessInfo.processInfo.environment["KLOCKI_NOTHEME"] != nil && t > 0 { return }
        let t = max(0, t)
        guard t != theme else { return }
        theme = t
        DispatchQueue.global(qos: .userInitiated).async {
            let img = Game.nebula(t)
            // tekstura wgrywana do GPU w tle (prepare), żeby awans poziomu nie przycinał gry
            var mat: SCNMaterial?
            DispatchQueue.main.sync { mat = self.bgNodes[1 - self.bgFront].geometry?.firstMaterial?.copy() as? SCNMaterial }
            mat?.diffuse.contents = NSImage(cgImage: img, size: NSSize(width: img.width, height: img.height))
            if let m = mat { self.view.prepare([m], completionHandler: nil) }
            DispatchQueue.main.async { [self] in
                guard theme == t else { return }          // nowszy motyw już w drodze
                SCNTransaction.lock(); defer { SCNTransaction.unlock() }
                let back = bgNodes[1 - bgFront], front = bgNodes[bgFront]
                if let m = mat { back.geometry?.firstMaterial = m }
                back.opacity = 0
                back.renderingOrder = -9; front.renderingOrder = -10
                back.runAction(.fadeIn(duration: 3.0))
                bgFront = 1 - bgFront
                SCNTransaction.begin(); SCNTransaction.animationDuration = 2
                neonMat.diffuse.contents = nsc(Game.themeColors(t).c[0]); neonMat.emission.contents = nsc(Game.themeColors(t).c[0])
                raysMat.diffuse.contents = nsc(Game.themeColors(t).c[1])
                for (i, g) in floaterGeo.enumerated() {
                    g.firstMaterial?.diffuse.contents = nsc(Game.themeColors(t).c[i % 3])
                }
                SCNTransaction.commit()
            }
        }
    }

    func buildScene() {
        let img = makeImage(16, 512) { ctx in
            ctx.drawLinearGradient(gradient([rgb(0x141A3E), rgb(0x0A0C1E), rgb(0x040509)], [0, 0.55, 1]),
                                   start: CGPoint(x: 0, y: 512), end: CGPoint(x: 0, y: 0), options: [])
        }
        scene.background.contents = NSImage(cgImage: img, size: NSSize(width: 16, height: 512))
        // studio: ciemny horyzont, duże softboxy (górny pas, boczne paski, kolorowe akcenty) — realistyczne odbicia na klockach i metalu
        let env = makeImage(2048, 1024) { ctx in
            ctx.drawLinearGradient(gradient([rgb(0x2A3570), rgb(0x0C1030), rgb(0x05060E), rgb(0x020205)], [0, 0.45, 0.55, 1]),
                                   start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 0, y: 0), options: [])
            func softbox(_ r: CGRect, _ hex: UInt32, _ a: CGFloat) {
                for i in 0..<10 {                                   // miękka krawędź
                    let k = CGFloat(i) / 10
                    ctx.setFillColor(rgb(hex, a * 0.14 * (1 - k * 0.5)))
                    ctx.addPath(CGPath(roundedRect: r.insetBy(dx: -CGFloat(10 - i) * 6, dy: -CGFloat(10 - i) * 6), cornerWidth: 20, cornerHeight: 20, transform: nil))
                    ctx.fillPath()
                }
                ctx.setFillColor(rgb(hex, a)); ctx.fill(r)
            }
            for cx in [512.0, 1536.0] as [CGFloat] {
                softbox(CGRect(x: cx - 260, y: 880, width: 520, height: 90), 0xFFFFFF, 1)          // górny pas
                softbox(CGRect(x: cx - 420, y: 520, width: 70, height: 300), 0x9FD8FF, 0.95)       // lewy pasek (chłodny)
                softbox(CGRect(x: cx + 350, y: 520, width: 70, height: 300), 0xFFC4E8, 0.9)        // prawy pasek (ciepły)
            }
            ctx.setFillColor(rgb(0x6A7CFF, 0.25)); ctx.fill(CGRect(x: 0, y: 470, width: 2048, height: 14))   // pas horyzontu
        }
        scene.lightingEnvironment.contents = NSImage(cgImage: env, size: NSSize(width: 2048, height: 1024))
        scene.lightingEnvironment.intensity = 1.25
        scene.lightingEnvironment.intensity = 1.3

        // materiały klocków
        let box = { () -> SCNBox in SCNBox(width: 0.95, height: 0.95, length: 0.95, chamferRadius: 0.13) }
        for hex in kindHex {
            let g = box()
            let m = SCNMaterial()
            m.lightingModel = .physicallyBased
            let face = faceImage(hex)
            m.diffuse.contents = Game.plasticImage(hex)
            m.metalness.contents = 0.0
            m.roughness.contents = 0.14
            m.emission.contents = face
            m.emission.intensity = 0.08
            m.clearCoat.contents = 1.0
            m.clearCoatRoughness.contents = 0.06
            // poświata krawędzi (fresnel) w kolorze klocka — nowocześniejszy, „szklany” wygląd
            m.shaderModifiers = [.surface: """
            #pragma arguments
            float3 rimCol;
            #pragma body
            float rimF = pow(1.0 - saturate(dot(_surface.normal, _surface.view)), 3.0);
            _surface.emission.rgb += rimCol * rimF * 0.45;
            """]
            let rc = nsc(hex).blended(withFraction: 0.35, of: .white)!.usingColorSpace(.sRGB)!
            m.setValue(SCNVector3(rc.redComponent, rc.greenComponent, rc.blueComponent), forKey: "rimCol")
            g.chamferSegmentCount = 6
            g.materials = [m]
            geo.append(g)
            // cień lądowania: świecący kontur + lekkie wypełnienie
            let gg = SCNBox(width: 0.97, height: 0.97, length: 0.97, chamferRadius: 0.06)
            let gm = SCNMaterial()
            gm.lightingModel = .constant
            gm.diffuse.contents = ghostImage(hex)
            gm.writesToDepthBuffer = false
            gm.isDoubleSided = true
            gm.blendMode = .add
            gg.materials = [gm]
            ghostGeo.append(gg)
            // promień od klocka do miejsca lądowania
            let bp = SCNPlane(width: 0.9, height: 1)
            let bm = SCNMaterial()
            bm.lightingModel = .constant
            bm.diffuse.contents = beamImage(hex)
            bm.writesToDepthBuffer = false
            bm.blendMode = .add
            bp.materials = [bm]
            beamGeo.append(bp)
        }
        for g in geo {
            let d = SCNBox(width: 0.95, height: 0.95, length: 0.95, chamferRadius: 0.1); d.chamferSegmentCount = 1
            d.materials = g.materials; debrisGeo.append(d)
        }
        flashGeo = box()
        let fm = SCNMaterial(); fm.lightingModel = .constant; fm.diffuse.contents = NSColor.white; fm.emission.contents = NSColor.white
        flashGeo.materials = [fm]
        grayGeo = box()
        let gm = SCNMaterial(); gm.lightingModel = .physicallyBased; gm.diffuse.contents = faceImage(0x50566E); gm.roughness.contents = 0.5; gm.metalness.contents = 0.1
        grayGeo.materials = [gm]
        geo.append(grayGeo)
        // finał: perłowo-srebrny, półprzezroczysty (zamiast czarnego)
        fadeGeo = box()
        let pm = SCNMaterial(); pm.lightingModel = .physicallyBased; pm.diffuse.contents = faceImage(0xC9D2EE)
        pm.emission.contents = nsc(0x5A6488); pm.roughness.contents = 0.3; pm.metalness.contents = 0.35
        fadeGeo.materials = [pm]

        scene.rootNode.addChildNode(board)

        // ściana studni z siatką
        let wall = SCNPlane(width: 10, height: 20)
        let grid = makeImage(500, 1000) { ctx in
            ctx.setFillColor(rgb(0x070A1A, 0.92)); ctx.fill(CGRect(x: 0, y: 0, width: 500, height: 1000))
            ctx.setStrokeColor(rgb(0x2B3672, 0.8)); ctx.setLineWidth(2)
            for i in 0...10 { ctx.move(to: CGPoint(x: CGFloat(i) * 50, y: 0)); ctx.addLine(to: CGPoint(x: CGFloat(i) * 50, y: 1000)) }
            for i in 0...20 { ctx.move(to: CGPoint(x: 0, y: CGFloat(i) * 50)); ctx.addLine(to: CGPoint(x: 500, y: CGFloat(i) * 50)) }
            ctx.strokePath()
        }
        let wm = wallMat; wm.lightingModel = .physicallyBased
        wm.diffuse.contents = Game.wallImage(glow: false)
        wm.emission.contents = Game.wallImage(glow: true)
        wm.emission.intensity = 0.5
        wm.roughness.contents = 0.18; wm.metalness.contents = 0.3
        _ = grid
        wall.materials = [wm]
        let wn = SCNNode(geometry: wall); wn.position = SCNVector3(0, 0, -0.55)
        board.addChildNode(wn)
        buildWell()

        // rama z metalu
        let metal = SCNMaterial(); metal.lightingModel = .physicallyBased
        metal.diffuse.contents = nsc(0x9AA2C0); metal.metalness.contents = 1
        metal.roughness.contents = NSImage(cgImage: makeImage(256, 256) { ctx in      // szczotkowanie: drobne pasy chropowatości
            ctx.setFillColor(CGColor(gray: 0.24, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            var r = SeededRNG(s: 7)
            for y in 0..<256 { ctx.setFillColor(CGColor(gray: CGFloat.random(in: 0.2...0.27, using: &r), alpha: 1)); ctx.fill(CGRect(x: 0, y: CGFloat(y), width: 256, height: 1)) }
        }, size: NSSize(width: 256, height: 256))
        for (x, y, w, h) in [(-5.25, -0.2, 0.5, 21.2), (5.25, -0.2, 0.5, 21.2), (0, -10.25, 11.0, 0.5)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
            let b = SCNBox(width: w, height: h, length: 1.5, chamferRadius: 0.12); b.materials = [metal]
            let n = SCNNode(geometry: b); n.position = SCNVector3(x, y, -0.05); n.castsShadow = true
            board.addChildNode(n)
        }
        // świecące listwy
        let neon = neonMat; neon.lightingModel = .constant; neon.diffuse.contents = nsc(0x6A7CFF); neon.emission.contents = nsc(0x6A7CFF)
        for x in [-4.98, 4.98] as [CGFloat] {
            let c = SCNCylinder(radius: 0.035, height: 20.6); c.materials = [neon]
            let n = SCNNode(geometry: c); n.position = SCNVector3(x, 0.2, 0.72)
            board.addChildNode(n)
        }

        // panele boczne (szkło)
        let glass = SCNMaterial(); glass.lightingModel = .constant; glass.diffuse.contents = nsc(0x0A1030, 0.55)
        glass.writesToDepthBuffer = false
        for (x, y, w, h) in [(-10.0, 7.4, 5.6, 4.8), (-10.0, -0.6, 5.6, 9.6), (10.0, 4.0, 5.6, 12.0)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
            let p = SCNPlane(width: w, height: h); p.cornerRadius = 0.4; p.materials = [glass]
            let n = SCNNode(geometry: p); n.position = SCNVector3(x, y, -1.6)
            scene.rootNode.addChildNode(n); p1.panels.append(n)
        }

        // podłoga z odbiciem
        let floor = SCNFloor(); floor.reflectivity = 0.22; floor.reflectionFalloffEnd = 8; floor.width = 90; floor.length = 60
        let flm = SCNMaterial(); flm.lightingModel = .physicallyBased; flm.diffuse.contents = NSImage(cgImage: makeImage(256, 256) { ctx in   // podłoga rozmywa się w tle
            ctx.drawRadialGradient(gradient([rgb(0x05060E, 1), rgb(0x05060E, 0.85), rgb(0x05060E, 0)], [0, 0.45, 1]), startCenter: CGPoint(x: 128, y: 128), startRadius: 0,
                                   endCenter: CGPoint(x: 128, y: 128), endRadius: 128, options: [])
        }, size: NSSize(width: 256, height: 256)); flm.roughness.contents = 0.35; flm.blendMode = .alpha
        floor.materials = [flm]
        let fn = SCNNode(geometry: floor); fn.position = SCNVector3(0, -10.52, 0)
        scene.rootNode.addChildNode(fn)

        // światła
        let key = SCNLight(); key.type = .directional; key.intensity = 1100; key.castsShadow = true
        key.shadowMode = .deferred; key.shadowRadius = 3; key.shadowSampleCount = 8
        key.shadowColor = NSColor(white: 0, alpha: 0.55); key.orthographicScale = 16; key.shadowMapSize = CGSize(width: 4096, height: 4096)
        key.zNear = 1; key.zFar = 120
        let kn = SCNNode(); kn.light = key; kn.position = SCNVector3(-12, 18, 26); kn.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(kn)
        let amb = SCNLight(); amb.type = .ambient; amb.intensity = 220; amb.color = nsc(0x7080B0)
        let an = SCNNode(); an.light = amb; scene.rootNode.addChildNode(an)
        for (n, p, hex) in [(rimA, SCNVector3(-14, 9, -4), 0x2FD0FF as UInt32), (rimB, SCNVector3(15, 3, -7), 0xFF3FD0)] {
            let l = SCNLight(); l.type = .omni; l.intensity = 900; l.color = nsc(hex); l.attenuationStartDistance = 5; l.attenuationEndDistance = 40
            n.light = l; n.position = p
            scene.rootNode.addChildNode(n)
        }
        let fl = SCNLight(); fl.type = .omni; fl.intensity = 0; fl.color = NSColor.white; fl.attenuationEndDistance = 30
        flashLight.light = fl; flashLight.position = SCNVector3(0, 0, 7)
        scene.rootNode.addChildNode(flashLight)

        // kamera
        let cam = SCNCamera(); cam.fieldOfView = 38; cam.zNear = 1; cam.zFar = 300
        cam.wantsHDR = true; cam.bloomIntensity = 0.5; cam.bloomThreshold = 1.0; cam.bloomBlurRadius = 16
        cam.whitePoint = 1.0; cam.exposureOffset = 0
        cam.vignettingIntensity = 0.5; cam.vignettingPower = 0.9
        cam.saturation = 1.1; cam.contrast = 0.06; cam.colorFringeIntensity = 1; cam.colorFringeStrength = 0
        cam.wantsExposureAdaptation = false
        let cn = camNode; cn.camera = cam; cn.position = SCNVector3(0, 3.2, 36); cn.look(at: SCNVector3(0, -0.4, 0))
        scene.rootNode.addChildNode(cn)
        view.pointOfView = cn

        // pył w tle
        spark = NSImage(cgImage: makeImage(64, 64) { ctx in
            ctx.drawRadialGradient(gradient([CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0)], [0, 1]), startCenter: CGPoint(x: 32, y: 32), startRadius: 0,
                                   endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
        }, size: NSSize(width: 64, height: 64))
        let dust = SCNParticleSystem()
        dust.particleImage = spark; dust.birthRate = 14; dust.particleLifeSpan = 14; dust.warmupDuration = 14
        dust.emitterShape = SCNBox(width: 80, height: 50, length: 20, chamferRadius: 0)
        dust.particleVelocity = 0.35; dust.spreadingAngle = 180; dust.particleSize = 0.12; dust.particleSizeVariation = 0.08
        dust.particleColor = nsc(0x7F9BFF, 0.5); dust.blendMode = .additive
        let dn = SCNNode(); dn.position = SCNVector3(0, 0, -16); dn.addParticleSystem(dust)
        scene.rootNode.addChildNode(dn)

        // tło: dwie warstwy mgławicy (przenikanie przy zmianie poziomu)
        for i in 0..<2 {
            let p = SCNPlane(width: 230, height: 130)
            let m = SCNMaterial(); m.lightingModel = .constant; m.writesToDepthBuffer = false; m.readsFromDepthBuffer = false
            p.materials = [m]
            let n = SCNNode(geometry: p); n.position = SCNVector3(0, -4, -75); n.renderingOrder = -10 + i
            n.opacity = i == 0 ? 1 : 0
            let sway = SCNAction.sequence([.rotateTo(x: 0, y: 0, z: 0.05, duration: 40, usesShortestUnitArc: true),
                                           .rotateTo(x: 0, y: 0, z: -0.05, duration: 40, usesShortestUnitArc: true)])
            sway.timingMode = .easeInEaseOut
            n.runAction(.repeatForever(sway))
            scene.rootNode.addChildNode(n); bgNodes.append(n)
        }
        let first = Game.nebula(0)
        bgNodes[0].geometry?.firstMaterial?.diffuse.contents = NSImage(cgImage: first, size: NSSize(width: first.width, height: first.height))
        theme = 0

        // dryfujące w tle półprzezroczyste klocki
        for i in 0..<3 {
            let b = SCNBox(width: 0.92, height: 0.92, length: 0.92, chamferRadius: 0.12)
            let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = nsc(Game.themes[0].c[i])
            m.blendMode = .add; m.writesToDepthBuffer = false
            b.materials = [m]; floaterGeo.append(b)
        }
        for i in 0..<30 {
            let k = Kind.allCases[i % 7], n = SCNNode()
            for (x, y) in shapes[k.rawValue][0] {
                let c = SCNNode(geometry: floaterGeo[i % 3]); c.position = SCNVector3(CGFloat(x) - 1.5, CGFloat(y) - 1.5, 0); n.addChildNode(c)
            }
            let z = CGFloat.random(in: -55 ... -16)
            n.position = SCNVector3(CGFloat.random(in: -60...60), CGFloat.random(in: -30...30), z)
            let s = CGFloat.random(in: 0.7...1.6); n.scale = SCNVector3(s, s, s)
            n.eulerAngles = SCNVector3(CGFloat.random(in: 0...6), CGFloat.random(in: 0...6), CGFloat.random(in: 0...6))
            n.opacity = 0.08 + 0.14 * (z + 55) / 39
            scene.rootNode.addChildNode(n)
            floaters.append((n, CGFloat.random(in: 0.4...1.3), CGFloat.random(in: -0.4...0.4)))
        }

        // aktywny klocek, cień, promienie i światło klocka
        for _ in 0..<4 {
            let p = SCNNode(geometry: geo[0]); p.castsShadow = true; p.isHidden = true; board.addChildNode(p); pieceNodes.append(p)
            let g = SCNNode(geometry: ghostGeo[0]); g.isHidden = true; g.castsShadow = false; board.addChildNode(g); ghostNodes.append(g)
            let b = SCNNode(geometry: beamGeo[0]); b.isHidden = true; b.castsShadow = false; board.addChildNode(b); beamNodes.append(b)
            let pulse = SCNAction.sequence([.fadeOpacity(to: 0.55, duration: 0.6), .fadeOpacity(to: 1, duration: 0.6)])
            pulse.timingMode = .easeInEaseOut
            g.runAction(.repeatForever(pulse))
        }
        decorate()
        let pl = SCNLight(); pl.type = .omni; pl.intensity = 0; pl.attenuationStartDistance = 0.5; pl.attenuationEndDistance = 5
        pieceLight.light = pl
        board.addChildNode(pieceLight)
        holdNode.position = SCNVector3(-10, 7.1, 0)
        scene.rootNode.addChildNode(holdNode)
        for (i, (y, s)) in [(7.6, 1.0), (3.6, 0.72), (0.7, 0.72)].enumerated() {
            let n = SCNNode(); n.position = SCNVector3(10, CGFloat(y), 0); n.scale = SCNVector3(s, s, s)
            scene.rootNode.addChildNode(n); nextNodes.append(n)
            spin(n, phase: Double(i) * 0.7)
        }
        spin(holdNode, phase: 0.3)
    }

    static func wallImage(glow: Bool) -> NSImage {
        let w = 500, h = 1000, W = CGFloat(w), H = CGFloat(h)
        let cg = makeImage(w, h) { ctx in
            if glow {
                ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
                ctx.drawLinearGradient(gradient([rgb(0x3B5BFF, 0.55), rgb(0x3B5BFF, 0)], [0, 1]), start: .zero, end: CGPoint(x: 0, y: H * 0.35), options: [])
            } else {
                ctx.drawLinearGradient(gradient([rgb(0x101634), rgb(0x070A1C), rgb(0x0C0F28)], [0, 0.6, 1]), start: CGPoint(x: 0, y: H), end: .zero, options: [])
                ctx.drawRadialGradient(gradient([rgb(0x2A3A90, 0.35), rgb(0x2A3A90, 0)], [0, 1]), startCenter: CGPoint(x: W / 2, y: H * 0.45), startRadius: 0,
                                       endCenter: CGPoint(x: W / 2, y: H * 0.45), endRadius: W * 0.9, options: [])
            }
            ctx.setStrokeColor(rgb(glow ? 0x5A78FF : 0x2B3672, glow ? 0.45 : 0.9)); ctx.setLineWidth(glow ? 2.5 : 2)
            for i in 0...10 { ctx.move(to: CGPoint(x: CGFloat(i) * 50, y: 0)); ctx.addLine(to: CGPoint(x: CGFloat(i) * 50, y: H)) }
            for i in 0...20 { ctx.move(to: CGPoint(x: 0, y: CGFloat(i) * 50)); ctx.addLine(to: CGPoint(x: W, y: CGFloat(i) * 50)) }
            ctx.strokePath()
            // kropki na skrzyżowaniach
            ctx.setFillColor(rgb(0x8FA4FF, glow ? 0.9 : 0.5))
            for i in 0...10 { for j in 0...20 { ctx.fillEllipse(in: CGRect(x: CGFloat(i) * 50 - 3, y: CGFloat(j) * 50 - 3, width: 6, height: 6)) } }
        }
        return NSImage(cgImage: cg, size: NSSize(width: w, height: h))
    }

    /// Ozdoby planszy i tła: podstawa, kule na filarach, skaner, promienie.
    /// Bryła studni: boczne ściany i dno z poświatą, szkło warstwowe (trzy tafle),
    /// neonowe krawędzie z przodu i z tyłu (prawdziwa głębia przy kołysaniu i obrocie planszy).
    func buildWell() {
        let depth: CGFloat = 1.3, zc: CGFloat = 0.08
        let side = SCNMaterial(); side.lightingModel = .physicallyBased
        side.diffuse.contents = NSImage(cgImage: makeImage(64, 256) { ctx in
            ctx.drawLinearGradient(gradient([rgb(0x1A2260), rgb(0x0A0E26)], [0, 1]), start: .zero, end: CGPoint(x: 64, y: 0), options: [])
            ctx.setFillColor(rgb(0x3B4BB0, 0.6))
            for i in 0..<20 { ctx.fill(CGRect(x: 0, y: CGFloat(i) * 12.8, width: 64, height: 1.2)) }
        }, size: NSSize(width: 64, height: 256))
        side.emission.contents = nsc(0x1C2A80); side.emission.intensity = 0.15
        side.metalness.contents = 0.6; side.roughness.contents = 0.2
        for sx in [-1.0, 1.0] as [CGFloat] {
            let p = SCNPlane(width: depth, height: 20); p.materials = [side]
            let n = SCNNode(geometry: p); n.position = SCNVector3(sx * 5.0, 0, zc); n.eulerAngles.y = -sx * .pi / 2
            board.addChildNode(n)
        }
        let bottom = SCNPlane(width: 10, height: depth); bottom.materials = [side]
        let bn = SCNNode(geometry: bottom); bn.position = SCNVector3(0, -10.0, zc); bn.eulerAngles.x = -.pi / 2
        board.addChildNode(bn)
        // neonowe krawędzie: tył (głębia) i górna belka z przodu
        for (pos, len, rotZ) in [(SCNVector3(-4.98, 0.2, -0.5), 20.6, false), (SCNVector3(4.98, 0.2, -0.5), 20.6, false),
                                 (SCNVector3(0, 10.05, 0.72), 10.0, true), (SCNVector3(0, -9.98, 0.72), 10.0, true)] as [(SCNVector3, CGFloat, Bool)] {
            let c = SCNCylinder(radius: 0.03, height: len); c.materials = [neonMat]
            let n = SCNNode(geometry: c); n.position = pos; if rotZ { n.eulerAngles.z = .pi / 2 }
            n.opacity = pos.z < 0 ? 0.55 : 1
            board.addChildNode(n)
        }
        // szkło warstwowe: trzy tafle w różnej głębokości, przezroczyste w środku,
        // z barwną poświatą krawędzi i tęczowym połyskiem (fresnel), widocznym przy przechyle planszy
        for (z, hex, w, a) in [(0.78, 0x8FE6FF, 1.0, 0.55), (0.62, 0xB48CFF, 0.8, 0.35), (-0.5, 0x5BC8FF, 0.6, 0.18)] as [(CGFloat, UInt32, CGFloat, CGFloat)] {
            let m = z > 0.7 ? glassMat : SCNMaterial()
            m.lightingModel = .constant; m.blendMode = .add; m.writesToDepthBuffer = false; m.isDoubleSided = true
            m.diffuse.contents = NSImage(cgImage: makeImage(200, 400) { ctx in
                for i in 0..<3 {                                               // cienka krawędź tafli
                    let k = CGFloat(i) / 3, inset = CGFloat(i) * 1.6 * w
                    ctx.setStrokeColor(rgb(hex, a * pow(1 - k, 2.2)))
                    ctx.setLineWidth(1.6 * w)
                    ctx.addPath(CGPath(roundedRect: CGRect(x: inset + 1, y: inset + 1, width: 198 - 2 * inset, height: 398 - 2 * inset),
                                       cornerWidth: 6, cornerHeight: 6, transform: nil))
                    ctx.strokePath()
                }
            }, size: NSSize(width: 200, height: 400))
            m.shaderModifiers = [.fragment: """
            float rimF = pow(1.0 - abs(dot(_surface.normal, _surface.view)), 2.0);
            float3 iri = 0.5 + 0.5 * cos(6.2832 * (rimF * 1.4 + _surface.diffuseTexcoord.y * 0.35 + float3(0.0, 0.33, 0.67)));
            _output.color.rgb += iri * rimF * 0.18;
            """]
            let gp = SCNPlane(width: 10, height: 20); gp.materials = [m]
            let gn = SCNNode(geometry: gp); gn.position = SCNVector3(0, 0, z); gn.renderingOrder = 50; gn.castsShadow = false
            board.addChildNode(gn)
        }
    }

    /// delikatne kołysanie planszy (dir: w którą stronę zaczyna)
    func startSway(_ b: SCNNode, dir: CGFloat, lead: Double = 3.5) {
        let sway = SCNAction.sequence([.rotateTo(x: 0, y: -0.11 * dir, z: 0, duration: 7, usesShortestUnitArc: true),
                                       .rotateTo(x: 0, y: 0.11 * dir, z: 0, duration: 7, usesShortestUnitArc: true)])
        sway.timingMode = .easeInEaseOut
        b.runAction(.sequence([.rotateTo(x: 0, y: 0.11 * dir, z: 0, duration: lead, usesShortestUnitArc: true), .repeatForever(sway)]), forKey: "sway")
    }

    func decorate() {
        // plansza delikatnie kołysze się w lewo i w prawo
        startSway(board, dir: -1)
        let chrome = SCNMaterial(); chrome.lightingModel = .physicallyBased
        chrome.diffuse.contents = nsc(0x2A2F48); chrome.metalness.contents = 1; chrome.roughness.contents = 0.15
        let base = SCNBox(width: 13, height: 0.9, length: 3, chamferRadius: 0.25); base.materials = [chrome]
        let bn = SCNNode(geometry: base); bn.position = SCNVector3(0, -10.95, 0); bn.castsShadow = true
        board.addChildNode(bn)
        for (y, z, len) in [(-10.5, 1.52, 12.6), (-11.4, 1.52, 12.6)] as [(CGFloat, CGFloat, CGFloat)] {
            let c = SCNCylinder(radius: 0.045, height: len); c.materials = [neonMat]
            let n = SCNNode(geometry: c); n.eulerAngles.z = .pi / 2; n.position = SCNVector3(0, y, z)
            board.addChildNode(n)
        }
        for x in [-5.52, 5.52] as [CGFloat] {
            let c = SCNCylinder(radius: 0.035, height: 20.8); c.materials = [neonMat]
            let n = SCNNode(geometry: c); n.position = SCNVector3(x, -0.2, 0.72)
            board.addChildNode(n)
            let orb = SCNSphere(radius: 0.38)
            let om = SCNMaterial(); om.lightingModel = .physicallyBased; om.diffuse.contents = NSColor.white
            om.emission.contents = neonMat.diffuse.contents; om.metalness.contents = 0.2; om.roughness.contents = 0.1
            orb.materials = [neonMat]
            let on = SCNNode(geometry: orb); on.name = "orb"; on.position = SCNVector3(x - (x > 0 ? 0.27 : -0.27), 10.6, 0.1)
            let breathe = SCNAction.sequence([.scale(to: 1.15, duration: 1.2), .scale(to: 0.9, duration: 1.2)]); breathe.timingMode = .easeInEaseOut
            on.runAction(.repeatForever(breathe))
            board.addChildNode(on)
        }
        // skaner przesuwający się po ścianie
        let sp = SCNPlane(width: 10, height: 0.9)
        let sm = SCNMaterial(); sm.lightingModel = .constant; sm.blendMode = .add; sm.writesToDepthBuffer = false
        sm.diffuse.contents = NSImage(cgImage: makeImage(8, 128) { ctx in
            ctx.drawLinearGradient(gradient([rgb(0x2FD0FF, 0), rgb(0x2FD0FF, 0.10), rgb(0x6FE8FF, 0.32), rgb(0x2FD0FF, 0)], [0, 0.6, 0.75, 1]),
                                   start: .zero, end: CGPoint(x: 0, y: 128), options: [])
        }, size: NSSize(width: 8, height: 128))
        sp.materials = [sm]
        let scan = SCNNode(geometry: sp); scan.name = "scan"; scan.position = SCNVector3(0, 11.5, -0.5)
        scan.runAction(.repeatForever(.sequence([.move(to: SCNVector3(0, 11.5, -0.5), duration: 0), .move(to: SCNVector3(0, -11.5, -0.5), duration: 3.2), .wait(duration: 2.5)])))
        board.addChildNode(scan)
        // promienie światła za planszą
        let rimg = makeImage(1024, 1024) { ctx in
            let c = CGPoint(x: 512, y: 512)
            for i in 0..<28 {
                let a0 = CGFloat(i) / 28 * 2 * .pi, a1 = a0 + .pi / 28 * CGFloat.random(in: 0.3...0.9)
                ctx.move(to: c)
                ctx.addArc(center: c, radius: 520, startAngle: a0, endAngle: a1, clockwise: false)
                ctx.closePath()
            }
            ctx.clip()
            ctx.drawRadialGradient(gradient([CGColor(gray: 1, alpha: 0.5), CGColor(gray: 1, alpha: 0.12), CGColor(gray: 1, alpha: 0)], [0, 0.35, 1]),
                                   startCenter: c, startRadius: 0, endCenter: c, endRadius: 512, options: [])
        }
        raysMat.lightingModel = .constant; raysMat.blendMode = .add; raysMat.writesToDepthBuffer = false
        raysMat.diffuse.contents = nsc(Game.themes[0].c[1])
        raysMat.multiply.contents = NSImage(cgImage: rimg, size: NSSize(width: 1024, height: 1024))
        for (n, size, z, dur) in [(rays, 80.0, -30.0, 140.0), (rays2, 60.0, -28.0, -90.0)] as [(SCNNode, CGFloat, CGFloat, Double)] {
            let p = SCNPlane(width: size, height: size); p.materials = [raysMat]
            n.geometry = p; n.position = SCNVector3(0, 2, z); n.renderingOrder = -5
            n.runAction(.repeatForever(.rotateBy(x: 0, y: 0, z: dur > 0 ? 2 * .pi : -2 * .pi, duration: abs(dur))))
            scene.rootNode.addChildNode(n)
        }
    }

    func shootingStar() {
        let p = SCNPlane(width: CGFloat.random(in: 5...10), height: 0.07)
        let m = SCNMaterial(); m.lightingModel = .constant; m.blendMode = .add; m.writesToDepthBuffer = false
        m.diffuse.contents = NSImage(cgImage: makeImage(256, 4) { ctx in
            ctx.drawLinearGradient(gradient([CGColor(gray: 1, alpha: 0), CGColor(gray: 1, alpha: 1)], [0, 1]), start: .zero, end: CGPoint(x: 256, y: 0), options: [])
        }, size: NSSize(width: 256, height: 4))
        p.materials = [m]
        let n = SCNNode(geometry: p)
        let dir: CGFloat = Bool.random() ? 1 : -1
        let ang = CGFloat.random(in: 0.2...0.5)
        n.eulerAngles.z = dir > 0 ? -ang : .pi + ang
        n.position = SCNVector3(-dir * CGFloat.random(in: 10...60), CGFloat.random(in: 5...35), CGFloat.random(in: -60 ... -35))
        n.opacity = 0
        let d = CGFloat.random(in: 40...70)
        n.runAction(.sequence([.group([.moveBy(x: dir * d * cos(ang), y: -d * sin(ang), z: 0, duration: 1.1),
                                       .sequence([.fadeIn(duration: 0.15), .wait(duration: 0.55), .fadeOut(duration: 0.4)])]), .removeFromParentNode()]))
        scene.rootNode.addChildNode(n)
    }

    func spin(_ n: SCNNode, phase: Double) {
        n.eulerAngles = SCNVector3(0.25, CGFloat(phase), 0)
        let a = SCNAction.sequence([.rotateTo(x: 0.25, y: CGFloat(phase) + 0.55, z: 0, duration: 3.2, usesShortestUnitArc: false),
                                    .rotateTo(x: 0.25, y: CGFloat(phase) - 0.55, z: 0, duration: 3.2, usesShortestUnitArc: false)])
        a.timingMode = .easeInEaseOut
        n.runAction(.repeatForever(a))
    }

    func pos(_ x: Int, _ y: Int) -> SCNVector3 { SCNVector3(CGFloat(x) - 4.5, CGFloat(y) - 9.5, 0) }

    func fillPreview(_ n: SCNNode, _ k: Kind?) {
        n.childNodes.forEach { $0.removeFromParentNode() }
        guard let k else { return }
        let c = shapes[k.rawValue][0]
        let mx = CGFloat(c.map { $0.0 }.min()! + c.map { $0.0 }.max()!) / 2
        let my = CGFloat(c.map { $0.1 }.min()! + c.map { $0.1 }.max()!) / 2
        for (x, y) in c {
            let b = SCNNode(geometry: geo[k.rawValue]); b.position = SCNVector3(CGFloat(x) - mx, CGFloat(y) - my, 0)
            n.addChildNode(b)
        }
    }
    func refreshPreviews() {
        fillPreview(holdNode, hold)
        holdNode.opacity = holdUsed ? 0.35 : 1
        for i in 0..<3 { fillPreview(nextNodes[i], i < queue.count ? queue[i] : nil) }
    }

    // MARK: HUD

    func proj(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        let p = view.projectPoint(SCNVector3(x, y, 0))
        return CGPoint(x: p.x, y: p.y)
    }
    func layoutHUD() { if state != .intro { refreshStats() } }

    var shownScore: [Double] = [0, 0], scoreHold: [Double] = [0, 0]
    var camHome = SCNVector3(0, 3.2, 36), camLook = SCNVector3(0, -0.4, 0), camAnimUntil = 0.0, bgKick: CGFloat = 0

    /// Najazd kamery: start z przesunięcia `from` (względem pozycji domowej) i płynny powrót; kamera cały czas patrzy na planszę.
    func camFly(from off: SCNVector3, look lookOff: SCNVector3 = SCNVector3Zero, duration d: Double) {
        let home = camHome, look = camLook
        camNode.removeAllActions()
        camAnimUntil = clock + d + 0.1
        let a = SCNAction.customAction(duration: d) { node, e in
            let k = CGFloat(e) / CGFloat(d), r = 1 - (k < 0.5 ? 4 * k * k * k : 1 - pow(-2 * k + 2, 3) / 2)
            node.position = SCNVector3(home.x + off.x * r, home.y + off.y * r, home.z + off.z * r)
            node.look(at: SCNVector3(look.x + lookOff.x * r, look.y + lookOff.y * r, look.z + lookOff.z * r))
        }
        camNode.runAction(.sequence([a, .run { n in n.position = home; n.look(at: look) }]))
    }

    /// Najazd na planszę i powrót (awans, finał). `toward`: punkt, do którego kamera się zbliża.
    func camPush(toward t: SCNVector3, amount: CGFloat, duration d: Double, hold: Double = 0.25) {
        let home = camHome, look = camLook
        camNode.removeAllActions()
        camAnimUntil = clock + d + hold + 0.1
        let dir = SCNVector3(t.x - home.x, t.y - home.y, t.z - home.z)
        let len = sqrt(dir.x * dir.x + dir.y * dir.y + dir.z * dir.z)
        let u = SCNVector3(dir.x / len * amount, dir.y / len * amount, dir.z / len * amount)
        let total = d + hold
        let a = SCNAction.customAction(duration: total) { node, e in
            let tt = Double(e)
            let inK = min(1, tt / (d * 0.4)), outK = max(0, (tt - d * 0.4 - hold) / (d * 0.6))
            let ein = CGFloat(inK * inK * (3 - 2 * inK)), eout = CGFloat(outK * outK * (3 - 2 * outK))
            let r = ein * (1 - eout)
            node.position = SCNVector3(home.x + u.x * r, home.y + u.y * r, home.z + u.z * r)
            node.look(at: SCNVector3(look.x + (t.x - look.x) * r * 0.6, look.y + (t.y - look.y) * r * 0.6, look.z))
        }
        camNode.runAction(.sequence([a, .run { n in n.position = home; n.look(at: look) }]))
    }

    /// Punkty lecą świetlistą kometą z planszy do licznika WYNIK; licznik rusza, gdy dolecą.
    func scoreFly(_ pts: Int, from p: CGPoint, player i: Int) {
        let h = view.bounds.height
        let target: CGPoint = {
            if !twoP { let q = proj(-10, 3.2); return CGPoint(x: q.x, y: q.y - h * 0.035) }
            let q = proj(i == 0 ? -16.6 : 16.6, -4.3); return CGPoint(x: q.x, y: q.y - h * 0.026)
        }()
        let dur = 0.75
        scoreHold[i] = clock + 0.35 + dur
        let n = SKNode(); n.position = p; n.alpha = 0
        hud.put("+\(fmt(pts))", h * 0.03, 0, 0, nsc(0xFFE27A), font: "AvenirNext-Heavy", in: n)
        let tex = SKTexture(cgImage: makeImage(32, 32) { ctx in
            ctx.drawRadialGradient(gradient([CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0)], [0, 1]), startCenter: CGPoint(x: 16, y: 16), startRadius: 0,
                                   endCenter: CGPoint(x: 16, y: 16), endRadius: 16, options: [])
        })
        let em = SKEmitterNode()                                   // ogon komety
        em.particleTexture = tex; em.particleBirthRate = 220 * fxQ; em.particleLifetime = 0.45
        em.particleScale = 0.5 * h / 1000; em.particleScaleSpeed = -0.8 * h / 1000
        em.particleAlpha = 0.9; em.particleAlphaSpeed = -2; em.particleColor = nsc(0xFFC23A); em.particleColorBlendFactor = 1
        em.particleBlendMode = .add; em.particlePositionRange = CGVector(dx: h * 0.01, dy: h * 0.01); em.targetNode = hud.fx
        n.addChild(em)
        // lot po łuku
        let start = p, ctrl = CGPoint(x: (p.x + target.x) / 2, y: max(p.y, target.y) + h * 0.18)
        let fly = SKAction.customAction(withDuration: dur) { node, e in
            let k = e / CGFloat(dur), t = k * k * (3 - 2 * k)
            let a = (1 - t) * (1 - t), b = 2 * (1 - t) * t, c = t * t
            node.position = CGPoint(x: a * start.x + b * ctrl.x + c * target.x, y: a * start.y + b * ctrl.y + c * target.y)
            node.setScale(1 - 0.45 * t)
        }
        n.run(.sequence([.wait(forDuration: 0.35), .fadeIn(withDuration: 0.08), fly, .run { [weak self] in
            guard let self else { return }
            em.particleBirthRate = 0
            self.scoreBurst(at: target)
        }, .fadeOut(withDuration: 0.15), .wait(forDuration: 0.5), .removeFromParent()]))
        hud.fx.addChild(n)
    }

    /// rozbłysk iskier przy liczniku punktów
    func scoreBurst(at p: CGPoint) {
        let h = view.bounds.height
        let ring = SKShapeNode(circleOfRadius: h * 0.03); ring.position = p
        ring.strokeColor = nsc(0xFFD21F); ring.lineWidth = h * 0.004; ring.glowWidth = h * 0.006; ring.fillColor = .clear; ring.blendMode = .add
        ring.run(.sequence([.group([.scale(to: 3.2, duration: 0.45), .fadeOut(withDuration: 0.45)]), .removeFromParent()]))
        hud.fx.addChild(ring)
        let cnt = Int(14 * fxQ) + 4
        for i in 0..<cnt {
            let a = CGFloat(i) / CGFloat(cnt) * .pi * 2 + .random(in: -0.2...0.2)
            let d = SKShapeNode(circleOfRadius: h * 0.004); d.position = p
            d.fillColor = [nsc(0xFFD21F), nsc(0xFFFFFF), nsc(0xFF8A1E)][i % 3]; d.strokeColor = .clear; d.blendMode = .add
            let r = h * CGFloat.random(in: 0.06...0.11)
            let mv = SKAction.moveBy(x: cos(a) * r, y: sin(a) * r, duration: 0.5); mv.timingMode = .easeOut
            d.run(.sequence([.group([mv, .fadeOut(withDuration: 0.5), .scale(to: 0.3, duration: 0.5)]), .removeFromParent()]))
            hud.fx.addChild(d)
        }
    }

    /// Fala za planszą: wielki pierścień w tle i podmuch, który rozpędza dryfujące klocki tła.
    func bgWave(color: NSColor, power: CGFloat) {
        bgKick = min(3, bgKick + power * 0.5)
        let t = SCNTorus(ringRadius: 1, pipeRadius: 0.025)
        let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = color; m.blendMode = .add; m.writesToDepthBuffer = false
        t.materials = [m]
        for i in 0..<(power >= 3 ? 2 : 1) {
            let n = SCNNode(geometry: t); n.eulerAngles.x = .pi / 2
            n.position = SCNVector3(cp.base.x, 0, -22); n.scale = SCNVector3(1, 1, 1)
            let a = SCNAction.group([.scale(to: 30 + 12 * power, duration: 1.4), .fadeOut(duration: 1.4)]); a.timingMode = .easeOut
            n.runAction(.sequence([.wait(duration: 0.15 * Double(i)), a, .removeFromParentNode()]))
            scene.rootNode.addChildNode(n)
        }
        // błysk promieni za planszą
        rays.opacity = 1
    }

    func refreshStats() {
        statsDirty = false
        lastStats = clock
        SCNTransaction.lock(); defer { SCNTransaction.unlock() }
        hud.beginLabels()
        let h = view.bounds.height
        let dim = nsc(0x8E97CC)
        if !twoP {
            let tA = proj(-10, 9.25), tB = proj(10, 9.25)
            hud.label("hold0", "SCHOWEK", h * 0.022, tA.x, tA.y, dim)
            hud.label("next0", "NASTĘPNE", h * 0.022, tB.x, tB.y, dim)
            let rows: [(String, String)] = [("WYNIK", fmt(Int(shownScore[0].rounded()))), ("REKORD", fmt(max(best, p1.score))), ("POZIOM", "\(p1.level)"), ("LINIE", "\(p1.lines)")]
            for (i, r) in rows.enumerated() {
                let p = proj(-10, 3.2 - CGFloat(i) * 2.15)
                hud.label("t0\(i)", r.0, h * 0.02, p.x, p.y, dim)
                hud.label(i == 0 ? "sc0" : "v0\(i)", r.1, h * 0.04, p.x, p.y - h * 0.035, i == 0 ? .white : nsc(0xDDE3FF), font: "AvenirNext-Bold")
            }
            hud.label("help", helpText(0) + "     ESC  pauza     M  muzyka", h * 0.016, view.bounds.width / 2, h * 0.025, nsc(0x6E77A8), font: "AvenirNext-Medium")
        } else {
            for (i, pl) in [p1, p2].enumerated() {
                let x: CGFloat = i == 0 ? -16.6 : 16.6
                let t = proj(pl.base.x, 12.4)
                hud.label("pl\(i)", "GRACZ \(i + 1)", h * 0.032, t.x, t.y, i == 0 ? nsc(0x20DDF0) : nsc(0xFF8A1E), font: "AvenirNext-Heavy")
                let a = proj(x, 10.1), b = proj(x, 5.1)
                hud.label("hold\(i)", "SCHOWEK", h * 0.017, a.x, a.y, dim)
                hud.label("next\(i)", "NASTĘPNE", h * 0.017, b.x, b.y, dim)
                let rows: [(String, String)] = [("WYNIK", fmt(Int(shownScore[i].rounded()))), ("POZIOM", "\(pl.level)"), ("LINIE", "\(pl.lines)")]
                for (j, r) in rows.enumerated() {
                    let q = proj(x, -4.3 - CGFloat(j) * 2.0)
                    hud.label("t\(i)\(j)", r.0, h * 0.016, q.x, q.y, dim)
                    hud.label(j == 0 ? "sc\(i)" : "v\(i)\(j)", r.1, h * 0.03, q.x, q.y - h * 0.026, j == 0 ? .white : nsc(0xDDE3FF), font: "AvenirNext-Bold")
                }
            }
            hud.label("help", "GRACZ 1:  " + helpText(1) + "          GRACZ 2:  " + helpText(2) + "          ESC  pauza", h * 0.015, view.bounds.width / 2, h * 0.022, nsc(0x6E77A8), font: "AvenirNext-Medium")
        }
        hud.endLabels()
    }

    /// Wynik nie przeskakuje — szybko „nabija się” do nowej wartości, pulsując na złoto.
    func countScores(_ dt: Double) {
        for pl in [p1, p2] {
            let i = pl.id, target = Double(pl.score)
            var shown = shownScore[i]
            if target < shown { shown = target; shownScore[i] = shown; hud.tweak("sc\(i)", text: fmt(pl.score), scale: 1, color: .white); continue }
            if clock < scoreHold[i] { continue }                     // czekamy, aż punkty dolecą
            let diff = target - shown
            if diff > 0.5 {
                shown = min(target, shown + max(diff * min(1, dt * 2.6), min(diff, 60 * dt)))
                shownScore[i] = shown
                let k = min(1, CGFloat(diff) / 800)
                let pulse = 1 + 0.08 * CGFloat(sin(clock * 30)) * k
                hud.tweak("sc\(i)", text: fmt(Int(shown.rounded())), scale: 1 + 0.22 * k * pulse, color: nsc(0xFFD21F))
            } else if shown != target || diff != 0 {
                shownScore[i] = target
                hud.tweak("sc\(i)", text: fmt(pl.score), scale: 1, color: .white)
            }
        }
    }

    // MARK: Ekrany

    func showMenu(animated: Bool = true) {
        attractStage = 0
        demo = false
        state = .menu
        entering = false
        music.song = menuSong
        music.intensity = 0.45
        if !demoBG { startBGDemo() }
        setBlur(true)
        hud.openPanel(dim: 0.32)
        if !animated { hud.panel.removeAllActions(); hud.panel.alpha = 1; hud.panel.setScale(1); hud.shade.removeAllActions(); hud.shade.alpha = 0.32 }
        let w = view.bounds.width, h = view.bounds.height
        hud.card(w / 2, h * 0.5, h * 0.84, h * 0.8)
        let before = hud.panel.children.count
        hud.title("KLOCKI", h * 0.12, w / 2, h * 0.76)
        // litery tytułu falują
        for (i, n) in hud.panel.children.dropFirst(before).enumerated() {
            let up = SKAction.sequence([.moveBy(x: 0, y: h * 0.009, duration: 0.6), .moveBy(x: 0, y: -h * 0.009, duration: 0.6)])
            n.run(.sequence([.wait(forDuration: Double(i / 2) * 0.12), .repeatForever(up)]))
        }
        hud.put("klasyczne spadające klocki  •  3D", h * 0.022, w / 2, h * 0.665, nsc(0x9AA4D8), font: "AvenirNext-Medium", in: hud.panel)
        let music = ["MUZYKA:  MELODIE", "MUZYKA:  AMBIENT", "MUZYKA:  WYŁĄCZONA"][musicMode % 3]
        let items = ["1 GRACZ", "2 GRACZY", "REKORDY", "OPCJE", "WYJŚCIE"]; _ = music
        for (i, t) in items.enumerated() {
            let y = h * (0.575 - CGFloat(i) * 0.068)
            if i == menuSel {
                let bw = h * 0.46, bh = h * 0.056
                let bar = SKShapeNode(rect: CGRect(x: w / 2 - bw / 2, y: y - bh / 2, width: bw, height: bh), cornerRadius: bh / 2)
                bar.fillColor = nsc(0x3A4CFF, 0.38); bar.strokeColor = nsc(0x8FA4FF, 0.9); bar.lineWidth = 2; bar.glowWidth = 8
                bar.run(.repeatForever(.sequence([.fadeAlpha(to: 0.65, duration: 0.7), .fadeAlpha(to: 1, duration: 0.7)])))
                hud.panel.addChild(bar)
                for (k, sx) in [(-1.0, -1.0), (1.0, 1.0)] as [(CGFloat, CGFloat)] {
                    let sq = SKShapeNode(rectOf: CGSize(width: bh * 0.42, height: bh * 0.42), cornerRadius: bh * 0.08)
                    sq.fillColor = nsc(kindHex[(i * 2 + (k > 0 ? 1 : 0)) % 7]); sq.strokeColor = .clear
                    sq.position = CGPoint(x: w / 2 + sx * (bw / 2 - bh * 0.5), y: y)
                    sq.run(.repeatForever(.rotate(byAngle: .pi * sx, duration: 2)))
                    hud.panel.addChild(sq)
                }
                hud.put(t, h * 0.034, w / 2, y, .white, font: "AvenirNext-Heavy", in: hud.panel)
            } else {
                hud.put(t, h * 0.028, w / 2, y, nsc(0x9AA4D8), font: "AvenirNext-DemiBold", in: hud.panel)
            }
        }
        hud.put("↑ ↓  wybór      ENTER  zatwierdź      1 / 2  szybki start      M  muzyka", h * 0.019, w / 2, h * 0.175, nsc(0x6E77A8), font: "AvenirNext-Medium", in: hud.panel)
        hud.put("trudność: \(Game.diffNames[difficulty])  (zmiana w OPCJACH)", h * 0.019, w / 2, h * 0.215, nsc(Game.diffHex[difficulty]), font: "AvenirNext-DemiBold", in: hud.panel)
        hud.put("najlepszy wynik: \(fmt(best))", h * 0.019, w / 2, h * 0.135, nsc(0x8E97CC), font: "AvenirNext-Medium", in: hud.panel)
        refreshStats()
    }

    func menuActivate() {
        switch menuSel {
        case 0: newGame(players: 1)
        case 1: newGame(players: 2)
        case 2: showScores(highlight: nil)
        case 3: optSel = 0; showOptions()
        default: NSApp.terminate(nil)
        }
    }

    func showScores(highlight: Int?) {
        setBlur(true)
        state = .scores
        music.intensity = 0.45
        hud.openPanel(dim: 0.4)
        let w = view.bounds.width, h = view.bounds.height
        hud.card(w / 2, h * 0.5, h * 0.95, h * 0.78)
        hud.title("REKORDY", h * 0.075, w / 2, h * 0.8)
        let recs = Records.load()
        let cx = w / 2, colW = h * 0.42
        let hdr = nsc(0x8E97CC)
        let hy = h * 0.71
        hud.put("GRACZ", h * 0.018, cx - colW + h * 0.06, hy, hdr, align: .left, in: hud.panel)
        hud.put("WYNIK", h * 0.018, cx + colW * 0.24, hy, hdr, align: .right, in: hud.panel)
        hud.put("TRUDNOŚĆ", h * 0.018, cx + colW * 0.46, hy, hdr, in: hud.panel)
        hud.put("LINIE", h * 0.018, cx + colW * 0.78, hy, hdr, align: .right, in: hud.panel)
        hud.put("POZ.", h * 0.018, cx + colW * 0.92, hy, hdr, align: .right, in: hud.panel)
        if recs.isEmpty {
            hud.put("Brak rekordów — zagraj pierwszą partię!", h * 0.026, cx, h * 0.5, .white, font: "AvenirNext-Medium", in: hud.panel)
        }
        for (i, r) in recs.enumerated() {
            let y = h * (0.66 - CGFloat(i) * 0.043)
            let c: NSColor = i == highlight ? nsc(0xFFD21F) : (i < 3 ? .white : nsc(0xC8CFF0))
            let medal = [nsc(0xFFD21F), nsc(0xD8DDEB), nsc(0xE09A5A)]
            hud.put("\(i + 1).", h * 0.026, cx - colW + h * 0.04, y, i < 3 ? medal[i] : nsc(0x8E97CC), font: "AvenirNext-Bold", align: .right, in: hud.panel)
            hud.put(r.name, h * 0.026, cx - colW + h * 0.06, y, c, font: "AvenirNext-DemiBold", align: .left, in: hud.panel)
            hud.put(fmt(r.score), h * 0.026, cx + colW * 0.24, y, c, font: "AvenirNext-Bold", align: .right, in: hud.panel)
            let dn = r.diff.map { Game.diffNames[max(0, min(3, $0))] } ?? "—"
            hud.put(dn, h * 0.02, cx + colW * 0.46, y, r.diff.map { nsc(Game.diffHex[max(0, min(3, $0))]) } ?? nsc(0x6E77A8), font: "AvenirNext-DemiBold", in: hud.panel)
            hud.put("\(r.lines)", h * 0.024, cx + colW * 0.78, y, c, font: "AvenirNext-Medium", align: .right, in: hud.panel)
            hud.put("\(r.level)", h * 0.024, cx + colW * 0.92, y, c, font: "AvenirNext-Medium", align: .right, in: hud.panel)
        }
        hud.put("ENTER — powrót", h * 0.022, cx, h * 0.15, nsc(0x8E97CC), font: "AvenirNext-Medium", in: hud.panel)
    }

    func showOver() {
        hud.openPanel(dim: 0.45)
        let w = view.bounds.width, h = view.bounds.height
        hud.card(w / 2, h * 0.5, h * 0.7, h * 0.44)
        hud.put("KONIEC GRY", h * 0.06, w / 2, h * 0.64, nsc(0xFF5A68), font: "AvenirNext-Heavy", in: hud.panel)
        hud.put("wynik  \(fmt(score))     linie  \(lines)     poziom  \(level)", h * 0.024, w / 2, h * 0.565, .white, font: "AvenirNext-Medium", in: hud.panel)
        if entering {
            hud.put("Nowy rekord! Wpisz imię:", h * 0.026, w / 2, h * 0.49, nsc(0xFFD21F), font: "AvenirNext-DemiBold", in: hud.panel)
            let field = SKShapeNode(rect: CGRect(x: w / 2 - h * 0.2, y: h * 0.405, width: h * 0.4, height: h * 0.055), cornerRadius: h * 0.012)
            field.fillColor = nsc(0x050818, 0.9); field.strokeColor = nsc(0xFFD21F, 0.7); field.lineWidth = 1.5
            hud.panel.addChild(field)
            hud.put(name + "▏", h * 0.032, w / 2, h * 0.432, .white, font: "AvenirNext-Bold", in: hud.panel)
            hud.put("ENTER — zapisz", h * 0.02, w / 2, h * 0.35, nsc(0x8E97CC), font: "AvenirNext-Medium", in: hud.panel)
        } else {
            hud.put("ENTER — menu     R — rekordy", h * 0.022, w / 2, h * 0.42, nsc(0x8E97CC), font: "AvenirNext-Medium", in: hud.panel)
        }
    }

    var pauseSel = 0
    var pauseItems: [String] { twoP ? ["WZNÓW", "OD NOWA", "MENU GŁÓWNE"] : ["WZNÓW", "OD NOWA", "ZAKOŃCZ I ZAPISZ WYNIK", "MENU GŁÓWNE"] }

    func showPause(animated: Bool = true) {
        hud.openPanel(dim: 0.5)
        if !animated { hud.panel.removeAllActions(); hud.panel.alpha = 1; hud.panel.setScale(1); hud.shade.removeAllActions(); hud.shade.alpha = 0.5 }
        let w = view.bounds.width, h = view.bounds.height
        let items = pauseItems
        hud.card(w / 2, h * 0.5, h * 0.7, h * (0.2 + CGFloat(items.count) * 0.068))
        let top = h * (0.5 + (0.1 + CGFloat(items.count) * 0.034) - 0.06)
        hud.put("PAUZA", h * 0.055, w / 2, top, .white, font: "AvenirNext-Heavy", in: hud.panel)
        for (i, t) in items.enumerated() {
            let y = top - h * (0.09 + CGFloat(i) * 0.065)
            if i == pauseSel {
                let bw = h * 0.52, bh = h * 0.052
                let b = SKShapeNode(rect: CGRect(x: w / 2 - bw / 2, y: y - bh / 2, width: bw, height: bh), cornerRadius: bh / 2)
                b.fillColor = nsc(0x3A4CFF, 0.38); b.strokeColor = nsc(0x8FA4FF, 0.9); b.lineWidth = 2; b.glowWidth = 6
                hud.panel.addChild(b)
            }
            hud.put(t, h * (i == pauseSel ? 0.03 : 0.026), w / 2, y, i == pauseSel ? .white : nsc(0x9AA4D8),
                    font: i == pauseSel ? "AvenirNext-Heavy" : "AvenirNext-DemiBold", in: hud.panel)
        }
        hud.put("↑ ↓  wybór      ENTER  zatwierdź      ESC  wznów", h * 0.017, w / 2, top - h * (0.09 + CGFloat(items.count) * 0.065), nsc(0x6E77A8), font: "AvenirNext-Medium", in: hud.panel)
    }

    func resumeGame() { state = .playing; hud.clearPanel(); music.duck = 1 }

    func pauseActivate() {
        music.duck = 1
        switch pauseItems[pauseSel] {
        case "WZNÓW": resumeGame()
        case "OD NOWA": newGame(players: twoP ? 2 : 1)
        case "ZAKOŃCZ I ZAPISZ WYNIK": hud.clearPanel(); gameOver()
        default: toMenuFromGame()
        }
    }

    /// Porzuca bieżącą partię i wraca do menu głównego (z demem w tle).
    func toMenuFromGame() {
        gen += 1
        state = .over
        for pl in [p1, p2] { cp = pl; hidePiece() }
        cp = p1
        demoBG = false
        music.duck = 1
        showMenu()
    }

    /// 3, 2, 1, START! — klocek czeka u góry, aż odliczanie się skończy.
    func countdown() {
        state = .countdown
        camFly(from: SCNVector3(twoP ? 0 : -5, 4, 7), look: SCNVector3(0, -2, 0), duration: 2.0)
        let g0 = gen, h = view.bounds.height
        let mid = proj(0, 3)
        let center = CGPoint(x: twoP ? view.bounds.width / 2 : mid.x, y: mid.y)
        for (i, t) in ["3", "2", "1", "START!"].enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35 + Double(i) * 0.7) { [weak self] in
                guard let self, self.gen == g0, self.state == .countdown else { return }
                let last = i == 3
                let n = SKNode()
                n.position = center
                self.hud.put(t, h * (last ? 0.11 : 0.17), 0, 0, last ? nsc(0x37DE58) : nsc([0x20DDF0, 0xFFD21F, 0xFF8A1E][i]), font: "AvenirNext-Heavy", in: n)
                n.setScale(1.8); n.alpha = 0
                n.run(.sequence([.group([.fadeIn(withDuration: 0.1), .scale(to: 1, duration: 0.28)]), .wait(forDuration: last ? 0.55 : 0.22),
                                 .group([.fadeOut(withDuration: 0.25), .scale(to: last ? 1.3 : 0.7, duration: 0.25)]), .removeFromParent()]))
                self.hud.fx.addChild(n)
                self.music.play(last ? 84 : 72, amp: 0.13, decay: last ? 0.9 : 0.3)
                if last { self.music.play(88, amp: 0.08, decay: 0.9); self.music.play(91, amp: 0.06, decay: 0.9) }
                if last { self.state = .playing; self.lastTime = CACurrentMediaTime() }
            }
        }
    }

    /// Rozgrzewka: każdy rodzaj efektu rysujemy raz, niewidocznie, w czasie intra —
    /// shadery kompilują się wtedy, a nie w środku gry (to dawało przycięcia do kilku klatek/s).
    func prewarmEffects() {
        let warm = SCNNode(); warm.position = SCNVector3(0, 0, -3); warm.opacity = 0.002
        var gs: [SCNGeometry] = ghostGeo + beamGeo + debrisGeo + [flashGeo, fadeGeo, grayGeo]
        let fp = SCNPlane(width: 1, height: 1); fp.materials = [glowMat(.white)]; gs.append(fp)
        let t = SCNTorus(ringRadius: 1, pipeRadius: 0.05)
        let tm = SCNMaterial(); tm.lightingModel = .constant; tm.diffuse.contents = NSColor.white; tm.blendMode = .add; tm.writesToDepthBuffer = false
        t.materials = [tm]; gs.append(t)
        let sph = SCNSphere(radius: 1); sph.segmentCount = 32
        let sm = SCNMaterial(); sm.lightingModel = .constant; sm.diffuse.contents = NSColor.white; sm.blendMode = .add
        sm.writesToDepthBuffer = false; sm.isDoubleSided = true
        sm.shaderModifiers = [.fragment: "float rimF = pow(1.0 - abs(dot(_surface.normal, _surface.view)), 2.5); _output.color.rgb *= rimF;"]
        sph.materials = [sm]; gs.append(sph)
        for (i, g) in gs.enumerated() { let n = SCNNode(geometry: g); n.position = SCNVector3(CGFloat(i % 6) * 0.5 - 1.5, CGFloat(i / 6) * 0.5, 0); warm.addChildNode(n) }
        for stretch in [CGFloat(0), 0.035] {                       // układy cząstek: zwykłe i rozciągnięte
            let ps = SCNParticleSystem(); ps.particleImage = spark; ps.birthRate = 50; ps.emissionDuration = 0.3; ps.loops = false
            ps.particleLifeSpan = 0.3; ps.blendMode = .additive; ps.stretchFactor = stretch; ps.particleSize = 0.05
            warm.addParticleSystem(ps)
        }
        scene.rootNode.addChildNode(warm)
        view.prepare([warm, scene]) { _ in }
        warm.runAction(.sequence([.wait(duration: 1.2), .removeFromParentNode()]))
        // nakładka 2D: kometa (emiter), pierścień z poświatą, napisy — też raz, niewidocznie
        SCNTransaction.lock(); defer { SCNTransaction.unlock() }
        let sk = SKNode(); sk.alpha = 0.01; sk.position = CGPoint(x: 40, y: 40)
        let em = SKEmitterNode(); em.particleTexture = SKTexture(cgImage: makeImage(8, 8) { $0.setFillColor(.white); $0.fill(CGRect(x: 0, y: 0, width: 8, height: 8)) })
        em.particleBirthRate = 30; em.particleLifetime = 0.3; em.particleBlendMode = .add; em.particleColorBlendFactor = 1
        sk.addChild(em)
        let ring = SKShapeNode(circleOfRadius: 20); ring.glowWidth = 6; ring.blendMode = .add; sk.addChild(ring)
        let dot = SKShapeNode(circleOfRadius: 3); dot.fillColor = .white; dot.blendMode = .add; sk.addChild(dot)
        let h = max(400, view.bounds.height)
        for (t, sz) in [("+800 POZIOM 0123456789 COMBO ×SUPER!", h * 0.03), ("POZIOM 2", h * 0.055), ("CZTERY LINIE!", h * 0.045)] {
            hud.put(t, sz, 0, 0, .white, font: "AvenirNext-Heavy", in: sk)
        }
        hud.fx.addChild(sk)
        sk.run(.sequence([.wait(forDuration: 1.2), .removeFromParent()]))
    }

    func start() {
        prewarmEffects()
        hud.px = view.window?.backingScaleFactor ?? 2
        hud.playIntro { [weak self] in
            guard let self else { return }
            self.music.duck = 1
            self.hud.stats.run(.fadeIn(withDuration: 0.6))
            self.showMenu()
            if ProcessInfo.processInfo.environment["KLOCKI_TEST"] != nil { self.autoplay() }
        }
    }

    /// Tryb testowy (KLOCKI_TEST=1): losowe ruchy bez klawiatury.
    func autoplay() {
        if let path = ProcessInfo.processInfo.environment["KLOCKI_SNAP"] {         // test: zapis klatki z gry po N s
            let ts = (ProcessInfo.processInfo.environment["KLOCKI_SNAPT"] ?? "5").split(separator: ",").compactMap { Double($0) }
            for (j, t) in ts.enumerated() { let path = ts.count > 1 ? path.replacingOccurrences(of: ".png", with: "_\(j).png") : path
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { [self] in
                let img = view.snapshot()
                if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: path)); print("SNAP", path); fflush(stdout)
                }
            } }
        }
        if let q = ProcessInfo.processInfo.environment["KLOCKI_Q"].flatMap(Int.init) { quality = max(0, min(2, q)); applyQuality() }   // test: jakość bez zapisu
        if ProcessInfo.processInfo.environment["KLOCKI_TEST"] == "6" {   // test: odliczanie, potem pauza
            newGame(players: 1)
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { [self] in state = .paused; pauseSel = 3; showPause() }
            return
        }
        if ProcessInfo.processInfo.environment["KLOCKI_TEST"] == "5" { ctlProfile = 1; ctlSel = 6; showControls(); return }
        if ProcessInfo.processInfo.environment["KLOCKI_TEST"] == "4" { optSel = 3; showOptions(); return }
        if ProcessInfo.processInfo.environment["KLOCKI_TEST"] == "7" { showScores(highlight: nil); return }
        if ProcessInfo.processInfo.environment["KLOCKI_TEST"] == "8" {   // test: pełna plansza i finał
            newGame(players: 1)
            for y in 0..<18 { for x in 0..<Game.W where (x * 7 + y * 3) % 10 != 0 {
                let k = (x + y) % 7; grid[y][x] = k
                let n = SCNNode(geometry: geo[k]); n.position = pos(x, y); board.addChildNode(n); cells[y][x] = n
            } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.5) { [self] in SCNTransaction.lock(); gameOver(); SCNTransaction.unlock() }
            return
        }
        newGame(players: ProcessInfo.processInfo.environment["KLOCKI_TEST"] == "3" ? 2 : 1)
        if ProcessInfo.processInfo.environment["KLOCKI_TEST"] == "2" {   // test: zbicie 4 linii
            for y in 0..<7 { for x in 0..<Game.W where y < 4 || (x + y) % 3 != 0 {
                let k = (x + y) % 7; grid[y][x] = k
                let n = SCNNode(geometry: geo[k]); n.position = pos(x, y); board.addChildNode(n); cells[y][x] = n
            } }
            if ProcessInfo.processInfo.environment["KLOCKI_LVUP"] != nil { lines = 6 }   // test: 4 linie dają awans
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in hidePiece(); clearLines([0, 1, 2, 3]) }
            if ProcessInfo.processInfo.environment["KLOCKI_REPEAT"] != nil {          // test wydajności: kolejne zbicia co 3 s
                for r in 1...4 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5 + Double(r) * 3) { [self] in
                        SCNTransaction.lock(); defer { SCNTransaction.unlock() }
                        guard state == .playing, !cp.busy else { return }
                        for y in 0..<4 { for x in 0..<Game.W where grid[y][x] < 0 {
                            let k = (x + y + r) % 7; grid[y][x] = k
                            let n = SCNNode(geometry: geo[k]); n.position = pos(x, y); board.addChildNode(n); cells[y][x] = n
                        } }
                        clearLines([0, 1, 2, 3])
                    }
                }
            }
            return
        }
        Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            guard let self, self.state == .playing else { return }
            self.cp = self.active.randomElement()!
            switch Int.random(in: 0..<10) {
            case 0...2: self.move(-1)
            case 3...5: self.move(1)
            case 6: self.rotate(1)
            case 7: if Int.random(in: 0..<3) == 0 { self.hardDrop() }
            default: break
            }
        }
    }

    // MARK: Rozgrywka

    func newGame(players n: Int = 1, keepUI: Bool = false) {
        gen += 1
        demoBG = keepUI
        if !keepUI { demo = false; setBlur(false) }
        twoP = n == 2
        layout()
        let seed = UInt64.random(in: 1...UInt64.max / 2)
        for pl in [p1, p2] {
            cp = pl
            for y in 0..<Game.H { for x in 0..<Game.W { cells[y][x]?.removeFromParentNode(); cells[y][x] = nil; grid[y][x] = -1 } }
            score = 0; lines = 0; level = keepUI ? 1 : startLevel; combo = -1; b2b = false
            bag = []; queue = []; hold = nil; holdUsed = false
            leftHeld = false; rightHeld = false; softDrop = false
            pl.busy = false; pl.garbage = 0; pl.alive = pl === p1 || twoP; pl.rng = seed
            if pl.board.action(forKey: "flip") != nil {                     // przerwany obrót planszy
                pl.board.removeAction(forKey: "flip"); pl.board.scale = SCNVector3(1, 1, 1); pl.board.eulerAngles = SCNVector3Zero
                startSway(pl.board, dir: pl === p2 ? 1 : -1)
            }
            hidePiece()
            refreshPreviews()
        }
        if !keepUI {
            hud.clearPanel()
            hud.retireChildren(hud.fx)
            music.duck = 1
            music.song = menuSong
            state = .playing
        }
        setRimColors()
        setTheme(keepUI ? 0 : startLevel - 1)
        for pl in active { cp = pl; fillQueue(); spawn(queue.removeFirst()) }
        refreshStats()
        if !keepUI { countdown() }
    }

    // MARK: Tryb pokazowy (menu bez gracza)

    var idleT = 0.0, attractT = 0.0, attractStage = 0, demo = false, demoBG = false
    var running: Bool { state == .playing || (demoBG && [State.menu, .scores, .options, .controls].contains(state)) }
    /// efekty dźwiękowe gry — w demie wyciszone
    var sfx: Music? { demoBG ? nil : music }
    var spawnCount = 0, aiFor = -1, aiTries = 0, aiPlan = (0, 3), aiT = 0.0
    lazy var idleLimit: Double = Double(ProcessInfo.processInfo.environment["KLOCKI_IDLE"] ?? "") ?? 15

    func attractTick(_ dt: Double) {
        switch state {
        case .menu:
            idleT += dt
            if idleT > idleLimit {
                idleT = 0
                showScores(highlight: nil)
                attractStage = 1; attractT = 0
                let h = view.bounds.height
                let l = hud.put("naciśnij dowolny klawisz", h * 0.02, view.bounds.width / 2, h * 0.105, nsc(0xFFD21F), font: "AvenirNext-DemiBold", in: hud.panel)
                l.run(.repeatForever(.sequence([.fadeAlpha(to: 0.25, duration: 0.7), .fadeAlpha(to: 1, duration: 0.7)])))
            }
        case .scores where attractStage == 1:
            attractT += dt
            if attractT > 8 { startDemo() }
        case .playing where demo:
            attractT += dt
            if attractT > 35 { endDemo() }
        default: break
        }
    }

    /// Demo w tle: komputer gra od losowego poziomu, bez dźwięków gry.
    func startBGDemo() {
        newGame(players: 1, keepUI: true)
        let lv = Int.random(in: 2...12)
        level = lv
        lines = (lv - 1) * 10
        setRimColors()
        setTheme(lv - 1)
        refreshStats()
    }

    /// Rozmycie sceny 3D (głębia ostrości kamery) — napisy HUD zostają ostre.
    func setBlur(_ on: Bool) {
        guard let cam = camNode.camera else { return }
        cam.wantsDepthOfField = true
        SCNTransaction.begin(); SCNTransaction.animationDuration = 0.7
        cam.focusDistance = on ? 2.5 : 36
        cam.fStop = on ? 0.25 : 32
        if !on {                                                     // w grze rozmycie wyłączone całkiem (drogie w 4K)
            SCNTransaction.completionBlock = { [weak self] in
                DispatchQueue.main.async { if let self, self.camNode.camera?.fStop ?? 0 > 30 { self.camNode.camera?.wantsDepthOfField = false } }
            }
        }
        SCNTransaction.commit()
    }

    /// Pełnoekranowy pokaz: ta sama rozgrywka, ale ostra i bez menu.
    func startDemo() {
        attractStage = 2
        attractT = 0
        if !demoBG { startBGDemo() }
        state = .playing
        demo = true
        hud.clearPanel()
        setBlur(false)
        music.song = songPick == 0 ? (maxLevel - 1) % Music.songs.count : songPick - 1
        music.intensity = 0.45
        let w = view.bounds.width, h = view.bounds.height
        hud.panel.removeAllActions(); hud.panel.alpha = 1; hud.panel.setScale(1)
        let t = hud.put("DEMO", h * 0.05, w / 2, h * 0.93, nsc(0xFFD21F), font: "AvenirNext-Heavy", in: hud.panel)
        let l = hud.put("naciśnij dowolny klawisz", h * 0.02, w / 2, h * 0.885, .white, font: "AvenirNext-DemiBold", in: hud.panel)
        for n in [t, l] { n.run(.repeatForever(.sequence([.fadeAlpha(to: 0.35, duration: 0.8), .fadeAlpha(to: 1, duration: 0.8)]))) }
    }

    func endDemo() {
        demo = false
        attractStage = 0
        showMenu()
        idleT = 0
    }

    func stopAttract() {
        if demo { endDemo() } else { attractStage = 0; showMenu() }
        idleT = 0
    }

    /// Prosty sztuczny gracz: ocenia każde ustawienie (obrót × kolumna) i wybiera najlepsze.
    func aiTarget() -> (Int, Int) {
        var best = (rot, px), bestScore = -Double.infinity
        for r in 0..<(cur == .O ? 1 : 4) {
            for x in -2..<Game.W {
                guard fits(x, py, r) else { continue }
                var y = py
                while fits(x, y - 1, r) { y -= 1 }
                var g = grid
                var usesWell = false
                for (cx, cy) in shapes[cur.rawValue][r] where y + cy < Game.H { g[y + cy][x + cx] = 0; if x + cx == Game.W - 1 { usesWell = true } }
                let full = g.filter { $0.allSatisfy { $0 >= 0 } }.count
                g = g.filter { !$0.allSatisfy { $0 >= 0 } }
                while g.count < Game.H { g.append([Int](repeating: -1, count: Game.W)) }
                var heights = [Int](repeating: 0, count: Game.W), holes = 0
                for cx in 0..<Game.W {
                    var top = -1
                    for cy in stride(from: Game.H - 1, through: 0, by: -1) where g[cy][cx] >= 0 { top = cy; break }
                    heights[cx] = top + 1
                    if top > 0 { for cy in 0..<top where g[cy][cx] < 0 { holes += 1 } }
                }
                // stos na kolumnach 0–8, kolumna 9 to studnia na długi klocek (4 linie naraz)
                let hs = Array(heights[0..<(Game.W - 1)])
                var bump = 0
                for i in 0..<(hs.count - 1) { bump += abs(hs[i] - hs[i + 1]) }
                let panic = (heights.max() ?? 0) > 13
                var sc = -0.51 * Double(hs.reduce(0, +)) - 0.9 * Double(holes) - 0.2 * Double(bump)
                if full == 4 { sc += 14 }
                else if full > 0 { sc += panic ? 0.9 * Double(full) : -1.5 * Double(full) }
                if usesWell && full < 4 && !panic { sc -= 5 }
                if sc > bestScore { bestScore = sc; best = (r, x) }
            }
        }
        return best
    }

    func aiStep() {
        guard running, !cp.busy, cp.alive else { return }
        if aiFor != spawnCount { aiFor = spawnCount; aiPlan = aiTarget(); aiTries = 0; softDrop = false; return }
        aiTries += 1
        if rot != aiPlan.0 && aiTries < 12 { rotate(1) }
        else if px < aiPlan.1 && aiTries < 30 { move(1) }
        else if px > aiPlan.1 && aiTries < 30 { move(-1) }
        else { softDrop = true }                 // widoczne opuszczanie zamiast błyskawicznego zrzutu
    }

    // MARK: Opcje

    let ud = UserDefaults.standard
    lazy var musicVol: Int = ud.object(forKey: "glosMuz") as? Int ?? 8
    lazy var sfxVol: Int = ud.object(forKey: "glosEf") as? Int ?? 8
    lazy var display: Int = ud.integer(forKey: "ekran")
    lazy var quality: Int = ud.integer(forKey: "jakosc")
    lazy var fps60: Bool = ud.bool(forKey: "fps60")
    lazy var shakeOn: Bool = ud.object(forKey: "wstrzasy") as? Bool ?? true
    lazy var dasSet: Int = ud.object(forKey: "das") as? Int ?? 1
    lazy var softSet: Int = ud.object(forKey: "miekki") as? Int ?? 1
    lazy var difficulty: Int = ud.object(forKey: "trudnosc") as? Int ?? 1   // 0 łatwy, 1 normalny, 2 trudny, 3 ekspert
    static let diffNames = ["Łatwy", "Normalny", "Trudny", "Ekspert"]
    static let diffHex: [UInt32] = [0x5BE37A, 0x5BC8FF, 0xFFA43A, 0xFF4A6A]
    var diffSpeed: Double { [0.72, 1, 1.35, 1.8][difficulty] }        // mnożnik prędkości opadania
    var lockDelay: Double { [0.75, 0.5, 0.4, 0.3][difficulty] }       // czas do zablokowania leżącego klocka
    var startLevel: Int { [1, 1, 3, 6][difficulty] }
    var optSel = 0
    lazy var songPick: Int = ud.integer(forKey: "utwor")        // 0 = automatycznie, 1… = konkretny utwór
    var menuSong: Int { songPick == 0 ? 0 : songPick - 1 }
    var onDisplay: ((Int) -> Void)?
    static let displays = ["pełny ekran", "okno 1280 × 720", "okno 1920 × 1080", "okno 2560 × 1440"]
    var baseBloom: CGFloat { quality == 2 ? 0 : 0.5 }

    func saveOptions() {
        ud.set(musicVol, forKey: "glosMuz"); ud.set(sfxVol, forKey: "glosEf"); ud.set(display, forKey: "ekran")
        ud.set(quality, forKey: "jakosc"); ud.set(fps60, forKey: "fps60"); ud.set(shakeOn, forKey: "wstrzasy")
        ud.set(dasSet, forKey: "das"); ud.set(softSet, forKey: "miekki"); ud.set(difficulty, forKey: "trudnosc"); ud.set(musicMode, forKey: "muzyka"); ud.set(songPick, forKey: "utwor")
    }
    func applyAudio() {
        music.volume = Float(musicVol) / 10 * 0.95
        music.sfxVolume = Float(sfxVol) / 10
    }
    func applyQuality() {
        view.antialiasingMode = [SCNAntialiasingMode.multisampling4X, .multisampling2X, .none][quality]
        view.preferredFramesPerSecond = fps60 ? 60 : 120
        scene.rootNode.enumerateHierarchy { n, _ in
            if let l = n.light, l.type == .directional {
                l.castsShadow = quality < 2
                l.shadowMapSize = quality == 0 ? CGSize(width: 4096, height: 4096) : CGSize(width: 2048, height: 2048)
                l.shadowSampleCount = quality == 0 ? 8 : 2
            }
            if let f = n.geometry as? SCNFloor { f.reflectivity = quality == 2 ? 0 : 0.32 }
        }
        camNode.camera?.bloomIntensity = baseBloom
        camNode.camera?.screenSpaceAmbientOcclusionIntensity = 0                           // SSAO wyłączone: za drogie w 4K
        camNode.camera?.screenSpaceAmbientOcclusionRadius = 0.35
        camNode.camera?.grainIntensity = quality < 2 ? 0.035 : 0                                 // delikatne ziarno jak z aparatu
        camNode.camera?.grainScale = 1
    }

    func optionRows() -> [(String, String)] {
        let bar = { (v: Int) in String(repeating: "■", count: v) + String(repeating: "□", count: 10 - v) }
        return [("GŁOŚNOŚĆ MUZYKI", bar(musicVol)), ("GŁOŚNOŚĆ EFEKTÓW", bar(sfxVol)),
                ("MUZYKA", ["melodie", "ambient", "wyłączona"][musicMode % 3]),
                ("UTWÓR", songPick == 0 ? "automatycznie (co poziom)" : Music.songs[songPick - 1].name),
                ("EKRAN", Game.displays[display]),
                ("JAKOŚĆ GRAFIKI", ["wysoka (4K, wygładzanie 4×)", "średnia", "niska"][quality]),
                ("KLATKI NA SEKUNDĘ", fps60 ? "60" : "120"),
                ("WSTRZĄSY EKRANU", shakeOn ? "włączone" : "wyłączone"),
                ("PRZESUWANIE NA BOK", ["szybkie", "normalne", "wolne"][dasSet]),
                ("PRZYSPIESZANIE  ↓", ["wolne", "średnie", "szybkie"][softSet]),
                ("POZIOM TRUDNOŚCI", ["łatwy", "normalny", "trudny", "ekspert (start: poziom 6)"][difficulty]),
                ("STEROWANIE", ""), ("POWRÓT", "")]
    }

    func changeOption(_ d: Int) {
        let ns = Music.songs.count + 1
        switch optSel {
        case 0: musicVol = max(0, min(10, musicVol + d)); applyAudio()
        case 1: sfxVol = max(0, min(10, sfxVol + d)); applyAudio(); music.holdSnd()
        case 2: musicMode = (musicMode + (d > 0 ? 1 : 2)) % 3; music.mode = musicMode
        case 3:
            songPick = (songPick + d + ns) % ns
            if musicMode != 0 { musicMode = 0; music.mode = 0 }
            music.song = menuSong                                   // od razu słychać wybrany utwór
        case 4: display = (display + d + 4) % 4; onDisplay?(display)
        case 5: quality = (quality + d + 3) % 3; applyQuality()
        case 6: fps60.toggle(); applyQuality()
        case 7: shakeOn.toggle(); if shakeOn { shake(0.2) }
        case 8: dasSet = (dasSet + d + 3) % 3
        case 9: softSet = (softSet + d + 3) % 3
        case 10: difficulty = (difficulty + d + 4) % 4
        case 11: showControls(); return
        default: showMenu(); return
        }
        saveOptions()
        music.tick()
        showOptions(animated: false)
    }

    func showOptions(animated: Bool = true) {
        setBlur(true)
        state = .options
        hud.openPanel(dim: 0.6)
        if !animated { hud.panel.removeAllActions(); hud.panel.alpha = 1; hud.panel.setScale(1); hud.shade.removeAllActions(); hud.shade.alpha = 0.6 }
        let w = view.bounds.width, h = view.bounds.height
        hud.card(w / 2, h * 0.5, h * 1.12, h * 0.88)
        hud.title("OPCJE", h * 0.075, w / 2, h * 0.865)
        for (i, r) in optionRows().enumerated() {
            let y = h * (0.78 - CGFloat(i) * 0.051)
            let sel = i == optSel
            if sel {
                let bw = h * 1.02, bh = h * 0.048
                let b = SKShapeNode(rect: CGRect(x: w / 2 - bw / 2, y: y - bh / 2, width: bw, height: bh), cornerRadius: bh / 2)
                b.fillColor = nsc(0x3A4CFF, 0.38); b.strokeColor = nsc(0x8FA4FF, 0.9); b.lineWidth = 2; b.glowWidth = 6
                b.run(.repeatForever(.sequence([.fadeAlpha(to: 0.7, duration: 0.7), .fadeAlpha(to: 1, duration: 0.7)])))
                hud.panel.addChild(b)
            }
            let col: NSColor = sel ? .white : nsc(0x9AA4D8)
            if r.1.isEmpty {
                hud.put(i == 11 ? "STEROWANIE  ›" : r.0, h * 0.025, w / 2, y, col, font: sel ? "AvenirNext-Heavy" : "AvenirNext-DemiBold", in: hud.panel)
            } else {
                hud.put(r.0, h * 0.023, w / 2 - h * 0.47, y, col, font: sel ? "AvenirNext-Bold" : "AvenirNext-DemiBold", align: .left, in: hud.panel)
                hud.put(sel ? "◀   \(r.1)   ▶" : r.1, h * 0.023, w / 2 + h * 0.47, y, sel ? nsc(0xFFD21F) : nsc(0xDDE3FF), font: "AvenirNext-DemiBold", align: .right, in: hud.panel)
            }
        }
        hud.put("↑ ↓  wybór      ← →  zmiana      ENTER  zatwierdź      ESC  powrót      (pad: krzyżak, \(padIsPS ? "✕, ○" : "A, B"))", h * 0.018, w / 2, h * 0.09, nsc(0x6E77A8), font: "AvenirNext-Medium", in: hud.panel)
    }

    func showControls() {
        state = .controls
        hud.openPanel(dim: 0.6)
        hud.panel.removeAllActions(); hud.panel.alpha = 1; hud.panel.setScale(1); hud.shade.removeAllActions(); hud.shade.alpha = 0.6
        let w = view.bounds.width, h = view.bounds.height
        hud.card(w / 2, h * 0.5, h * 1.42, h * 0.86)
        hud.title("STEROWANIE", h * 0.06, w / 2, h * 0.865)
        // zakładki profili
        let lx = w / 2 - h * 0.66, kx = w / 2 + h * 0.06
        for (i, n) in Game.profileNames.enumerated() {
            let x = w / 2 - h * 0.66 + h * 0.135 + CGFloat(i) * h * 0.27
            if i == ctlProfile {
                let tw = h * 0.25, th = h * 0.042
                let t = SKShapeNode(rect: CGRect(x: x - tw / 2, y: h * 0.775 - th / 2, width: tw, height: th), cornerRadius: th / 2)
                t.fillColor = nsc(0xFFD21F, 0.22); t.strokeColor = nsc(0xFFD21F, 0.9); t.lineWidth = 1.5
                hud.panel.addChild(t)
            }
            hud.put(n, h * 0.018, x, h * 0.775, i == ctlProfile ? nsc(0xFFD21F) : nsc(0x8E97CC), font: "AvenirNext-Bold", in: hud.panel)
        }
        hud.put("KLAWIATURA", h * 0.019, lx, h * 0.715, nsc(0xFFD21F), font: "AvenirNext-Bold", align: .left, in: hud.panel)
        let rows = Game.actNames.map { $0 } + ["Przywróć domyślne", "Powrót"]
        for (i, r) in rows.enumerated() {
            let y = h * (0.665 - CGFloat(i) * 0.054)
            let sel = i == ctlSel
            if sel {
                let bw = h * 0.74, bh = h * 0.046
                let b = SKShapeNode(rect: CGRect(x: lx - h * 0.02, y: y - bh / 2, width: bw, height: bh), cornerRadius: bh / 2)
                b.fillColor = nsc(0x3A4CFF, 0.38); b.strokeColor = nsc(0x8FA4FF, 0.9); b.lineWidth = 2; b.glowWidth = 6
                hud.panel.addChild(b)
            }
            let col: NSColor = sel ? .white : nsc(0x9AA4D8)
            hud.put(r, h * 0.022, lx, y, col, font: sel ? "AvenirNext-Bold" : "AvenirNext-DemiBold", align: .left, in: hud.panel)
            if i < 7 {
                let txt = sel && capturing ? "naciśnij klawisz…" : keyName(keymap[ctlProfile][i])
                let l = hud.put(txt, h * 0.022, kx, y, sel && capturing ? nsc(0xFFD21F) : (sel ? .white : nsc(0xDDE3FF)), font: "AvenirNext-Bold", align: .right, in: hud.panel)
                if sel && capturing { l.run(.repeatForever(.sequence([.fadeAlpha(to: 0.3, duration: 0.4), .fadeAlpha(to: 1, duration: 0.4)]))) }
            }
        }
        // pad: opisy wg podłączonego typu
        let ps = padIsPS
        let px = w / 2 + h * 0.2, pv = w / 2 + h * 0.66
        let pads = GCController.controllers().filter { $0.extendedGamepad != nil }
        let padName = pads.first.map { ($0.vendorName ?? $0.productCategory) } ?? (ps ? "PlayStation" : "nie podłączono")
        hud.put("PAD  —  \(padName)", h * 0.019, px, h * 0.715, nsc(0x37DE58), font: "AvenirNext-Bold", align: .left, in: hud.panel)
        let padRows: [(String, String)] = [
            ("Ruch", "krzyżak / lewa gałka"),
            ("Przyspieszanie", "krzyżak ↓"),
            ("Obrót", ps ? "✕" : "A"),
            ("Obrót w lewo", ps ? "○" : "B"),
            ("Zrzut", "krzyżak ↑"),
            ("Schowek", ps ? "□  △  L1  R1" : "X  Y  LB  RB"),
            ("Pauza", ps ? "OPTIONS" : "MENU"),
            ("W menu", ps ? "✕ wybierz   ○ wróć" : "A wybierz   B wróć")]
        for (i, r) in padRows.enumerated() {
            let y = h * (0.665 - CGFloat(i) * 0.054)
            hud.put(r.0, h * 0.02, px, y, nsc(0x9AA4D8), font: "AvenirNext-DemiBold", align: .left, in: hud.panel)
            hud.put(r.1, h * 0.02, pv, y, .white, font: "AvenirNext-Medium", align: .right, in: hud.panel)
        }
        hud.put("Pad 1 steruje graczem 1, pad 2 graczem 2  (PS4, PS5, Xbox i inne zgodne z macOS).   Podłączone pady: \(pads.count)",
                h * 0.017, w / 2, h * 0.135, nsc(0x8E97CC), font: "AvenirNext-Medium", in: hud.panel)
        hud.put("← →  profil      ↑ ↓  wybór      ENTER  zmień klawisz      ESC  powrót", h * 0.018, w / 2, h * 0.095, nsc(0x6E77A8), font: "AvenirNext-Medium", in: hud.panel)
    }

    /// Po zmianie rozmiaru okna: przebudowa HUD i bieżącego ekranu.
    func relayout() {
        refreshStats()
        switch state {
        case .options: showOptions(animated: false)
        case .menu: showMenu(animated: false)
        default: break
        }
    }

    // MARK: Pady

    var padCodes: [String: UInt16] = [:]

    func setupPads() {
        let nc = NotificationCenter.default
        nc.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in self?.bindPads(announce: true) }
        nc.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in self?.bindPads(announce: false) }
        GCController.startWirelessControllerDiscovery {}
        bindPads(announce: false)
    }

    func bindPads(announce: Bool) {
        let pads = GCController.controllers().filter { $0.extendedGamepad != nil }
        for (i, c) in pads.prefix(2).enumerated() {
            guard let g = c.extendedGamepad else { continue }
            c.playerIndex = i == 0 ? .index1 : .index2
            func bind(_ b: GCControllerButtonInput, _ name: String) {
                b.pressedChangedHandler = { [weak self] _, _, pressed in self?.pad(i, name, pressed) }
            }
            bind(g.dpad.left, "L"); bind(g.dpad.right, "R"); bind(g.dpad.up, "U"); bind(g.dpad.down, "D")
            bind(g.leftThumbstick.left, "sL"); bind(g.leftThumbstick.right, "sR"); bind(g.leftThumbstick.up, "sU"); bind(g.leftThumbstick.down, "sD")
            bind(g.buttonA, "A"); bind(g.buttonB, "B"); bind(g.buttonX, "X"); bind(g.buttonY, "Y")
            bind(g.leftShoulder, "H"); bind(g.rightShoulder, "H2"); bind(g.buttonMenu, "M")
        }
        if announce && state != .intro {
            hud.popup("🎮  pady: \(pads.count)", nsc(0x37DE58), at: CGPoint(x: view.bounds.width / 2, y: view.bounds.height * 0.9), size: view.bounds.height * 0.026)
        }
        if state == .controls { showControls() }
    }

    /// Przycisk pada → wirtualny klawisz właściwego gracza.
    func pad(_ i: Int, _ b: String, _ pressed: Bool) {
        if capturing { return }
        let id = "\(i)\(b)"
        if !pressed {
            if let code = padCodes.removeValue(forKey: id) { handleKey(code, down: false, isRepeat: false, chars: nil) }
            return
        }
        let btn = b.hasPrefix("s") ? String(b.dropFirst()) : b
        let second = twoP && i == 1
        var code: UInt16?
        if state == .playing {
            switch btn {
            case "L": code = twoP ? (second ? 123 : 0) : 123
            case "R": code = twoP ? (second ? 124 : 2) : 124
            case "D": code = twoP ? (second ? 125 : 1) : 125
            case "U": code = twoP ? (second ? 36 : 49) : 49
            case "A": code = twoP ? (second ? 126 : 13) : 126
            case "B": code = twoP ? (second ? 44 : 12) : 6
            case "X", "Y", "H", "H2": code = twoP ? (second ? 47 : 14) : 8
            case "M": code = 53
            default: break
            }
        } else {
            switch btn {
            case "U": code = 126
            case "D": code = 125
            case "L": code = 123
            case "R": code = 124
            case "A": code = 36
            case "B", "M": code = 53
            case "Y": code = state == .paused ? 12 : nil
            default: break
            }
        }
        guard let code else { return }
        padCodes[id] = code
        handleKey(code, down: true, isRepeat: false, chars: nil)
    }

    // MARK: Tryb 2 graczy

    /// Druga plansza = klon pierwszej (te same geometrie), z własnymi podglądami i panelami.
    func setupSecondPlayer() {
        for (i, n) in p1.pieceNodes.enumerated() { n.name = "piece\(i)" }
        for (i, n) in p1.ghostNodes.enumerated() { n.name = "ghost\(i)" }
        for (i, n) in p1.beamNodes.enumerated() { n.name = "beam\(i)" }
        p1.pieceLight.name = "plight"
        let b = p1.board.clone()
        p2.board = b
        scene.rootNode.addChildNode(b)
        p2.pieceNodes = (0..<4).compactMap { b.childNode(withName: "piece\($0)", recursively: false) }
        p2.ghostNodes = (0..<4).compactMap { b.childNode(withName: "ghost\($0)", recursively: false) }
        p2.beamNodes = (0..<4).compactMap { b.childNode(withName: "beam\($0)", recursively: false) }
        if let l = b.childNode(withName: "plight", recursively: false) { l.light = p1.pieceLight.light?.copy() as? SCNLight; p2.pieceLight = l }
        b.enumerateHierarchy { n, _ in
            guard !n.hasActions else { return }
            let name = n.name ?? ""
            if name.hasPrefix("ghost") {
                let a = SCNAction.sequence([.fadeOpacity(to: 0.55, duration: 0.6), .fadeOpacity(to: 1, duration: 0.6)]); a.timingMode = .easeInEaseOut
                n.runAction(.repeatForever(a))
            } else if name == "scan" {
                n.runAction(.repeatForever(.sequence([.move(to: SCNVector3(0, 11.5, -0.5), duration: 0), .move(to: SCNVector3(0, -11.5, -0.5), duration: 3.2), .wait(duration: 2.5)])))
            } else if name == "orb" {
                let a = SCNAction.sequence([.scale(to: 1.15, duration: 1.2), .scale(to: 0.9, duration: 1.2)]); a.timingMode = .easeInEaseOut
                n.runAction(.repeatForever(a))
            }
        }
        b.removeAllActions()
        startSway(b, dir: 1)
        p2.holdNode = SCNNode(); scene.rootNode.addChildNode(p2.holdNode); spin(p2.holdNode, phase: 0.9)
        for i in 0..<3 { let n = SCNNode(); scene.rootNode.addChildNode(n); p2.nextNodes.append(n); spin(n, phase: Double(i) * 0.7 + 0.4) }
        p2.panels = p1.panels.map { let n = $0.clone(); scene.rootNode.addChildNode(n); return n }
    }

    /// Rozstawienie plansz, podglądów, paneli i kamery dla 1 albo 2 graczy.
    func layout() {
        for n in [p2.board, p2.holdNode] + p2.nextNodes + p2.panels { n.isHidden = !twoP }
        func panel(_ n: SCNNode, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
            let g = SCNPlane(width: w, height: h); g.cornerRadius = 0.4
            if let m = n.geometry?.firstMaterial { g.materials = [m] }
            n.geometry = g; n.position = SCNVector3(x, y, -1.6)
        }
        if twoP {
            for (pl, sgn) in [(p1, CGFloat(-1)), (p2, CGFloat(1))] {
                pl.base = SCNVector3(8.6 * sgn, 0, 0)
                let x = 16.6 * sgn
                pl.holdNode.position = SCNVector3(x, 7.5, 0); pl.holdNode.scale = SCNVector3(0.8, 0.8, 0.8)
                for (i, (y, k)) in [(3.4, 0.8), (0.9, 0.6), (-1.3, 0.6)].enumerated() {
                    pl.nextNodes[i].position = SCNVector3(x, CGFloat(y), 0); pl.nextNodes[i].scale = SCNVector3(k, k, k)
                }
                panel(pl.panels[0], x, 7.6, 5, 4.2); panel(pl.panels[1], x, 0.9, 5, 7.6); panel(pl.panels[2], x, -6.9, 5, 6.6)
            }
            camNode.position = SCNVector3(0, 3.6, 45); camNode.look(at: SCNVector3(0, -0.6, 0))
        } else {
            p1.base = SCNVector3Zero
            p1.holdNode.position = SCNVector3(-10, 7.1, 0); p1.holdNode.scale = SCNVector3(1, 1, 1)
            for (i, (y, k)) in [(7.6, 1.0), (3.6, 0.72), (0.7, 0.72)].enumerated() {
                p1.nextNodes[i].position = SCNVector3(10, CGFloat(y), 0); p1.nextNodes[i].scale = SCNVector3(k, k, k)
            }
            panel(p1.panels[0], -10, 7.4, 5.6, 4.8); panel(p1.panels[1], -10, -0.6, 5.6, 9.6); panel(p1.panels[2], 10, 4.0, 5.6, 12)
            camNode.position = SCNVector3(0, 3.2, 36); camNode.look(at: SCNVector3(0, -0.4, 0))
        }
        for pl in [p1, p2] { pl.board.position = pl.base }
        camNode.removeAllActions()
        camHome = camNode.position; camLook = twoP ? SCNVector3(0, -0.6, 0) : SCNVector3(0, -0.4, 0)
    }

    /// 2/3/4 linie → 1/2/4 linie-śmieci u przeciwnika.
    func sendGarbage(_ n: Int) {
        guard twoP else { return }
        let g = [0, 0, 1, 2, 4][min(n, 4)]
        guard g > 0 else { return }
        let opp = cp === p1 ? p2 : p1
        opp.garbage += g
        hud.popup("+\(g) ▲", nsc(0xFF5A68), at: proj(opp.base.x, -5), size: view.bounds.height * 0.035, delay: 0.2)
    }

    /// Wsuwa od dołu linie-śmieci (z jedną dziurą) do planszy bieżącego gracza.
    func applyGarbage() {
        let n = cp.garbage
        guard n > 0 else { return }
        cp.garbage = 0
        for y in (Game.H - n)..<Game.H { for x in 0..<Game.W { cells[y][x]?.removeFromParentNode() } }
        var g = grid, c = cells
        for y in stride(from: Game.H - 1, through: 0, by: -1) {
            g[y] = y >= n ? grid[y - n] : [Int](repeating: -1, count: Game.W)
            c[y] = y >= n ? cells[y - n] : [SCNNode?](repeating: nil, count: Game.W)
        }
        let hole = Int.random(in: 0..<Game.W)
        for y in 0..<n { for x in 0..<Game.W where x != hole {
            g[y][x] = 7
            let node = SCNNode(geometry: grayGeo); node.castsShadow = true
            node.position = pos(x, y - n)
            board.addChildNode(node)
            c[y][x] = node
        } }
        grid = g; cells = c
        for y in 0..<Game.H { for x in 0..<Game.W {
            guard let node = cells[y][x] else { continue }
            let a = SCNAction.move(to: pos(x, y), duration: 0.2); a.timingMode = .easeOut
            node.runAction(a)
        } }
        sfx?.play(30, amp: 0.3, decay: 0.2)
        shake(0.15)
    }

    /// Spokojny finał: od góry klocki kolejno rozjarzają się własnym kolorem, lekko opadają i gasną.
    /// Bez wybuchów, wstrząsów i błysku. Zwraca czas, po którym można pokazać panel (≤ ok. 1,6 s).
    @discardableResult
    func finale(_ pl: Player) -> Double {
        if ProcessInfo.processInfo.environment["KLOCKI_TEST"] != nil { print("FINALE"); fflush(stdout) }
        let rows = (0..<Game.H).filter { y in pl.cells[y].contains { $0 != nil } }.reversed() as [Int]
        guard !rows.isEmpty else { return 0.9 }
        let step = min(0.045, 0.75 / Double(rows.count))
        for (i, y) in rows.enumerated() {
            for x in 0..<Game.W {
                guard let n = pl.cells[y][x] else { continue }
                let t = Double(i) * step + Double((x * 7) % 10) * 0.012
                let p0 = n.position
                let fade = SCNAction.customAction(duration: 0.7) { node, e in
                    let k = CGFloat(e) / 0.7, ease = k * k * (3 - 2 * k)
                    node.position = SCNVector3(p0.x, p0.y - 0.45 * ease, p0.z - 0.3 * ease)
                    node.opacity = 1 - ease
                    let sc = 1 - 0.18 * ease
                    node.scale = SCNVector3(sc, sc, sc)
                }
                let col = nsc(hexOf(pl.grid[y][x])).blended(withFraction: 0.25, of: .white)!
                n.runAction(.sequence([.wait(duration: t), .run { [weak self] node in      // klocek rozjarza się własnym kolorem
                    guard let self else { return }
                    let g = SCNNode(geometry: SCNPlane(width: 1, height: 1)); g.geometry?.materials = [self.glowMat(col)]
                    g.position = SCNVector3(0, 0, 0.55); g.scale = SCNVector3(0.8, 0.8, 0.8); g.opacity = 0
                    g.runAction(.group([.fadeOpacity(to: 0.8, duration: 0.25), .scale(to: 2.2, duration: 0.8)]))
                    node.addChildNode(g)
                }, .wait(duration: 0.12), fade, .hide()]))
            }
        }
        flashLight.light?.intensity = 0
        if !demoBG { camPush(toward: SCNVector3(pl.base.x, 2, 0), amount: 6, duration: 2.6, hold: 0.9) }   // powolny najazd na finał
        return min(1.6, Double(rows.count) * step + 0.95)
    }

    func versusOver() {
        let loser = cp
        state = .over
        for pl in active { cp = pl; hidePiece() }
        cp = loser
        loser.alive = false
        danger = 0
        music.gameOver()
        music.intensity = 0
        let tEnd = finale(loser)
        winner = loser === p1 ? 2 : 1
        entering = false
        let g0 = gen
        DispatchQueue.main.asyncAfter(deadline: .now() + tEnd) { [weak self] in
            guard let self, self.gen == g0, self.state == .over else { return }
            self.showVersus()
        }
    }

    func showVersus() {
        hud.openPanel(dim: 0.45)
        let w = view.bounds.width, h = view.bounds.height
        hud.card(w / 2, h * 0.5, h * 0.85, h * 0.44)
        let col = winner == 1 ? nsc(0x20DDF0) : nsc(0xFF8A1E)
        hud.put("WYGRYWA GRACZ \(winner)!", h * 0.06, w / 2, h * 0.64, col, font: "AvenirNext-Heavy", in: hud.panel)
        for (i, pl) in [p1, p2].enumerated() {
            hud.put("Gracz \(i + 1):   \(fmt(pl.score)) pkt   •   \(pl.lines) linii   •   poziom \(pl.level)", h * 0.024, w / 2, h * (0.555 - CGFloat(i) * 0.05),
                    i + 1 == winner ? .white : nsc(0x9AA4D8), font: "AvenirNext-Medium", in: hud.panel)
        }
        hud.put("ENTER — rewanż     ESC — menu", h * 0.022, w / 2, h * 0.37, nsc(0x8E97CC), font: "AvenirNext-Medium", in: hud.panel)
    }


    func fillQueue() {
        while queue.count < 3 {
            if bag.isEmpty { var b = Kind.allCases; for i in stride(from: b.count - 1, to: 0, by: -1) { b.swapAt(i, cp.random(i + 1)) }; bag = b }
            queue.append(bag.removeLast())
        }
    }

    func spawn(_ k: Kind) {
        spawnCount += 1
        cur = k; rot = 0; px = 3; py = 18
        fillQueue()
        fallT = 0; lockT = 0; lockResets = 0; lowest = 99
        guard fits(px, py, rot) else { gameOver(); return }
        if fits(px, py - 1, rot) { py -= 1 }
        for i in 0..<4 {
            pieceNodes[i].geometry = geo[k.rawValue]; pieceNodes[i].isHidden = false
            ghostNodes[i].geometry = ghostGeo[k.rawValue]
            beamNodes[i].geometry = beamGeo[k.rawValue]
        }
        pieceLight.light?.color = nsc(kindHex[k.rawValue])
        pieceLight.light?.intensity = 70
        syncPiece(snap: true, dt: 0)
        refreshPreviews()
        if !demoBG { music.intensity = min(1, Float(maxLevel - 1) / 14 + 0.08) }
    }

    func fits(_ x: Int, _ y: Int, _ r: Int) -> Bool {
        for (cx, cy) in shapes[cur.rawValue][r] {
            let gx = x + cx, gy = y + cy
            if gx < 0 || gx >= Game.W || gy < 0 { return false }
            if gy < Game.H && grid[gy][gx] >= 0 { return false }
        }
        return true
    }
    var grounded: Bool { !fits(px, py - 1, rot) }

    func afterMove() {
        if grounded && lockResets < 15 { lockT = 0; lockResets += 1 }
    }

    /// smuga: świecący ślad klocka w miejscu, które właśnie opuścił
    func afterimage(spin: Bool) {
        guard quality < 2, !demoBG || state == .playing else { return }
        for pn in pieceNodes where !pn.isHidden {
            let n = SCNNode(geometry: ghostGeo[cur.rawValue]); n.position = pn.position; n.opacity = spin ? 0.7 : 0.55
            let a = SCNAction.group([.fadeOut(duration: spin ? 0.22 : 0.16), .scale(to: spin ? 1.25 : 0.85, duration: spin ? 0.22 : 0.16)])
            n.runAction(.sequence([a, .removeFromParentNode()]))
            board.addChildNode(n)
        }
    }

    /// iskry i poświata pod lądującym klockiem
    func landFx(_ cellsXY: [(Int, Int)], kind: Int) {
        let col = nsc(hexOf(kind)).blended(withFraction: 0.35, of: .white)!
        for (x, y) in cellsXY where y < Game.H {
            let f = SCNNode(geometry: SCNPlane(width: 1, height: 1)); f.geometry?.materials = [glowMat(col)]
            f.position = SCNVector3(CGFloat(x) - 4.5, CGFloat(y) - 9.5, 0.6); f.scale = SCNVector3(1.1, 1.1, 1.1)
            let a = SCNAction.group([.scale(to: 2.4, duration: 0.28), .fadeOut(duration: 0.28)]); a.timingMode = .easeOut
            f.runAction(.sequence([a, .removeFromParentNode()]))
            board.addChildNode(f)
        }
        let low = cellsXY.map { $0.1 }.min() ?? 0
        let xs = cellsXY.filter { $0.1 == low }.map { CGFloat($0.0) - 4.5 }
        if !xs.isEmpty {
            let ps = SCNParticleSystem()
            ps.particleImage = spark
            ps.birthRate = 500 * fxQ; ps.emissionDuration = 0.04; ps.loops = false
            ps.particleLifeSpan = 0.35; ps.particleLifeSpanVariation = 0.15
            ps.particleVelocity = 3.5; ps.particleVelocityVariation = 2; ps.spreadingAngle = 80
            ps.emittingDirection = SCNVector3(0, 1, 0.3); ps.stretchFactor = 0.03
            ps.emitterShape = SCNBox(width: CGFloat(xs.count), height: 0.05, length: 0.6, chamferRadius: 0)
            ps.particleSize = 0.05; ps.particleColor = col; ps.blendMode = .additive; ps.acceleration = SCNVector3(0, -14, 0)
            let n = SCNNode(); n.position = SCNVector3(xs.reduce(0, +) / CGFloat(xs.count), CGFloat(low) - 10, 0.3); n.addParticleSystem(ps)
            board.addChildNode(n)
            n.runAction(.sequence([.wait(duration: 1), .removeFromParentNode()]))
        }
    }

    /// wir przy schowku
    func holdFx() {
        let p = cp.holdNode.position
        let col = nsc(hexOf(cur.rawValue))
        let t = SCNTorus(ringRadius: 1, pipeRadius: 0.05)
        let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = col; m.blendMode = .add; m.writesToDepthBuffer = false
        t.materials = [m]
        for (i, ax) in [CGFloat(0.5), -0.5].enumerated() {
            let n = SCNNode(geometry: t); n.position = p; n.eulerAngles = SCNVector3(.pi / 2 + ax, 0, ax)
            n.scale = SCNVector3(0.3, 0.3, 0.3)
            let a = SCNAction.group([.scale(to: 2.6, duration: 0.45), .fadeOut(duration: 0.45), .rotateBy(x: 0, y: 3, z: 0, duration: 0.45)]); a.timingMode = .easeOut
            n.runAction(.sequence([.wait(duration: Double(i) * 0.08), a, .removeFromParentNode()]))
            scene.rootNode.addChildNode(n)
        }
        let f = SCNNode(geometry: SCNPlane(width: 1, height: 1)); f.geometry?.materials = [glowMat(col.blended(withFraction: 0.4, of: .white)!)]
        f.position = p; f.constraints = [SCNBillboardConstraint()]; f.scale = SCNVector3(1, 1, 1)
        f.runAction(.sequence([.group([.scale(to: 5, duration: 0.35), .fadeOut(duration: 0.35)]), .removeFromParentNode()]))
        scene.rootNode.addChildNode(f)
    }

    /// combo i seria: pierścienie w kolejnych barwach, im dłuższa seria, tym więcej
    func comboFx(_ c: Int, row: Int) {
        let k = min(c, 6)
        for i in 0..<k {
            let col = NSColor(hue: CGFloat(i) / CGFloat(max(1, k)) * 0.8 + 0.05, saturation: 0.85, brightness: 1, alpha: 1)
            board.runAction(.sequence([.wait(duration: 0.07 * Double(i)), .run { [weak self] _ in
                DispatchQueue.main.async { SCNTransaction.lock(); self?.shockwave(row: row, color: col, big: i == k - 1); SCNTransaction.unlock() }
            }]))
        }
    }

    @discardableResult func move(_ d: Int) -> Bool {
        guard running, !cp.busy, cp.alive, fits(px + d, py, rot) else { return false }
        afterimage(spin: false)
        px += d
        afterMove()
        return true
    }

    func rotate(_ d: Int) {
        guard running, !cp.busy, cp.alive, cur != .O else { return }
        let nr = (rot + d + 4) % 4
        let table = cur == .I ? kicksI : kicksJ
        let ks = d > 0 ? table[rot] : table[nr].map { (-$0.0, -$0.1) }
        for (kx, ky) in ks where fits(px + kx, py + ky, nr) {
            afterimage(spin: true)
            px += kx; py += ky; rot = nr
            afterMove()
            sfx?.tick()
            return
        }
    }

    func holdPiece() {
        guard running, !cp.busy, cp.alive, !holdUsed else { return }
        let c = cur
        let next: Kind
        if let h = hold { next = h } else { next = queue.removeFirst() }
        hold = c
        holdUsed = true
        sfx?.holdSnd()
        if !demoBG { holdFx() }
        spawn(next)
    }

    func hardDrop() {
        guard running, !cp.busy, cp.alive else { return }
        let startY = py
        var d = 0
        while fits(px, py - 1, rot) { py -= 1; d += 1 }
        score += 2 * d
        syncPiece(snap: true, dt: 0)
        sfx?.drop()
        // smuga po zrzucie i pył przy lądowaniu
        if d > 0 {
            var cols: [Int: (lo: Int, hi: Int)] = [:]
            for (cx, cy) in shapes[cur.rawValue][rot] { let c = cols[cx]; cols[cx] = (min(c?.lo ?? 99, cy), max(c?.hi ?? -99, cy)) }
            for (cx, c) in cols {
                let top = CGFloat(startY + c.hi) - 9.5 + 0.5, bottom = CGFloat(py + c.lo) - 9.5 - 0.5
                let n = SCNNode(geometry: beamGeo[cur.rawValue])
                n.scale = SCNVector3(1.05, top - bottom, 1)
                n.position = SCNVector3(CGFloat(px + cx) - 4.5, (top + bottom) / 2, 0.1)
                n.eulerAngles.z = .pi                         // jasny koniec u dołu
                let fade = SCNAction.group([.fadeOut(duration: 0.35), .scale(to: 0.2, duration: 0.35)])
                n.runAction(.sequence([fade, .removeFromParentNode()]))
                n.scale = SCNVector3(1.05, top - bottom, 1)
                board.addChildNode(n)
            }
            let lowest = shapes[cur.rawValue][rot].map { $0.1 }.min()! + py
            dust(at: SCNVector3(CGFloat(px) - 3.5 + 0.5, CGFloat(lowest) - 10, 0.4), color: nsc(kindHex[cur.rawValue]))
        }
        shake(0.12 + min(0.2, CGFloat(d) * 0.012))
        lockPiece()
    }

    func shake(_ amt: CGFloat) {
        guard shakeOn else { return }
        board.removeAction(forKey: "shake")
        board.position = cp.base
        let s = SCNAction.sequence([.moveBy(x: 0, y: -amt, z: 0, duration: 0.04), .moveBy(x: amt * 0.4, y: amt * 1.3, z: 0, duration: 0.06),
                                    .moveBy(x: -amt * 0.4, y: -amt * 0.3, z: 0, duration: 0.1), .move(to: cp.base, duration: 0.08)])
        board.runAction(s, forKey: "shake")
    }

    func dust(at p: SCNVector3, color: NSColor) {
        let ps = SCNParticleSystem()
        ps.particleImage = spark
        ps.birthRate = 900 * fxQ; ps.emissionDuration = 0.05; ps.loops = false
        ps.particleLifeSpan = 0.5; ps.particleLifeSpanVariation = 0.2
        ps.particleVelocity = 4; ps.particleVelocityVariation = 2; ps.spreadingAngle = 70
        ps.emittingDirection = SCNVector3(0, 1, 0)
        ps.emitterShape = SCNBox(width: 3, height: 0.1, length: 0.6, chamferRadius: 0)
        ps.particleSize = 0.1; ps.particleSizeVariation = 0.05
        ps.particleColor = color.blended(withFraction: 0.5, of: .white)!
        ps.blendMode = .additive
        ps.acceleration = SCNVector3(0, -12, 0)
        let n = SCNNode(); n.position = p; n.addParticleSystem(ps)
        board.addChildNode(n)
        n.runAction(.sequence([.wait(duration: 1.5), .removeFromParentNode()]))
    }

    /// Baner za 4 linie naraz: kolorowe, podskakujące litery.
    func quadBanner(at p: CGPoint) {
        let h = view.bounds.height
        let size = h * 0.085
        let text = Array("SUPER!")
        let n = SKNode()
        n.position = CGPoint(x: twoP ? p.x : p.x, y: p.y + h * 0.03)
        let probe = text.map { hud.text(String($0), size, .white, font: "AvenirNext-Heavy") }
        let gap = size * 0.04
        let total = probe.reduce(0) { $0 + $1.frame.width } + gap * CGFloat(text.count - 1)
        var x = -total / 2
        let order = [0, 6, 1, 3, 5, 2, 4]
        for (i, ch) in text.enumerated() {
            let w = probe[i].frame.width
            let l = SKNode()
            l.position = CGPoint(x: x + w / 2, y: 0)
            hud.put(String(ch), size, 0, 0, nsc(kindHex[order[i % 7]]), font: "AvenirNext-Heavy", in: l)
            let hop = SKAction.sequence([.wait(forDuration: 0.25 + Double(i) * 0.05), .moveBy(x: 0, y: size * 0.35, duration: 0.12), .moveBy(x: 0, y: -size * 0.35, duration: 0.16)])
            l.run(.sequence([hop, .wait(forDuration: 0.25), hop]))
            n.addChild(l)
            x += w + gap
        }
        // poświata pod napisem
        let glow = SKSpriteNode(texture: SKTexture(cgImage: makeImage(256, 64) { ctx in
            ctx.drawRadialGradient(gradient([CGColor(gray: 1, alpha: 0.55), CGColor(gray: 1, alpha: 0)], [0, 1]), startCenter: CGPoint(x: 128, y: 32), startRadius: 0,
                                   endCenter: CGPoint(x: 128, y: 32), endRadius: 128, options: [])
        }), size: CGSize(width: total * 1.5, height: size * 1.6))
        glow.blendMode = .add; glow.zPosition = -1; glow.alpha = 0.6
        n.addChild(glow)
        n.setScale(0.2); n.alpha = 0
        let pop = SKAction.sequence([.group([.fadeIn(withDuration: 0.12), .scale(to: 1.15, duration: 0.2)]), .scale(to: 1, duration: 0.12)])
        n.run(.sequence([pop, .wait(forDuration: 1.3), .group([.fadeOut(withDuration: 0.35), .scale(to: 1.35, duration: 0.35)]), .removeFromParent()]))
        hud.fx.addChild(n)
    }

    var fxQ: CGFloat { [1, 0.6, 0.3][quality] }      // mniej cząstek przy niższej jakości

    func glowMat(_ c: NSColor) -> SCNMaterial {
        let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = spark; m.multiply.contents = c
        m.blendMode = .add; m.writesToDepthBuffer = false; m.readsFromDepthBuffer = false
        return m
    }

    /// Wybuch przy zbiciu linii: flara, smugi laserowe, kula uderzeniowa, żar, światło, aberracja.
    func explode(rows full: [Int], power: CGFloat, color: NSColor) {
        let n = full.count
        if ProcessInfo.processInfo.environment["KLOCKI_TEST"] != nil { print("EXPLODE", power); fflush(stdout) }
        let midY = CGFloat(full.reduce(0, +)) / CGFloat(n) - 9.5
        let hot = color.blended(withFraction: 0.45, of: .white)!
        // 1. flara
        let fp = SCNPlane(width: 1, height: 1); fp.materials = [glowMat(hot)]
        let flare = SCNNode(geometry: fp); flare.position = SCNVector3(0, midY, 1.4)
        flare.constraints = [SCNBillboardConstraint()]; flare.scale = SCNVector3(1.5, 1.5, 1.5)
        let fa = SCNAction.group([.scale(to: 7 + 4 * power, duration: 0.4), .sequence([.wait(duration: 0.06), .fadeOut(duration: 0.34)])]); fa.timingMode = .easeOut
        flare.runAction(.sequence([fa, .removeFromParentNode()]))
        board.addChildNode(flare)
        // 2. smugi laserowe wzdłuż każdego wiersza
        for y in full {
            let sp = SCNPlane(width: 13, height: 0.9); sp.materials = [glowMat(hot)]
            let st = SCNNode(geometry: sp); st.position = SCNVector3(0, CGFloat(y) - 9.5, 0.9)
            st.scale = SCNVector3(0.05, 1, 1)
            let grow = SCNAction.customAction(duration: 0.45) { node, e in
                let k = CGFloat(e) / 0.45
                node.scale = SCNVector3(0.05 + 1.6 * min(1, k * 3), 1.4 * (1 - k) + 0.1, 1)
                node.opacity = 1 - k * k
            }
            st.runAction(.sequence([grow, .removeFromParentNode()]))
            board.addChildNode(st)
        }
        // 3. kula uderzeniowa i druga fala (3+ linie albo combo)
        if power >= 3 {
            let sph = SCNSphere(radius: 1); sph.segmentCount = 32
            let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = hot; m.blendMode = .add
            m.writesToDepthBuffer = false; m.isDoubleSided = true
            m.shaderModifiers = [.fragment: "float rimF = pow(1.0 - abs(dot(_surface.normal, _surface.view)), 2.5); _output.color.rgb *= rimF;"]
            sph.materials = [m]
            let sn = SCNNode(geometry: sph); sn.position = SCNVector3(0, midY, 0.5); sn.scale = SCNVector3(0.4, 0.4, 0.4)
            let sa = SCNAction.group([.scale(to: 5 + 2.5 * power, duration: 0.7), .fadeOut(duration: 0.7)]); sa.timingMode = .easeOut
            sn.runAction(.sequence([sa, .removeFromParentNode()]))
            board.addChildNode(sn)
            let c2 = NSColor(hue: (color.usingColorSpace(.sRGB)!.hueComponent + 0.5).truncatingRemainder(dividingBy: 1), saturation: 0.8, brightness: 1, alpha: 1)
            board.runAction(.sequence([.wait(duration: 0.12), .run { [weak self] _ in
                DispatchQueue.main.async { SCNTransaction.lock(); self?.shockwave(row: Int(midY + 9.5), color: c2, big: true); SCNTransaction.unlock() }
            }]))
        }
        // 4. żar unoszący się w górę
        let ps = SCNParticleSystem()
        ps.particleImage = spark
        ps.birthRate = (400 + 350 * power) * fxQ; ps.emissionDuration = 0.15; ps.loops = false
        ps.particleLifeSpan = 1.8; ps.particleLifeSpanVariation = 0.8
        ps.particleVelocity = 1.5; ps.particleVelocityVariation = 1.5; ps.spreadingAngle = 60
        ps.emittingDirection = SCNVector3(0, 1, 0.4)
        ps.emitterShape = SCNBox(width: 10, height: CGFloat(n), length: 0.6, chamferRadius: 0)
        ps.particleSize = 0.07; ps.particleSizeVariation = 0.05
        ps.particleColor = hot; ps.particleColorVariation = SCNVector4(0.15, 0.2, 0, 0)
        ps.blendMode = .additive
        ps.acceleration = SCNVector3(0, 1.6, 0); ps.dampingFactor = 0.6
        let en = SCNNode(); en.position = SCNVector3(0, midY, 0.6); en.addParticleSystem(ps)
        board.addChildNode(en)
        en.runAction(.sequence([.wait(duration: 3), .removeFromParentNode()]))
        // 5. kolorowe światło i aberracja chromatyczna
        flashLight.light?.color = hot
        if let cam = camNode.camera, quality < 2, power >= 2 {
            cam.colorFringeStrength = min(4, 0.8 * power)
            SCNTransaction.begin(); SCNTransaction.animationDuration = 0.7; cam.colorFringeStrength = 0; SCNTransaction.commit()
        }
    }

    /// Szarpnięcie kamery: przybliżenie i przechył (sumuje się do zera).
    func camKick(_ power: CGFloat) {
        guard shakeOn else { return }
        let r = 0.012 * power, z = 0.35 * power
        let roll = SCNAction.sequence([.rotateBy(x: 0, y: 0, z: r, duration: 0.05), .rotateBy(x: 0, y: 0, z: -2 * r, duration: 0.1),
                                       .rotateBy(x: 0, y: 0, z: r * 1.4, duration: 0.1), .rotateBy(x: 0, y: 0, z: -r * 0.4, duration: 0.14)])
        let push = SCNAction.sequence([.moveBy(x: 0, y: 0, z: -z, duration: 0.06), .moveBy(x: 0, y: 0, z: z, duration: 0.4)])
        push.timingMode = .easeOut
        camNode.runAction(.group([roll, push]))
    }

    /// Obrót całej planszy 3D: przy awansie pełny obrót, przy 4 liniach obrót z przechyłem i „beczką”.
    func boardFlip(big: Bool) {
        guard shakeOn else { return }
        let b = board
        guard b.action(forKey: "flip") == nil else { return }
        b.removeAction(forKey: "sway")
        let s0 = b.eulerAngles
        let d = big ? 1.35 : 1.1
        let dir: CGFloat = cp === p2 ? -1 : 1
        let flip = SCNAction.customAction(duration: d) { node, e in
            let k = CGFloat(e) / CGFloat(d)
            let ease = k < 0.5 ? 4 * k * k * k : 1 - pow(-2 * k + 2, 3) / 2       // easeInOutCubic
            let bell = sin(k * .pi)
            node.eulerAngles = SCNVector3(s0.x + bell * (big ? -0.42 : 0.18),
                                          s0.y + dir * 2 * .pi * ease,
                                          s0.z + (big ? sin(k * 2 * .pi) * 0.14 * dir : 0))
            let sc = 1 - bell * (big ? 0.1 : 0.06)
            node.scale = SCNVector3(sc, sc, sc)
        }
        let isP2 = cp === p2
        b.runAction(.sequence([flip, .run { [weak self] node in
            node.eulerAngles = s0; node.scale = SCNVector3(1, 1, 1)
            DispatchQueue.main.async { SCNTransaction.lock(); self?.startSway(node, dir: isP2 ? 1 : -1, lead: 2); SCNTransaction.unlock() }
        }]), forKey: "flip")
    }

    func shockwave(row y: Int, color: NSColor, big: Bool) {
        let t = SCNTorus(ringRadius: 1, pipeRadius: 0.04)
        let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = color; m.blendMode = .add; m.writesToDepthBuffer = false
        t.materials = [m]
        let n = SCNNode(geometry: t)
        n.eulerAngles.x = .pi / 2
        n.position = SCNVector3(0, CGFloat(y) - 9.5, 0.6)
        n.scale = SCNVector3(0.3, 0.3, 0.3)
        let s: CGFloat = big ? 16 : 8
        let a = SCNAction.group([.scale(to: s, duration: big ? 0.9 : 0.6), .fadeOut(duration: big ? 0.9 : 0.6)]); a.timingMode = .easeOut
        n.runAction(.sequence([a, .removeFromParentNode()]))
        board.addChildNode(n)
    }

    func hidePiece() {
        pieceNodes.forEach { $0.isHidden = true }
        ghostNodes.forEach { $0.isHidden = true }
        beamNodes.forEach { $0.isHidden = true }
        pieceLight.light?.intensity = 0
    }

    func lockPiece() {
        var above = true
        for (cx, cy) in shapes[cur.rawValue][rot] {
            let x = px + cx, y = py + cy
            if y < 20 { above = false }
            guard y < Game.H else { continue }
            grid[y][x] = cur.rawValue
            let n = SCNNode(geometry: geo[cur.rawValue]); n.castsShadow = true
            n.position = pos(x, y)
            n.scale = SCNVector3(1.1, 1.1, 1.1)
            n.runAction(.scale(to: 1, duration: 0.15))
            board.addChildNode(n)
            cells[y][x] = n
        }
        hidePiece()
        sfx?.thud()
        if above { gameOver(); return }
        landFx(shapes[cur.rawValue][rot].map { (px + $0.0, py + $0.1) }, kind: cur.rawValue)
        holdUsed = false
        let full = (0..<Game.H).filter { y in grid[y].allSatisfy { $0 >= 0 } }
        if full.isEmpty {
            combo = -1
            refreshStats()
            applyGarbage()
            spawn(queue.removeFirst())
        } else {
            clearLines(full)
        }
    }

    func clearLines(_ full: [Int]) {
        cp.busy = true
        let n = full.count
        for y in full {
            for x in 0..<Game.W {
                guard let c = cells[y][x] else { continue }
                let d = abs(Double(x) - 4.5) * 0.018
                let k = grid[y][x]
                c.runAction(.sequence([.wait(duration: d), .run { $0.geometry = self.flashGeo },
                                       .scale(to: 1.18, duration: 0.08),
                                       .run { [weak self] node in DispatchQueue.main.async { self?.shatter(node, kind: k) } }]))
            }
            let col = nsc(hexOf(grid[y][Int.random(in: 0..<Game.W)]))
            burst(row: y, color: col, rainbow: n == 4)
            shockwave(row: y, color: col, big: n == 4)
        }
        flashLight.position = SCNVector3(cp.base.x, 0, 7)
        if let l = flashLight.light {
            l.intensity = CGFloat(600 + 500 * n)
            SCNTransaction.begin(); SCNTransaction.animationDuration = 0.5; l.intensity = 0; SCNTransaction.commit()
        }
        if let cam = camNode.camera {
            cam.bloomIntensity = baseBloom + 0.4 * CGFloat(n)
            SCNTransaction.begin(); SCNTransaction.animationDuration = 0.8; cam.bloomIntensity = baseBloom; SCNTransaction.commit()
        }
        hud.flash(n == 4 ? 0.35 : 0.08 * CGFloat(n), color: n == 4 ? nsc(0xBFF6FF) : .white)
        var pts = [0, 100, 300, 500, 800][n] * level
        if n == 4 { if b2b { pts = pts * 3 / 2 }; b2b = true } else { b2b = false }
        combo += 1
        // siła wybuchu: liczba linii + combo
        let power = CGFloat(n) + CGFloat(max(0, combo)) * 0.6
        explode(rows: full, power: power, color: nsc(hexOf(grid[full[0]][Int.random(in: 0..<Game.W)])))
        shake(0.1 + 0.08 * power)
        if n >= 3 || combo > 0 { camKick(power) }
        if n == 4 && !demoBG { boardFlip(big: true) }
        if combo >= 1 { comboFx(combo, row: full[0]) }
        if combo > 0 { pts += 50 * combo * level }
        score += pts
        lines += n
        sfx?.clear(n)
        sendGarbage(n)

        let h = view.bounds.height
        let p = proj(cp.base.x, 3)
        let label = ["", "", "PODWÓJNA!", "POTRÓJNA!", "CZTERY LINIE!"][n]
        let showFx = !demoBG || state == .playing
        if showFx && n == 4 { quadBanner(at: p) } else if showFx && !label.isEmpty { hud.popup(label, n == 4 ? nsc(0x20DDF0) : nsc(0xFFD21F), at: p, size: h * (n == 4 ? 0.06 : 0.045)) }
        if showFx && combo > 0 { hud.popup("COMBO ×\(combo)", nsc(0xFF8A1E), at: CGPoint(x: p.x, y: p.y - h * 0.07), size: h * 0.032, delay: 0.1) }
        if showFx { scoreFly(pts, from: CGPoint(x: p.x, y: p.y - h * 0.12), player: cp.id); bgWave(color: nsc(hexOf(grid[full[0]][0])), power: power) }

        let newLevel = lines / 10 + (demoBG ? 1 : startLevel)
        if newLevel > level {
            level = newLevel
            setRimColors()
            setTheme(maxLevel - 1)
            levelWave()
            if !demoBG { bgWave(color: nsc(0x37DE58), power: 4); boardFlip(big: false); camPush(toward: SCNVector3(cp.base.x, 0, 0), amount: 7, duration: 1.6, hold: 0.3) }
            let song = (maxLevel - 1) % Music.songs.count
            if song != music.song && musicMode == 0 && !demoBG && songPick == 0 {
                music.song = song
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [self] in
                    hud.popup("♪ " + Music.songs[song].name, nsc(0x9AA4D8), at: CGPoint(x: view.bounds.width / 2, y: view.bounds.height * 0.9), size: view.bounds.height * 0.024)
                }
            }
            let lvl = level, bx = cp.base.x
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [self] in
                sfx?.levelUp()
                hud.popup("POZIOM \(lvl)", nsc(0x37DE58), at: proj(bx, 7), size: h * 0.055)
            }
        }
        refreshStats()
        let who = cp, g0 = gen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) { [weak self] in
            guard let self, self.gen == g0 else { return }
            self.cp = who
            self.collapse(full)
        }
    }

    func collapse(_ full: [Int]) {
        guard cp.busy else { return }
        let who = cp, g0 = gen
        var g: [[Int]] = [], c: [[SCNNode?]] = []
        for y in 0..<Game.H where !full.contains(y) { g.append(grid[y]); c.append(cells[y]) }
        while g.count < Game.H { g.append([Int](repeating: -1, count: Game.W)); c.append([SCNNode?](repeating: nil, count: Game.W)) }
        grid = g; cells = c
        var maxT = 0.0
        for y in 0..<Game.H {
            for x in 0..<Game.W {
                guard let n = cells[y][x] else { continue }
                let p = pos(x, y)
                let dist = Double(n.position.y - p.y)
                if dist > 0.01 {
                    let t = 0.1 + sqrt(dist) * 0.085
                    let delay = Double(x) * 0.014 + Double(y) * 0.012
                    let fall = SCNAction.move(to: p, duration: t); fall.timingMode = .easeIn
                    let squash = SCNAction.customAction(duration: 0.22) { node, e in
                        let k = CGFloat(e) / 0.22, a = sin(k * .pi) * 0.22 * (1 - k * 0.5)
                        node.scale = SCNVector3(1 + a, 1 - a, 1 + a)
                    }
                    let hop = SCNAction.sequence([.moveBy(x: 0, y: 0.14, z: 0, duration: 0.08), .move(to: p, duration: 0.09)])
                    n.runAction(.sequence([.wait(duration: delay), fall, .group([squash, hop]), .run { $0.scale = SCNVector3(1, 1, 1) }]))
                    maxT = max(maxT, delay + t)
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + maxT) { [weak self] in
            guard let self, maxT > 0, self.gen == g0 else { return }
            self.cp = who
            self.sfx?.thud()
            self.shake(0.08 + 0.04 * CGFloat(full.count))
            self.dust(at: SCNVector3(0, -10, 0.5), color: .white)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + min(0.45, maxT) + 0.05) { [weak self] in
            guard let self, self.gen == g0, who.busy, who.alive, self.state != .over else { return }
            self.cp = who
            who.busy = false
            self.applyGarbage()
            self.spawn(self.queue.removeFirst())
        }
    }

    /// Klocek pęka na 8 odłamków, które koziołkują w stronę gracza.
    func shatter(_ node: SCNNode, kind: Int) {
        let p = node.position
        let parentNode = node.parent ?? board
        node.removeFromParentNode()
        for ox in [-0.24, 0.24] as [CGFloat] { for oy in [-0.24, 0.24] as [CGFloat] { for oz in [-0.24, 0.24] as [CGFloat] {
            let f = SCNNode(geometry: debrisGeo[min(kind, debrisGeo.count - 1)]); f.scale = SCNVector3(0.44, 0.44, 0.44); f.castsShadow = false
            f.position = SCNVector3(p.x + ox, p.y + oy, p.z + oz)
            let v = SCNVector3(ox * 16 + p.x * 0.8 + .random(in: -2...2), .random(in: 5...12) + oy * 10, .random(in: 4...15) + oz * 8)
            let w = SCNVector3(.random(in: -10...10), .random(in: -10...10), .random(in: -10...10))
            parentNode.addChildNode(f)
            debris.append((f, v, w, .random(in: 0.9...1.5)))
        } } }
    }

    func burst(row y: Int, color: NSColor, rainbow: Bool) {
        let ps = SCNParticleSystem()
        if rainbow { ps.particleColorVariation = SCNVector4(1, 0.2, 0, 0) }
        ps.particleImage = spark
        ps.birthRate = 2500 * fxQ; ps.emissionDuration = 0.08; ps.loops = false
        ps.stretchFactor = 0.035                       // iskry rozciągnięte w smugi
        ps.particleLifeSpan = 0.9; ps.particleLifeSpanVariation = 0.4
        ps.particleVelocity = 6; ps.particleVelocityVariation = 4; ps.spreadingAngle = 180
        ps.emitterShape = SCNBox(width: 10, height: 0.8, length: 0.8, chamferRadius: 0)
        ps.particleSize = 0.16; ps.particleSizeVariation = 0.08
        ps.particleColor = color.blended(withFraction: 0.3, of: .white)!
        ps.blendMode = .additive
        ps.acceleration = SCNVector3(0, -9, 0)
        let n = SCNNode(); n.position = SCNVector3(0, CGFloat(y) - 9.5, 0.3)
        n.addParticleSystem(ps)
        board.addChildNode(n)
        n.runAction(.sequence([.wait(duration: 2.5), .removeFromParentNode()]))
    }

    /// Fala światła przez cały stos przy awansie na wyższy poziom.
    func levelWave() {
        for y in 0..<Game.H { for x in 0..<Game.W {
            guard let n = cells[y][x], grid[y][x] >= 0 else { continue }
            let g = geo[grid[y][x]]
            let up = SCNAction.scale(to: 1.18, duration: 0.1), down = SCNAction.scale(to: 1, duration: 0.2)
            n.runAction(.sequence([.wait(duration: Double(y) * 0.035 + Double(x) * 0.01),
                                   .run { $0.geometry = self.flashGeo }, up, .run { $0.geometry = g }, down]))
        } }
    }

    func dangerEmbers(_ pl: Player, top: Int) {
        let ps = SCNParticleSystem()
        ps.particleImage = spark
        ps.birthRate = 160 * fxQ; ps.emissionDuration = 0.2; ps.loops = false
        ps.particleLifeSpan = 1.2; ps.particleLifeSpanVariation = 0.5
        ps.particleVelocity = 2.2; ps.particleVelocityVariation = 1; ps.spreadingAngle = 25
        ps.emittingDirection = SCNVector3(0, 1, 0.2)
        ps.emitterShape = SCNBox(width: 10, height: 0.3, length: 0.8, chamferRadius: 0)
        ps.particleSize = 0.06; ps.particleSizeVariation = 0.04
        ps.particleColor = nsc(0xFF4A2A); ps.particleColorVariation = SCNVector4(0.05, 0.2, 0, 0)
        ps.blendMode = .additive; ps.acceleration = SCNVector3(0, 1.2, 0)
        let n = SCNNode(); n.position = SCNVector3(0, CGFloat(top) - 9.8, 0.3); n.addParticleSystem(ps)
        pl.board.addChildNode(n)
        n.runAction(.sequence([.wait(duration: 2), .removeFromParentNode()]))
    }

    func setRimColors() {
        let hue = (0.55 + CGFloat(maxLevel - 1) * 0.085).truncatingRemainder(dividingBy: 1)
        for (k, hh) in [hue, (hue + 0.33).truncatingRemainder(dividingBy: 1)].enumerated() {
            let c = NSColor(hue: hh, saturation: k == 0 ? 0.8 : 0.75, brightness: 1, alpha: 1).usingColorSpace(.sRGB)!
            rimBase[k] = SIMD3<Float>(Float(c.redComponent), Float(c.greenComponent), Float(c.blueComponent))
        }
        SCNTransaction.begin(); SCNTransaction.animationDuration = 1.5
        rimA.light?.color = NSColor(hue: hue, saturation: 0.8, brightness: 1, alpha: 1)
        rimB.light?.color = NSColor(hue: (hue + 0.33).truncatingRemainder(dividingBy: 1), saturation: 0.75, brightness: 1, alpha: 1)
        SCNTransaction.commit()
    }

    func gameOver() {
        if demoBG { startBGDemo(); return }
        guard state != .over else { return }
        if twoP { versusOver(); return }
        state = .over
        hidePiece()
        danger = 0
        music.gameOver()
        music.intensity = 0
        let tEnd = finale(cp)
        entering = Records.qualifies(score)
        name = UserDefaults.standard.string(forKey: "imie") ?? ""
        DispatchQueue.main.asyncAfter(deadline: .now() + tEnd) { [weak self] in
            guard let self, self.state == .over else { return }
            self.showOver()
        }
    }

    func saveRecord() {
        let n = name.trimmingCharacters(in: .whitespaces)
        let rec = Record(name: n.isEmpty ? "Gracz" : n, score: score, lines: lines, level: level, date: Date(), diff: difficulty)
        UserDefaults.standard.set(rec.name, forKey: "imie")
        let idx = Records.insert(rec)
        best = Records.load().first?.score ?? 0
        entering = false
        showScores(highlight: idx)
    }

    func syncPiece(snap: Bool, dt: Double) {
        guard running else { return }
        let cs = shapes[cur.rawValue][rot]
        var gy = py
        while fits(px, gy - 1, rot) { gy -= 1 }
        let a = CGFloat(snap ? 1 : 1 - exp(-dt * 30))
        // płynne opadanie: klocek sunie między wierszami zamiast przeskakiwać
        let off: CGFloat = snap || grounded ? 0 : CGFloat(min(0.999, fallT / currentG))
        var sx: CGFloat = 0, sy: CGFloat = 0
        for i in 0..<4 {
            let (cx, cy) = cs[i]
            var t = pos(px + cx, py + cy); t.y -= off
            let n = pieceNodes[i]
            let p = n.position
            n.position = SCNVector3(p.x + (t.x - p.x) * a, p.y + (t.y - p.y) * a, 0)
            sx += n.position.x / 4; sy += n.position.y / 4
            ghostNodes[i].position = pos(px + cx, gy + cy)
            ghostNodes[i].isHidden = gy == py
        }
        // promienie: w każdej kolumnie od spodu klocka do wierzchu cienia
        var cols: [Int: (lo: Int, hi: Int)] = [:]
        for (cx, cy) in cs { let c = cols[cx]; cols[cx] = (min(c?.lo ?? 99, cy), max(c?.hi ?? -99, cy)) }
        let keys = cols.keys.sorted()
        for i in 0..<4 {
            let b = beamNodes[i]
            guard i < keys.count, let c = cols[keys[i]] else { b.isHidden = true; continue }
            let top = CGFloat(py + c.lo) - 9.5 - 0.5, bottom = CGFloat(gy + c.hi) - 9.5 + 0.5
            let h = top - bottom
            b.isHidden = h <= 0.05
            b.scale = SCNVector3(1, max(0.01, h), 1)
            b.position = SCNVector3(CGFloat(px + keys[i]) - 4.5, (top + bottom) / 2, -0.4)
            b.opacity = softDrop ? 1 : 0.75
        }
        pieceLight.position = SCNVector3(sx, sy, 2.2)
    }

    /// ↓ — ok. 7 wierszy na sekundę
    var currentG: Double {
        if demoBG { return softDrop ? 0.05 : max(gravity, 0.6) }       // demo zawsze w spokojnym tempie
        return softDrop ? min(gravity, [0.25, 0.14, 0.07][softSet]) : gravity
    }
    /// sekundy na wiersz: szybszy start (1–3), od poziomu 8 bardzo stromo; mnożnik trudności (demo bez niego)
    var gravity: Double {
        let L = Double(max(1, level))
        var g = L < 8 ? 0.72 * pow(0.80, L - 1) : 0.72 * pow(0.80, 6) * pow(0.55, L - 7)
        if !demoBG { g /= diffSpeed }
        return max(0.004, g)
    }

    func update() {
        SCNTransaction.lock(); defer { SCNTransaction.unlock() }
        let now = CACurrentMediaTime()
        let rawDt = now - lastTime
        let dt = min(0.05, rawDt)
        lastTime = now
        clock += dt
        if statsDirty && clock - lastStats > 0.12 { refreshStats() }
        attractTick(dt)
        countScores(dt)

        if clock < camAnimUntil && ProcessInfo.processInfo.environment["KLOCKI_NOREF"] == nil { refreshStats() }                 // napisy podążają za kamerą w czasie najazdu
        bgKick *= CGFloat(exp(-dt * 1.6))
        // tło: klocki dryfują w górę i obracają się
        let boost: CGFloat = (state == .playing ? 1 + CGFloat(maxLevel - 1) * 0.12 : 0.6) + bgKick * 5
        for f in floaters {
            var p = f.node.position
            p.y += f.speed * boost * CGFloat(dt)
            if p.y > 36 { p.y = -36; p.x = CGFloat.random(in: -60...60) }
            f.node.position = p
            f.node.eulerAngles.y += f.spin * (1 + bgKick * 6) * CGFloat(dt)
            f.node.eulerAngles.x += f.spin * 0.5 * CGFloat(dt)
        }
        // odłamki
        for i in debris.indices.reversed() {
            var d = debris[i]
            d.life -= dt
            if d.life <= 0 { d.n.removeFromParentNode(); debris.remove(at: i); continue }
            let t = CGFloat(dt)
            d.v.y -= 30 * t
            d.n.position = SCNVector3(d.n.position.x + d.v.x * t, d.n.position.y + d.v.y * t, d.n.position.z + d.v.z * t)
            d.n.eulerAngles = SCNVector3(d.n.eulerAngles.x + d.w.x * t, d.n.eulerAngles.y + d.w.y * t, d.n.eulerAngles.z + d.w.z * t)
            d.n.opacity = CGFloat(min(1, d.life / 0.4))
            debris[i] = d
        }
        // puls do rytmu muzyki
        let bp = musicMode == 2 ? clock * 2 : Double(music.beatPos)
        let pulse = CGFloat(exp(-(bp - floor(bp)) * 5))
        let lv = state == .playing || state == .clearing ? min(1, CGFloat(maxLevel - 1) / 10) : 0.2
        wallMat.emission.intensity = 0.35 + pulse * (0.25 + 0.35 * lv)
        for g in geo { g.firstMaterial?.emission.intensity = 0.07 + pulse * 0.07 }
        neonMat.emission.intensity = 0.75 + pulse * (0.5 + 0.6 * lv)                      // listwy pulsują do rytmu
        if ProcessInfo.processInfo.environment["KLOCKI_TEST"] != nil {
            fpsN += 1; fpsT += rawDt; worstDt = max(worstDt, rawDt)
            if fpsT >= 1 { print(String(format: "t=%.1f FPS %d najgorsza %.0f ms stan %@ odlamki %d", clock, Int(Double(fpsN) / fpsT), worstDt * 1000, "\(state)", debris.count)); fflush(stdout); fpsN = 0; fpsT = 0; worstDt = 0 }
        }
        rays.opacity = 0.35 + pulse * (0.25 + 0.3 * lv)
        rays2.opacity = 0.25 + (1 - pulse) * 0.2
        // spadające gwiazdy
        nextStar -= dt
        if nextStar <= 0 { nextStar = .random(in: 0.8...3.0) / Double(1 + lv); shootingStar() }

        // zagrożenie: czerwona poświata, gdy stos sięga wysoko
        var top = 0
        if state == .playing || state == .clearing {
            for pl in active { for y in stride(from: Game.H - 1, through: 0, by: -1) where pl.grid[y].contains(where: { $0 >= 0 }) { top = max(top, y + 1); break } }
        }
        let target = max(0, min(1, CGFloat(top - 12) / 6))
        danger += (target - danger) * CGFloat(min(1, dt * 3))
        hud.danger.alpha = danger * (0.55 + 0.35 * CGFloat(sin(clock * (3 + 4 * Double(danger)))))
        // napięcie: światła boczne czerwienieją z bijącym pulsem, ze stosu unosi się czerwony żar
        let beatD = Float(danger) * Float(0.6 + 0.4 * sin(clock * (4 + 5 * Double(danger))))
        for (k, n) in [rimA, rimB].enumerated() {
            let tgt = rimBase[k] * (1 - beatD) + SIMD3<Float>(1, 0.12, 0.08) * beatD
            rimCur[k] += (tgt - rimCur[k]) * Float(min(1, dt * 4))
            n.light?.color = NSColor(srgbRed: CGFloat(rimCur[k].x), green: CGFloat(rimCur[k].y), blue: CGFloat(rimCur[k].z), alpha: 1)
        }
        emberT -= dt
        if danger > 0.25 && emberT <= 0 && (state == .playing) {
            emberT = 0.35 / Double(danger)
            for pl in active where pl.alive { dangerEmbers(pl, top: top) }
        }

        if demoBG && running { aiT += dt; if aiT > 0.14 { aiT = 0; cp = p1; aiStep() } }
        guard running else { return }
        for pl in active where pl.alive && !pl.busy {
            cp = pl
            step(dt)
            if !running { return }
        }
    }

    func step(_ dt: Double) {
        // DAS / ARR
        let dir = leftHeld && !rightHeld ? -1 : rightHeld && !leftHeld ? 1 : (leftHeld && rightHeld ? lastDir : 0)
        if dir != lastDir { dasT = 0; arrT = 0 }
        if dir != 0 {
            dasT += dt
            let arrV = [0.022, 0.033, 0.05][dasSet]
            if dasT >= [0.10, 0.15, 0.22][dasSet] {
                arrT += dt
                while arrT >= arrV { arrT -= arrV; if !move(dir) { arrT = 0; break } }
            }
        }

        // grawitacja
        let g = currentG
        fallT += dt
        while fallT >= g && !grounded {
            fallT -= g
            py -= 1
            if softDrop { score += 1; statsDirty = true }
            if py < lowest { lowest = py; lockResets = 0 }
        }
        if grounded {
            fallT = 0
            lockT += dt
            if lockT >= (softDrop ? min(0.25, lockDelay) : (demoBG ? 0.5 : lockDelay)) { syncPiece(snap: true, dt: 0); lockPiece(); return }
        } else {
            lockT = 0
        }
        syncPiece(snap: false, dt: dt)
    }

    // MARK: Klawiatura

    func toggleMusic() {
        musicMode = (musicMode + 1) % 3
        music.mode = musicMode
        UserDefaults.standard.set(musicMode, forKey: "muzyka")
        hud.popup(["♪ melodie", "♪ ambient", "muzyka wyłączona"][musicMode], nsc(0x9AA4D8), at: CGPoint(x: view.bounds.width / 2, y: view.bounds.height * 0.9), size: view.bounds.height * 0.026)
        if state == .menu { showMenu(animated: false) }
    }

    enum Act: Int, CaseIterable { case left, right, soft, rot, rotL, drop, hold }

    /// Klawisz → (gracz, akcja) w bieżącym trybie.
    func binding(_ c: UInt16) -> (Player, Act)? {
        let code = Int(c)
        if !twoP {
            if let i = keymap[0].firstIndex(of: code) { return (p1, Act(rawValue: i)!) }
            return nil
        }
        if let i = keymap[1].firstIndex(of: code) { return (p1, Act(rawValue: i)!) }
        if let i = keymap[2].firstIndex(of: code) { return (p2, Act(rawValue: i)!) }
        return nil
    }

    // MARK: Własne klawisze

    /// Profile: 0 = 1 gracz, 1 = gracz 1 (tryb 2 graczy), 2 = gracz 2. Kolejność jak w `Act`.
    static let defaultKeys: [[Int]] = [
        [123, 124, 125, 126, 6, 49, 8],       // ← → ↓ ↑ Z SPACJA C
        [0, 2, 1, 13, 12, 49, 14],            // A D S W Q SPACJA E
        [123, 124, 125, 126, 44, 36, 47]]     // ← → ↓ ↑ / ENTER .
    static let actNames = ["Ruch w lewo", "Ruch w prawo", "Przyspieszanie", "Obrót", "Obrót w lewo", "Zrzut", "Schowek"]
    static let profileNames = ["1 GRACZ", "GRACZ 1  (2 graczy)", "GRACZ 2  (2 graczy)"]
    lazy var keymap: [[Int]] = {
        if let k = ud.array(forKey: "klawisze") as? [[Int]], k.count == 3, k.allSatisfy({ $0.count == 7 }) { return k }
        return Game.defaultKeys
    }()
    lazy var keyNames: [String: String] = ud.dictionary(forKey: "nazwyKlawiszy") as? [String: String] ?? [:]
    var ctlProfile = 0, ctlSel = 0, capturing = false
    var modsDown = Set<UInt16>()

    func keyName(_ c: Int) -> String {
        let fixed: [Int: String] = [123: "←", 124: "→", 125: "↓", 126: "↑", 49: "SPACJA", 36: "ENTER", 76: "ENTER (num.)", 48: "TAB",
                                    51: "BACKSPACE", 117: "DELETE", 56: "LEWY ⇧", 60: "PRAWY ⇧", 58: "LEWY ⌥", 61: "PRAWY ⌥",
                                    59: "LEWY CTRL", 62: "PRAWY CTRL", 0: "A", 1: "S", 2: "D", 6: "Z", 7: "X", 8: "C", 12: "Q", 13: "W",
                                    14: "E", 44: "/", 47: ".", 43: ",", 41: ";", 39: "'", 50: "`"]
        return keyNames[String(c)] ?? fixed[c] ?? "#\(c)"
    }
    func helpText(_ prof: Int) -> String {
        let k = keymap[prof]
        return "\(keyName(k[0]))  \(keyName(k[1]))  ruch    \(keyName(k[3]))  obrót    \(keyName(k[4]))  w lewo    \(keyName(k[2]))  przyspiesz    \(keyName(k[5]))  zrzut    \(keyName(k[6]))  schowek"
    }
    func saveKeys() {
        ud.set(keymap, forKey: "klawisze")
        ud.set(keyNames, forKey: "nazwyKlawiszy")
    }

    /// Klawisz naciśnięty w trybie przypisywania.
    func captureKey(_ c: UInt16, chars: String?) {
        capturing = false
        if c == 53 { showControls(); return }                    // ESC = anuluj
        if c == 55 || c == 54 { capturing = true; return }        // ⌘ zarezerwowany
        let code = Int(c)
        if let ch = chars?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), !ch.isEmpty, ch.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value < 0xF700 }) {
            keyNames[String(code)] = ch
        }
        // ten sam klawisz nie może służyć dwóm akcjom w jednym trybie gry
        let clash: [Int] = ctlProfile == 0 ? [0] : [1, 2]
        for pr in clash { for a in 0..<7 where keymap[pr][a] == code && !(pr == ctlProfile && a == ctlSel) {
            keymap[pr][a] = keymap[ctlProfile][ctlSel]                // zamiana miejscami
        } }
        keymap[ctlProfile][ctlSel] = code
        saveKeys()
        music.holdSnd()
        showControls()
        if state == .controls { refreshStats() }
    }

    /// Shift / Option / Ctrl przychodzą jako flagsChanged — zamieniamy je na wciśnięcie/puszczenie.
    func modifier(_ e: NSEvent) {
        let c = e.keyCode
        guard [56, 60, 58, 61, 59, 62].contains(c) else { return }
        if modsDown.contains(c) { modsDown.remove(c); handleKey(c, down: false, isRepeat: false, chars: nil) }
        else { modsDown.insert(c); handleKey(c, down: true, isRepeat: false, chars: nil) }
    }

    var padIsPS: Bool {
        GCController.controllers().contains {
            $0.extendedGamepad is GCDualShockGamepad || $0.extendedGamepad is GCDualSenseGamepad ||
            $0.productCategory.contains("DualShock") || $0.productCategory.contains("DualSense")
        }
    }

    func key(_ e: NSEvent, down: Bool) { handleKey(e.keyCode, down: down, isRepeat: e.isARepeat, chars: e.characters) }

    func handleKey(_ c: UInt16, down: Bool, isRepeat: Bool, chars: String?) {
        SCNTransaction.lock(); defer { SCNTransaction.unlock() }
        if !down {
            if let (pl, act) = binding(c) {
                switch act {
                case .left: pl.leftHeld = false; if pl.rightHeld { pl.lastDir = 0 }
                case .right: pl.rightHeld = false; if pl.leftHeld { pl.lastDir = 0 }
                case .soft: pl.softDrop = false
                default: break
                }
            }
            return
        }
        NSCursor.setHiddenUntilMouseMoves(true)
        idleT = 0
        if demo || attractStage == 1 { if !isRepeat { stopAttract() }; return }
        if state == .controls && capturing { if !isRepeat { captureKey(c, chars: chars) }; return }
        let enter = c == 36 || c == 76
        switch state {
        case .intro:
            hud.skipIntro()
        case .menu:
            if c == 126 || c == 13 { menuSel = (menuSel + 4) % 5; music.tick(); showMenu(animated: false) }
            else if c == 125 || c == 1 { menuSel = (menuSel + 1) % 5; music.tick(); showMenu(animated: false) }
            else if enter || c == 49 { menuActivate() }
            else if c == 18 { newGame(players: 1) }
            else if c == 19 { newGame(players: 2) }
            else if c == 15 { showScores(highlight: nil) }
            else if c == 46 { toggleMusic() }
            else if c == 53 { NSApp.terminate(nil) }
        case .scores:
            if enter || c == 53 || c == 49 { showMenu() }
        case .options:
            if c == 126 || c == 13 { optSel = (optSel + 12) % 13; music.tick(); showOptions(animated: false) }
            else if c == 125 || c == 1 { optSel = (optSel + 1) % 13; music.tick(); showOptions(animated: false) }
            else if c == 123 || c == 0 { if optSel < 11 { changeOption(-1) } }
            else if c == 124 || c == 2 { if optSel < 11 { changeOption(1) } }
            else if enter || c == 49 { changeOption(1) }
            else if c == 53 { showMenu() }
        case .controls:
            if c == 123 { ctlProfile = (ctlProfile + 2) % 3; music.tick(); showControls() }
            else if c == 124 { ctlProfile = (ctlProfile + 1) % 3; music.tick(); showControls() }
            else if c == 126 { ctlSel = (ctlSel + 8) % 9; music.tick(); showControls() }
            else if c == 125 { ctlSel = (ctlSel + 1) % 9; music.tick(); showControls() }
            else if c == 53 { showOptions() }
            else if enter || c == 49 {
                if ctlSel < 7 { capturing = true; showControls() }
                else if ctlSel == 7 { keymap[ctlProfile] = Game.defaultKeys[ctlProfile]; saveKeys(); music.holdSnd(); showControls() }
                else { showOptions() }
            }
        case .countdown:
            break
        case .paused:
            let n = pauseItems.count
            if c == 126 || c == 13 { pauseSel = (pauseSel + n - 1) % n; music.tick(); showPause(animated: false) }
            else if c == 125 || c == 1 { pauseSel = (pauseSel + 1) % n; music.tick(); showPause(animated: false) }
            else if c == 53 || c == 35 { resumeGame() }
            else if enter || c == 49 { pauseActivate() }
            else if c == 12 { toMenuFromGame() }
            else if c == 46 { toggleMusic() }
        case .over:
            if twoP {
                if enter { newGame(players: 2) } else if c == 53 { showMenu() }
                return
            }
            if entering {
                if enter { saveRecord() }
                else if c == 51 { if !name.isEmpty { name.removeLast(); showOverQuick() } }
                else if c == 53 { entering = false; showOver() }
                else if let ch = chars, name.count < 14 {
                    let ok = ch.filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" || $0 == "_" }
                    if !ok.isEmpty { name += ok; showOverQuick() }
                }
            } else {
                if enter || c == 53 { showMenu() } else if c == 15 { showScores(highlight: nil) }
            }
        case .playing, .clearing:
            if isRepeat { return }
            if c == 53 || c == 35 { state = .paused; pauseSel = 0; music.duck = 0.35; showPause(); return }
            if c == 46 { toggleMusic(); return }
            guard let (pl, act) = binding(c) else { return }
            cp = pl
            switch act {
            case .left: leftHeld = true; lastDir = -1; dasT = 0; arrT = 0; move(-1)
            case .right: rightHeld = true; lastDir = 1; dasT = 0; arrT = 0; move(1)
            case .soft: softDrop = true
            case .rot: rotate(1)
            case .rotL: rotate(-1)
            case .drop: hardDrop()
            case .hold: holdPiece()
            }
        }
    }

    /// Odświeżenie panelu końca gry bez animacji wejścia (przy wpisywaniu imienia).
    func showOverQuick() {
        showOver()
        hud.panel.removeAllActions(); hud.panel.alpha = 1; hud.panel.setScale(1)
        hud.shade.removeAllActions(); hud.shade.alpha = 0.45
    }
}

// MARK: - Aplikacja

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var game: Game!
    var started = false
    let cover = NSView()

    func applicationDidFinishLaunching(_ n: Notification) {
        let menu = NSMenu(), item = NSMenuItem(), sub = NSMenu()
        sub.addItem(withTitle: "Zakończ Klocki", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = sub; menu.addItem(item)
        NSApp.mainMenu = menu

        let frame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Klocki"
        window.collectionBehavior = [.fullScreenPrimary]
        window.backgroundColor = .black
        window.isOpaque = true
        let root = NSView(frame: NSRect(origin: .zero, size: frame.size))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.black.cgColor
        let v = GameView(frame: root.bounds)
        v.autoresizingMask = [.width, .height]
        root.addSubview(v)
        cover.frame = root.bounds
        cover.autoresizingMask = [.width, .height]
        cover.wantsLayer = true
        cover.layer?.backgroundColor = NSColor(srgbRed: 7 / 255, green: 8 / 255, blue: 15 / 255, alpha: 1).cgColor
        root.addSubview(cover)
        window.contentView = root
        game = Game(view: v)
        game.onDisplay = { [weak self] m in self?.applyDisplay(m) }
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(v)
        NSApp.activate(ignoringOtherApps: true)
        if game.display == 0 { window.toggleFullScreen(nil) } else { setSize(AppDelegate.sizes[game.display]); DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.begin() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in self?.begin() }
    }
    var pendingSize: NSSize?
    static let sizes = [NSSize.zero, NSSize(width: 1280, height: 720), NSSize(width: 1920, height: 1080), NSSize(width: 2560, height: 1440)]
    func applyDisplay(_ m: Int) {
        let full = window.styleMask.contains(.fullScreen)
        if m == 0 { if !full { window.toggleFullScreen(nil) }; return }
        if full { pendingSize = AppDelegate.sizes[m]; window.toggleFullScreen(nil) } else { setSize(AppDelegate.sizes[m]) }
    }
    func setSize(_ s: NSSize) {
        let vis = window.screen?.visibleFrame.size ?? s
        window.setContentSize(NSSize(width: min(s.width, vis.width), height: min(s.height, vis.height - 32)))
        window.center()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.game.relayout() }
    }
    func windowDidExitFullScreen(_ n: Notification) {
        if let s = pendingSize { pendingSize = nil; setSize(s) }
    }
    func windowDidEnterFullScreen(_ n: Notification) {
        if started { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.game.relayout() } }
 DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.begin() } }
    func begin() {
        guard !started else { return }
        started = true
        game.start()
        // zasłona znika dopiero, gdy intro (z własnym ciemnym tłem) jest już na ekranie
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; self?.cover.animator().alphaValue = 0 },
                                                 completionHandler: { self?.cover.removeFromSuperview() })
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
}

if let dir = ProcessInfo.processInfo.environment["KLOCKI_INTRO"] { BluerootIntro.dumpFrames(dir); exit(0) }   // test: klatki intro do PNG
if let dir = ProcessInfo.processInfo.environment["KLOCKI_TLA"] {   // test: podgląd tła dla poziomów
    for lv in [1, 3, 5, 8, 11, 15] {
        let rep = NSBitmapImageRep(cgImage: Game.nebula(lv - 1))
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir + "/tlo\(lv).png"))
    }
    exit(0)
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

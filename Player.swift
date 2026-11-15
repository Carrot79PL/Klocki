import SceneKit

/// Stan jednego gracza: jego plansza 3D, klocki, wynik i wciśnięte klawisze.
final class Player {
    let id: Int
    var board = SCNNode()
    var base = SCNVector3Zero                 // położenie planszy w scenie
    var pieceNodes: [SCNNode] = [], ghostNodes: [SCNNode] = [], beamNodes: [SCNNode] = []
    var pieceLight = SCNNode()
    var holdNode = SCNNode(), nextNodes: [SCNNode] = []
    var panels: [SCNNode] = []

    var grid = [[Int]](repeating: [Int](repeating: -1, count: 10), count: 22)
    var cells = [[SCNNode?]](repeating: [SCNNode?](repeating: nil, count: 10), count: 22)
    var cur: Kind = .T, rot = 0, px = 3, py = 18
    var bag: [Kind] = [], queue: [Kind] = []
    var hold: Kind?, holdUsed = false
    var score = 0, lines = 0, level = 1, combo = -1, b2b = false
    var fallT = 0.0, lockT = 0.0, lockResets = 0, lowest = 99
    var leftHeld = false, rightHeld = false, softDrop = false, lastDir = 0, dasT = 0.0, arrT = 0.0
    var busy = false                          // trwa zbijanie linii
    var alive = true
    var garbage = 0                           // linie-śmieci od przeciwnika do wstawienia
    var rng: UInt64 = 1                       // wspólne ziarno = ta sama kolejka klocków u obu graczy

    init(id: Int) { self.id = id }

    func random(_ n: Int) -> Int {
        rng = rng &* 6364136223846793005 &+ 1442695040888963407
        return Int((rng >> 33) % UInt64(n))
    }
}

func hexOf(_ k: Int) -> UInt32 { k >= 0 && k < kindHex.count ? kindHex[k] : 0x8890AA }

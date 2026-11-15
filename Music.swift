import AVFoundation

/// Syntezator muzyki i efektów.
/// Tryb 0 — klasyczna: własna aranżacja ludowej melodii „Korobeiniki” (domena publiczna),
/// tempo i perkusja rosną z `intensity`. Tryb 1 — ambient. Tryb 2 — bez muzyki (efekty zostają).
struct Bell { var f: Float; var ph: Float = 0; var ph2: Float = 0; var amp: Float; var dec: Float; var pan: Float; var delay: Int; var mus = false }

func mtof(_ m: Float) -> Float { 440 * powf(2, (m - 69) / 12) }

final class Music {
    private let engine = AVAudioEngine()
    private let reverb = AVAudioUnitReverb()
    private var src: AVAudioSourceNode?
    private let lock = NSLock()
    private var pending: [Bell] = []

    var intensity: Float = 0
    var volume: Float = 0.9
    var sfxVolume: Float = 0.8
    var duck: Float = 0          // przyciszenie (pauza); 0 na starcie = cisza pod logo
    var mode = 0                 // 0 klasyczna, 1 ambient, 2 wyłączona
    var sfxOn = true
    var beatPos: Float = 0       // pozycja w taktach (dla efektów w rytm)

    private var sr: Float = 48000
    private var inten: Float = 0, vol: Float = 0, gC: Float = 0, gA: Float = 0
    private var seed: UInt32 = 0x9E3779B9
    private var bells: [Bell] = []

    // --- ambient ---
    private var chord = 0
    private var chordT: Float = 0
    private var padPh = [Float](repeating: 0, count: 8)
    private var padF = [Float](repeating: 220, count: 8)
    private var padTarget = [Float](repeating: 220, count: 8)
    private var lpL: Float = 0, lpR: Float = 0
    private var arpT: Float = 0, step = 0
    private var bassPh: Float = 0, bassF: Float = 110, bassEnv: Float = 0, hatEnv: Float = 0, lastN: Float = 0
    private var lfo: Float = 0
    static let chords: [(root: Float, pad: [Float])] = [
        (45, [57, 60, 64, 71]), (41, [53, 57, 60, 64]), (48, [52, 55, 59, 62]), (43, [50, 55, 59, 64])]
    static let penta: [Float] = [69, 72, 74, 76, 79, 81, 84, 86, 88]

    // --- melodie (domena publiczna + własna), własne aranżacje ---
    struct Song {
        let name: String, meter: Int, melody: [(Float, Float)], roots: [Float], stabs: [[Float]], gate: Float, tempo: Float, major: Bool, emin: Bool, cmaj: Bool
        let starts: [Float], total: Float
        /// aranżacja: transpozycja i tryb każdej nuty i każdego taktu
        /// tryb (bity): 1 oktawa wyżej, 2 druga głos (tercja), 8 przejście perkusji, 16 bez perkusji
        let nTr: [Float], nMode: [Int], mTr: [Float], mMode: [Int]
        init(_ name: String, meter: Int = 4, gate: Float = 0.86, tempo: Float = 1, major: Bool = false, emin: Bool = false, cmaj: Bool = false,
             _ theme: [(Float, Float)], roots themeRoots: [Float], stabs themeStabs: [[Float]]) {
            self.name = name; self.meter = meter
            self.gate = gate; self.tempo = tempo; self.major = major; self.emin = emin; self.cmaj = cmaj
            // --- własna aranżacja z tematu: intro, temat, głosy, łącznik, zmiana tonacji, wariacja, przejście, powrót, koda
            let bars = themeRoots.count, M = Float(meter)
            var mel: [(Float, Float)] = [], ntr: [Float] = [], nmd: [Int] = []
            var rr: [Float] = [], ss: [[Float]] = [], mtr: [Float] = [], mmd: [Int] = []
            func note(_ m: Float, _ d: Float, _ tr: Float, _ md: Int) { mel.append((m, d)); ntr.append(tr); nmd.append(md) }
            func bar(_ i: Int, _ tr: Float, _ md: Int) { rr.append(themeRoots[i]); ss.append(themeStabs[i]); mtr.append(tr); mmd.append(md) }
            func themeSec(_ tr: Float, _ md: Int, varied: Bool = false) {
                for n in theme {
                    if varied && n.0 > 0 && n.1 >= 1 {             // wariacja: ozdobnik oktawowy w środku dłuższej nuty
                        note(n.0, n.1 / 2, tr, md); note(n.0 + 12, n.1 / 4, tr, md); note(n.0, n.1 / 4, tr, md)
                    } else { note(n.0, n.1, tr, md) }
                }
                for i in 0..<bars { bar(i, tr, md) }
            }
            func restSec(_ b: Int, _ md: Int) {                  // bez melodii (intro, przejście)
                note(0, Float(b) * M, 0, md)
                for k in 0..<b { bar(k % bars, 0, md) }
            }
            func bridge(_ b: Int, _ tr: Float) {                  // łącznik: rozłożone akordy tematu, oktawę wyżej
                for k in 0..<b {
                    let i = (k * 3 + bars / 2) % bars, ch = themeStabs[i]
                    if k == b - 1 { note(ch[0] + 12, M, tr, 2) }
                    else { for j in 0..<meter { note(ch[[0, 1, 2, 1][j % 4]] + 12, 1, tr, 0) } }
                    bar(i, tr, 0)
                }
            }
            let up: Float = major || cmaj ? 2 : 3                 // zmiana tonacji
            restSec(min(4, bars), 16)                              // intro: pad i bas
            themeSec(0, 0)                                         // temat
            themeSec(0, 2)                                         // temat z drugim głosem
            bridge(4, 0)
            themeSec(up, 2)                                        // temat w nowej tonacji
            bridge(2, up)
            var total0: Float = 0
            func len() -> Float { mel.reduce(0) { $0 + $1.1 } }
            themeSec(0, 0, varied: true)                           // wariacja
            total0 = len()
            let target = 240 * tempo - Float(bars + 4) * M         // obieg ≥ ok. 100 s przy 120 BPM
            var extra = 0
            while total0 < target {                                // krótkie tematy: dodatkowe odmiany
                themeSec(extra % 2 == 0 ? 0 : up, extra % 2 == 0 ? 1 : 3, varied: extra % 3 == 2)
                total0 = len(); extra += 1
            }
            restSec(1, 16); restSec(1, 8)                          // przejście perkusji
            themeSec(0, 3)                                         // powrót tematu: oktawa wyżej i dwa głosy
            note(themeStabs[bars - 1][0] + 12, M * 2, 0, 16)       // koda
            bar(bars - 1, 0, 16); bar(bars - 1, 0, 16)
            self.melody = mel; self.roots = rr; self.stabs = ss
            nTr = ntr; nMode = nmd; mTr = mtr; mMode = mmd
            var st: [Float] = [], t: Float = 0
            for n in mel { st.append(t); t += n.1 }
            starts = st; total = t
        }
        /// tercja diatoniczna w dół (a-moll albo G-dur)
        func third(_ m: Float) -> Float {
            let pc = Int(m) % 12
            if cmaj { return [0, 2, 5, 7].contains(pc) ? m - 3 : m - 4 }
            if emin { return [7, 9, 0, 2].contains(pc) ? m - 3 : m - 4 }
            if major { return [7, 9, 0, 2].contains(pc) ? m - 3 : m - 4 }
            return [0, 2, 5, 7, 10].contains(pc) ? m - 3 : m - 4
        }
    }
    static let am: [Float] = [57, 60, 64], E: [Float] = [56, 59, 64], dm: [Float] = [57, 62, 65], F: [Float] = [57, 60, 65]
    static let em: [Float] = [55, 59, 64], Bmaj: [Float] = [54, 59, 63]
    static let C: [Float] = [55, 60, 64], G: [Float] = [55, 59, 62], D: [Float] = [54, 57, 62], B7: [Float] = [59, 63, 69], Bb: [Float] = [58, 62, 65]
    static let songs: [Song] = [
        Song("Korobeiniki (ludowa)", [
            (76, 1), (71, 0.5), (72, 0.5), (74, 1), (72, 0.5), (71, 0.5),
            (69, 1), (69, 0.5), (72, 0.5), (76, 1), (74, 0.5), (72, 0.5),
            (71, 1.5), (72, 0.5), (74, 1), (76, 1),
            (72, 1), (69, 1), (69, 1), (0, 1),
            (0, 0.5), (74, 1), (77, 0.5), (81, 1), (79, 0.5), (77, 0.5),
            (76, 1.5), (72, 0.5), (76, 1), (74, 0.5), (72, 0.5),
            (71, 1), (71, 0.5), (72, 0.5), (74, 1), (76, 1),
            (72, 1), (69, 1), (69, 1), (0, 1)],
             roots: [40, 45, 40, 45, 38, 45, 40, 45], stabs: [E, am, E, am, dm, am, E, am]),
        Song("Neonowy bieg", tempo: 1.05, [
            (69, 0.5), (72, 0.5), (76, 1), (74, 0.5), (72, 0.5), (71, 1),
            (72, 0.5), (74, 0.5), (76, 1), (79, 1), (76, 1),
            (77, 1), (76, 0.5), (74, 0.5), (72, 1), (74, 1),
            (76, 3), (0, 1),
            (81, 0.5), (79, 0.5), (77, 1), (76, 0.5), (74, 0.5), (72, 1),
            (74, 0.5), (76, 0.5), (77, 1), (76, 1), (72, 1),
            (71, 1), (72, 0.5), (74, 0.5), (76, 1), (71, 1),
            (69, 3), (0, 1)],
             roots: [45, 48, 41, 40, 41, 38, 40, 45], stabs: [am, C, F, E, F, dm, E, am]),
        Song("Grieg – W grocie Króla Gór", gate: 0.55, tempo: 0.92, [
            (69, 1), (71, 1), (72, 1), (74, 1),
            (76, 1), (72, 1), (76, 2),
            (75, 1), (71, 1), (75, 2),
            (74, 1), (70, 1), (74, 2),
            (69, 1), (71, 1), (72, 1), (74, 1),
            (76, 1), (72, 1), (76, 1), (81, 1),
            (79, 1), (76, 1), (72, 1), (76, 1),
            (79, 4)],
             roots: [45, 45, 47, 46, 45, 45, 48, 43], stabs: [am, am, B7, Bb, am, am, C, G]),
        Song("Petzold – Menuet G-dur", meter: 3, gate: 0.8, tempo: 0.85, major: true, [
            (74, 1), (67, 0.5), (69, 0.5), (71, 0.5), (72, 0.5),
            (74, 1), (67, 1), (67, 1),
            (76, 1), (72, 0.5), (74, 0.5), (76, 0.5), (78, 0.5),
            (79, 1), (67, 1), (67, 1),
            (72, 1), (74, 0.5), (72, 0.5), (71, 0.5), (69, 0.5),
            (71, 1), (72, 0.5), (71, 0.5), (69, 0.5), (67, 0.5),
            (66, 1), (67, 0.5), (69, 0.5), (71, 0.5), (67, 0.5),
            (69, 3),
            (74, 1), (67, 0.5), (69, 0.5), (71, 0.5), (72, 0.5),
            (74, 1), (67, 1), (67, 1),
            (76, 1), (72, 0.5), (74, 0.5), (76, 0.5), (78, 0.5),
            (79, 1), (67, 1), (67, 1),
            (72, 1), (74, 0.5), (72, 0.5), (71, 0.5), (69, 0.5),
            (71, 1), (72, 0.5), (71, 0.5), (69, 0.5), (67, 0.5),
            (69, 1), (71, 0.5), (69, 0.5), (67, 0.5), (66, 0.5),
            (67, 3)],
             roots: [43, 43, 48, 43, 45, 43, 38, 38, 43, 43, 48, 43, 45, 43, 38, 43],
             stabs: [G, G, C, G, am, G, D, D, G, G, C, G, am, G, D, G]),
        Song("Gwiezdny puls", tempo: 1.08, emin: true, [
            (64, 0.5), (67, 0.5), (71, 0.5), (74, 1), (72, 0.5), (71, 0.5), (69, 0.5),
            (67, 1.5), (64, 0.5), (67, 1), (69, 1),
            (71, 0.5), (72, 0.5), (74, 1), (76, 0.5), (74, 0.5), (72, 1),
            (71, 3), (0, 1),
            (64, 0.5), (67, 0.5), (71, 0.5), (74, 1), (76, 0.5), (79, 0.5), (78, 0.5),
            (76, 1.5), (74, 0.5), (72, 1), (71, 1),
            (69, 0.5), (71, 0.5), (72, 1), (71, 0.5), (69, 0.5), (67, 1),
            (64, 3), (0, 1)],
             roots: [40, 36, 43, 47, 40, 36, 45, 40], stabs: [em, C, G, Bmaj, em, C, am, em]),
        // Beethoven, „Dla Elizy” (1810) — miara: ósemka = 1
        Song("Beethoven – Dla Elizy", meter: 3, gate: 0.8, tempo: 1.5, [
            (76, 0.5), (75, 0.5), (76, 0.5), (71, 0.5), (74, 0.5), (72, 0.5),
            (69, 1), (0, 0.5), (60, 0.5), (64, 0.5), (69, 0.5),
            (71, 1), (0, 0.5), (64, 0.5), (68, 0.5), (71, 0.5),
            (72, 1), (0, 0.5), (64, 0.5), (76, 0.5), (75, 0.5),
            (76, 0.5), (75, 0.5), (76, 0.5), (71, 0.5), (74, 0.5), (72, 0.5),
            (69, 1), (0, 0.5), (60, 0.5), (64, 0.5), (69, 0.5),
            (71, 1), (0, 0.5), (64, 0.5), (72, 0.5), (71, 0.5),
            (69, 1), (0, 1), (76, 0.5), (75, 0.5)],
             roots: [40, 45, 40, 45, 40, 45, 40, 45], stabs: [E, am, E, am, E, am, E, am]),
        // Beethoven, „Oda do radości” (IX Symfonia, 1824)
        Song("Beethoven – Oda do radości", tempo: 0.95, major: true, [
            (71, 1), (71, 1), (72, 1), (74, 1),
            (74, 1), (72, 1), (71, 1), (69, 1),
            (67, 1), (67, 1), (69, 1), (71, 1),
            (71, 1.5), (69, 0.5), (69, 2),
            (71, 1), (71, 1), (72, 1), (74, 1),
            (74, 1), (72, 1), (71, 1), (69, 1),
            (67, 1), (67, 1), (69, 1), (71, 1),
            (69, 1.5), (67, 0.5), (67, 2),
            (69, 1), (69, 1), (71, 1), (67, 1),
            (69, 1), (71, 0.5), (72, 0.5), (71, 1), (67, 1),
            (69, 1), (71, 0.5), (72, 0.5), (71, 1), (69, 1),
            (67, 1), (69, 1), (62, 2),
            (71, 1), (71, 1), (72, 1), (74, 1),
            (74, 1), (72, 1), (71, 1), (69, 1),
            (67, 1), (67, 1), (69, 1), (71, 1),
            (69, 1.5), (67, 0.5), (67, 2)],
             roots: [43, 38, 43, 38, 43, 38, 43, 43, 38, 38, 38, 38, 43, 38, 43, 43],
             stabs: [G, D, G, D, G, D, G, G, D, D, D, D, G, D, G, G]),
        // Mozart, „Eine kleine Nachtmusik” (1787), początek
        Song("Mozart – Eine kleine Nachtmusik", gate: 0.7, tempo: 1.0, major: true, [
            (67, 1), (0, 0.5), (62, 0.5), (67, 1), (0, 0.5), (62, 0.5),
            (67, 0.5), (62, 0.5), (67, 0.5), (71, 0.5), (74, 2),
            (72, 1), (0, 0.5), (69, 0.5), (72, 1), (0, 0.5), (69, 0.5),
            (72, 0.5), (69, 0.5), (66, 0.5), (69, 0.5), (62, 2)],
             roots: [43, 43, 38, 38], stabs: [G, G, D, D]),
        // „Wlazł kotek na płotek” — polska piosenka ludowa
        Song("Wlazł kotek na płotek (ludowa)", gate: 0.8, tempo: 1.0, cmaj: true, [
            (67, 1), (64, 1), (64, 2),
            (65, 1), (62, 1), (62, 2),
            (60, 1), (64, 1), (67, 2),
            (67, 1), (64, 1), (64, 2),
            (65, 1), (62, 1), (62, 2),
            (60, 1), (64, 1), (60, 2)],
             roots: [48, 43, 48, 48, 43, 48], stabs: [C, G, C, C, G, C]),
    ]
    var song = 0                 // żądany utwór (wątek główny)
    private var cur = 0
    private var beat: Float = 0, noteIdx = 0, loopN = 0, lastEighth = -1
    private var leadPh: Float = 0, leadPh2: Float = 0, leadF: Float = 440, harmF: Float = 0, harmPh: Float = 0
    private var leadEnv: Float = 0, leadGate = false, leadOff: Float = 0, leadAge: Float = 0, leadLP: Float = 0, harmLP: Float = 0
    private var cBassPh: Float = 0, cBassF: Float = 82, cBassEnv: Float = 0
    private var leadPh3: Float = 0, filtEnv: Float = 0, leadLP2: Float = 0, kickClick: Float = 0, snPh: Float = 0, last16 = -1
    private var cPadPh = [Float](repeating: 0, count: 3), cPadF = [Float](repeating: 220, count: 3), cPadT = [Float](repeating: 220, count: 3), cPadLP: Float = 0
    private var dBufL = [Float](repeating: 0, count: 96000), dBufR = [Float](repeating: 0, count: 96000), dPos = 0, sv: Float = 0
    private var kickEnv: Float = 0, kickPh: Float = 0, snEnv: Float = 0, cHat: Float = 0, snLP: Float = 0

    init() {
        let outSR = engine.outputNode.inputFormat(forBus: 0).sampleRate
        sr = Float(outSR > 0 ? outSR : 48000)
        let fmt = AVAudioFormat(standardFormatWithSampleRate: Double(sr), channels: 2)!
        setChord(0, snap: true)
        let s = AVAudioSourceNode(format: fmt) { [unowned self] _, _, frames, abl -> OSStatus in
            self.render(Int(frames), UnsafeMutableAudioBufferListPointer(abl))
            return noErr
        }
        src = s
        engine.attach(s)
        engine.attach(reverb)
        reverb.loadFactoryPreset(.largeHall2)
        reverb.wetDryMix = 30
        engine.connect(s, to: reverb, format: fmt)
        engine.connect(reverb, to: engine.mainMixerNode, format: fmt)
        try? engine.start()
    }

    private func setChord(_ c: Int, snap: Bool = false) {
        chord = c
        let ch = Music.chords[c]
        for v in 0..<8 {
            padTarget[v] = mtof(ch.pad[v >> 1]) * (v & 1 == 0 ? 0.9965 : 1.0035)
            if snap { padF[v] = padTarget[v] }
        }
        bassF = mtof(ch.root)
    }

    private func rnd() -> Float {
        seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
        return Float(seed) / Float(UInt32.max)
    }

    // MARK: Efekty (wątek główny)

    func play(_ m: Float, amp: Float, decay: Float, delay: Float = 0, pan: Float = 0) {
        guard sfxOn else { return }
        let b = Bell(f: mtof(m), amp: amp, dec: expf(-1 / (sr * decay)), pan: pan, delay: Int(delay * sr))
        lock.lock(); pending.append(b); lock.unlock()
    }
    func tick() { play(91, amp: 0.02, decay: 0.03) }
    func thud() { play(33, amp: 0.30, decay: 0.10); play(45, amp: 0.08, decay: 0.06) }
    func drop() { play(28, amp: 0.42, decay: 0.16); play(40, amp: 0.12, decay: 0.08); play(64, amp: 0.03, decay: 0.2) }
    func holdSnd() { play(76, amp: 0.05, decay: 0.15); play(83, amp: 0.04, decay: 0.2, delay: 0.05) }
    func clear(_ n: Int) {
        let notes: [Float] = n >= 4 ? [69, 72, 76, 79, 81, 84, 88, 93] : Array([72, 76, 79, 84, 88].prefix(n + 2))
        for (i, m) in notes.enumerated() {
            play(m, amp: n >= 4 ? 0.11 : 0.09, decay: n >= 4 ? 1.4 : 0.9, delay: Float(i) * 0.055, pan: Float(i % 2 == 0 ? -0.4 : 0.4))
        }
    }
    func levelUp() { for (i, m) in [64, 69, 71, 76, 81].enumerated() { play(Float(m), amp: 0.08, decay: 1.6, delay: Float(i) * 0.09) } }
    func gameOver() { for (i, m) in [76, 72, 69, 64, 57, 52].enumerated() { play(Float(m), amp: 0.09, decay: 1.8, delay: Float(i) * 0.22) } }

    // MARK: Synteza (wątek audio)

    private func render(_ frames: Int, _ abl: UnsafeMutableAudioBufferListPointer) {
        guard abl.count >= 2, let L = abl[0].mData?.assumingMemoryBound(to: Float.self),
              let R = abl[1].mData?.assumingMemoryBound(to: Float.self) else { return }
        if lock.try() { if !pending.isEmpty { bells += pending; pending.removeAll() }; lock.unlock() }
        let dt = 1 / sr
        let bt = Float(frames) * dt
        inten += (min(1, max(0, intensity)) - inten) * min(1, bt * 0.8)
        let tv: Float = volume
        let m = mode
        let tC: Float = m == 0 ? duck : 0, tA: Float = m == 1 ? duck : 0
        let tau = 2 * Float.pi

        // ambient – parametry bloku
        let chordDur = 9 - 5 * inten
        let interval = 1.25 * powf(0.11, inten)
        let cut = 0.012 + 0.10 * inten * inten + 0.02 * inten
        let hatOn = inten > 0.3
        let bassAmp = 0.05 + 0.13 * inten
        // klasyczna – tempo 120 → 235 BPM
        let bps = (120 + 115 * inten) / 60
        let drums = 0.25 + 0.75 * inten
        let dLen = max(2000, min(95000, Int(0.75 / max(0.5, bps * Music.songs[cur].tempo) * sr)))   // echo co ósemkę z kropką

        for i in 0..<frames {
            vol += (tv - vol) * 0.00008
            sv += (sfxVolume - sv) * 0.00008
            gC += (tC - gC) * 0.00005
            gA += (tA - gA) * 0.00005
            var outL: Float = 0, outR: Float = 0

            if gA > 0.001 {
                chordT += dt
                if chordT >= chordDur { chordT = 0; setChord((chord + 1) % 4) }
                lfo += dt * 0.11 * tau; if lfo > tau { lfo -= tau }
                var pl: Float = 0, pr: Float = 0
                let br = 0.22 + 0.3 * inten
                for v in 0..<8 {
                    padF[v] += (padTarget[v] - padF[v]) * 0.00006
                    padPh[v] += tau * padF[v] * dt; if padPh[v] > tau { padPh[v] -= tau }
                    let p = padPh[v]
                    let s = sinf(p) + br * sinf(2 * p) + 0.12 * sinf(3 * p)
                    if v & 1 == 0 { pl += s } else { pr += s }
                }
                lpL += (pl - lpL) * cut; lpR += (pr - lpR) * cut
                let trem = 0.85 + 0.15 * sinf(lfo)
                arpT += dt
                if arpT >= interval {
                    arpT -= interval
                    step += 1
                    let ch = Music.chords[chord]
                    let pool = ch.pad.map { $0 + 12 } + ch.pad.map { $0 + 24 } + (inten > 0.4 ? Music.penta : [])
                    if inten > 0.15 || step % 2 == 0 || rnd() < 0.5 {
                        let mm = pool[Int(rnd() * Float(pool.count)) % pool.count]
                        let d = 1.6 - 0.9 * inten
                        bells.append(Bell(f: mtof(mm), amp: (0.045 + 0.02 * rnd()) * gA, dec: expf(-1 / (sr * d)), pan: rnd() * 1.2 - 0.6, delay: 0, mus: true))
                    }
                    if step % 4 == 0 || (inten > 0.55 && step % 2 == 0) { bassEnv = 1 }
                    if hatOn { hatEnv = (inten - 0.3) * (step % 2 == 0 ? 0.16 : 0.09) }
                }
                bassPh += tau * bassF * dt; if bassPh > tau { bassPh -= tau }
                bassEnv *= 0.99992
                let bass = sinf(bassPh) * (0.025 + bassEnv * bassAmp) + sinf(2 * bassPh) * bassEnv * 0.02
                let n = rnd() * 2 - 1
                let hat = (n - lastN) * hatEnv
                lastN = n
                hatEnv *= 0.9991
                outL += (lpL * 0.03 * trem + bass + hat * 0.7) * gA
                outR += (lpR * 0.03 * trem + bass + hat * 0.5) * gA
            }

            if gC > 0.001 {
                var sg = Music.songs[cur]
                beat += bps * sg.tempo * dt
                if beat >= sg.total { beat -= sg.total; noteIdx = 0; loopN += 1 }
                var e = Int(beat * 2)
                if e != lastEighth && e % (sg.meter * 2) == 0 && song != cur && song < Music.songs.count {
                    cur = song; sg = Music.songs[cur]                    // zmiana utworu na początku taktu
                    beat = 0; noteIdx = 0; loopN = 0; e = 0; leadGate = false
                }
                while noteIdx < sg.melody.count && beat >= sg.starts[noteIdx] {
                    let (mm, d) = sg.melody[noteIdx]
                    if mm > 0 {
                        let md = sg.nMode[noteIdx], tr = sg.nTr[noteIdx]
                        let up: Float = md & 1 != 0 ? 12 : 0
                        leadF = mtof(mm + up + tr)
                        harmF = md & 2 != 0 ? mtof(sg.third(mm) + up + tr) : 0
                        leadGate = true; leadAge = 0; filtEnv = 1
                        leadOff = sg.starts[noteIdx] + d * sg.gate
                    } else { leadGate = false }
                    noteIdx += 1
                }
                if leadGate && beat >= leadOff { leadGate = false }
                if e != lastEighth {
                    lastEighth = e
                    let per = sg.meter * 2, inBar = e % per
                    let meas = min(sg.roots.count - 1, e / per)
                    let mtr = sg.mTr[meas], mmd = sg.mMode[meas]
                    let root = sg.roots[meas] + mtr
                    for k in 0..<3 { cPadT[k] = mtof(sg.stabs[meas][k] + mtr - (k == 0 ? 12 : 0)) }
                    cBassF = mtof(inBar % 2 == 0 ? root : root + 12)
                    cBassEnv = 1
                    cHat = (0.02 + 0.07 * inten) * (inBar % 2 == 0 ? 1 : 0.6)
                    let drumsOn = mmd & 16 == 0
                    if drumsOn && (inBar == 0 || (sg.meter == 4 && inBar == 4)) { kickEnv = 1; kickClick = 1 }
                    if mmd & 8 != 0 { snEnv = 0.35 + 0.65 * Float(inBar) / Float(per) }   // przejście: werbel na ósemkach
                    let back = sg.meter == 4 ? (inBar == 2 || inBar == 6) : (inBar == 2 || inBar == 4)
                    if back {
                        if inten > 0.12 && drumsOn && mmd & 8 == 0 { snEnv = sg.meter == 4 ? 1 : 0.5 }
                        for (k, s) in sg.stabs[meas].enumerated() {
                            bells.append(Bell(f: mtof(s + mtr), amp: 0.022 * gC, dec: expf(-1 / (sr * 0.12)), pan: Float(k - 1) * 0.5, delay: 0, mus: true))
                        }
                    }
                }
                // arpeggio szesnastkowe przy szybszej grze
                let s16 = Int(beat * 4)
                if s16 != last16 {
                    last16 = s16
                    let mi = min(sg.roots.count - 1, Int(beat) / sg.meter)
                    if inten > 0.3 && sg.mMode[mi] & 16 == 0 {
                        let ch = sg.stabs[mi]
                        let nn = ch[s16 % 3] + sg.mTr[mi] + (s16 % 6 < 3 ? 12 : 24)
                        bells.append(Bell(f: mtof(nn), amp: (0.006 + 0.014 * inten) * gC, dec: expf(-1 / (sr * 0.08)), pan: s16 % 2 == 0 ? -0.5 : 0.5, delay: 0, mus: true))
                    }
                }
                // prowadzenie: puls + dwie rozstrojone piły, filtr otwierany na początku nuty, vibrato
                leadAge += dt
                leadEnv += ((leadGate ? 1 : 0) - leadEnv) * (leadGate ? 0.012 : 0.0009)
                let vib = 1 + 0.005 * sinf(tau * 5.5 * leadAge) * min(1, max(0, leadAge * 3 - 0.4))
                leadPh += leadF * vib * dt; if leadPh >= 1 { leadPh -= 1 }
                leadPh2 += leadF * 1.0045 * vib * dt; if leadPh2 >= 1 { leadPh2 -= 1 }
                leadPh3 += leadF * 0.9955 * vib * dt; if leadPh3 >= 1 { leadPh3 -= 1 }
                let pulse: Float = leadPh < 0.3 ? 1 : -1
                let saw = (leadPh2 * 2 - 1) + (leadPh3 * 2 - 1)
                filtEnv *= 0.99985
                let cutL = min(0.9, 0.07 + 0.1 * inten + 0.35 * filtEnv)
                leadLP += (pulse * 0.45 + saw * 0.4 - leadLP) * cutL
                leadLP2 += (leadLP - leadLP2) * cutL
                var harm: Float = 0
                if harmF > 0 {
                    harmPh += harmF * dt; if harmPh >= 1 { harmPh -= 1 }
                    harmLP += ((harmPh < 0.5 ? 1 : -1) - harmLP) * 0.1
                    harm = harmLP * leadEnv * 0.035
                }
                let lead = leadLP2 * leadEnv * 0.085
                // echo (ping-pong) na prowadzeniu
                if dPos >= dLen { dPos = 0 }
                let dl = dBufL[dPos], dr = dBufR[dPos]
                dBufL[dPos] = lead + dr * 0.36
                dBufR[dPos] = dl * 0.36
                dPos += 1
                // pad akordowy pod melodią, przyciszany stopą
                var pad: Float = 0
                for k in 0..<3 {
                    cPadF[k] += (cPadT[k] - cPadF[k]) * 0.0004
                    cPadPh[k] += cPadF[k] * dt; if cPadPh[k] >= 1 { cPadPh[k] -= 1 }
                    let ph = cPadPh[k] * tau
                    pad += sinf(ph) + 0.35 * sinf(2 * ph) + 0.15 * sinf(3 * ph)
                }
                cPadLP += (pad - cPadLP) * (0.03 + 0.05 * inten)
                let duckK = 1 - 0.45 * kickEnv
                // bas (trójkąt, oktawy na ósemkach)
                cBassPh += cBassF * dt; if cBassPh >= 1 { cBassPh -= 1 }
                cBassEnv = max(0.35, cBassEnv * 0.99985)
                let bass = (4 * abs(cBassPh - 0.5) - 1) * cBassEnv * 0.13 * (1 - 0.25 * kickEnv)
                // perkusja
                kickPh += (45 + 110 * kickEnv * kickEnv) * dt; if kickPh >= 1 { kickPh -= 1 }
                let kick = (sinf(tau * kickPh) * kickEnv * 0.32 + (rnd() * 2 - 1) * kickClick * 0.1) * drums
                kickEnv *= 0.99925
                kickClick *= 0.993
                let n = rnd() * 2 - 1
                snLP += (n - snLP) * 0.35
                snPh += 185 * dt; if snPh >= 1 { snPh -= 1 }
                let snare = (snLP * 0.11 + sinf(tau * snPh) * 0.05 * snEnv) * snEnv * drums
                snEnv *= 0.9988
                let hat = (n - lastN) * cHat
                lastN = n
                cHat *= 0.9988
                outL += (lead * 0.85 + harm * 1.2 + bass + kick + snare + hat * 0.6 + dl * 0.32 + cPadLP * 0.012 * duckK) * gC
                outR += (lead * 1.15 + harm * 0.8 + bass + kick + snare * 0.9 + hat + dr * 0.32 + cPadLP * 0.012 * duckK) * gC
            }

            // dzwonki i efekty
            var bl: Float = 0, brr: Float = 0, ml: Float = 0, mr: Float = 0
            for j in bells.indices {
                if bells[j].delay > 0 { bells[j].delay -= 1; continue }
                let f = bells[j].f
                bells[j].ph += tau * f * dt; if bells[j].ph > tau { bells[j].ph -= tau }
                bells[j].ph2 += tau * f * 2.76 * dt; if bells[j].ph2 > tau { bells[j].ph2 -= tau }
                let s = (sinf(bells[j].ph) + 0.25 * sinf(bells[j].ph2) * bells[j].amp * 6) * bells[j].amp
                bells[j].amp *= bells[j].dec
                if bells[j].mus { ml += s * (1 - bells[j].pan) * 0.7; mr += s * (1 + bells[j].pan) * 0.7 }
                else { bl += s * (1 - bells[j].pan) * 0.7; brr += s * (1 + bells[j].pan) * 0.7 }
            }
            L[i] = tanhf((outL + ml) * vol + bl * sv)
            R[i] = tanhf((outR + mr) * vol + brr * sv)
        }
        bells.removeAll { $0.amp < 0.0004 && $0.delay <= 0 }
        beatPos = gC > 0.3 ? beat : Float(step)
    }
}

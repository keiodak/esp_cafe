// Modes.swift — coco duo (k.odk)
// The preset manager's model: which preset (1–10) each Cafe is on, the BLE preset's mode, the target (A / B / both),
// the shared tempo, and the pads of DELAY, NOISE and HARMONY. (GRAIN and RUNGLER pads: GrainMode.swift, Benjolin.swift)
//
// Firmware esp_cafe_duo v3 playlist ("G <n>", 0-based):
//   0 COCO_MOD · 1 ECHO · 2 BLE (modes GRAIN / COCO / DELAY / NOISE, "M 25 <m>") · 3 RESONATOR · 4 FORMANT
//   5 SATURATOR · 6 HARMONY (three-layer harmonic delay) · 7 RUNGLER (coco + shift register) · 8 SELF_READ
//   9 MULTI (seven effects: FLIP = next, SKIP = random, crossfaded; EARTH modulates each)
//
// COCO (C ids) — the 8 pads go to both (L · R = only B moves):
//   SPEED (speed · overdub) LOOP (start · length) EARTH_FM (depth · slew) WOBBLE (rate · depth)
//   FILTER  CRUSH (hold · bits)  L · R (B faster · B's loop later)  MIX (dry · level)
//   keys: REC · reverse · back to the loop start · sync
//
// DELAY (Y ids) — pads per Cafe, top row = A, bottom row = B:
//   TIME · FB    X = time (on the grid: steps through 1/16 … 1/1)   Y = feedback      -> Y 0, Y 7, Y 2
//   L·R · PING   X = R time vs L (centre = same)                     Y = ping-pong     -> Y 1, Y 3
//   TONE · WOW   X = tone of the repeats                             Y = EARTH wow     -> Y 5, Y 6
//   WET · DRY    X = wet                                             Y = dry           -> Y 4, Y 9
//   keys: HOLD (Y 10) · LINK (Y 11 / Y 12: the two Cafes are one delay, ping-pong goes A -> B) · GRID (Y 8) · TAP
// NOISE (N ids) — the 8 pads go to both:
//   RING (size · spread) FEEDBACK · GRIT  SHIFT · LOOP  GATE (rate · open)  FILTER  SELF · INPUT  L · R  LEVEL
// HARMONY (V ids) — pads per Cafe like DELAY:
//   TIME · FB (V 0, V 10, V 1)  5TH DN · 5TH UP (V 4, V 5)  TONE · SPREAD (V 7, V 6)  UNISON · DRY (V 3, V 2)
//   keys: HOLD (V 13) · LINK (both rows move together) · GRID (V 11) · TAP

import Foundation

enum Preset {
    static let names = ["COCO_MOD", "ECHO", "BLE", "RESONATOR", "FORMANT", "SATURATOR", "HARMONY", "RUNGLER", "SELF_READ", "MULTI"]
    static let notes = [
        "coco looper · knobs + EARTH / FLIP / SKIP on the Cafe",
        "four-tap echo · organ on YELLOW · FLIP deeper · SKIP wobble",
        "played from here · GRAIN / COCO / DELAY / NOISE",
        "resonator bank · on the Cafe",
        "vowel filter · EARTH moves the vowel",
        "8 kinds · BUTTON = next · FLIP / SKIP change it",
        "unison + fifth down + fifth up · repeats climb in fifths",
        "coco chopped by a shift register · FLIP = clock · SKIP = data",
        "the sound on the tape steers the head · load a file = its own path",
        "7 effects · FLIP = next · SKIP = random · EARTH modulates",
    ]
    /// presets that exist in the firmware
    static let count = 10
    static let ble = 2
    static let harmony = 6
    static let multi = 9
    static let modeNames = ["GRAIN", "COCO", "DELAY", "NOISE"]
    static let modeIcons = ["circle.grid.3x3", "infinity", "repeat", "scribble.variable"]
    /// "03_BLE"
    static func tag(_ n: Int) -> String { String(format: "%02ld_", n + 1) + (n >= 0 && n < names.count ? names[n] : "—") }
}

/// what the 8 pads are right now
enum PadSet { case grain, coco, delay, noise, harmony, multi, knob }

/// MULTI's effects (firmware ids "F <effect> <0..7> <v>"; pad k = ids 2k, 2k+1; "—" = not used)
enum Fx {
    static let count = 7
    static let names = ["CLEAN", "TAP DELAY", "SAMPLER", "REVERSE", "GLITCH", "FOLD+OCT", "REVERB"]
    static let short = ["CLEAN", "TAPS", "SAMPLE", "REVRS", "GLITCH", "FOLD", "VERB"]
    static let titles: [[String]] = [
        ["LEVEL · —", "—", "—", "—"],
        ["TIME · FEEDBACK", "PATTERN · WIDTH", "TONE · WOW", "WET · DRY"],
        ["PITCH · LENGTH", "START · DECAY", "AUTO · TONE", "WET · DRY"],
        ["LENGTH · SPEED", "TONE · —", "—", "WET · DRY"],
        ["GRID · CHANCE", "SLICE · REPEATS", "PITCH · REVERSE", "CRUSH · WET"],
        ["DRIVE · BIAS", "OCT DN · OCT UP", "TONE · —", "WET · DRY"],
        ["SIZE · DAMP", "WIDTH · DIFFUSE", "—", "WET · DRY"],
    ]
    /// the firmware's defaults (fx_default)
    static let defaults: [[Int]] = [
        [500, 0, 0, 0, 0, 0, 0, 0],
        [625, 400, 0, 800, 700, 0, 600, 1000],
        [333, 400, 0, 300, 0, 1000, 700, 700],
        [400, 500, 1000, 0, 0, 0, 700, 500],
        [300, 500, 400, 300, 200, 200, 0, 1000],
        [300, 500, 600, 200, 800, 0, 1000, 0],
        [600, 400, 800, 500, 0, 0, 500, 1000],
    ]
}

enum CoPad: Int, CaseIterable {
    case speed, loop, fm, wobble, filter, crush, stereo, mix
    var title: String { ["SPEED · DUB", "LOOP", "EARTH FM", "WOBBLE", "FILTER", "CRUSH", "L · R", "DRY · LEVEL"][rawValue] }
    /// the same as the firmware's defaults (speed 1x forward, whole tape)
    var start: (Double, Double) { [(0.75, 0.0), (0.0, 1.0), (0.3, 0.2), (0.3, 0.0), (1.0, 0.2), (0.0, 0.0), (0.0, 0.0), (0.0, 0.5)][rawValue] }
    var ids: [Int] {
        switch self {
        case .speed: return [0, 1]
        case .loop: return [2, 3]
        case .fm: return [4, 5]
        case .wobble: return [6, 7]
        case .filter: return [8, 9]
        case .crush: return [10, 11]
        case .stereo: return [14, 15]           // only B: a little faster, its loop a little later
        case .mix: return [12, 13]
        }
    }
}

enum DlPad: Int, CaseIterable {
    case time, spread, tone, mix
    var title: String { ["TIME · FB", "L·R · PING", "TONE · WOW", "WET · DRY"][rawValue] }
    var start: (Double, Double) { [(0.625, 0.45), (0.5, 1.0), (0.7, 0.0), (0.6, 1.0)][rawValue] }
}

enum HdPad: Int, CaseIterable {
    case time, fifths, color, mix
    var title: String { ["TIME · FB", "5TH DN · 5TH UP", "TONE · SPREAD", "UNISON · DRY"][rawValue] }
    var start: (Double, Double) { [(0.625, 0.38), (0.6, 0.6), (0.65, 0.2), (0.55, 1.0)][rawValue] }
}

enum NzPad: Int, CaseIterable {
    case ring, feedback, shift, gate, filter, selfmod, stereo, out
    var title: String { ["RING", "FEEDBACK · GRIT", "SHIFT · LOOP", "GATE", "FILTER", "SELF · INPUT", "L · R", "LEVEL"][rawValue] }
    var start: (Double, Double) { [(0.45, 0.5), (0.85, 0.35), (0.6, 0.0), (0.35, 0.6), (0.65, 0.45), (0.3, 0.0), (0.0, 0.0), (0.5, 0.5)][rawValue] }
    var ids: [Int] {
        switch self {
        case .ring: return [0, 1]
        case .feedback: return [2, 3]
        case .shift: return [4, 5]
        case .gate: return [6, 7]
        case .filter: return [8, 9]
        case .selfmod: return [10, 12]
        case .stereo: return [0, 4, 6]            // B's ring, clock and gate drift away from A's
        case .out: return [11]
        }
    }
}

final class Rig: ObservableObject {
    private static let d = UserDefaults.standard

    /// the preset each Cafe is on (app side, 0-based) and the BLE preset's mode per Cafe
    @Published var preset: [Int] = (Rig.d.array(forKey: "rig.preset") as? [Int]) ?? [Preset.ble, Preset.ble] {
        didSet { Self.d.set(preset, forKey: "rig.preset") }
    }
    @Published var mode: [Int] = (Rig.d.array(forKey: "rig.mode") as? [Int]) ?? [0, 0] {
        didSet { Self.d.set(mode, forKey: "rig.mode") }
    }
    /// who the preset manager talks to: 0 = A, 1 = B, 2 = both
    @Published var target: Int = (Rig.d.object(forKey: "rig.target") as? Int) ?? 2 {
        didSet { Self.d.set(target, forKey: "rig.target") }
    }
    /// firmware update: 0 = A, 1 = B, 2 = both
    @Published var updTarget: Int = 2
    @Published var bpm: Double = (Rig.d.object(forKey: "rig.bpm") as? Double) ?? 120 {
        didSet { Self.d.set(bpm, forKey: "rig.bpm") }
    }
    @Published var link = false
    @Published var dlHold = false
    @Published var hdHold = false
    @Published var grid = true

    let dlAxes: [PadAxis] = (0..<8).map { PadAxis(DlPad(rawValue: $0 % 4)!.start) }
    let hdAxes: [PadAxis] = (0..<8).map { PadAxis(HdPad(rawValue: $0 % 4)!.start) }
    let nzAxes: [PadAxis] = NzPad.allCases.map { PadAxis($0.start) }
    let coAxes: [PadAxis] = CoPad.allCases.map { PadAxis($0.start) }
    @Published var coReverse = false

    // MULTI: pads per Cafe, per effect (4 each); the effect each Cafe is on; switches
    let fxAxes: [[[PadAxis]]] = (0..<2).map { _ in
        (0..<Fx.count).map { e in (0..<4).map { k in PadAxis((Double(Fx.defaults[e][2 * k]) / 1000, Double(Fx.defaults[e][2 * k + 1]) / 1000)) } }
    }
    @Published var fxLocal = [0, 0]
    @Published var fxLink = false
    @Published var fxHold = false
    @Published var fxXfade = 0.35          // F 91: 0.02 + v² × 2 s
    @Published var fxEarth = 0.62          // F 95: EARTH depth
    @Published var fxLock = 0.3            // F 96: the shortest time between changes, 0.05 + v² × 4.95 s

    /// the Cafe whose preset the screen shows
    var focus: Int { target == 1 ? 1 : 0 }
    var ctxPreset: Int { preset[focus] }
    var ctxMode: Int { mode[focus] }
    var slots: [Int] { target == 2 ? [0, 1] : [target] }

    var padSet: PadSet {
        if ctxPreset == Preset.harmony { return .harmony }
        if ctxPreset == Preset.multi { return .multi }
        guard ctxPreset == Preset.ble else { return .knob }
        return [PadSet.grain, .coco, .delay, .noise][min(max(ctxMode, 0), 3)]
    }
    /// pads laid out per Cafe (top row A, bottom row B)
    var perRow: Bool { padSet == .delay || padSet == .harmony || padSet == .multi }

    /// is this Cafe on what the screen shows?
    func inCtx(_ slot: Int) -> Bool {
        guard preset[slot] == ctxPreset else { return false }
        return ctxPreset != Preset.ble || mode[slot] == ctxMode
    }

    // MARK: DELAY
    func dlCommands(pad i: Int) -> [String] {
        let a = dlAxes[i]
        let x = Int((a.x * 1000).rounded()), y = Int((a.y * 1000).rounded())
        switch DlPad(rawValue: i % 4)! {
        case .time: return ["Y 0 \(x)", "Y 7 \(x)", "Y 2 \(y)"]
        case .spread: return ["Y 1 \(x)", "Y 3 \(y)"]
        case .tone: return ["Y 5 \(x)", "Y 6 \(y)"]
        case .mix: return ["Y 4 \(x)", "Y 9 \(y)"]
        }
    }
    func dlAll(slot: Int) -> [String] {
        (0..<4).flatMap { dlCommands(pad: slot * 4 + $0) }
            + ["Y 8 \(grid ? 1000 : 0)", "Y 10 \(dlHold ? 1000 : 0)",
               "Y 12 \(slot == 1 ? 1000 : 0)", "Y 11 \(link ? 1000 : 0)"]
    }

    // MARK: HARMONY
    func hdCommands(pad i: Int) -> [String] {
        let a = hdAxes[i]
        let x = Int((a.x * 1000).rounded()), y = Int((a.y * 1000).rounded())
        switch HdPad(rawValue: i % 4)! {
        case .time: return ["V 0 \(x)", "V 10 \(x)", "V 1 \(y)"]
        case .fifths: return ["V 4 \(x)", "V 5 \(y)"]
        case .color: return ["V 7 \(x)", "V 6 \(y)"]
        case .mix: return ["V 3 \(x)", "V 2 \(y)"]
        }
    }
    func hdAll(slot: Int) -> [String] {
        (0..<4).flatMap { hdCommands(pad: slot * 4 + $0) } + ["V 11 \(grid ? 1000 : 0)", "V 13 \(hdHold ? 1000 : 0)"]
    }

    // MARK: COCO
    func coValue(_ id: Int, slot: Int) -> Double {
        func a(_ p: CoPad) -> PadAxis { coAxes[p.rawValue] }
        let v: Double
        switch id {
        case 0: v = a(.speed).x
        case 1: v = a(.speed).y
        case 2: v = a(.loop).x
        case 3: v = a(.loop).y
        case 4: v = a(.fm).x
        case 5: v = a(.fm).y
        case 6: v = a(.wobble).x
        case 7: v = a(.wobble).y
        case 8: v = a(.filter).x
        case 9: v = a(.filter).y
        case 10: v = a(.crush).x
        case 11: v = a(.crush).y
        case 12: v = a(.mix).x
        case 13: v = a(.mix).y
        case 14: v = slot == 1 ? a(.stereo).x : 0
        case 15: v = slot == 1 ? a(.stereo).y : 0
        default: v = 0
        }
        return min(max(v, 0), 1)
    }
    func coLine(_ id: Int, slot: Int) -> String { "C \(id) \(Int((coValue(id, slot: slot) * 1000).rounded()))" }
    func coCommands(pad i: Int, slot: Int) -> [String] {
        guard let p = CoPad(rawValue: i) else { return [] }
        return p.ids.map { coLine($0, slot: slot) }
    }
    func coAll(slot: Int) -> [String] { (0...15).map { coLine($0, slot: slot) } + ["C 16 \(coReverse ? 1 : 0)"] }

    // MARK: MULTI
    func fxCommands(slot: Int, e: Int, k: Int) -> [String] {
        let a = fxAxes[slot][e][k]
        return ["F \(e) \(2 * k) \(Int((a.x * 1000).rounded()))", "F \(e) \(2 * k + 1) \(Int((a.y * 1000).rounded()))"]
    }
    func fxSettings() -> [String] {
        ["F 91 \(Int(fxXfade * 1000))", "F 95 \(Int(fxEarth * 1000))", "F 96 \(Int(fxLock * 1000))", "F 94 \(fxHold ? 1 : 0)"]
    }
    func fxAll(slot: Int) -> [String] {
        (0..<Fx.count).flatMap { e in (0..<4).flatMap { k in fxCommands(slot: slot, e: e, k: k) } }
            + fxSettings() + ["F 90 \(fxLocal[slot])"]
    }

    // MARK: NOISE
    func nzValue(_ id: Int, slot: Int) -> Double {
        func a(_ p: NzPad) -> PadAxis { nzAxes[p.rawValue] }
        let b = slot == 1, lr = a(.stereo)
        let v: Double
        switch id {
        case 0: v = a(.ring).x + (b ? lr.x * 0.08 : 0)
        case 1: v = a(.ring).y
        case 2: v = a(.feedback).x
        case 3: v = a(.feedback).y
        case 4: v = a(.shift).x + (b ? lr.x * 0.12 : 0)
        case 5: v = a(.shift).y
        case 6: v = a(.gate).x + (b ? lr.y * 0.15 : 0)
        case 7: v = a(.gate).y
        case 8: v = a(.filter).x
        case 9: v = a(.filter).y
        case 10: v = a(.selfmod).x
        case 11: v = a(.out).x
        case 12: v = a(.selfmod).y
        default: v = 0
        }
        return min(max(v, 0), 1)
    }
    func nzLine(_ id: Int, slot: Int) -> String { "N \(id) \(Int((nzValue(id, slot: slot) * 1000).rounded()))" }
    func nzCommands(pad i: Int, slot: Int) -> [String] {
        guard let p = NzPad(rawValue: i) else { return [] }
        return p.ids.map { nzLine($0, slot: slot) }
    }
    func nzAll(slot: Int) -> [String] { (0...12).map { nzLine($0, slot: slot) } }
    /// the dice key: somewhere new for every NOISE pad (except the level)
    func nzDice() {
        for p in NzPad.allCases where p != .out && p != .stereo {
            nzAxes[p.rawValue].x = Double.random(in: 0.05...0.95)
            nzAxes[p.rawValue].y = Double.random(in: 0...0.9)
        }
    }

    // MARK: tap tempo (the phone's TAP key)
    private var taps: [Date] = []
    /// returns a new BPM after the second tap
    func tap() -> Double? {
        let now = Date()
        taps = taps.filter { now.timeIntervalSince($0) < 2.5 } + [now]
        guard taps.count >= 2 else { return nil }
        let gaps = zip(taps.dropFirst(), taps).map { $0.timeIntervalSince($1) }
        let avg = gaps.suffix(3).reduce(0, +) / Double(min(3, gaps.count))
        guard avg > 0.1 else { return nil }
        var b = 60 / avg
        while b < 40 { b *= 2 }
        while b > 240 { b /= 2 }
        return b
    }
}

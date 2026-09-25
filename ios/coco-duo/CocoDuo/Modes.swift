// Modes.swift — coco duo (k.odk)
// The preset manager's model: which preset (1–10) each Cafe is on, the BLE preset's mode, the target (A / B / both),
// the shared tempo, and the pads of DELAY, NOISE and HARMONY. (GRAIN and RUNGLER pads: GrainMode.swift, Benjolin.swift)
//
// Firmware esp_cafe_duo v3 playlist ("G <n>", 0-based):
//   0 COCO_MOD · 1 ECHO · 2 BLE (modes GRAIN / RUNGLER / DELAY / NOISE, "M 25 <m>") · 3 RESONATOR · 4 FORMANT
//   5 SATURATOR · 6 HARMONY (three-layer harmonic delay)            slots 8–10: empty for now
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
    static let names = ["COCO_MOD", "ECHO", "BLE", "RESONATOR", "FORMANT", "SATURATOR", "HARMONY", "EMPTY", "EMPTY", "EMPTY"]
    static let notes = [
        "coco looper · knobs + EARTH / FLIP / SKIP on the Cafe",
        "four-tap echo · organ on YELLOW · FLIP deeper · SKIP wobble",
        "played from here · GRAIN / RUNGLER / DELAY / NOISE",
        "resonator bank · on the Cafe",
        "vowel filter · EARTH moves the vowel",
        "8 kinds · BUTTON = next · FLIP / SKIP change it",
        "unison + fifth down + fifth up · repeats climb in fifths",
        "—", "—", "—",
    ]
    /// presets that exist in the firmware
    static let count = 7
    static let ble = 2
    static let harmony = 6
    static let modeNames = ["GRAIN", "RUNGLER", "DELAY", "NOISE"]
    static let modeIcons = ["circle.grid.3x3", "waveform.path.ecg", "repeat", "scribble.variable"]
    /// "03_BLE"
    static func tag(_ n: Int) -> String { String(format: "%02ld_", n + 1) + (n >= 0 && n < names.count ? names[n] : "—") }
}

/// what the 8 pads are right now
enum PadSet { case grain, rungler, delay, noise, harmony, knob }

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

    /// the Cafe whose preset the screen shows
    var focus: Int { target == 1 ? 1 : 0 }
    var ctxPreset: Int { preset[focus] }
    var ctxMode: Int { mode[focus] }
    var slots: [Int] { target == 2 ? [0, 1] : [target] }

    var padSet: PadSet {
        if ctxPreset == Preset.harmony { return .harmony }
        guard ctxPreset == Preset.ble else { return .knob }
        return [PadSet.grain, .rungler, .delay, .noise][min(max(ctxMode, 0), 3)]
    }
    /// pads laid out per Cafe (top row A, bottom row B)
    var perRow: Bool { padSet == .delay || padSet == .harmony }

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

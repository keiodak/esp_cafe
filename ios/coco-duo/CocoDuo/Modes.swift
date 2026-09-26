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
//   FILTER  CRUSH (hold · bits)  L · R (B faster · B's loop later)   (levels / dry / wet: on the Cafe itself)
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
// HARMONY (V ids) — rpls-like replay, pads per Cafe like DELAY:
//   VOICE 1 · TIMING (V 0, V 1)  VOICE 2 · TIMING (V 2, V 3)  CYCLE · FEEDBACK (V 4, V 5)  OVERDUB · TONE (V 8, V 9)
//   keys: HOLD (V 13) · LINK (both rows move together) · SYNC (cycles start together) · TAP

import Foundation

enum Preset {
    /// the firmware's pool (esp_cafe_duo 3.21+): 0–10 ours, 11–35 Apple π's (ieat31415). "G <id>" loads any of them.
    static let names = ["COCO_MOD", "ECHO", "BLE", "RESONATOR", "FORMANT", "SATURATOR", "HARMONY", "RUNGLER", "SELF_READ", "MULTI", "ARP_DELAY",
                        "COCO_OG", "ECHO_MOD", "FLANGER", "KARPLUS", "SPRING", "GRAIN_VERB", "FDN_VERB", "HARMONIZER",
                        "EXT_SYNC", "WINDOW", "SPLICER", "SCRAMBLER", "DISSOLVE", "SAMPLER", "SAMPLER_4X", "GRANULAR",
                        "PHASING", "BYTEBEATS", "MEGABYTES", "ARCADE", "BYTE_FX", "WAVETABLE", "DRONE", "GROOVEBOX", "POLYRHYTHM"]
    static let notes = [
        "coco looper · knobs + EARTH / FLIP / SKIP on the Cafe",
        "four-tap echo · organ on YELLOW · FLIP deeper · SKIP wobble",
        "played from here · GRAIN / COCO / DELAY / NOISE",
        "resonator bank · on the Cafe",
        "vowel filter · EARTH moves the vowel",
        "8 kinds · BUTTON = next · FLIP / SKIP change it",
        "replay in intervals (like rpls) · 2 voices: interval + timing",
        "coco chopped by a shift register · FLIP = clock · SKIP = data",
        "the sound on the tape steers the head · load a file = its own path",
        "7 effects · FLIP = next · SKIP = random · EARTH modulates",
        "the phone plays a sine arpeggio into the Cafe's stereo tap delay · SKIP = tap",
        "Apple π · the original Cocoquantus coco · EARTH = record switch",
        "Apple π · prime-number delay / reverb · EARTH = low-pass · SKIP = room",
        "Apple π · very short delay · EARTH = head spread · ASH + YELLOW = stereo",
        "Apple π · plucked string",
        "Apple π · spring reverb · EARTH = damping · FLIP = surf / lush",
        "Apple π · live granular reverb · EARTH = grain size · FLIP = shimmer",
        "Apple π · feedback delay network · EARTH = room size",
        "Apple π · pitch-tracking over / under tones",
        "Apple π · delay locked to a clock on SKIP · FLIP = reverse",
        "Apple π · buffer length without pitch · reverb <-> delay",
        "Apple π · loop start / end on EARTH (FLIP = which) · SKIP = jump",
        "Apple π · stutter in segments · EARTH = segment · FLIP = random",
        "Apple π · the loop slowly falls apart · EARTH = drop-outs",
        "Apple π · one-shot sampler · BUTTON = mode · SKIP = trigger",
        "Apple π · 4 slices · EARTH = slice · SKIP / FLIP = one-shots",
        "Apple π · 16 grains · SKIP = trigger · EARTH = position",
        "Apple π · 4 drifting play heads · BUTTON = rec / play",
        "Apple π · bytebeat synth",
        "Apple π · more bytebeats",
        "Apple π · 8-bit arcade sounds",
        "Apple π · bytebeat effects",
        "Apple π · wavetable voice",
        "Apple π · drone voices",
        "Apple π · drum machine",
        "Apple π · polyrhythmic drums",
    ]
    /// how many the firmware has (the pool) and how many the playlist may hold
    static let poolCount = 36
    static let maxPlaylist = 11
    /// the presets played from the phone over Bluetooth (their rows are tinted)
    static let phonePlayed: Set<Int> = [2, 9, 10]
    /// CHAR: the slider next to the tempo, one per preset ("X <0..1000> <preset>"); what it does on each
    static let charNames = ["BIT", "WEAR", "BIT", "BIT", "VOWEL", "DRIVE", "GRAIN", "BIT", "BIT", "BIT", "BIT"]
    /// the firmware's defaults (ch_v): echo = full wobble, formant = its original Q, harmony = GRAIN (rpls)
    static let charDefaults: [Double] = [0, 1, 0, 0, 0.714, 0, 1, 0, 0, 0, 0]
    /// our own presets (0–10): the ones with CHAR values and phone pads
    static let count = 11
    static let ble = 2
    static let harmony = 6
    static let multi = 9
    static let arp = 10
    static let modeNames = ["GRAIN", "COCO", "DELAY", "NOISE"]
    /// the default playlist (up to 11 pool ids): BLE, MULTI, ARP_DELAY, HARMONY, then the Cafe's own ones
    static let defaultPlaylist = [2, 9, 10, 6, 0, 1, 3, 4, 5, 7, 8]
    /// the playlist now (Rig keeps it; it is also the Cafe's BUTTON menu) — the numbers shown are places in it
    static var order = defaultPlaylist
    static func number(_ n: Int) -> Int { (order.firstIndex(of: n) ?? -1) + 1 }
    static let modeIcons = ["circle.grid.3x3", "infinity", "repeat", "scribble.variable"]
    /// "03_BLE"
    static func tag(_ n: Int) -> String {
        let k = number(n)
        return (k > 0 ? String(format: "%02ld_", k) : "--_") + (n >= 0 && n < names.count ? names[n] : "—")
    }
}

/// what the 8 pads are right now
enum PadSet { case grain, coco, delay, noise, harmony, multi, arp, knob }

/// ARP_DELAY: top row = the phone's arpeggiator, bottom row = the Cafe's tap delay ("F 1 <id> <v>")
enum ArpPad {
    static let titles = ["ROOT · CHORD", "PATTERN · OCTAVES", "RATE · SWING", "GATE · DECAY",
                         "TIME · FEEDBACK", "PING-PONG · SPREAD", "—", "TAP"]      // (a clean digital delay: no tone / wow)
    static let starts: [(Double, Double)] = [(0.5, 0.0), (0.0, 0.3), (0.55, 0.0), (0.5, 0.35),
                                             (0.625, 0.55), (1.0, 0.5), (0.8, 0.3), (0.9, 1.0)]
    static func root(_ x: Double) -> Int { 24 + min(48, Int(x * 49)) }        // C1 … C5 (with OCTAVES up to C9)
    static func chord(_ y: Double) -> Int { min(6, Int(y * 7)) }
    static func pattern(_ x: Double) -> Int { min(6, Int(x * 7)) }
    static func octaves(_ y: Double) -> Int { 1 + min(3, Int(y * 4)) }
    static func rate(_ x: Double) -> Int { min(5, Int(x * 6)) }
    /// what a pad is set to, under its title
    static func caption(_ i: Int, _ x: Double, _ y: Double) -> String {
        switch i {
        case 0: let r = root(x); return "\(ArpEngine.noteNames[r % 12])\(r / 12 - 1) \(ArpEngine.chordNames[chord(y)])"
        case 1: return "\(ArpEngine.patterns[pattern(x)]) ×\(octaves(y))"
        case 2: return "\(ArpEngine.rateNames[rate(x)]) · SWING \(Int(y * 60))%"
        case 3: return "GATE \(Int((0.05 + x * 0.9) * 100))%"
        default: return ""
        }
    }
}

/// MULTI's effects (firmware ids "F <effect> <0..7> <v>"; pad k = ids 2k, 2k+1; "—" = not used)
enum Fx {
    static let count = 8
    static let names = ["CLEAN", "ECHO", "SAMPLER", "REVERSE", "GLITCH", "FOLD+OCT", "REVERB", "KARPLUS"]
    static let short = ["CLEAN", "ECHO", "SAMPLE", "REVRS", "GLITCH", "FOLD", "VERB", "KARP"]
    static let titles: [[String]] = [
        ["—", "—", "—", "—"],
        ["TIME · FEEDBACK", "PING-PONG · SPREAD", "TONE · WOW", "—"],
        ["PITCH · LENGTH", "START · DECAY", "AUTO · TONE", "—"],
        ["LENGTH · SPEED", "TONE · —", "—", "—"],
        ["GRID · CHANCE", "SLICE · LENGTH", "VARIETY · PITCH", "—"],
        ["DRIVE · BIAS", "OCT DN · OCT UP", "TONE · —", "—"],
        ["SIZE · DAMP", "WIDTH · DIFFUSE", "HOWL · MOD", "—"],
        ["PITCH · DECAY", "DAMP · PLUCK", "WOBBLE · SPREAD", "—"],
    ]
    /// the firmware's defaults (fx_default)
    static let defaults: [[Int]] = [
        [500, 0, 0, 0, 0, 0, 0, 0],
        [625, 550, 1000, 500, 800, 300, 900, 1000],
        [333, 400, 0, 300, 0, 1000, 900, 600],
        [400, 500, 1000, 0, 0, 0, 1000, 300],
        [300, 550, 400, 300, 750, 300, 150, 1000],
        [300, 500, 600, 200, 800, 0, 1000, 0],
        [750, 300, 800, 500, 400, 400, 450, 1000],
        [350, 550, 700, 300, 300, 500, 800, 1000],
    ]
}

enum CoPad: Int, CaseIterable {
    case speed, loop, fm, wobble, filter, crush, stereo, mix
    var title: String { ["SPEED · DUB", "LOOP", "EARTH FM", "WOBBLE", "FILTER", "CRUSH", "L · R", "—"][rawValue] }
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
        case .mix: return []                     // (levels are set on the Cafe itself)
        }
    }
}

enum DlPad: Int, CaseIterable {
    case time, spread, tone, mix
    var title: String { ["TIME · FB", "L·R · PING", "TONE · WOW", "TAP"][rawValue] }
    var start: (Double, Double) { [(0.625, 0.45), (0.5, 1.0), (0.7, 0.0), (0.6, 1.0)][rawValue] }
}

/// HARMONY (rpls-like replay): per Cafe, VOICE 1 / VOICE 2 = interval (X) and timing in the cycle (Y)
enum HdPad: Int, CaseIterable {
    case voice1, voice2, cycle, tape
    var title: String { ["VOICE 1 · TIMING", "VOICE 2 · TIMING", "CYCLE · FEEDBACK", "TAP"][rawValue] }
    var start: (Double, Double) { [(0.273, 0.0), (0.727, 0.267), (0.6, 0.15), (0.0, 1.0)][rawValue] }
    var ids: (Int, Int) { [(0, 1), (2, 3), (4, 5), (8, 9)][rawValue] }
    static let intervals = ["REV", "REV -OCT", "-2 OCT", "-OCT", "-5TH", "-4TH", "UNISON", "+4TH", "+5TH", "+OCT", "+OCT+5TH", "+2 OCT"]
    static let cycles = ["1/4", "1/2", "1", "2", "4", "8"]
    static func caption(_ k: Int, _ x: Double, _ y: Double) -> String {
        switch k {
        case 0, 1: return "\(intervals[min(11, Int(x * 11 + 0.5))]) · \(Int(y * 15 + 0.5))/16"
        case 2: return "\(cycles[min(5, Int(x * 5 + 0.5))]) BEAT · FB \(Int(y * 100))%"
        default: return "KEEP \(Int(x * 90))%"
        }
    }
}

enum NzPad: Int, CaseIterable {
    case ring, feedback, shift, gate, filter, selfmod, stereo, osc
    var title: String { ["RING", "FEEDBACK · GRIT", "SHIFT · LOOP", "GATE", "FILTER", "SELF · INPUT", "L · R", "OSC · FOLD"][rawValue] }
    var start: (Double, Double) { [(0.45, 0.5), (0.85, 0.35), (0.6, 0.0), (0.35, 0.6), (0.65, 0.45), (0.3, 0.0), (0.0, 0.0), (0.4, 0.0)][rawValue] }
    var ids: [Int] {
        switch self {
        case .ring: return [0, 1]
        case .feedback: return [2, 3]
        case .shift: return [4, 5]
        case .gate: return [6, 7]
        case .filter: return [8, 9]
        case .selfmod: return [10, 12]
        case .stereo: return [0, 4, 6, 13]        // B's ring, clock, gate and oscillators drift away from A's
        case .osc: return [13, 14]               // three cross-modulated oscillators through a folder (Y = 0: off)
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
    /// CHAR per Cafe, per preset (0...1)
    @Published var charV: [[Double]] = (Rig.d.array(forKey: "rig.char") as? [[Double]]).flatMap { $0.count == 2 && $0.allSatisfy { $0.count == Preset.count } ? $0 : nil }
        ?? [Preset.charDefaults, Preset.charDefaults] {
        didSet { Self.d.set(charV, forKey: "rig.char") }
    }
    /// the playlist: up to 11 pool ids, in order (PRESET DESIGN edits it; it goes to the Cafes as "L …")
    @Published var playlist: [Int] = {
        let p = (Rig.d.array(forKey: "rig.playlist") as? [Int])?.filter { $0 >= 0 && $0 < Preset.poolCount } ?? []
        let v = p.isEmpty ? Preset.defaultPlaylist : Array(p.prefix(Preset.maxPlaylist))
        Preset.order = v
        return v
    }() {
        didSet { Preset.order = playlist; Self.d.set(playlist, forKey: "rig.playlist") }
    }
    /// PRESET DESIGN memories 1–5: saved sets of the 11 slots ([] = nothing saved)
    @Published var designBank: [[Int]] = (Rig.d.array(forKey: "rig.designBank") as? [[Int]]).flatMap { $0.count == 5 ? $0 : nil }
        ?? Array(repeating: [], count: 5) {
        didSet { Self.d.set(designBank, forKey: "rig.designBank") }
    }
    /// PRESET DESIGN's 11 slots (pool ids, -1 = empty); the playlist is these without the empties
    @Published var design: [Int] = {
        let v = (Rig.d.array(forKey: "rig.design") as? [Int]) ?? []
        if v.count == Preset.maxPlaylist { return v }
        let p = (Rig.d.array(forKey: "rig.playlist") as? [Int]) ?? Preset.defaultPlaylist
        return Array((p + Array(repeating: -1, count: Preset.maxPlaylist)).prefix(Preset.maxPlaylist))
    }() {
        didSet { Self.d.set(design, forKey: "rig.design") }
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
    @Published var fxLink = false          // LINK FX: both Cafes on the same effect
    @Published var fxPadLink = false       // LINK PADS: the XY pads move both Cafes
    @Published var fxHold = false
    @Published var fxDrift = false         // DRIFT: the pads wander by themselves
    @Published var fxXfade = 0.35          // F 91: 0.02 + v² × 2 s
    @Published var fxEarth = 0.62          // F 95: EARTH depth
    @Published var fxLock = 0.3            // F 96: the shortest time between changes, 0.05 + v² × 4.95 s

    // ARP_DELAY
    let arpAxes: [PadAxis] = ArpPad.starts.map { PadAxis($0) }
    @Published var arpPlaying = false
    @Published var arpGlide = 0.0
    @Published var arpFifth = 0.0
    @Published var arpLevel = 0.7
    @Published var arpEarth = true            // EARTH → NOTES (ARP_DELAY)
    /// the Cafe's tap delay from the bottom row (pad 4..7 -> F 1 ids 0..7)
    func arpDelayCommands(pad i: Int) -> [String] {
        let a = arpAxes[i], k = i - 4
        return ["F 1 \(2 * k) \(Int((a.x * 1000).rounded()))", "F 1 \(2 * k + 1) \(Int((a.y * 1000).rounded()))"]
    }
    func arpDelayAll() -> [String] { (4..<7).flatMap { arpDelayCommands(pad: $0) } + ["F 94 \(fxHold ? 1 : 0)", "F 95 \(Int(fxEarth * 1000))"] }

    /// the Cafe whose preset the screen shows
    var focus: Int { target == 1 ? 1 : 0 }
    var ctxPreset: Int { preset[focus] }
    var ctxMode: Int { mode[focus] }
    var slots: [Int] { target == 2 ? [0, 1] : [target] }

    var padSet: PadSet {
        if ctxPreset == Preset.harmony { return .harmony }
        if ctxPreset == Preset.multi { return .multi }
        if ctxPreset == Preset.arp { return .arp }
        guard ctxPreset == Preset.ble else { return .knob }
        return [PadSet.grain, .coco, .delay, .noise][min(max(ctxMode, 0), 3)]
    }
    /// pads laid out per Cafe (top row A, bottom row B)
    var perRow: Bool { padSet == .delay || padSet == .harmony || padSet == .multi }
    /// the TAP pad (tempo): the 4th pad of each row where there is a tempo (ARP: only the bottom row's)
    func isTapPad(_ i: Int) -> Bool {
        switch padSet {
        case .delay, .harmony, .multi: return i % 4 == 3
        case .arp: return i == 7
        default: return false
        }
    }

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
        (0..<3).flatMap { dlCommands(pad: slot * 4 + $0) }
            + ["Y 8 \(grid ? 1000 : 0)", "Y 10 \(dlHold ? 1000 : 0)",
               "Y 12 \(slot == 1 ? 1000 : 0)", "Y 11 \(link ? 1000 : 0)"]
    }

    // MARK: HARMONY
    func hdCommands(pad i: Int) -> [String] {
        let a = hdAxes[i]
        let x = Int((a.x * 1000).rounded()), y = Int((a.y * 1000).rounded())
        let ids = HdPad(rawValue: i % 4)!.ids
        return ["V \(ids.0) \(x)", "V \(ids.1) \(y)"]
    }
    func hdAll(slot: Int) -> [String] {
        (0..<3).flatMap { hdCommands(pad: slot * 4 + $0) } + ["V 13 \(hdHold ? 1000 : 0)"]
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
    func coAll(slot: Int) -> [String] { (0...15).filter { $0 != 12 && $0 != 13 }.map { coLine($0, slot: slot) } + ["C 16 \(coReverse ? 1 : 0)"] }

    // MARK: MULTI
    /// a pad's lines; "—" halves are not sent (the mix stays at the firmware's settings)
    func fxCommands(slot: Int, e: Int, k: Int) -> [String] {
        let t = Fx.titles[e][k]
        if t == "—" { return [] }
        let a = fxAxes[slot][e][k]
        var out = ["F \(e) \(2 * k) \(Int((a.x * 1000).rounded()))"]
        if !t.hasSuffix("· —") { out.append("F \(e) \(2 * k + 1) \(Int((a.y * 1000).rounded()))") }
        return out
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
        case 13: v = a(.osc).x + (b ? lr.x * 0.05 : 0)
        case 14: v = a(.osc).y
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
    func nzAll(slot: Int) -> [String] { (0...14).filter { $0 != 11 }.map { nzLine($0, slot: slot) } }
    /// the dice key: somewhere new for every NOISE pad (except the level)
    func nzDice() {
        for p in NzPad.allCases where p != .stereo {
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

// GrainMode.swift — coco duo (k.odk)
// GRAIN mode of the BLE preset (preset 3 of esp_cafe_duo). Left input -> Cafe A, right -> Cafe B.
// Each Cafe keeps recording its input and plays smooth, overlapping grains of it (granular).
// Both follow ONE score (grain n gets the same time / pitch / place on both), synced by "Z",
// so L and R move together; the L · R pad pulls them apart gradually and shifts one in time.
//
//   DENSITY  X = grains per second (1 … 80)       Y = jitter (0 = an even stream)
//   LENGTH   X = grain length (10 … 500 ms)       Y = shape (0 = pure sin² window, up = flatter)
//   PITCH    X = speed / pitch (-3 .. +3 octaves, centre = 1x)       Y = spread over intervals (bottom = one pitch only)
//   WHERE    X = how far back in the tape         Y = scatter
//   FILTER   X = low-pass cutoff (right = open)   Y = resonance
//   REV·HOLD X = share of backwards grains        Y = pitch hold (1 … 64 grains keep one pitch)
//   L · R    X = separation: 0 = the same grains L and R; up = each its own dice, AND tempo (±30 %), pitch
//              (A down / B up, to a fifth), length, jitter, spread and scatter pull apart. Back to 0 = re-synced.
//            Y = R later (up to one gap)
//   LAYERS   X = grains at once (1 … 6)           (levels are set on the Cafe itself)
// Firmware ids: M <id> <0..1000> — 0 density 1 jitter 2 length 3 shape 4 pitch 5 spread 6 where 7 scatter
//   8 filter 9 resonance 10 reverse 11 pitch hold 12 layers 13 level 14 offset 15 separation 16 which Cafe
//   20 mark · 21 clear · 22 use marks · 23 freeze · 24 percussion · "Z" = restart the score (sent to both at once)
// Keys in GRAIN: top-left CAFES panel · snowflake = FREEZE (stop recording, keep taking grains from this moment)
//   bottom-left = mode (DUO / GRAIN) · metronome = PERCUSSION (struck grains: instant attack, curved fall)

import Foundation

enum GrainPad: Int, CaseIterable {
    case density, length, pitch, place, filter, reverse, stereo, layers
    var title: String { ["DENSITY", "LENGTH", "PITCH", "WHERE", "FILTER", "REV · HOLD", "L · R", "LAYERS · —"][rawValue] }
    /// same as the firmware's defaults
    var start: (Double, Double) {
        [(0.55, 0.15), (0.55, 0.2), (0.5, 0), (0.2, 0.25), (1.0, 0.2), (0, 0.7), (0, 0), (0.6, 0.5)][rawValue]
    }
    /// the firmware ids this pad changes
    var ids: [Int] {
        switch self {
        case .density: return [0, 1]
        case .length:  return [2, 3]
        case .pitch:   return [4, 5]
        case .place:   return [6, 7]
        case .filter:  return [8, 9]
        case .reverse: return [10, 11]
        case .stereo:  return [15, 14]           // separation (both), offset (only B moves)
        case .layers:  return [12]
        }
    }
}

final class GrainMode: ObservableObject {
    @Published var useMarks = false
    @Published var freeze = false                  // hold the moment (both Cafes)
    @Published var perc = false                    // struck grains instead of smooth ones
    @Published var move = false                    // MOVE: a new pitch every grain, gliding
    @Published var fold = false                    // FOLD: a little wave fold on the grains (more with longer grains)
    @Published var marks = 0                       // how many of the 8 slots hold something
    private var nextMark = 0

    let axes: [PadAxis] = GrainPad.allCases.map { PadAxis($0.start) }

    /// one parameter for one side (slot 0 = A = left, 1 = B = right)
    func value(_ id: Int, slot: Int) -> Double {
        func a(_ p: GrainPad) -> PadAxis { axes[p.rawValue] }
        let v: Double
        switch id {
        case 0: v = a(.density).x
        case 1: v = a(.density).y
        case 2: v = a(.length).x
        case 3: v = a(.length).y
        case 4: v = a(.pitch).x
        case 5: v = a(.pitch).y
        case 6: v = a(.place).x
        case 7: v = a(.place).y
        case 8: v = a(.filter).x
        case 9: v = a(.filter).y
        case 10: v = a(.reverse).x
        case 11: v = a(.reverse).y
        case 12: v = a(.layers).x
        case 13: v = a(.layers).y
        case 14: v = slot == 1 ? a(.stereo).y : 0          // only the right side is shifted in time
        case 15: v = a(.stereo).x
        case 16: v = Double(slot)                          // which side this Cafe is (its "own" score)
        default: v = 0
        }
        return min(max(v, 0), 1)
    }

    func line(_ id: Int, slot: Int) -> String {
        if id == 16 { return "M 16 \(slot == 1 ? 1000 : 0)" }
        return "M \(id) \(Int((value(id, slot: slot) * 1000).rounded()))"
    }

    /// what to send when pad `i` moved
    func commands(pad i: Int, slot: Int) -> [String] {
        guard let p = GrainPad(rawValue: i) else { return [] }
        return p.ids.map { line($0, slot: slot) }
    }

    /// everything (after connecting or switching mode)
    func allCommands(slot: Int) -> [String] {
        (0...16).filter { $0 != 13 }.map { line($0, slot: slot) }
            + ["M 22 \(useMarks ? 1 : 0)", "M 23 \(freeze ? 1 : 0)", "M 24 \(perc ? 1 : 0)", "M 26 \(move ? 1 : 0)", "M 27 \(fold ? 1 : 0)"]
    }

    /// true once, when the L · R separation comes back to (almost) zero: time to put L and R back in step
    private var lastSep = 0.0
    func separationReturned() -> Bool {
        let s = axes[GrainPad.stereo.rawValue].x
        defer { lastSep = s }
        return lastSep > 0.03 && s <= 0.03
    }

    /// restart the score on both Cafes at the same moment, so L and R are in step
    func sync(_ units: [CafeUnit]) {
        units.filter { $0.isConnected }.forEach { $0.send("Z") }
    }

    func setFreeze(_ v: Bool, _ units: [CafeUnit]) {
        freeze = v
        units.forEach { $0.send("M 23 \(v ? 1 : 0)") }
    }
    func setMove(_ v: Bool, _ units: [CafeUnit]) {
        move = v
        units.forEach { $0.send("M 26 \(v ? 1 : 0)") }
    }
    /// the PITCH key's steps: off -> PITCH (MOVE) -> FOLD -> off
    func cyclePitchFold(_ units: [CafeUnit]) {
        if move { setMove(false, units); setFold(true, units) }
        else if fold { setFold(false, units) }
        else { setMove(true, units) }
    }
    func setFold(_ v: Bool, _ units: [CafeUnit]) {
        fold = v
        units.forEach { $0.send("M 27 \(v ? 1 : 0)") }
    }
    func setPerc(_ v: Bool, _ units: [CafeUnit]) {
        perc = v
        units.forEach { $0.send("M 24 \(v ? 1 : 0)") }
    }

    // marks: remember the piece that was just hit (on both Cafes), up to 8
    func mark(_ units: [CafeUnit]) {
        units.forEach { $0.send("M 20 \(nextMark)") }
        nextMark = (nextMark + 1) % 8
        marks = min(8, marks + 1)
    }
    func clearMarks(_ units: [CafeUnit]) {
        units.forEach { $0.send("M 21 0") }
        nextMark = 0; marks = 0
        if useMarks { setUseMarks(false, units) }
    }
    func setUseMarks(_ v: Bool, _ units: [CafeUnit]) {
        useMarks = v
        units.forEach { $0.send("M 22 \(v ? 1 : 0)") }
    }
}

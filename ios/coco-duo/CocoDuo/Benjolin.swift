// Benjolin.swift — coco duo (k.odk)
// BENJOLIN mode (the third mode of the duo preset): each Cafe runs a Benjolin-style voice —
// two triangle oscillators, a rungler (8-bit shift register clocked by osc 2, fed by osc 1's pulse),
// its 3-bit voltage bending both oscillators and the filter, PWM of the two triangles into a resonant low-pass.
// Links to the Cafe: the tape / live input can go into the filter, the Benjolin can be PRINTED onto the tape
// (LOOP and GRAIN then play what it made), EARTH = FM for oscillator 1.
// The 8 pads set both Cafes; the L · R pad detunes the right side and moves its filter.
//
//   OSC 1    X = frequency (0.5 Hz … 4 kHz)        Y = rungler -> osc 1
//   OSC 2    X = frequency (it clocks the rungler) Y = rungler -> osc 2
//   FILTER   X = cutoff                            Y = resonance
//   F · MOD  X = rungler -> cutoff                 Y = osc 2 -> cutoff
//   RUNGLER  X = chaos (left = the pattern loops)  Y = cross FM (osc 2 -> osc 1)
//   TAPE     X = tape / input into the filter      Y = PRINT (the Benjolin onto the tape)
//   L · R    X = right side detuned (up to an octave)   Y = right side's filter higher
//   OUT      X = PWM … filter                      Y = level
// Firmware: B <id> <0..1000> — 0 osc1 1 run>osc1 2 osc2 3 run>osc2 4 cutoff 5 res 6 run>cutoff 7 osc2>cutoff
//           8 chaos 9 cross FM 10 input 11 print 12 pwm..filter 13 level 15 lock · 16 = new pattern

import Foundation

enum BjPad: Int, CaseIterable {
    case osc1, osc2, filter, fmod, rungler, tape, stereo, out
    var title: String { ["OSC 1", "OSC 2", "FILTER", "F · MOD", "RUNGLER", "TAPE", "L · R", "OUT"][rawValue] }
    /// the same as the firmware's defaults
    var start: (Double, Double) {
        [(0.45, 0.3), (0.25, 0.2), (0.55, 0.45), (0.35, 0.15), (0.8, 0.15), (0, 0), (0, 0), (0.6, 0.35)][rawValue]
    }
    var ids: [Int] {
        switch self {
        case .osc1:    return [0, 1]
        case .osc2:    return [2, 3]
        case .filter:  return [4, 5]
        case .fmod:    return [6, 7]
        case .rungler: return [8, 9]
        case .tape:    return [10, 11]
        case .stereo:  return [0, 2, 4]          // it shifts the right side's oscillators and filter
        case .out:     return [12, 13]
        }
    }
}

extension GrainMode {
    func bjValue(_ id: Int, slot: Int) -> Double {
        func a(_ p: BjPad) -> PadAxis { bjAxes[p.rawValue] }
        let right = slot == 1
        let lr = a(.stereo)
        let v: Double
        switch id {
        case 0: v = a(.osc1).x + (right ? lr.x * 0.077 : 0)      // 0.077 of 13 octaves ≈ 1 octave
        case 1: v = a(.osc1).y
        case 2: v = a(.osc2).x + (right ? lr.x * 0.05 : 0)
        case 3: v = a(.osc2).y
        case 4: v = a(.filter).x + (right ? lr.y * 0.15 : 0)
        case 5: v = a(.filter).y
        case 6: v = a(.fmod).x
        case 7: v = a(.fmod).y
        case 8: v = a(.rungler).x
        case 9: v = a(.rungler).y
        case 10: v = a(.tape).x
        case 11: v = a(.tape).y
        case 12: v = a(.out).x
        case 13: v = a(.out).y
        default: v = 0
        }
        return min(max(v, 0), 1)
    }

    func bjLine(_ id: Int, slot: Int) -> String { "B \(id) \(Int((bjValue(id, slot: slot) * 1000).rounded()))" }

    func bjCommands(pad i: Int, slot: Int) -> [String] {
        guard let p = BjPad(rawValue: i) else { return [] }
        return p.ids.map { bjLine($0, slot: slot) }
    }

    func bjAllCommands(slot: Int) -> [String] {
        (0...13).map { bjLine($0, slot: slot) } + ["B 15 \(bjLock ? 1000 : 0)"]
    }

    /// LOCK: the rungler's pattern repeats (both Cafes)
    func setBjLock(_ v: Bool, _ units: [CafeUnit]) {
        bjLock = v
        units.forEach { $0.send("B 15 \(v ? 1000 : 0)") }
    }
    /// a new pattern: flip one bit of the rungler (both Cafes, so they stay alike)
    func bjKick(_ units: [CafeUnit]) { units.forEach { $0.send("B 16 1") } }
}

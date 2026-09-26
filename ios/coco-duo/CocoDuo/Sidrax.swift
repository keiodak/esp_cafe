// Sidrax.swift — coco duo (k.odk)
// SIDRAX: mode 5 of the BLE preset, after Ciat-Lonbarde's Sidrax Organ (firmware: sx_tick, "S" lines).
// Plain triangle oscillators, one per touch PLATE (bottom row): each plate is one note, the touched AREA = the volume.
// SEESAW across the two Cafes: plates 1 and 3 sound on A while pressed and, lifted, crossfade over to B and ring out
// there; plates 2 and 4 the other way round. How long it rings = where the finger was up the plate (0.05 … 6 s).
// Top row: SCALE · KEY (left) and CHORD · OCTAVE (right) decide the four notes; in between FM · SELF (mutual FM, and
// each on itself) and CHAOS · GLITCH (the Sidrax's circle of FM · a triangle turning round). One Cafe alone does both.

import SwiftUI
import UIKit

enum SxPad {
    static let titles = ["SCALE · KEY", "FM · SELF", "CHAOS · GLITCH", "CHORD · OCTAVE",
                         "PLATE 1", "PLATE 2", "PLATE 3", "PLATE 4"]
    static let starts: [(Double, Double)] = [(0.15, 0.0), (0.0, 0.0), (0.0, 0.0), (0.2, 0.5),
                                             (0.2, 0.3), (0.45, 0.3), (0.65, 0.3), (0.85, 0.3)]
    static let scales = ["FREE", "PENTA", "MAJOR", "MINOR", "WHOLE", "CHROMA", "FIFTHS"]
    static let chordsInScale = ["STEPS", "THIRDS", "TRIAD+8", "FOURTHS", "FIFTHS", "OPEN", "WIDE"]
    static let chordsFree = ["CLUSTER", "MAJ7", "MIN7", "SUS", "QUARTAL", "FIFTHS", "OCTAVES"]
    /// (the firmware's tables, to name each plate's note)
    static let scaleSemis: [[Int]] = [[0], [0, 2, 4, 7, 9], [0, 2, 4, 5, 7, 9, 11], [0, 2, 3, 5, 7, 8, 10],
                                      [0, 2, 4, 6, 8, 10], Array(0...11), [0, 7]]
    static let chordDeg: [[Int]] = [[0, 1, 2, 3], [0, 2, 4, 6], [0, 2, 4, 100], [0, 3, 6, 9], [0, 4, 8, 12], [0, 4, 9, 13], [0, 100, 102, 104]]
    static let chordSemi: [[Int]] = [[0, 1, 2, 3], [0, 4, 7, 11], [0, 3, 7, 10], [0, 5, 7, 10], [0, 5, 10, 15], [0, 7, 14, 21], [0, 12, 19, 24]]
    /// plate k's note name, as the Cafe plays it
    static func note(_ k: Int, rig: Rig) -> String {
        let a = rig.sxAxes
        let sc = min(6, Int(a[0].x * 6.99)), key = min(11, Int(a[0].y * 11.99))
        let ch = min(6, Int(a[3].x * 6.99)), oc = min(4, Int(a[3].y * 4.99))
        var semi: Int
        if rig.sxAligned && sc >= 1 {
            let t = scaleSemis[sc], n = t.count
            var d = chordDeg[ch][k]
            if d >= 100 { d = n * (d - 99) }
            semi = t[d % n] + 12 * (d / n)
        } else { semi = chordSemi[ch][k] }
        let m = 24 + 12 * oc + key + semi                 // C1 = midi 24
        return "\(noteNames[m % 12])\(m / 12 - 1)"
    }
    static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    static func caption(_ i: Int, _ x: Double, _ y: Double, rig: Rig) -> String {
        let scaleOn = rig.sxAligned && Int(rig.sxAxes[0].x * 6.99) >= 1
        switch i {
        case 0: return "\(scales[min(6, Int(x * 6.99))]) · \(noteNames[min(11, Int(y * 11.99))])"
        case 1: return "FM \(Int(x * 100))% · SELF \(Int(y * 100))%"
        case 2: return "CHAOS \(Int(x * 100))% · GLITCH \(Int(y * 100))%"
        case 3:
            let c = min(6, Int(x * 6.99)), o = min(4, Int(y * 4.99))
            return "\(scaleOn ? chordsInScale[c] : chordsFree[c]) · C\(o + 1)"
        default: return ""
        }
    }
}

/// one plate: the finger's place and its touched area (0 = lifted). UIKit, because SwiftUI does not give the area.
struct PlatePad: View {
    @ObservedObject var axis: PadAxis
    @ObservedObject var rig: Rig
    let k: Int                       // 0…3
    let tag: String
    let send: () -> Void

    var body: some View {
        let a = rig.sxArea[k]
        GeometryReader { g in
            ZStack {
                Rectangle().fill(PastelTheme.padScreen)
                HudDots(step: 12)
                Rectangle().strokeBorder(PastelTheme.hudLine, lineWidth: 1)
                HudCorners(arm: 8).stroke(PastelTheme.hudBlack, lineWidth: 1.2).padding(3)
                // the finger: a disc as big as it presses
                Circle()
                    .fill(PastelTheme.hudOrange.opacity(a > 0 ? 0.25 + a * 0.55 : 0))
                    .overlay(Circle().strokeBorder(PastelTheme.hudBlack, lineWidth: a > 0 ? 1 : 0.6))
                    .frame(width: 10 + a * 64, height: 10 + a * 64)
                    .position(x: axis.x * g.size.width, y: (1 - axis.y) * g.size.height)
                    .animation(.easeOut(duration: 0.08), value: a)
                TouchPlate { x, y, area in
                    axis.x = x; axis.y = y
                    var ar = rig.sxArea
                    ar[k] = area == 0 && rig.sxHold ? ar[k] : area
                    rig.sxArea = ar
                    send()
                }
            }
        }
        .overlay(alignment: .topLeading) {
            HStack(spacing: 4) {
                HudTag(text: tag, size: 7)
                Text("PLATE_\(k + 1)")
                    .font(.hud(8, .semibold))
                    .tracking(0.8)
                    .foregroundStyle(PastelTheme.hudOrange)
            }
            .padding(.leading, 7).padding(.top, 6)
            .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomLeading) {
            Text(SxPad.note(k, rig: rig) + String(format: " · %.1f s", 0.05 * pow(120, axis.y)) + (a > 0 ? " · \(Int(a * 100))%" : ""))
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(PastelTheme.hudBlack.opacity(0.7))
                .padding(.leading, 8).padding(.bottom, 6)
                .allowsHitTesting(false)
        }
    }
}

/// the touch surface: reports x, y (0…1, y up) and the area (0…1; 0 when the finger lifts)
private struct TouchPlate: UIViewRepresentable {
    let report: (Double, Double, Double) -> Void
    func makeUIView(context: Context) -> PlateView { let v = PlateView(); v.report = report; return v }
    func updateUIView(_ v: PlateView, context: Context) { v.report = report }

    final class PlateView: UIView {
        var report: ((Double, Double, Double) -> Void)?
        private var finger: UITouch?
        private var smooth = 0.0

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isMultipleTouchEnabled = false
        }
        required init?(coder: NSCoder) { fatalError() }

        /// the area of the touch: the contact's radius (points), and the force where the screen has it
        private func area(_ t: UITouch) -> Double {
            let r = Double(t.majorRadius)                    // ~7 (fingertip, light) … ~30 (flat, pressed)
            var a = min(max((r - 6) / 22, 0), 1)
            if t.maximumPossibleForce > 0 { a = max(a, Double(t.force / t.maximumPossibleForce)) }
            return 0.12 + a * 0.88                            // (a light touch still sounds)
        }
        private func send(_ t: UITouch) {
            let p = t.location(in: self)
            let w = max(bounds.width, 1), h = max(bounds.height, 1)
            let x = min(max(Double(p.x / w), 0), 1), y = min(max(1 - Double(p.y / h), 0), 1)
            let a = area(t)
            smooth = smooth == 0 ? a : smooth + (a - smooth) * 0.35
            report?(x, y, smooth)
        }
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard finger == nil, let t = touches.first else { return }
            finger = t; smooth = 0; send(t)
        }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let f = finger, touches.contains(f) else { return }
            send(f)
        }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { lift(touches) }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { lift(touches) }
        private func lift(_ touches: Set<UITouch>) {
            guard let f = finger, touches.contains(f) else { return }
            let p = f.location(in: self)
            let w = max(bounds.width, 1), h = max(bounds.height, 1)
            finger = nil; smooth = 0
            report?(min(max(Double(p.x / w), 0), 1), min(max(1 - Double(p.y / h), 0), 1), 0)
        }
    }
}

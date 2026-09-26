// Sidrax.swift — coco duo (k.odk)
// SIDRAX: mode 5 of the BLE preset, after Ciat-Lonbarde's Sidrax Organ (firmware: sx_tick, "S" lines).
// Plain triangle oscillators, one per touch PLATE (bottom row): the touched AREA = the volume, X = the plate's tuning.
// Top row: SCALE · KEY (the plates snap to it; FREE = anywhere) · FM · SELF (mutual FM between the four, and each on
// itself) · CHAOS · GLITCH (each one FMs the one on its right, in a circle · a triangle turns round when the one on
// its left crosses zero) · PITCH · SPREAD. ALIGN off = free whatever the scale. HOLD keeps the plates sounding.

import SwiftUI
import UIKit

enum SxPad {
    static let titles = ["SCALE · KEY", "FM · SELF", "CHAOS · GLITCH", "PITCH · SPREAD",
                         "PLATE 1", "PLATE 2", "PLATE 3", "PLATE 4"]
    static let starts: [(Double, Double)] = [(0.15, 0.0), (0.0, 0.0), (0.0, 0.0), (0.35, 0.45),
                                             (0.2, 0.3), (0.45, 0.3), (0.65, 0.3), (0.85, 0.3)]
    static let scales = ["FREE", "PENTA", "MAJOR", "MINOR", "WHOLE", "CHROMA", "FIFTHS"]
    static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    static func caption(_ i: Int, _ x: Double, _ y: Double) -> String {
        switch i {
        case 0: return "\(scales[min(6, Int(x * 6.99))]) · \(noteNames[min(11, Int(y * 11.99))])"
        case 1: return "FM \(Int(x * 100))% · SELF \(Int(y * 100))%"
        case 2: return "CHAOS \(Int(x * 100))% · GLITCH \(Int(y * 100))%"
        case 3:
            let hz = 30 * pow(2, x * 5)
            let m = Int((12 * log2(hz / 440) + 69).rounded())
            return "\(noteNames[((m % 12) + 12) % 12])\(m / 12 - 1) · ±\(Int(y * 24)) st"
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
            Text(a > 0 ? "\(Int(a * 100))%" : "—")
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

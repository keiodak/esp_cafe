// FoursesBoard.swift — coco duo (k.odk)
// FOURSES (BLE mode 7): the board itself — crucFX's TARPTERGE (Cafe A) / ARPSERGE (Cafe B), its 44 touch nodes
// where they are on it (clockwise from the top left), each with Blasser's glyph for what it is. Four more
// terminals inside: the Cafe's IN and EARTH, OUT L (main) and OUT R (ASH). The four pots in the middle.
// PLAY: a finger is a finger — every node under it is joined through the skin (a light touch: ~10M, a flat one:
// ~20K), and the body hums. DRAW: a line from node to node is a wire (again = gone).

import SwiftUI
import UIKit

enum FrBoard {
    /// the nodes: where (x, y: -1…1, y up), what, which horse (0 = the bottom of the stack)
    static let pos: [(Double, Double)] = [(-0.859, 1.000), (-0.688, 1.000), (-0.500, 1.000), (-0.328, 1.000), (-0.141, 1.000), (0.031, 1.000), (0.188, 1.000), (0.375, 1.000), (0.547, 1.000), (0.734, 1.000), (0.875, 0.922), (1.000, 0.828), (1.000, 0.656), (1.000, 0.469), (1.000, 0.297), (1.000, 0.109), (1.000, -0.062), (1.000, -0.250), (1.000, -0.422), (1.000, -0.609), (1.000, -0.781), (0.922, -0.922), (0.859, -1.047), (0.672, -1.047), (0.500, -1.047), (0.312, -1.047), (0.141, -1.047), (-0.047, -1.047), (-0.203, -1.047), (-0.375, -1.047), (-0.562, -1.047), (-0.734, -1.047), (-0.875, -0.984), (-1.000, -0.875), (-1.000, -0.688), (-1.000, -0.516), (-1.000, -0.328), (-1.000, -0.156), (-1.000, 0.031), (-1.000, 0.203), (-1.000, 0.391), (-1.000, 0.562), (-1.000, 0.750), (-0.953, 0.891)]
    /// 0 capacitor · 1 buffer · 2 pulse · 3 threshold · 4 gate · 5 gate, inverted · 6 / 7 bounds · 8 / 9 / 10 the rate ladder
    static let role: [Int] = [4, 3, 2, 1, 0, 7, 9, 10, 8, 5, 6, 4, 3, 2, 1, 0, 9, 10, 8, 7, 5, 6, 4, 3, 2, 1, 0, 7, 9, 10, 8, 5, 6, 4, 3, 2, 1, 0, 9, 10, 8, 7, 5, 6]
    static let horse: [Int] = [0, 0, 0, 0, 0, 0, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 2, 2, 2, 3, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 1, 0, 0]
    /// the terminals (44…47) and where they sit
    static let terms = ["IN", "EARTH", "OUT L", "OUT R"]
    static let termPos: [(Double, Double)] = [(-0.62, 0.35), (-0.62, -0.35), (0.62, 0.35), (0.62, -0.35)]
    static let count = 48
    /// a buffer's node (for the default wires)
    static func buf(_ h: Int) -> Int { (0..<44).first { role[$0] == 1 && horse[$0] == h } ?? 0 }
    static let defaultWires: [[Int]] = [[46, buf(0)], [47, buf(2)]]
}

/// Blasser's glyphs, as on the board
struct FrGlyph: Shape {
    let role: Int
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY), s = min(r.width, r.height) / 2
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: c.x + x * s, y: c.y - y * s) }
        switch role {
        case 0, 3:                                                   // a cloud: the capacitor, the threshold
            p.addEllipse(in: CGRect(x: c.x - s * 0.9, y: c.y - s * 0.35, width: s * 1.8, height: s * 0.8))
            p.addEllipse(in: CGRect(x: c.x - s * 0.45, y: c.y - s * 0.75, width: s * 0.9, height: s * 0.8))
        case 1:                                                      // two bowties: the buffer
            for dx in [-0.45, 0.45] {
                p.move(to: pt(dx - 0.35, 0.6)); p.addLine(to: pt(dx + 0.35, -0.6)); p.addLine(to: pt(dx + 0.35, 0.6))
                p.addLine(to: pt(dx - 0.35, -0.6)); p.closeSubpath()
            }
        case 2:                                                      // a bowtie: the pulse
            p.move(to: pt(-0.6, 0.6)); p.addLine(to: pt(0.6, -0.6)); p.addLine(to: pt(0.6, 0.6)); p.addLine(to: pt(-0.6, -0.6)); p.closeSubpath()
        case 4, 5:                                                   // a diamond: the gates
            p.move(to: pt(0, 0.85)); p.addLine(to: pt(0.5, 0)); p.addLine(to: pt(0, -0.85)); p.addLine(to: pt(-0.5, 0)); p.closeSubpath()
            if role == 5 { p.move(to: pt(-0.5, 0)); p.addLine(to: pt(0.5, 0)) }
        case 6, 7:                                                   // a star: the bounds
            for k in 0..<14 {
                let a = Double(k) * .pi / 7 + .pi / 2, rr = k % 2 == 0 ? 0.9 : 0.4
                let q = pt(cos(a) * rr, sin(a) * rr)
                if k == 0 { p.move(to: q) } else { p.addLine(to: q) }
            }
            p.closeSubpath()
        case 8, 10:                                                  // a cross: the ladder's ends
            let a = 0.28, b = 0.8
            let xs: [(Double, Double)] = [(-a, b), (a, b), (a, a), (b, a), (b, -a), (a, -a), (a, -b), (-a, -b), (-a, -a), (-b, -a), (-b, a), (-a, a)]
            p.move(to: pt(xs[0].0, xs[0].1)); xs.dropFirst().forEach { p.addLine(to: pt($0.0, $0.1)) }; p.closeSubpath()
        default:                                                     // three bars: the ladder's middle
            for x in [-0.4, 0.0, 0.4] { p.move(to: pt(x, 0.7)); p.addLine(to: pt(x, -0.7)) }
            p.move(to: pt(-0.7, 0)); p.addLine(to: pt(0.7, 0))
        }
        return p
    }
}

/// the touches, with how much of the finger is down (UIKit: SwiftUI has no touch radius)
struct FrTouchLayer: UIViewRepresentable {
    var onChange: ([(id: Int, p: CGPoint, r: CGFloat, ended: Bool)]) -> Void
    func makeUIView(context: Context) -> V { let v = V(); v.onChange = onChange; v.isMultipleTouchEnabled = true; v.backgroundColor = .clear; return v }
    func updateUIView(_ v: V, context: Context) { v.onChange = onChange }
    final class V: UIView {
        var onChange: (([(id: Int, p: CGPoint, r: CGFloat, ended: Bool)]) -> Void)?
        private var ids: [ObjectIdentifier: Int] = [:]
        private func report(_ t: Set<UITouch>, ended: Bool) {
            var out: [(id: Int, p: CGPoint, r: CGFloat, ended: Bool)] = []
            for u in t {
                let k = ObjectIdentifier(u)
                if ids[k] == nil { ids[k] = (0..<5).first { f in !ids.values.contains(f) } ?? 4 }
                out.append((ids[k]!, u.location(in: self), u.majorRadius, ended))
                if ended { ids[k] = nil }
            }
            onChange?(out)
        }
        override func touchesBegan(_ t: Set<UITouch>, with e: UIEvent?) { report(t, ended: false) }
        override func touchesMoved(_ t: Set<UITouch>, with e: UIEvent?) { report(t, ended: false) }
        override func touchesEnded(_ t: Set<UITouch>, with e: UIEvent?) { report(t, ended: true) }
        override func touchesCancelled(_ t: Set<UITouch>, with e: UIEvent?) { report(t, ended: true) }
    }
}

struct FoursesBoard: View {
    let d: Director
    @ObservedObject var rig: Rig
    @State private var fingers: [Int: (p: CGPoint, r: CGFloat)] = [:]
    @State private var drawFrom: Int? = nil
    @State private var drawTo: CGPoint? = nil
    @State private var knobStart: [Int: Double] = [:]

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(PastelTheme.hudBlack.opacity(0.04))
                RoundedRectangle(cornerRadius: 6).strokeBorder(PastelTheme.hudLine, lineWidth: 1)
                // the wires
                Path { p in
                    for w in rig.frWires where w.count == 2 {
                        p.move(to: at(w[0], size)); p.addLine(to: at(w[1], size))
                    }
                    if let a = drawFrom, let b = drawTo { p.move(to: at(a, size)); p.addLine(to: b) }
                }
                .stroke(PastelTheme.hudBlack.opacity(0.75), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                // the nodes
                ForEach(0..<44, id: \.self) { i in
                    let q = at(i, size), s = node(size)
                    FrGlyph(role: FrBoard.role[i])
                        .stroke(PastelTheme.hudBlack, lineWidth: 1.2)
                        .background(FrGlyph(role: FrBoard.role[i]).fill(touched(i, size) ? PastelTheme.selection : Color.clear))
                        .frame(width: s, height: s)
                        .position(q)
                }
                ForEach(0..<4, id: \.self) { k in
                    let q = at(44 + k, size)
                    Text(FrBoard.terms[k])
                        .font(.hud(8, .semibold))
                        .foregroundStyle(touched(44 + k, size) ? PastelTheme.selectionText : PastelTheme.hudBlack)
                        .padding(.horizontal, 5).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 3).fill(touched(44 + k, size) ? PastelTheme.selection : Color.clear))
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(PastelTheme.hudLine, lineWidth: 1))
                        .position(q)
                }
                // the fingers
                ForEach(Array(fingers.keys), id: \.self) { f in
                    if let t = fingers[f] {
                        Circle().strokeBorder(PastelTheme.hudBlack.opacity(0.35), lineWidth: 1)
                            .frame(width: reach(t.r) * 2, height: reach(t.r) * 2).position(t.p)
                    }
                }
                FrTouchLayer { ts in touches(ts, size) }
                // the pots (above the touch layer: they turn)
                HStack(spacing: size.width * 0.05) {
                    ForEach(0..<4, id: \.self) { h in knob(h, size) }
                }
                .position(x: size.width / 2, y: size.height / 2)
            }
        }
    }

    // MARK: layout

    private func node(_ s: CGSize) -> CGFloat { max(12, min(s.width, s.height) * 0.075) }
    private func at(_ i: Int, _ s: CGSize) -> CGPoint {
        let (x, y) = i < 44 ? FrBoard.pos[i] : FrBoard.termPos[i - 44]
        let m = node(s) * 0.75
        return CGPoint(x: s.width / 2 + x * (s.width / 2 - m), y: s.height / 2 - y / 1.05 * (s.height / 2 - m))
    }
    private func reach(_ r: CGFloat) -> CGFloat { 14 + r * 0.9 }
    private func nearest(_ p: CGPoint, _ s: CGSize, within d: CGFloat) -> Int? {
        var best: (Int, CGFloat)? = nil
        for i in 0..<FrBoard.count {
            let q = at(i, s), dd = hypot(q.x - p.x, q.y - p.y)
            if dd < d && (best == nil || dd < best!.1) { best = (i, dd) }
        }
        return best?.0
    }
    private func touched(_ i: Int, _ s: CGSize) -> Bool {
        let q = at(i, s)
        return fingers.values.contains { hypot($0.p.x - q.x, $0.p.y - q.y) < reach($0.r) } || drawFrom == i
    }

    // MARK: touches

    private func touches(_ ts: [(id: Int, p: CGPoint, r: CGFloat, ended: Bool)], _ s: CGSize) {
        if rig.frDraw {
            guard let t = ts.first else { return }
            if drawFrom == nil { drawFrom = nearest(t.p, s, within: node(s) * 1.2) }
            drawTo = t.p
            if t.ended {
                if let a = drawFrom, let b = nearest(t.p, s, within: node(s) * 1.2), a != b { d.frToggleWire(a, b) }
                drawFrom = nil; drawTo = nil
            }
            return
        }
        for t in ts { if t.ended { fingers[t.id] = nil } else { fingers[t.id] = (t.p, t.r) } }
        // every node under a finger, joined to that finger: light (~10M) … flat (~20K)
        var links: [Int: [Int: Int]] = [:]
        for (f, t) in fingers {
            let R = reach(t.r)
            for i in 0..<FrBoard.count {
                let q = at(i, s), dd = hypot(q.x - t.p.x, q.y - t.p.y)
                guard dd < R else { continue }
                let firm = min(1, max(0, (t.r - 7) / 22))                    // the finger's contact: tip … flat
                let near = 1 - dd / R * 0.6                                   // (the edge of the finger touches less)
                links[48 + f, default: [:]][i] = Int((150 + firm * 780) * near)
            }
        }
        d.frTouches(links)
    }

    // MARK: the pots

    private func knob(_ h: Int, _ s: CGSize) -> some View {
        let v = rig.frPots[h], k = max(26, min(s.width, s.height) * 0.16)
        return ZStack {
            Circle().fill(PastelTheme.hudBlack.opacity(0.05))
            Circle().strokeBorder(PastelTheme.hudLine, lineWidth: 1)
            Rectangle().fill(PastelTheme.hudBlack).frame(width: 1.5, height: k * 0.4)
                .offset(y: -k * 0.2).rotationEffect(.degrees((v - 0.5) * 270))
        }
        .frame(width: k, height: k)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { g in
                if knobStart[h] == nil { knobStart[h] = rig.frPots[h] }
                d.setFrPot(h, min(1, max(0, knobStart[h]! - g.translation.height / 200)))
            }
            .onEnded { _ in knobStart[h] = nil })
    }
}
